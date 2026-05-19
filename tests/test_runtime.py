from __future__ import annotations

import tempfile
import unittest
from unittest.mock import Mock, patch

from core.config import AppConfig
from core.proxy_links import parse_proxy_link
from core.runtime import AppRuntime


class RuntimeProxyStackTests(unittest.TestCase):
    def _make_runtime(self) -> AppRuntime:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = f"{temp_dir}/config.json"
            config = AppConfig.default().updated(
                proxy_link="vless://123e4567-e89b-12d3-a456-426614174000@example.net:443?security=tls&type=ws&host=cdn.example.net&sni=edge.example.net&path=%2Fws#EDGE"
            )
            config.save(path)
            runtime = AppRuntime(path)
        return runtime

    def test_start_proxy_stack_manual_mode_skips_system_proxy_and_sets_probe(self) -> None:
        runtime = self._make_runtime()
        runtime._config = runtime.config.updated(enable_system_proxy=False)
        runtime._proxy_link_profile = parse_proxy_link(runtime.config.proxy_link)
        runtime._xray_service.start = Mock()
        runtime._system_proxy_manager.enable = Mock()

        with patch.object(runtime, "_wait_for_local_port"), patch("core.runtime.probe_via_local_http_proxy", return_value="https://www.facebook.com/"):
            runtime._start_proxy_stack()

        runtime._xray_service.start.assert_called_once()
        runtime._system_proxy_manager.enable.assert_not_called()
        self.assertEqual(runtime.summary.route_summary, "Manual proxy only | system settings unchanged")
        self.assertEqual(runtime.summary.probe_summary, "https://www.facebook.com/")

    def test_start_proxy_stack_auto_mode_enables_system_proxy(self) -> None:
        runtime = self._make_runtime()
        runtime._config = runtime.config.updated(enable_system_proxy=True)
        runtime._proxy_link_profile = parse_proxy_link(runtime.config.proxy_link)
        runtime._xray_service.start = Mock()
        runtime._system_proxy_manager.enable = Mock(return_value="http=127.0.0.1:30000;https=127.0.0.1:30000;socks=127.0.0.1:20000")

        with patch.object(runtime, "_wait_for_local_port"), patch("core.runtime.probe_via_local_http_proxy", return_value="https://www.facebook.com/"):
            runtime._start_proxy_stack()

        runtime._xray_service.start.assert_called_once()
        runtime._system_proxy_manager.enable.assert_called_once()
        self.assertIn("System proxy | http=127.0.0.1:30000", runtime.summary.route_summary)

    def test_traffic_callback_updates_snapshot(self) -> None:
        runtime = self._make_runtime()
        runtime._consume_traffic_update(128, 256, 2)

        snapshot = runtime.traffic_snapshot
        self.assertEqual(snapshot.bytes_uploaded, 128)
        self.assertEqual(snapshot.bytes_downloaded, 256)
        self.assertEqual(snapshot.active_connections, 2)
        self.assertEqual(snapshot.total_bytes, 384)

    def test_diagnostic_dump_contains_workflow_and_traffic(self) -> None:
        runtime = self._make_runtime()
        runtime._consume_traffic_update(100, 200, 1)
        runtime._emit("info", "sample event")

        dump = runtime.diagnostic_dump()

        self.assertIn("Traffic up: 100", dump)
        self.assertIn("Traffic down: 200", dump)
        self.assertIn("Recent events:", dump)
        self.assertIn("sample event", dump)


if __name__ == "__main__":
    unittest.main()
