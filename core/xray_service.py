from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


class XrayServiceError(RuntimeError):
    pass


class XrayService:
    def __init__(self) -> None:
        self._process: subprocess.Popen[str] | None = None
        self._config_path: Path | None = None
        self._output_path: Path | None = None

    @property
    def is_running(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def executable_path(self) -> str:
        candidates = [
            os.environ.get("XRAY_EXECUTABLE"),
            str(_app_root() / "resources" / "windows" / "xray.exe"),
            str(_app_root() / "dist" / "SNI-Spoofing" / "resources" / "windows" / "xray.exe"),
            str(_app_root() / "xray.exe"),
            shutil.which("xray.exe"),
            shutil.which("xray"),
        ]
        for candidate in candidates:
            if candidate and os.path.exists(candidate):
                return candidate
        raise XrayServiceError(
            "xray executable peyda نشد. `XRAY_EXECUTABLE` ra set kon ya `resources/windows/xray.exe` ra kenar app gharar بده."
        )

    def start(self, config_text: str) -> None:
        if self.is_running:
            self.stop()

        executable = self.executable_path()
        temp_dir = Path(tempfile.mkdtemp(prefix="sni-xray-"))
        config_path = temp_dir / "config.json"
        output_path = temp_dir / "xray.log"
        config_path.write_text(config_text, encoding="utf-8")
        log_handle = output_path.open("w", encoding="utf-8")
        process = subprocess.Popen(
            [executable, "run", "-c", str(config_path)],
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self._process = process
        self._config_path = config_path
        self._output_path = output_path

        time.sleep(0.6)
        if process.poll() is not None:
            output = self.recent_output_snapshot().strip()
            raise XrayServiceError(output or "Xray exited immediately after launch.")

    def stop(self) -> None:
        process = self._process
        self._process = None
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)

    def recent_output_snapshot(self, max_bytes: int = 8192) -> str:
        if self._output_path is None or not self._output_path.exists():
            return ""
        data = self._output_path.read_bytes()
        return data[-max_bytes:].decode("utf-8", errors="replace")


def _app_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent
