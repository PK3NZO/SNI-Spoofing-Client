from __future__ import annotations

from dataclasses import dataclass
import json
import os
from dataclasses import replace
import sys

from core.models import ConnectionMode


def get_app_root() -> str:
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_user_data_root() -> str:
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, "SNI-Spoofing")
    if sys.platform == "darwin":
        return os.path.join(os.path.expanduser("~/Library/Application Support"), "SNI-Spoofing")
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "SNI-Spoofing")


def get_default_config_path() -> str:
    return os.path.join(get_user_data_root(), "config.json")


def _safe_int(value: object, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


@dataclass(frozen=True)
class AppConfig:
    listen_host: str
    listen_port: int
    connect_ip: str
    connect_port: int
    fake_sni: str
    whitelist_domain: str
    whitelist_ip: str
    whitelist_port: int
    proxy_link: str
    ui_language: str = "english"
    connection_mode: str = ConnectionMode.PROXY.value
    enable_system_proxy: bool = True
    log_level: str = "error"
    backend: str | None = None
    inbound_host: str = "127.0.0.1"
    socks_port: int = 20000
    http_port: int = 30000

    @classmethod
    def default(cls) -> "AppConfig":
        return cls(
            listen_host="127.0.0.1",
            listen_port=40444,
            connect_ip="104.19.229.21",
            connect_port=443,
            fake_sni="hcaptcha.com",
            whitelist_domain="hcaptcha.com",
            whitelist_ip="104.19.229.21",
            whitelist_port=443,
            proxy_link="",
            ui_language="english",
            connection_mode=ConnectionMode.PROXY.value,
            enable_system_proxy=True,
            log_level="error",
            backend=None,
            inbound_host="127.0.0.1",
            socks_port=20000,
            http_port=30000,
        )

    @classmethod
    def load(cls, config_path: str | None = None) -> "AppConfig":
        path = config_path or get_default_config_path()
        if not os.path.exists(path):
            config = cls.default()
            config.save(path)
            return config
        try:
            with open(path, "r", encoding="utf-8") as file_obj:
                raw = json.load(file_obj)
            default = cls.default()
            whitelist_domain = str(raw.get("WHITELIST_DOMAIN") or raw.get("FAKE_SNI") or default.whitelist_domain)
            whitelist_ip = str(raw.get("WHITELIST_IP") or raw.get("CONNECT_IP") or default.whitelist_ip)
            whitelist_port = _safe_int(raw.get("WHITELIST_PORT") or raw.get("CONNECT_PORT"), default.whitelist_port)
            config = cls(
                listen_host=str(raw.get("LISTEN_HOST", default.listen_host)),
                listen_port=_safe_int(raw.get("LISTEN_PORT"), default.listen_port),
                connect_ip=str(raw.get("CONNECT_IP") or whitelist_ip),
                connect_port=_safe_int(raw.get("CONNECT_PORT"), whitelist_port),
                fake_sni=str(raw.get("FAKE_SNI") or whitelist_domain),
                whitelist_domain=whitelist_domain,
                whitelist_ip=whitelist_ip,
                whitelist_port=whitelist_port,
                proxy_link=str(raw.get("PROXY_LINK", "")),
                ui_language=str(raw.get("UI_LANGUAGE", default.ui_language)).lower(),
                connection_mode=str(raw.get("CONNECTION_MODE", default.connection_mode)).lower(),
                enable_system_proxy=bool(raw.get("ENABLE_SYSTEM_PROXY", default.enable_system_proxy)),
                log_level=str(raw.get("LOG_LEVEL", default.log_level)),
                backend=raw.get("BACKEND"),
                inbound_host=str(raw.get("INBOUND_HOST", default.inbound_host)),
                socks_port=_safe_int(raw.get("SOCKS_PORT"), default.socks_port),
                http_port=_safe_int(raw.get("HTTP_PORT"), default.http_port),
            )
            return config.runtime_compatible()
        except (json.JSONDecodeError, KeyError, TypeError, OSError):
            broken_path = f"{path}.broken"
            try:
                if os.path.exists(path):
                    os.replace(path, broken_path)
            except OSError:
                pass
            config = cls.default()
            config.save(path)
            return config

    def to_dict(self) -> dict[str, object]:
        normalized = self.runtime_compatible()
        return {
            "LISTEN_HOST": normalized.listen_host,
            "LISTEN_PORT": normalized.listen_port,
            "CONNECT_IP": normalized.connect_ip,
            "CONNECT_PORT": normalized.connect_port,
            "FAKE_SNI": normalized.fake_sni,
            "WHITELIST_DOMAIN": normalized.whitelist_domain,
            "WHITELIST_IP": normalized.whitelist_ip,
            "WHITELIST_PORT": normalized.whitelist_port,
            "PROXY_LINK": normalized.proxy_link,
            "UI_LANGUAGE": normalized.ui_language,
            "CONNECTION_MODE": normalized.connection_mode,
            "ENABLE_SYSTEM_PROXY": normalized.enable_system_proxy,
            "LOG_LEVEL": normalized.log_level,
            "BACKEND": normalized.backend,
            "INBOUND_HOST": normalized.inbound_host,
            "SOCKS_PORT": normalized.socks_port,
            "HTTP_PORT": normalized.http_port,
        }

    def save(self, config_path: str | None = None) -> None:
        path = config_path or get_default_config_path()
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(path, "w", encoding="utf-8") as file_obj:
            json.dump(self.to_dict(), file_obj, indent=2, ensure_ascii=False)
            file_obj.write("\n")

    def updated(self, **changes) -> "AppConfig":
        return replace(self, **changes).runtime_compatible()

    def runtime_compatible(self) -> "AppConfig":
        mode = self.connection_mode if self.connection_mode in {ConnectionMode.PROXY.value, ConnectionMode.TUNNEL.value} else ConnectionMode.PROXY.value
        whitelist_domain = self.whitelist_domain.strip() or self.fake_sni.strip() or self.default().whitelist_domain
        whitelist_ip = self.whitelist_ip.strip() or self.connect_ip.strip() or self.default().whitelist_ip
        whitelist_port = self.whitelist_port if self.whitelist_port > 0 else self.default().whitelist_port
        ui_language = self.ui_language if self.ui_language in {"english", "persian"} else "english"
        socks_port = self.socks_port if self.socks_port > 0 else self.default().socks_port
        http_port = self.http_port if self.http_port > 0 else self.default().http_port
        inbound_host = self.inbound_host.strip() or self.default().inbound_host
        return replace(
            self,
            connect_ip=whitelist_ip,
            connect_port=whitelist_port,
            fake_sni=whitelist_domain,
            whitelist_domain=whitelist_domain,
            whitelist_ip=whitelist_ip,
            whitelist_port=whitelist_port,
            ui_language=ui_language,
            connection_mode=mode,
            socks_port=socks_port,
            http_port=http_port,
            inbound_host=inbound_host,
        )

    def selected_backend(self) -> str:
        if sys.platform == "win32":
            return self.backend if self.backend == "windows-pydivert" else "windows-pydivert"
        if sys.platform == "darwin":
            return self.backend if self.backend == "macos-network-extension" else "macos-network-extension"
        return "unsupported"
