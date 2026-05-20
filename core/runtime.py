from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
import platform
import queue
import socket
import sys
import threading
import time
from typing import Iterable

from backends import build_backend
from core.connectivity_probe import ConnectivityProbeError, probe_via_local_http_proxy
from core.config import AppConfig
from core.models import (
    ConnectionMode,
    ProxyRuntimeSummary,
    TrafficSnapshot,
    WorkflowStep,
    WorkflowStepKey,
    WorkflowStepState,
    default_workflow_steps,
)
from core.proxy_links import ProxyLinkError, ProxyLinkProfile, build_xray_config, parse_proxy_link
from core.server import SniSpoofingServer
from core.system_proxy import SystemProxyError, SystemProxyManager
from core.xray_service import XrayService, XrayServiceError


class RuntimeState(str, Enum):
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    ERROR = "error"


@dataclass(frozen=True)
class RuntimeEvent:
    timestamp: float
    level: str
    message: str


class AppRuntime:
    def __init__(self, config_path: str | None = None) -> None:
        self._config_path = config_path
        self._config = AppConfig.load(config_path)
        self._state = RuntimeState.STOPPED
        self._state_message = "Ready"
        self._headline = "Ready"
        self._detail = "Set the allowlist and proxy config, then connect."
        self._route_summary = "-"
        self._active_summary = "-"
        self._original_server_summary = "-"
        self._probe_summary = "-"
        self._last_error = ""
        self._proxy_link_profile: ProxyLinkProfile | None = None
        self._workflow_steps = default_workflow_steps()
        self._events: queue.Queue[RuntimeEvent] = queue.Queue()
        self._event_history: list[RuntimeEvent] = []
        self._lock = threading.RLock()
        self._telemetry_lock = threading.RLock()
        self._thread: threading.Thread | None = None
        self._startup_thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._task: asyncio.Task | None = None
        self._server: SniSpoofingServer | None = None
        self._backend = None
        self._xray_service = XrayService()
        self._system_proxy_manager = SystemProxyManager()
        self._traffic_snapshot = TrafficSnapshot(bytes_uploaded=0, bytes_downloaded=0, active_connections=0)

    @property
    def config(self) -> AppConfig:
        return self._config

    @property
    def state(self) -> RuntimeState:
        return self._state

    @property
    def state_message(self) -> str:
        return self._state_message

    @property
    def workflow_steps(self) -> list[WorkflowStep]:
        return list(self._workflow_steps)

    @property
    def last_error(self) -> str:
        return self._last_error

    @property
    def summary(self) -> ProxyRuntimeSummary:
        return ProxyRuntimeSummary(
            headline=self._headline,
            detail=self._detail,
            route_summary=self._route_summary,
            active_summary=self._active_summary,
            original_server_summary=self._original_server_summary,
            probe_summary=self._probe_summary,
        )

    @property
    def traffic_snapshot(self) -> TrafficSnapshot:
        with self._telemetry_lock:
            return self._traffic_snapshot

    def reload_config(self) -> AppConfig:
        self._config = AppConfig.load(self._config_path)
        return self._config

    def save_config(self, config: AppConfig | None = None) -> None:
        normalized = (config or self._config).runtime_compatible()
        normalized.save(self._config_path)
        self._config = normalized

    def update_config(self, **changes) -> AppConfig:
        self._config = self._config.updated(**changes)
        return self._config

    def drain_events(self) -> list[RuntimeEvent]:
        events: list[RuntimeEvent] = []
        while True:
            try:
                events.append(self._events.get_nowait())
            except queue.Empty:
                return events

    def _emit(self, level: str, message: str) -> None:
        event = RuntimeEvent(time.time(), level, message)
        self._events.put(event)
        self._event_history.append(event)
        if len(self._event_history) > 300:
            self._event_history = self._event_history[-300:]

    def _consume_server_log(self, level: str, message: str) -> None:
        self._emit(level, message)

    def _consume_traffic_update(self, uploaded: int, downloaded: int, active_connections: int) -> None:
        with self._telemetry_lock:
            self._traffic_snapshot = TrafficSnapshot(
                bytes_uploaded=uploaded,
                bytes_downloaded=downloaded,
                active_connections=active_connections,
            )

    def _set_state(self, state: RuntimeState, message: str) -> None:
        self._state = state
        self._state_message = message
        self._emit("state", f"{state.value}: {message}")

    def _set_step(self, key: WorkflowStepKey, state: WorkflowStepState, detail: str) -> None:
        updated: list[WorkflowStep] = []
        for step in self._workflow_steps:
            if step.key == key:
                updated.append(WorkflowStep(step.key, step.title, state, detail))
            else:
                updated.append(step)
        self._workflow_steps = updated

    def _reset_workflow(self) -> None:
        self._workflow_steps = default_workflow_steps()
        self._last_error = ""
        self._headline = "Ready"
        self._detail = "Set the allowlist and proxy config, then connect."
        self._route_summary = "-"
        self._active_summary = "-"
        self._original_server_summary = "-"
        self._probe_summary = "-"
        self._proxy_link_profile = None
        self._event_history = []
        with self._telemetry_lock:
            self._traffic_snapshot = TrafficSnapshot(bytes_uploaded=0, bytes_downloaded=0, active_connections=0)

    def _validate_config_for_profile(self, config: AppConfig) -> ProxyLinkProfile | None:
        if not config.whitelist_domain.strip():
            raise ValueError("Allowlist domain is required.")
        if not config.whitelist_ip.strip():
            raise ValueError("Allowlist IP is required.")
        if config.whitelist_port <= 0:
            raise ValueError("Allowlist port is invalid.")
        self._set_step(
            WorkflowStepKey.WHITELIST,
            WorkflowStepState.SUCCESS,
            f"{config.whitelist_domain} -> {config.whitelist_ip}:{config.whitelist_port}",
        )
        if not config.proxy_link.strip():
            self._set_step(WorkflowStepKey.PROXY_CONFIG, WorkflowStepState.SKIPPED, "No proxy link provided yet")
            return None
        profile = parse_proxy_link(config.proxy_link)
        self._set_step(
            WorkflowStepKey.PROXY_CONFIG,
            WorkflowStepState.SUCCESS,
            f"{profile.remark} | {profile.network.upper()}/{profile.security.upper()}",
        )
        self._original_server_summary = f"{profile.server}:{profile.port} | {profile.remark}"
        return profile

    def _wait_for_local_port(self, host: str, port: int, timeout: float = 3.0) -> None:
        target_host = "127.0.0.1" if host in {"0.0.0.0", ""} else host
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with socket.create_connection((target_host, port), timeout=0.2):
                    return
            except OSError:
                time.sleep(0.1)
        raise RuntimeError(f"Timed out waiting for local listener on {target_host}:{port}")

    def _start_proxy_stack(self) -> None:
        self._wait_for_local_port(self._config.listen_host, self._config.listen_port)
        self._set_step(
            WorkflowStepKey.LOCAL_PROXY,
            WorkflowStepState.SUCCESS,
            f"Listener active on {self._config.listen_host}:{self._config.listen_port}",
        )
        if self._proxy_link_profile is None:
            self._headline = f"Local listener up on {self._config.listen_host}:{self._config.listen_port}"
            self._detail = "Proxy link nadari, pas faghat bypass listener bala oomad."
            self._route_summary = "Local listener only"
            self._set_step(WorkflowStepKey.XRAY, WorkflowStepState.SKIPPED, "No proxy link provided")
            self._set_step(WorkflowStepKey.SYSTEM_ROUTE, WorkflowStepState.SKIPPED, "No Xray session")
            self._set_step(WorkflowStepKey.PROBE, WorkflowStepState.SKIPPED, "No proxy session to probe")
            self._set_state(RuntimeState.RUNNING, "Local listener is active")
            return

        self._set_step(WorkflowStepKey.XRAY, WorkflowStepState.RUNNING, "Starting Xray with generated config")
        xray_config = build_xray_config(
            self._proxy_link_profile,
            inbound_socks_port=self._config.socks_port,
            inbound_http_port=self._config.http_port,
            inbound_host=self._config.inbound_host,
            outbound_address=self._config.listen_host,
            outbound_port=self._config.listen_port,
            log_level=self._config.log_level,
        )
        self._emit(
            "debug",
            f"Xray config prepared | inbounds=socks:{self._config.socks_port},http:{self._config.http_port} "
            f"listen={self._config.inbound_host} "
            f"outbound={self._config.listen_host}:{self._config.listen_port} original={self._original_server_summary}",
        )
        self._xray_service.start(xray_config)
        self._emit(
            "debug",
            f"Xray process started | config={self._xray_service.config_path} log={self._xray_service.output_path}",
        )
        self._set_step(
            WorkflowStepKey.XRAY,
            WorkflowStepState.SUCCESS,
            f"Xray started | HTTP {self._config.inbound_host}:{self._config.http_port} | SOCKS {self._config.inbound_host}:{self._config.socks_port}",
        )
        proxy_host = "127.0.0.1" if self._config.inbound_host in {"0.0.0.0", ""} else self._config.inbound_host
        if self._config.enable_system_proxy:
            self._set_step(WorkflowStepKey.SYSTEM_ROUTE, WorkflowStepState.RUNNING, "Configuring Windows system proxy")
            proxy_server = self._system_proxy_manager.enable(
                http_host=proxy_host,
                http_port=self._config.http_port,
                socks_host=proxy_host,
                socks_port=self._config.socks_port,
            )
            self._route_summary = f"System proxy | {proxy_server}"
            self._set_step(WorkflowStepKey.SYSTEM_ROUTE, WorkflowStepState.SUCCESS, proxy_server)
        else:
            self._route_summary = "Manual proxy only | system settings unchanged"
            self._set_step(WorkflowStepKey.SYSTEM_ROUTE, WorkflowStepState.SKIPPED, "Manual proxy mode")

        self._headline = "Testing proxy route"
        self._detail = "Xray is running; validating traffic through the local bypass stack."
        self._set_step(WorkflowStepKey.PROBE, WorkflowStepState.RUNNING, "Testing internet access through the local HTTP proxy")
        self._emit("debug", f"Connectivity probe started | http_proxy=127.0.0.1:{self._config.http_port}")
        probe_url = probe_via_local_http_proxy(self._config.http_port)

        self._set_step(WorkflowStepKey.PROBE, WorkflowStepState.SUCCESS, f"Probe success: {probe_url}")
        self._probe_summary = probe_url
        self._headline = f"SOCKS {self._config.inbound_host}:{self._config.socks_port} | HTTP {self._config.inbound_host}:{self._config.http_port}"
        self._detail = "Xray + local bypass stack is active. App traffic can route through the generated local proxies."
        self._set_state(RuntimeState.RUNNING, "Proxy route validated")

    def _run_startup_stack(self) -> None:
        try:
            self._start_proxy_stack()
        except (ProxyLinkError, RuntimeError, XrayServiceError, SystemProxyError, ConnectivityProbeError) as exc:
            self._last_error = str(exc)
            self._headline = "Connection Failed"
            self._detail = f"Proxy validation failed: {self._last_error}"
            self._probe_summary = self._last_error
            self._set_state(RuntimeState.ERROR, self._last_error)
            self._emit("error", self._last_error)
            self._set_step(WorkflowStepKey.PROBE, WorkflowStepState.FAILURE, self._last_error)
            self.stop(preserve_error=True)
        finally:
            with self._lock:
                self._startup_thread = None

    @staticmethod
    def _is_expected_shutdown_error(exc: Exception) -> bool:
        return isinstance(exc, OSError) and getattr(exc, "winerror", None) == 995

    @staticmethod
    def _environment_summary() -> str:
        return (
            f"os={platform.platform()} machine={platform.machine()} "
            f"processor={platform.processor() or '-'} python={platform.python_version()} "
            f"python_bits={64 if sys.maxsize > 2**32 else 32}"
        )

    def start(self) -> None:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return

            self._reset_workflow()
            try:
                self.reload_config()
                self._config = self._config.runtime_compatible()
                proxy_link_profile = self._validate_config_for_profile(self._config)
                if self._config.connection_mode == ConnectionMode.TUNNEL.value:
                    self._set_step(
                        WorkflowStepKey.SYSTEM_ROUTE,
                        WorkflowStepState.FAILURE,
                        "Tunnel mode dar Windows adapter hanooz implement نشده."
                    )
                    raise RuntimeError("Tunnel mode is not implemented yet for the Windows shared runtime.")

                backend = build_backend(self._config.selected_backend())
                server = SniSpoofingServer(
                    self._config,
                    backend,
                    traffic_callback=self._consume_traffic_update,
                    log_callback=self._consume_server_log,
                )
            except (ValueError, ProxyLinkError, RuntimeError) as exc:
                self._backend = None
                self._server = None
                self._last_error = str(exc)
                self._headline = "Connection Failed"
                self._detail = str(exc)
                self._set_state(RuntimeState.ERROR, str(exc))
                self._emit("error", str(exc))
                return
            except Exception as exc:
                self._backend = None
                self._server = None
                self._last_error = f"{type(exc).__name__}: {exc}"
                self._headline = "Connection Failed"
                self._detail = self._last_error
                self._set_state(RuntimeState.ERROR, self._last_error)
                self._emit("error", self._last_error)
                return

            self._proxy_link_profile = proxy_link_profile
            self._backend = backend
            self._server = server
            self._emit("debug", f"Runtime environment | {self._environment_summary()}")
            if sys.platform == "win32" and platform.machine().lower() in {"arm64", "aarch64"}:
                self._emit(
                    "error",
                    "Windows ARM64 detected. windows-pydivert depends on WinDivert packet capture/injection and may not work reliably in ARM/VM environments.",
                )
            self._active_summary = f"Proxy: {self._config.whitelist_domain} -> {self._config.whitelist_ip}:{self._config.whitelist_port}"
            self._route_summary = "-"
            self._set_step(
                WorkflowStepKey.LOCAL_PROXY,
                WorkflowStepState.RUNNING,
                f"Starting local listener on {self._config.listen_host}:{self._config.listen_port}",
            )
            self._set_step(WorkflowStepKey.XRAY, WorkflowStepState.PENDING, "Waiting for local bypass listener")
            self._set_step(WorkflowStepKey.SYSTEM_ROUTE, WorkflowStepState.PENDING, "Waiting for Xray startup")
            self._set_step(WorkflowStepKey.PROBE, WorkflowStepState.PENDING, "Waiting for connectivity probe")
            self._headline = f"Starting {backend.name}"
            self._detail = "Preparing local proxy workflow."
            self._set_state(
                RuntimeState.STARTING,
                f"Starting {backend.name} on {self._config.listen_host}:{self._config.listen_port}",
            )
            self._thread = threading.Thread(target=self._run_server, name="SNI Runtime", daemon=True)
            self._thread.start()
            self._startup_thread = threading.Thread(target=self._run_startup_stack, name="SNI Startup", daemon=True)
            self._startup_thread.start()

    def _run_server(self) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        self._loop = loop
        assert self._server is not None
        task = loop.create_task(self._server.serve_forever())
        self._task = task
        self._emit("info", f"backend={self._config.selected_backend()}")
        try:
            loop.run_until_complete(task)
        except asyncio.CancelledError:
            pass
        except Exception as exc:  # pragma: no cover - runtime surface
            if self._is_expected_shutdown_error(exc) and self._state in {RuntimeState.STOPPING, RuntimeState.ERROR}:
                pass
            else:
                self._last_error = f"{type(exc).__name__}: {exc}"
                self._headline = "Connection Failed"
                self._detail = self._last_error
                self._set_state(RuntimeState.ERROR, self._last_error)
                self._emit("error", self._last_error)
                self._set_step(WorkflowStepKey.LOCAL_PROXY, WorkflowStepState.FAILURE, self._last_error)
        finally:
            try:
                self._system_proxy_manager.disable()
            except SystemProxyError:
                pass
            self._xray_service.stop()
            pending: Iterable[asyncio.Task] = [t for t in asyncio.all_tasks(loop) if not t.done()]
            for pending_task in pending:
                pending_task.cancel()
            if pending:
                loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            loop.run_until_complete(loop.shutdown_asyncgens())
            loop.close()
            with self._lock:
                self._loop = None
                self._task = None
                self._server = None
                self._backend = None
                self._thread = None
                self._startup_thread = None
                if self._state != RuntimeState.ERROR:
                    self._set_state(RuntimeState.STOPPED, "Ready")
                    self._headline = "Ready"
                    self._detail = "Set the allowlist and proxy config, then connect."

    def stop(self, preserve_error: bool = False) -> None:
        with self._lock:
            if self._thread is None or not self._thread.is_alive():
                if not preserve_error:
                    self._set_state(RuntimeState.STOPPED, "Ready")
                    self._headline = "Ready"
                    self._detail = "Set the allowlist and proxy config, then connect."
                return

            if not preserve_error:
                self._headline = "Disconnecting"
                self._detail = "Stopping backend and cleaning up local resources."
                self._set_state(RuntimeState.STOPPING, "Stopping backend")
            try:
                self._system_proxy_manager.disable()
            except SystemProxyError as exc:
                self._emit("error", str(exc))
            self._xray_service.stop()
            if self._server is not None:
                self._server.close()
            if self._loop is not None and self._task is not None:
                self._loop.call_soon_threadsafe(self._task.cancel)

        thread = self._thread
        if thread is not None:
            thread.join(timeout=5)
            if thread.is_alive():
                self._emit("error", "Runtime stop timed out")
                self._set_state(RuntimeState.ERROR, "Stop timed out")

    def diagnostic_dump(self) -> str:
        summary = self.summary
        traffic = self.traffic_snapshot
        lines = [
            "=== SNI-Spoofing Client Diagnostic Dump ===",
            f"Generated at: {datetime.now().isoformat(timespec='seconds')}",
            f"State: {self.state.value}",
            f"State message: {self.state_message}",
            f"Headline: {summary.headline}",
            f"Detail: {summary.detail}",
            f"Allowlist: {summary.active_summary}",
            f"Route summary: {summary.route_summary}",
            f"Original server: {summary.original_server_summary}",
            f"Probe: {summary.probe_summary}",
            f"Traffic up: {traffic.bytes_uploaded}",
            f"Traffic down: {traffic.bytes_downloaded}",
            f"Traffic total: {traffic.total_bytes}",
            f"Active connections: {traffic.active_connections}",
            f"Proxy mode: {self._config.connection_mode}",
            f"System proxy automation: {self._config.enable_system_proxy}",
            f"Backend: {self._config.selected_backend()}",
            f"Environment: {self._environment_summary()}",
            f"Listen: {self._config.listen_host}:{self._config.listen_port}",
            f"Whitelist: {self._config.whitelist_domain} -> {self._config.whitelist_ip}:{self._config.whitelist_port}",
            f"Last error: {self._last_error or '-'}",
            "Workflow:",
        ]
        for step in self._workflow_steps:
            lines.append(f"  - {step.title}: {step.state.value} | {step.detail}")
        lines.append("Recent events:")
        for event in self._event_history[-120:]:
            lines.append(f"  - {event.level.upper()} | {event.message}")
        return "\n".join(lines)
