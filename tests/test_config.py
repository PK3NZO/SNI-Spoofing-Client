from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backends import available_backend_names
from core.config import AppConfig
from core.models import ConnectionMode
from core.proxy_links import ProxyLinkError, build_xray_config, parse_proxy_link
from core.xray_service import XrayService


class AppConfigTests(unittest.TestCase):
    def test_save_and_load_roundtrip_preserves_shared_profile_fields(self) -> None:
        config = AppConfig(
            listen_host="127.0.0.1",
            listen_port=40444,
            connect_ip="1.1.1.1",
            connect_port=443,
            fake_sni="example.com",
            whitelist_domain="example.com",
            whitelist_ip="1.1.1.1",
            whitelist_port=443,
            proxy_link="vless://uuid@example.net:443?security=tls&type=ws&host=cdn.example.net&sni=edge.example.net&path=%2Fws#EDGE",
            ui_language="persian",
            connection_mode=ConnectionMode.PROXY.value,
            enable_system_proxy=False,
            log_level="info",
            backend="windows-pydivert",
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            path = f"{temp_dir}/config.json"
            config.save(path)
            loaded = AppConfig.load(path)

        self.assertEqual(loaded.listen_host, config.listen_host)
        self.assertEqual(loaded.listen_port, config.listen_port)
        self.assertEqual(loaded.whitelist_domain, config.whitelist_domain)
        self.assertEqual(loaded.whitelist_ip, config.whitelist_ip)
        self.assertEqual(loaded.whitelist_port, config.whitelist_port)
        self.assertEqual(loaded.proxy_link, config.proxy_link)
        self.assertEqual(loaded.ui_language, config.ui_language)
        self.assertEqual(loaded.connection_mode, config.connection_mode)
        self.assertEqual(loaded.enable_system_proxy, config.enable_system_proxy)
        self.assertEqual(loaded.log_level, config.log_level)
        self.assertEqual(loaded.backend, config.backend)

    def test_runtime_compatible_normalizes_ui_language(self) -> None:
        normalized = AppConfig.default().updated(ui_language="unknown")

        self.assertEqual(normalized.ui_language, "english")

    def test_load_creates_default_config_when_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "missing.json"
            loaded = AppConfig.load(str(path))

            self.assertTrue(path.exists())
            self.assertEqual(loaded, AppConfig.default())

    def test_load_repairs_corrupted_config_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "broken.json"
            path.write_text("{not-json", encoding="utf-8")

            loaded = AppConfig.load(str(path))

            self.assertEqual(loaded, AppConfig.default())
            self.assertTrue(path.exists())
            self.assertTrue(Path(f"{path}.broken").exists())

    def test_load_migrates_legacy_fields_to_shared_profile(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "legacy.json"
            path.write_text(
                """
                {
                  "LISTEN_HOST": "0.0.0.0",
                  "LISTEN_PORT": 40444,
                  "CONNECT_IP": "9.9.9.9",
                  "CONNECT_PORT": 8443,
                  "FAKE_SNI": "legacy.example"
                }
                """.strip(),
                encoding="utf-8",
            )
            loaded = AppConfig.load(str(path))

            self.assertEqual(loaded.whitelist_domain, "legacy.example")
            self.assertEqual(loaded.whitelist_ip, "9.9.9.9")
            self.assertEqual(loaded.whitelist_port, 8443)
            self.assertEqual(loaded.connect_ip, "9.9.9.9")
            self.assertEqual(loaded.connect_port, 8443)
            self.assertEqual(loaded.fake_sni, "legacy.example")

    def test_selected_backend_uses_platform_default_when_config_backend_missing(self) -> None:
        base = AppConfig.default()

        with patch("core.config.sys.platform", "win32"):
            self.assertEqual(base.selected_backend(), "windows-pydivert")

        with patch("core.config.sys.platform", "darwin"):
            self.assertEqual(base.selected_backend(), "macos-network-extension")

    def test_selected_backend_normalizes_mismatched_backend_for_current_platform(self) -> None:
        base = AppConfig.default().updated(backend="macos-network-extension")

        with patch("core.config.sys.platform", "win32"):
            self.assertEqual(base.selected_backend(), "windows-pydivert")

        with patch("core.config.sys.platform", "darwin"):
            self.assertEqual(base.selected_backend(), "macos-network-extension")


class ProxyLinkParserTests(unittest.TestCase):
    def test_parse_vless_link(self) -> None:
        profile = parse_proxy_link(
            "vless://uuid@example.net:443?security=tls&type=ws&host=cdn.example.net&sni=edge.example.net&path=%2Fws#EDGE"
        )
        self.assertEqual(profile.protocol, "vless")
        self.assertEqual(profile.server, "example.net")
        self.assertEqual(profile.port, 443)
        self.assertEqual(profile.remark, "EDGE")
        self.assertEqual(profile.host, "cdn.example.net")
        self.assertEqual(profile.sni, "edge.example.net")

    def test_parse_vmess_link(self) -> None:
        vmess_payload = (
            "eyJhZGQiOiJ2bWVzcy5leGFtcGxlLm5ldCIsInBvcnQiOiI0NDMiLCJwcyI6IlZNRVNTIiwibmV0Ijoid3MiLCJ0bHMiOiJ0bHMiLCJob3N0IjoiY2RuLmV4YW1wbGUubmV0Iiwic25pIjoiZWRnZS5leGFtcGxlLm5ldCIsInBhdGgiOiIvd3MifQ=="
        )
        profile = parse_proxy_link(f"vmess://{vmess_payload}")
        self.assertEqual(profile.protocol, "vmess")
        self.assertEqual(profile.server, "vmess.example.net")
        self.assertEqual(profile.port, 443)
        self.assertEqual(profile.network, "ws")

    def test_parse_invalid_link_raises(self) -> None:
        with self.assertRaises(ProxyLinkError):
            parse_proxy_link("http://example.com")

    def test_build_xray_config_for_vless_contains_expected_ports(self) -> None:
        profile = parse_proxy_link(
            "vless://123e4567-e89b-12d3-a456-426614174000@example.net:443?security=tls&type=ws&host=cdn.example.net&sni=edge.example.net&path=%2Fws#EDGE"
        )
        config_text = build_xray_config(
            profile,
            inbound_socks_port=20000,
            inbound_http_port=30000,
            outbound_address="127.0.0.1",
            outbound_port=40444,
            log_level="info",
        )
        self.assertIn('"protocol": "vless"', config_text)
        self.assertIn('"port": 20000', config_text)
        self.assertIn('"port": 30000', config_text)
        self.assertIn('"address": "127.0.0.1"', config_text)


class BackendAvailabilityTests(unittest.TestCase):
    def test_available_backend_names_returns_list(self) -> None:
        self.assertIsInstance(available_backend_names(), list)


class XrayServiceTests(unittest.TestCase):
    def test_executable_path_prefers_environment_variable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            candidate = Path(temp_dir) / "xray.exe"
            candidate.write_text("stub", encoding="utf-8")
            service = XrayService()
            with patch.dict("os.environ", {"XRAY_EXECUTABLE": str(candidate)}, clear=False):
                self.assertEqual(service.executable_path(), str(candidate))


if __name__ == "__main__":
    unittest.main()
