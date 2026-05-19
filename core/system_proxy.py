from __future__ import annotations

from dataclasses import dataclass
import sys


class SystemProxyError(RuntimeError):
    pass


@dataclass(frozen=True)
class SystemProxySnapshot:
    enabled: bool
    server: str


class SystemProxyManager:
    def __init__(self) -> None:
        self._snapshot: SystemProxySnapshot | None = None
        self._managed = False

    @property
    def is_managing_proxy(self) -> bool:
        return self._managed

    def enable(self, *, http_host: str, http_port: int, socks_host: str, socks_port: int) -> str:
        if sys.platform != "win32":
            raise SystemProxyError("System proxy automation dar in platform implement نشده.")
        winreg, ctypes = self._imports()
        if self._snapshot is None:
            self._snapshot = self._read_snapshot(winreg)

        proxy_server = f"http={http_host}:{http_port};https={http_host}:{http_port};socks={socks_host}:{socks_port}"
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Internet Settings",
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            winreg.SetValueEx(key, "ProxyEnable", 0, winreg.REG_DWORD, 1)
            winreg.SetValueEx(key, "ProxyServer", 0, winreg.REG_SZ, proxy_server)
        self._broadcast_refresh(ctypes)
        self._managed = True
        return proxy_server

    def disable(self) -> None:
        if sys.platform != "win32":
            return
        if not self._managed:
            return
        winreg, ctypes = self._imports()
        snapshot = self._snapshot or SystemProxySnapshot(enabled=False, server="")
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Internet Settings",
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            winreg.SetValueEx(key, "ProxyEnable", 0, winreg.REG_DWORD, 1 if snapshot.enabled else 0)
            winreg.SetValueEx(key, "ProxyServer", 0, winreg.REG_SZ, snapshot.server)
        self._broadcast_refresh(ctypes)
        self._managed = False

    @staticmethod
    def _imports():
        try:
            import ctypes
            import winreg  # type: ignore
        except ImportError as exc:  # pragma: no cover - windows only
            raise SystemProxyError("Windows proxy APIs available نیست.") from exc
        return winreg, ctypes

    @staticmethod
    def _read_snapshot(winreg_module) -> SystemProxySnapshot:
        with winreg_module.OpenKey(
            winreg_module.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Internet Settings",
            0,
            winreg_module.KEY_QUERY_VALUE,
        ) as key:
            try:
                enabled_value, _ = winreg_module.QueryValueEx(key, "ProxyEnable")
            except FileNotFoundError:
                enabled_value = 0
            try:
                server_value, _ = winreg_module.QueryValueEx(key, "ProxyServer")
            except FileNotFoundError:
                server_value = ""
        return SystemProxySnapshot(enabled=bool(enabled_value), server=str(server_value))

    @staticmethod
    def _broadcast_refresh(ctypes_module) -> None:
        internet_option_settings_changed = 39
        internet_option_refresh = 37
        ctypes_module.windll.Wininet.InternetSetOptionW(0, internet_option_settings_changed, 0, 0)
        ctypes_module.windll.Wininet.InternetSetOptionW(0, internet_option_refresh, 0, 0)
