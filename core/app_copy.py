from __future__ import annotations

from dataclasses import dataclass

from core.models import ConnectionMode, WorkflowStepKey, WorkflowStepState
from core.runtime import RuntimeState


class AppLanguage:
    ENGLISH = "english"
    PERSIAN = "persian"

    @classmethod
    def normalize(cls, value: str) -> str:
        return value if value in {cls.ENGLISH, cls.PERSIAN} else cls.ENGLISH


@dataclass(frozen=True)
class DesktopCopy:
    language: str

    @property
    def is_rtl(self) -> bool:
        return self.language == AppLanguage.PERSIAN

    @property
    def app_title(self) -> str:
        return "SNI-Spoofing Client"

    @property
    def app_subtitle(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "ابزار حالت `Proxy` یا `Tunnel` همراه helper و Xray."
        return "utility for `Proxy` or `Tunnel` mode with a helper and Xray."

    @property
    def ready_headline(self) -> str:
        return "Ready" if self.language == AppLanguage.ENGLISH else "آماده"

    @property
    def ready_detail(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "فهرست مجاز و تنظیمات پروکسی را وارد کن و بعد اتصال را بزن."
        return "Set the allowlist and proxy config, then connect."

    @property
    def connect(self) -> str:
        return "Connect" if self.language == AppLanguage.ENGLISH else "Connect"

    @property
    def disconnect(self) -> str:
        return "Disconnect" if self.language == AppLanguage.ENGLISH else "Disconnect"

    @property
    def save_profile(self) -> str:
        return "Save Profile" if self.language == AppLanguage.ENGLISH else "ذخیره پروفایل"

    @property
    def connection_mode(self) -> str:
        return "Connection Mode" if self.language == AppLanguage.ENGLISH else "حالت اتصال"

    @property
    def proxy(self) -> str:
        return "Proxy" if self.language == AppLanguage.ENGLISH else "Proxy"

    @property
    def tunnel(self) -> str:
        return "Tunnel" if self.language == AppLanguage.ENGLISH else "Tunnel"

    @property
    def connection(self) -> str:
        return "Connection" if self.language == AppLanguage.ENGLISH else "اتصال"

    @property
    def step1_domain(self) -> str:
        return "Step 1: Allowlist Domain" if self.language == AppLanguage.ENGLISH else "مرحله 1: دامنه فهرست مجاز"

    @property
    def step1_ip(self) -> str:
        return "Step 1: Allowlist IP:Port" if self.language == AppLanguage.ENGLISH else "مرحله 1: IP:Port فهرست مجاز"

    @property
    def step2_proxy(self) -> str:
        return "Step 2: Proxy Config" if self.language == AppLanguage.ENGLISH else "مرحله 2: تنظیمات پروکسی"

    @property
    def proxy_link_placeholder(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "این‌جا لینک VLESS یا VMess یا Trojan یا Shadowsocks را وارد کن"
        return "Paste a VLESS, VMess, Trojan, or Shadowsocks link here"

    @property
    def auto_proxy_title(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "تنظیم خودکار پروکسی ویندوز"
        return "Set Windows proxy settings automatically"

    @property
    def auto_proxy_hint(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "اگر خاموش باشد، listener محلی اجرا می‌شود ولی تنظیمات سراسری پروکسی ویندوز دست‌نخورده می‌ماند."
        return "If disabled, the local listener still runs, but Windows system-wide proxy settings stay unchanged."

    @property
    def listen_host(self) -> str:
        return "Listen host" if self.language == AppLanguage.ENGLISH else "Listen host"

    @property
    def listen_port(self) -> str:
        return "Listen port" if self.language == AppLanguage.ENGLISH else "Listen port"

    @property
    def inbound_host(self) -> str:
        return "Proxy listen host" if self.language == AppLanguage.ENGLISH else "آدرس listen پروکسی"

    @property
    def socks_port(self) -> str:
        return "SOCKS5 port" if self.language == AppLanguage.ENGLISH else "پورت SOCKS5"

    @property
    def http_port(self) -> str:
        return "HTTP proxy port" if self.language == AppLanguage.ENGLISH else "پورت پروکسی HTTP"

    @property
    def log_level(self) -> str:
        return "Log level" if self.language == AppLanguage.ENGLISH else "سطح لاگ"

    @property
    def backend(self) -> str:
        return "Backend" if self.language == AppLanguage.ENGLISH else "Backend"

    @property
    def advanced_settings(self) -> str:
        return "Advanced Settings" if self.language == AppLanguage.ENGLISH else "تنظیمات پیشرفته"

    @property
    def details(self) -> str:
        return "Details" if self.language == AppLanguage.ENGLISH else "جزئیات"

    @property
    def workflow(self) -> str:
        return "Workflow" if self.language == AppLanguage.ENGLISH else "فلو"

    @property
    def logs(self) -> str:
        return "Logs" if self.language == AppLanguage.ENGLISH else "لاگ‌ها"

    @property
    def copy_diagnostic_dump(self) -> str:
        return "Copy Diagnostic Dump" if self.language == AppLanguage.ENGLISH else "کپی گزارش عیب‌یابی"

    @property
    def clear_logs(self) -> str:
        return "Clear Logs" if self.language == AppLanguage.ENGLISH else "پاک کردن لاگ‌ها"

    @property
    def runtime_events_placeholder(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "رویدادهای runtime اینجا نمایش داده می‌شوند."
        return "Runtime events will appear here."

    @property
    def download(self) -> str:
        return "Download" if self.language == AppLanguage.ENGLISH else "دانلود"

    @property
    def upload(self) -> str:
        return "Upload" if self.language == AppLanguage.ENGLISH else "آپلود"

    @property
    def total_usage(self) -> str:
        return "Total Usage" if self.language == AppLanguage.ENGLISH else "مصرف کل"

    @property
    def active_connections(self) -> str:
        return "Active Connections" if self.language == AppLanguage.ENGLISH else "اتصال‌های فعال"

    @property
    def show(self) -> str:
        return "Show" if self.language == AppLanguage.ENGLISH else "نمایش"

    @property
    def hide(self) -> str:
        return "Hide" if self.language == AppLanguage.ENGLISH else "بستن"

    @property
    def language_label(self) -> str:
        return "Language" if self.language == AppLanguage.ENGLISH else "زبان"

    def language_name(self, value: str) -> str:
        if value == AppLanguage.PERSIAN:
            return "فارسی" if self.language == AppLanguage.PERSIAN else "Persian"
        return "English" if self.language == AppLanguage.ENGLISH else "انگلیسی"

    def status_headline(self, state: RuntimeState, current: str) -> str:
        if self.language == AppLanguage.ENGLISH:
            return current
        mapping = {
            RuntimeState.STOPPED: "آماده",
            RuntimeState.STARTING: "در حال اتصال",
            RuntimeState.RUNNING: "متصل",
            RuntimeState.STOPPING: "در حال قطع",
            RuntimeState.ERROR: "خطا",
        }
        return mapping.get(state, current)

    def detail_label(self, key: str) -> str:
        mapping = {
            "Mode": "Mode" if self.language == AppLanguage.ENGLISH else "حالت",
            "Connection": "Connection" if self.language == AppLanguage.ENGLISH else "اتصال",
            "Allowlist": "Allowlist" if self.language == AppLanguage.ENGLISH else "فهرست مجاز",
            "System Route": "System Route" if self.language == AppLanguage.ENGLISH else "مسیر سیستم",
            "Original Server": "Original Server" if self.language == AppLanguage.ENGLISH else "سرور اصلی",
            "Probe": "Probe" if self.language == AppLanguage.ENGLISH else "پروب",
        }
        return mapping[key]

    def workflow_title(self, key: WorkflowStepKey, fallback: str) -> str:
        if self.language == AppLanguage.ENGLISH:
            return fallback
        mapping = {
            WorkflowStepKey.WHITELIST: "فهرست مجاز",
            WorkflowStepKey.PROXY_CONFIG: "تنظیمات پروکسی",
            WorkflowStepKey.LOCAL_PROXY: "پروکسی محلی",
            WorkflowStepKey.XRAY: "Xray",
            WorkflowStepKey.SYSTEM_ROUTE: "مسیر سیستم",
            WorkflowStepKey.PROBE: "پروب اینترنت",
        }
        return mapping.get(key, fallback)

    def workflow_state(self, state: WorkflowStepState) -> str:
        if self.language == AppLanguage.ENGLISH:
            return state.value.capitalize()
        mapping = {
            WorkflowStepState.PENDING: "در انتظار",
            WorkflowStepState.RUNNING: "در حال اجرا",
            WorkflowStepState.SUCCESS: "موفق",
            WorkflowStepState.FAILURE: "ناموفق",
            WorkflowStepState.SKIPPED: "رد شد",
        }
        return mapping[state]

    def mode_title(self, mode: str) -> str:
        return self.proxy if mode == ConnectionMode.PROXY.value else self.tunnel

    def workflow_subtitle(self, count: int) -> str:
        if self.language == AppLanguage.PERSIAN:
            return f"{count} مرحله"
        return f"{count} steps"

    @property
    def configuration_saved(self) -> str:
        return "Configuration saved." if self.language == AppLanguage.ENGLISH else "تنظیمات ذخیره شد."

    @property
    def start_requested(self) -> str:
        return "Start requested." if self.language == AppLanguage.ENGLISH else "درخواست اتصال ارسال شد."

    @property
    def stop_requested(self) -> str:
        return "Stop requested." if self.language == AppLanguage.ENGLISH else "درخواست قطع ارسال شد."

    @property
    def diagnostic_dump_copied(self) -> str:
        if self.language == AppLanguage.PERSIAN:
            return "گزارش عیب‌یابی در clipboard کپی شد."
        return "Diagnostic dump copied to clipboard."

    @property
    def logs_cleared(self) -> str:
        return "Logs cleared." if self.language == AppLanguage.ENGLISH else "لاگ‌ها پاک شدند."
