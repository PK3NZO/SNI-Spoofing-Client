from __future__ import annotations

from urllib.error import URLError
from urllib.request import ProxyHandler, build_opener


class ConnectivityProbeError(RuntimeError):
    pass


def probe_via_local_http_proxy(http_port: int) -> str:
    probe_urls = [
        "https://www.facebook.com/",
        "https://www.apple.com/library/test/success.html",
        "https://www.cloudflare.com/cdn-cgi/trace",
    ]
    last_error: Exception | None = None
    proxies = {
        "http": f"http://127.0.0.1:{http_port}",
        "https": f"http://127.0.0.1:{http_port}",
    }
    opener = build_opener(ProxyHandler(proxies))
    for url in probe_urls:
        try:
            with opener.open(url, timeout=12) as response:
                status = getattr(response, "status", 200)
                if 200 <= status < 400:
                    return url
                last_error = ConnectivityProbeError(f"Probe response was not successful for {url}")
        except (URLError, OSError, ConnectivityProbeError) as exc:
            last_error = exc
    raise ConnectivityProbeError(str(last_error or "All probe URLs failed."))
