from __future__ import annotations

import base64
from dataclasses import dataclass
import json
from urllib.parse import parse_qs, unquote, urlparse


class ProxyLinkError(ValueError):
    pass


@dataclass(frozen=True)
class ProxyLinkProfile:
    protocol: str
    remark: str
    server: str
    port: int
    network: str
    security: str
    sni: str
    host: str
    path: str
    uuid: str | None = None
    password: str | None = None
    method: str | None = None
    flow: str | None = None
    fingerprint: str | None = None
    encryption: str = "none"
    allow_insecure: bool = False


def parse_proxy_link(uri: str) -> ProxyLinkProfile:
    trimmed = uri.strip()
    if not trimmed:
        raise ProxyLinkError("Proxy config is empty.")

    lower = trimmed.lower()
    if lower.startswith("vless://"):
        return _parse_vless(trimmed)
    if lower.startswith("trojan://"):
        return _parse_trojan(trimmed)
    if lower.startswith("vmess://"):
        return _parse_vmess(trimmed)
    if lower.startswith("ss://"):
        return _parse_shadowsocks(trimmed)
    raise ProxyLinkError("Unsupported proxy link scheme.")


def build_xray_config(
    profile: ProxyLinkProfile,
    *,
    inbound_socks_port: int,
    inbound_http_port: int,
    outbound_address: str,
    outbound_port: int,
    log_level: str,
) -> str:
    outbound: dict[str, object]

    if profile.protocol == "vless":
        if not profile.uuid:
            raise ProxyLinkError("VLESS config is missing UUID.")
        user: dict[str, object] = {
            "id": profile.uuid,
            "encryption": profile.encryption or "none",
        }
        if profile.flow:
            user["flow"] = profile.flow
        outbound = {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": outbound_address,
                        "port": outbound_port,
                        "users": [user],
                    }
                ]
            },
        }
    elif profile.protocol == "vmess":
        if not profile.uuid:
            raise ProxyLinkError("VMess config is missing id.")
        outbound = {
            "protocol": "vmess",
            "settings": {
                "vnext": [
                    {
                        "address": outbound_address,
                        "port": outbound_port,
                        "users": [{"id": profile.uuid, "security": "auto"}],
                    }
                ]
            },
        }
    elif profile.protocol == "trojan":
        if not profile.password:
            raise ProxyLinkError("Trojan config is missing password.")
        outbound = {
            "protocol": "trojan",
            "settings": {
                "servers": [
                    {
                        "address": outbound_address,
                        "port": outbound_port,
                        "password": profile.password,
                    }
                ]
            },
        }
    elif profile.protocol == "shadowsocks":
        if not profile.password or not profile.method:
            raise ProxyLinkError("Shadowsocks config is missing method or password.")
        outbound = {
            "protocol": "shadowsocks",
            "settings": {
                "servers": [
                    {
                        "address": outbound_address,
                        "port": outbound_port,
                        "method": profile.method,
                        "password": profile.password,
                    }
                ]
            },
        }
    else:  # pragma: no cover - defensive
        raise ProxyLinkError(f"Unsupported profile protocol: {profile.protocol}")

    if profile.protocol != "shadowsocks":
        outbound["streamSettings"] = _build_stream_settings(profile)

    root = {
        "log": {"loglevel": _xray_log_level(log_level)},
        "inbounds": [
            {
                "tag": "socks-in",
                "port": inbound_socks_port,
                "listen": "127.0.0.1",
                "protocol": "socks",
                "settings": {"auth": "noauth", "udp": True},
            },
            {
                "tag": "http-in",
                "port": inbound_http_port,
                "listen": "127.0.0.1",
                "protocol": "http",
                "settings": {"allowTransparent": False},
            },
        ],
        "outbounds": [outbound],
    }
    return json.dumps(root, indent=2, sort_keys=True)


def _build_stream_settings(profile: ProxyLinkProfile) -> dict[str, object]:
    stream_settings: dict[str, object] = {
        "network": profile.network or "tcp",
        "security": profile.security or "none",
    }
    security = profile.security or "none"
    if security == "tls":
        tls_settings: dict[str, object] = {
            "serverName": profile.sni or profile.server,
            "allowInsecure": profile.allow_insecure,
        }
        if profile.fingerprint:
            tls_settings["fingerprint"] = profile.fingerprint
        stream_settings["tlsSettings"] = tls_settings

    network = profile.network or "tcp"
    if network == "ws":
        ws_headers = {"Host": profile.host or profile.sni or profile.server}
        stream_settings["wsSettings"] = {
            "path": profile.path or "/",
            "headers": ws_headers,
        }
    elif network == "grpc":
        stream_settings["grpcSettings"] = {"serviceName": profile.path.lstrip("/") or "grpc"}
    return stream_settings


def _parse_vless(uri: str) -> ProxyLinkProfile:
    parsed = urlparse(uri)
    if not parsed.hostname or not parsed.port:
        raise ProxyLinkError("VLESS config is missing host or port.")
    query = parse_qs(parsed.query)
    uuid = parsed.username or None
    return ProxyLinkProfile(
        protocol="vless",
        remark=unquote(parsed.fragment) if parsed.fragment else "VLESS",
        server=parsed.hostname,
        port=parsed.port,
        network=_first(query, "type", "tcp"),
        security=_first(query, "security", "none"),
        sni=_first(query, "sni", parsed.hostname),
        host=_first(query, "host", parsed.hostname),
        path=_first(query, "path", "/"),
        uuid=uuid,
        flow=_none_if_empty(_first(query, "flow", "")),
        fingerprint=_none_if_empty(_first(query, "fp", "")),
        encryption=_first(query, "encryption", "none"),
        allow_insecure=_first(query, "allowInsecure", "0") in {"1", "true", "yes"},
    )


def _parse_trojan(uri: str) -> ProxyLinkProfile:
    parsed = urlparse(uri)
    if not parsed.hostname or not parsed.port:
        raise ProxyLinkError("Trojan config is missing host or port.")
    query = parse_qs(parsed.query)
    return ProxyLinkProfile(
        protocol="trojan",
        remark=unquote(parsed.fragment) if parsed.fragment else "Trojan",
        server=parsed.hostname,
        port=parsed.port,
        network=_first(query, "type", "tcp"),
        security=_first(query, "security", "tls"),
        sni=_first(query, "sni", parsed.hostname),
        host=_first(query, "host", parsed.hostname),
        path=_first(query, "path", "/"),
        password=parsed.username or None,
        fingerprint=_none_if_empty(_first(query, "fp", "")),
        allow_insecure=_first(query, "allowInsecure", "0") in {"1", "true", "yes"},
    )


def _parse_vmess(uri: str) -> ProxyLinkProfile:
    payload = uri.split("://", 1)[1].strip()
    if not payload:
        raise ProxyLinkError("VMess config is missing payload.")
    decoded = _decode_base64(payload)
    try:
        raw = json.loads(decoded)
    except json.JSONDecodeError as exc:
        raise ProxyLinkError(f"Invalid VMess JSON: {exc}") from exc

    server = str(raw.get("add", "")).strip()
    port_text = str(raw.get("port", "")).strip()
    if not server or not port_text:
        raise ProxyLinkError("VMess config is missing host or port.")
    try:
        port = int(port_text)
    except ValueError as exc:
        raise ProxyLinkError("VMess port is invalid.") from exc

    tls_value = str(raw.get("tls", "")).strip()
    if tls_value in {"tls", "reality"}:
        security = tls_value
    else:
        security = "tls" if tls_value else "none"
    return ProxyLinkProfile(
        protocol="vmess",
        remark=str(raw.get("ps", "")).strip() or "VMess",
        server=server,
        port=port,
        network=str(raw.get("net", "")).strip() or "tcp",
        security=security,
        sni=str(raw.get("sni", "")).strip() or server,
        host=str(raw.get("host", "")).strip() or server,
        path=str(raw.get("path", "")).strip() or "/",
        uuid=str(raw.get("id", "")).strip() or None,
        fingerprint=str(raw.get("fp", "")).strip() or None,
    )


def _parse_shadowsocks(uri: str) -> ProxyLinkProfile:
    payload = uri.split("://", 1)[1].strip()
    main, _, fragment = payload.partition("#")
    if "@" not in main:
        raise ProxyLinkError("Shadowsocks config is missing credentials.")
    credentials_part, server_part = main.rsplit("@", 1)
    decoded_credentials = _decode_base64(credentials_part)
    if ":" not in decoded_credentials:
        raise ProxyLinkError("Shadowsocks credentials are invalid.")
    method, password = decoded_credentials.split(":", 1)
    if ":" not in server_part:
        raise ProxyLinkError("Shadowsocks config is missing host or port.")
    server, port_text = server_part.rsplit(":", 1)
    try:
        port = int(port_text)
    except ValueError as exc:
        raise ProxyLinkError("Shadowsocks port is invalid.") from exc
    return ProxyLinkProfile(
        protocol="shadowsocks",
        remark=unquote(fragment) if fragment else "Shadowsocks",
        server=server.strip(),
        port=port,
        network="tcp",
        security="none",
        sni=server.strip(),
        host=server.strip(),
        path="/",
        password=password,
        method=method,
    )


def _decode_base64(payload: str) -> str:
    normalized = payload.strip()
    missing_padding = (-len(normalized)) % 4
    normalized += "=" * missing_padding
    try:
        return base64.urlsafe_b64decode(normalized.encode("utf-8")).decode("utf-8")
    except Exception as exc:  # pragma: no cover - defensive
        raise ProxyLinkError("Invalid base64 payload.") from exc


def _first(values: dict[str, list[str]], key: str, default: str) -> str:
    selected = values.get(key, [default])
    return selected[0] if selected else default


def _none_if_empty(value: str) -> str | None:
    stripped = value.strip()
    return stripped or None


def _xray_log_level(level: str) -> str:
    normalized = level.lower().strip()
    if normalized in {"debug", "info", "warning", "error"}:
        return normalized
    return "warning"
