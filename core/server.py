from __future__ import annotations

import asyncio
import os
import socket
import threading
from typing import Callable

from backends.base import BypassBackend
from core.config import AppConfig
from core.socket_options import configure_keepalive
from utils.network_tools import get_default_interface_ipv4
from utils.packet_templates import ClientHelloMaker


class SniSpoofingServer:
    def __init__(
        self,
        config: AppConfig,
        backend: BypassBackend,
        traffic_callback: Callable[[int, int, int], None] | None = None,
        log_callback: Callable[[str, str], None] | None = None,
    ) -> None:
        self.config = config
        self.backend = backend
        self._traffic_callback = traffic_callback
        self._log_callback = log_callback
        self.interface_ipv4 = get_default_interface_ipv4(config.connect_ip)
        self._mother_sock: socket.socket | None = None
        self._traffic_lock = threading.Lock()
        self._bytes_uploaded = 0
        self._bytes_downloaded = 0
        self._active_connections = 0
        if not self.interface_ipv4:
            raise RuntimeError(
                f"natavanestam interface e IPv4 baraye route be {config.connect_ip} peyda konam."
            )

    def close(self) -> None:
        if self._mother_sock is None:
            return
        try:
            self._mother_sock.close()
        finally:
            self._mother_sock = None

    def _emit_log(self, level: str, message: str) -> None:
        if self._log_callback is not None:
            self._log_callback(level, message)

    def _increment_active_connections(self, delta: int) -> None:
        with self._traffic_lock:
            self._active_connections = max(0, self._active_connections + delta)
            self._emit_traffic_locked()

    def _record_traffic(self, uploaded: int = 0, downloaded: int = 0) -> None:
        with self._traffic_lock:
            self._bytes_uploaded += uploaded
            self._bytes_downloaded += downloaded
            self._emit_traffic_locked()

    def _emit_traffic_locked(self) -> None:
        if self._traffic_callback is not None:
            self._traffic_callback(self._bytes_uploaded, self._bytes_downloaded, self._active_connections)

    async def relay_main_loop(
        self,
        source_sock: socket.socket,
        destination_sock: socket.socket,
        peer_task: asyncio.Task,
        first_prefix_data: bytes,
        is_upload: bool,
    ) -> None:
        loop = asyncio.get_running_loop()
        while True:
            try:
                data = await loop.sock_recv(source_sock, 65575)
                if not data:
                    raise ValueError("eof")
                if first_prefix_data:
                    data = first_prefix_data + data
                    first_prefix_data = b""
                await loop.sock_sendall(destination_sock, data)
                if is_upload:
                    self._record_traffic(uploaded=len(data))
                else:
                    self._record_traffic(downloaded=len(data))
            except Exception:
                source_sock.close()
                destination_sock.close()
                peer_task.cancel()
                return

    async def handle(self, incoming_sock: socket.socket, incoming_remote_addr) -> None:
        del incoming_remote_addr
        self._increment_active_connections(1)
        loop = asyncio.get_running_loop()
        fake_data = ClientHelloMaker.get_client_hello_with(
            os.urandom(32),
            os.urandom(32),
            self.config.fake_sni.encode(),
            os.urandom(32),
        )
        outgoing_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        outgoing_sock.setblocking(False)
        outgoing_sock.bind((self.interface_ipv4, 0))
        configure_keepalive(outgoing_sock)

        src_port = outgoing_sock.getsockname()[1]
        connection = self.backend.register_connection(
            outgoing_sock,
            self.interface_ipv4,
            self.config.connect_ip,
            src_port,
            self.config.connect_port,
            fake_data,
            incoming_sock,
        )
        try:
            await loop.sock_connect(outgoing_sock, (self.config.connect_ip, self.config.connect_port))
        except Exception:
            self.backend.unregister_connection(connection)
            outgoing_sock.close()
            incoming_sock.close()
            self._increment_active_connections(-1)
            return

        try:
            await connection.wait_until_ready(timeout=2)
        except Exception:
            self.backend.unregister_connection(connection)
            outgoing_sock.close()
            incoming_sock.close()
            self._increment_active_connections(-1)
            return

        self.backend.unregister_connection(connection)
        self._emit_log("info", f"Bypass ready for {self.config.connect_ip}:{self.config.connect_port}")

        oti_task = asyncio.create_task(
            self.relay_main_loop(outgoing_sock, incoming_sock, asyncio.current_task(), b"", False)
        )
        try:
            await self.relay_main_loop(incoming_sock, outgoing_sock, oti_task, b"", True)
        finally:
            self._increment_active_connections(-1)

    async def serve_forever(self) -> None:
        self.backend.start(self.interface_ipv4, self.config.connect_ip)
        self._emit_log("info", f"Bypass backend started on {self.interface_ipv4} -> {self.config.connect_ip}")

        mother_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._mother_sock = mother_sock
        mother_sock.setblocking(False)
        mother_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        mother_sock.bind((self.config.listen_host, self.config.listen_port))
        configure_keepalive(mother_sock)
        mother_sock.listen()
        self._emit_log("info", f"Local listener active on {self.config.listen_host}:{self.config.listen_port}")

        loop = asyncio.get_running_loop()
        try:
            while True:
                incoming_sock, addr = await loop.sock_accept(mother_sock)
                incoming_sock.setblocking(False)
                configure_keepalive(incoming_sock)
                self._emit_log("debug", f"Accepted client from {addr[0]}:{addr[1]}")
                asyncio.create_task(self.handle(incoming_sock, addr))
        finally:
            self._mother_sock = None
            mother_sock.close()
            self.backend.stop()
            self._emit_log("info", "Bypass backend stopped")
