import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case persian

    var id: String { rawValue }

    var isRTL: Bool {
        self == .persian
    }

    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .persian:
            return Locale(identifier: "fa_IR")
        }
    }

    func displayName(in uiLanguage: AppLanguage) -> String {
        switch (self, uiLanguage) {
        case (.english, .english):
            return "English"
        case (.english, .persian):
            return "انگلیسی"
        case (.persian, .english):
            return "Persian"
        case (.persian, .persian):
            return "فارسی"
        }
    }

    func subtitle(in uiLanguage: AppLanguage) -> String {
        switch (self, uiLanguage) {
        case (.english, .english):
            return "English | UK"
        case (.english, .persian):
            return "English | بریتانیا"
        case (.persian, .english):
            return "Persian | Iran"
        case (.persian, .persian):
            return "فارسی | ایران"
        }
    }

    var flagEmoji: String {
        switch self {
        case .english:
            return "🇬🇧"
        case .persian:
            return "🇮🇷"
        }
    }

    var flagURL: URL? {
        switch self {
        case .english:
            return URL(string: "https://hatscripts.github.io/circle-flags/flags/uk.svg")
        case .persian:
            return URL(string: "https://hatscripts.github.io/circle-flags/flags/ir.svg")
        }
    }

    var flagResourceName: String {
        switch self {
        case .english:
            return "flag_uk"
        case .persian:
            return "flag_ir"
        }
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    @Published var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "app.language"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        self.selectedLanguage = AppLanguage(rawValue: stored ?? "") ?? .english
    }
}

struct AppCopy {
    let language: AppLanguage

    var appTitle: String {
        switch language {
        case .english:
            return "SNI-Spoofing Client"
        case .persian:
            return "SNI-Spoofing Client"
        }
    }

    var appSubtitle: String {
        switch language {
        case .english:
            return "utility for `Proxy` or `Tunnel` mode with a helper and Xray."
        case .persian:
            return "یک ابزار برای حالت `Proxy` یا `Tunnel` با helper و Xray."
        }
    }

    var connectionTitle: String {
        switch language {
        case .english:
            return "Connection"
        case .persian:
            return "اتصال"
        }
    }

    var connectionSubtitle: String {
        switch language {
        case .english:
            return "Set the allowlist and proxy config, then connect."
        case .persian:
            return "فهرست مجاز و تنظیمات پروکسی را وارد کن و بعد اتصال را بزن."
        }
    }

    var configurationSaved: String {
        language == .english ? "Configuration saved" : "تنظیمات ذخیره شد"
    }

    var configurationLoaded: String {
        language == .english ? "Configuration loaded from System Preferences" : "تنظیمات از تنظیمات سیستم بارگذاری شد"
    }

    var createdNewManager: String {
        language == .english ? "Created a new manager, not saved yet" : "یک مدیر جدید ساخته شد و هنوز ذخیره نشده است"
    }

    var vpnPreferencesReset: String {
        language == .english ? "VPN preferences reset" : "تنظیمات VPN بازنشانی شد"
    }

    var managerNotLoaded: String {
        language == .english ? "Manager is not loaded" : "مدیر بارگذاری نشده است"
    }

    var providerStatusUnknown: String {
        language == .english ? "Provider status unknown" : "وضعیت provider نامشخص است"
    }

    var helperIdle: String {
        language == .english ? "Helper idle" : "helper در حالت بیکار"
    }

    var noEventsRecorded: String {
        language == .english ? "No events recorded yet" : "هنوز رویدادی ثبت نشده است"
    }

    func connectionStatusDescription(_ status: String) -> String {
        switch language {
        case .english:
            return "connection status: \(status)"
        case .persian:
            return "وضعیت اتصال: \(status)"
        }
    }

    var proxyError: String {
        language == .english ? "Proxy error" : "خطای پروکسی"
    }

    var startRequestSent: String {
        language == .english ? "Start request sent" : "درخواست شروع ارسال شد"
    }

    var stopRequestSent: String {
        language == .english ? "Stop request sent" : "درخواست توقف ارسال شد"
    }

    var allowlistDomainPlaceholder: String {
        "hcaptcha.com"
    }

    var allowlistIPPlaceholder: String {
        switch language {
        case .english:
            return "104.19.229.21 or 104.19.229.21:80"
        case .persian:
            return "104.19.229.21 یا 104.19.229.21:80"
        }
    }

    var allowlistDomainTitle: String {
        switch language {
        case .english:
            return "Step 1: Allowlist Domain"
        case .persian:
            return "مرحله 1: دامنه فهرست مجاز"
        }
    }

    var allowlistIPTitle: String {
        switch language {
        case .english:
            return "Step 1: Allowlist IP"
        case .persian:
            return "مرحله 1: IP فهرست مجاز"
        }
    }

    var vlessConfigTitle: String {
        switch language {
        case .english:
            return "Step 2: Proxy Config"
        case .persian:
            return "مرحله 2: تنظیمات پروکسی"
        }
    }

    var detailsTitle: String {
        language == .english ? "Details" : "جزئیات"
    }

    var workflowTitle: String {
        language == .english ? "Workflow" : "جریان کار"
    }

    var hideTitle: String {
        language == .english ? "Hide" : "مخفی"
    }

    var showTitle: String {
        language == .english ? "Show" : "نمایش"
    }

    var workingTitle: String {
        switch language {
        case .english:
            return "Working on the current step..."
        case .persian:
            return "در حال انجام مرحله فعلی..."
        }
    }

    var disconnectTitle: String {
        language == .english ? "Disconnect" : "قطع اتصال"
    }

    var connectTitle: String {
        language == .english ? "Connect" : "اتصال"
    }

    var connectingTitle: String {
        language == .english ? "Connecting..." : "در حال اتصال..."
    }

    var cancelConnectingTitle: String {
        language == .english ? "Cancel Connecting" : "لغو اتصال"
    }

    var cancellingConnectionTitle: String {
        language == .english ? "Cancelling..." : "در حال لغو..."
    }

    var disconnectingTitle: String {
        language == .english ? "Disconnecting..." : "در حال قطع اتصال..."
    }

    var cancellingConnectionHeadline: String {
        language == .english ? "Cancelling Connection" : "در حال لغو اتصال"
    }

    var cancellingConnectionDetail: String {
        language == .english ? "Stopping the connection attempt and cleaning up resources." : "در حال توقف تلاش اتصال و پاک‌سازی منابع."
    }

    var connectionCancelledHeadline: String {
        language == .english ? "Connection Cancelled" : "اتصال لغو شد"
    }

    var connectionCancelledDetail: String {
        language == .english ? "The connection attempt was cancelled." : "تلاش اتصال لغو شد."
    }

    var logsTitle: String {
        language == .english ? "Logs" : "گزارش‌ها"
    }

    var filterPickerLabel: String {
        language == .english ? "Filter" : "فیلتر"
    }

    var modeLabel: String {
        language == .english ? "Mode" : "حالت"
    }

    var connectionLabel: String {
        language == .english ? "Connection" : "اتصال"
    }

    var allowlistLabel: String {
        language == .english ? "Allowlist" : "فهرست مجاز"
    }

    var systemRouteLabel: String {
        language == .english ? "System Route" : "مسیر سیستم"
    }

    var originalServerLabel: String {
        language == .english ? "Original Server" : "سرور اصلی"
    }

    var probeLabel: String {
        language == .english ? "Probe" : "آزمایش"
    }

    var logsHeader: String {
        language == .english ? "Logs" : "گزارش‌ها"
    }

    var logsDescription: String {
        switch language {
        case .english:
            return "Open this only when you need diagnostics."
        case .persian:
            return "فقط وقتی به عیب‌یابی نیاز داری این بخش را باز کن."
        }
    }

    var closeLogsLabel: String {
        language == .english ? "Close Logs" : "بستن گزارش‌ها"
    }

    var copyVisibleLogsLabel: String {
        language == .english ? "Copy Visible Logs" : "کپی گزارش‌های نمایش‌داده‌شده"
    }

    var copyDiagnosticDumpLabel: String {
        language == .english ? "Copy Full Diagnostic Dump" : "کپی خروجی کامل عیب‌یابی"
    }

    var preparingDiagnosticDumpTitle: String {
        language == .english ? "Preparing diagnostic dump..." : "در حال آماده‌سازی گزارش عیب‌یابی..."
    }

    func diagnosticDumpReadyTitle(path: String) -> String {
        switch language {
        case .english:
            return "Diagnostic dump copied. Saved at \(path)"
        case .persian:
            return "گزارش عیب‌یابی کپی شد. مسیر ذخیره: \(path)"
        }
    }

    func diagnosticDumpSavedTitle(path: String) -> String {
        switch language {
        case .english:
            return "Diagnostic dump saved at \(path)"
        case .persian:
            return "گزارش عیب‌یابی در این مسیر ذخیره شد: \(path)"
        }
    }

    var clearLogsLabel: String {
        language == .english ? "Clear Logs" : "پاک کردن گزارش‌ها"
    }

    var noLogsAvailable: String {
        language == .english ? "No logs available." : "هیچ گزارشی موجود نیست."
    }

    var connectionsStatLabel: String {
        language == .english ? "Connections" : "اتصال‌ها"
    }

    var uploadStatLabel: String {
        language == .english ? "Upload" : "آپلود"
    }

    var downloadStatLabel: String {
        language == .english ? "Download" : "دانلود"
    }

    func connectionModeTitle(_ mode: AppConnectionMode) -> String {
        switch (mode, language) {
        case (.proxy, .english):
            return "Proxy"
        case (.proxy, .persian):
            return "پروکسی"
        case (.tunnel, .english):
            return "Tunnel"
        case (.tunnel, .persian):
            return "تونل"
        }
    }

    func workflowSubtitle(count: Int) -> String {
        switch language {
        case .english:
            return "\(count) steps"
        case .persian:
            return "\(count) مرحله"
        }
    }

    func workflowStateTitle(_ state: ConnectionWorkflowStepState) -> String {
        switch (state, language) {
        case (.pending, .english):
            return "Pending"
        case (.pending, .persian):
            return "در انتظار"
        case (.running, .english):
            return "Running"
        case (.running, .persian):
            return "در حال اجرا"
        case (.success, .english):
            return "Success"
        case (.success, .persian):
            return "موفق"
        case (.failure, .english):
            return "Failed"
        case (.failure, .persian):
            return "ناموفق"
        }
    }

    func workflowStepTitle(_ step: ConnectionWorkflowStepKey) -> String {
        switch (step, language) {
        case (.whitelist, .english):
            return "Allowlist"
        case (.whitelist, .persian):
            return "Allowlist"
        case (.vless, .english):
            return "Config"
        case (.vless, .persian):
            return "تنظیمات"
        case (.localProxy, .english):
            return "Local Proxy"
        case (.localProxy, .persian):
            return "پروکسی محلی"
        case (.xray, .english):
            return "Xray Core"
        case (.xray, .persian):
            return "هسته Xray"
        case (.systemProxy, .english):
            return "System Route"
        case (.systemProxy, .persian):
            return "مسیر سیستم"
        case (.probe, .english):
            return "Internet Probe"
        case (.probe, .persian):
            return "آزمایش اینترنت"
        }
    }

    func logFilterTitle(_ filter: String) -> String {
        switch (filter, language) {
        case ("All", .english):
            return "All"
        case ("All", .persian):
            return "همه"
        case ("Info", .english):
            return "Info"
        case ("Info", .persian):
            return "اطلاعات"
        case ("Error", .english):
            return "Error"
        case ("Error", .persian):
            return "خطا"
        case ("Debug", .english):
            return "Debug"
        case ("Debug", .persian):
            return "دیباگ"
        default:
            return filter
        }
    }

    var readyHeadline: String {
        language == .english ? "Ready" : "آماده"
    }

    var validatingHeadline: String {
        language == .english ? "Validating" : "در حال بررسی"
    }

    var startingLocalProxyHeadline: String {
        language == .english ? "Starting Local Proxy" : "در حال شروع پروکسی محلی"
    }

    var startingXrayHeadline: String {
        language == .english ? "Starting Xray" : "در حال شروع Xray"
    }

    var enablingProxyRouteHeadline: String {
        language == .english ? "Enabling Proxy Route" : "فعال‌سازی مسیر پروکسی"
    }

    var startingTunnelHeadline: String {
        language == .english ? "Starting Tunnel Session" : "در حال شروع نشست تونل"
    }

    var proxyConnectedHeadline: String {
        language == .english ? "Proxy Connected" : "پروکسی متصل شد"
    }

    var tunnelConnectedHeadline: String {
        language == .english ? "Tunnel Connected" : "تونل متصل شد"
    }

    var vpnIsOnHeadline: String {
        language == .english ? "VPN Is On" : "VPN روشن است"
    }

    var testingConnectivityHeadline: String {
        language == .english ? "Testing Connectivity" : "در حال آزمایش اتصال"
    }

    func socksProxyUpHeadline(host: String, port: Int) -> String {
        switch language {
        case .english:
            return "SOCKS Proxy Is Up on \(host):\(port)"
        case .persian:
            return "پروکسی SOCKS روی \(host):\(port) آماده است"
        }
    }

    var connectionFailedHeadline: String {
        language == .english ? "Connection Failed" : "اتصال ناموفق بود"
    }

    var disconnectedHeadline: String {
        language == .english ? "Disconnected" : "قطع شد"
    }

    var validatingDetail: String {
        switch language {
        case .english:
            return "Checking the allowlist and proxy config..."
        case .persian:
            return "در حال بررسی allowlist و تنظیمات پروکسی..."
        }
    }

    func startingHelperDetail(host: String, port: Int) -> String {
        switch language {
        case .english:
            return "Starting helper on \(host):\(port)"
        case .persian:
            return "در حال شروع helper روی \(host):\(port)"
        }
    }

    var localProxyStartingDetail: String {
        language == .english ? "The stage-1 spoofing helper is starting." : "helper مرحله اول در حال شروع است."
    }

    func helperStartedDetail(host: String, port: Int) -> String {
        switch language {
        case .english:
            return "Helper started on \(host):\(port)"
        case .persian:
            return "helper روی \(host):\(port) شروع شد"
        }
    }

    var startingXrayDetail: String {
        language == .english ? "Starting Xray with the embedded config" : "در حال شروع Xray با تنظیمات داخلی"
    }

    var xrayConnectingDetail: String {
        switch language {
        case .english:
            return "The proxy config is being converted into the Xray config and connected to the local helper."
        case .persian:
            return "تنظیمات پروکسی در حال تبدیل به تنظیمات Xray و اتصال به helper محلی است."
        }
    }

    func xrayStartedDetail(httpPort: Int, socksPort: Int) -> String {
        switch language {
        case .english:
            return "Xray started | HTTP \(httpPort) | SOCKS \(socksPort)"
        case .persian:
            return "Xray شروع شد | HTTP \(httpPort) | SOCKS \(socksPort)"
        }
    }

    var configuringSystemProxyDetail: String {
        language == .english ? "Configuring the system proxy for active services" : "در حال تنظیم پروکسی سیستم برای سرویس‌های فعال"
    }

    var systemProxyDetail: String {
        language == .english ? "HTTP, HTTPS, and SOCKS proxies are being configured for macOS services." : "پروکسی‌های HTTP، HTTPS و SOCKS برای سرویس‌های macOS در حال تنظیم هستند."
    }

    var startingTunnelDetail: String {
        language == .english ? "Starting a VPN-style tunnel session" : "در حال شروع نشست تونل به سبک VPN"
    }

    var packetTunnelStartingDetail: String {
        language == .english ? "PacketTunnelProvider is starting." : "PacketTunnelProvider در حال شروع است."
    }

    var proxyCompleteDetail: String {
        language == .english ? "The flow is complete. System proxy is active and traffic passes through the local spoof proxy plus embedded Xray." : "فرآیند کامل شد. پروکسی سیستم فعال است و ترافیک از پروکسی محلی و Xray داخلی عبور می‌کند."
    }

    var tunnelCompleteDetail: String {
        language == .english ? "The tunnel session is up. macOS routes traffic through PacketTunnelProvider and embedded Xray." : "نشست تونل بالا آمده است. macOS ترافیک را از طریق PacketTunnelProvider و Xray داخلی مسیردهی می‌کند."
    }

    var proxyProbeDetail: String {
        language == .english ? "Testing internet access through the proxy" : "در حال آزمایش دسترسی اینترنت از طریق پروکسی"
    }

    var tunnelProbeDetail: String {
        language == .english ? "Testing internet access through the tunnel session" : "در حال آزمایش دسترسی اینترنت از طریق نشست تونل"
    }

    var probingProxyDetail: String {
        language == .english ? "Probing traffic through Xray and the spoof proxy..." : "در حال آزمایش ترافیک از طریق Xray و پروکسی spoof..."
    }

    var probingTunnelDetail: String {
        language == .english ? "Probing traffic through PacketTunnelProvider and embedded Xray..." : "در حال آزمایش ترافیک از طریق PacketTunnelProvider و Xray داخلی..."
    }

    var probeFailedDetail: String {
        language == .english ? "The tunnel session is up, but the probe failed. Test the browser manually." : "نشست تونل بالا آمده اما آزمایش ناموفق بود. مرورگر را به‌صورت دستی تست کن."
    }

    var disconnectedDetail: String {
        language == .english ? "The helper, Xray, and system-managed route have stopped." : "helper، Xray و مسیر مدیریت‌شده سیستم متوقف شدند."
    }

    var helperStoppedDetail: String {
        language == .english ? "The helper process did not start." : "فرآیند helper شروع نشد."
    }

    func systemProxyFailedDetail(status: String, providerMessage: String?) -> String {
        let suffix = providerMessage.map { " | providerMessage=\($0)" } ?? ""
        switch language {
        case .english:
            return "The packet tunnel could not connect. status=\(status)\(suffix)"
        case .persian:
            return "تونل بسته نتوانست متصل شود. وضعیت=\(status)\(suffix)"
        }
    }

    var helperPrivilegesTitle: String {
        language == .english ? "Administrator Privileges Required" : "دسترسی مدیر لازم است"
    }

    var helperPrivilegesMessage: String {
        switch language {
        case .english:
            return "SNI-Spoofing Client needs your Mac password to start the proxy. It will be securely cached in memory and won't ask again until you quit."
        case .persian:
            return "SNI-Spoofing Client برای شروع پروکسی به رمز عبور مک شما نیاز دارد. این رمز به‌صورت امن در حافظه نگه داشته می‌شود و تا زمانی که برنامه را ببندی دوباره پرسیده نمی‌شود."
        }
    }

    var helperPrivilegesOK: String {
        language == .english ? "OK" : "تأیید"
    }

    var helperPrivilegesCancel: String {
        language == .english ? "Cancel" : "لغو"
    }

    var helperStartCancelled: String {
        language == .english ? "Authentication cancelled by user." : "احراز هویت توسط کاربر لغو شد."
    }

    var incorrectPassword: String {
        language == .english ? "Incorrect administrator password. Please try again." : "رمز عبور مدیر اشتباه است. لطفاً دوباره تلاش کن."
    }

    var allowlistDomainEmpty: String {
        language == .english ? "Allowlist domain is empty." : "دامنه فهرست مجاز خالی است."
    }

    func invalidAllowlistDomain(_ rawValue: String) -> String {
        switch language {
        case .english:
            return "Invalid allowlist domain: \(rawValue)"
        case .persian:
            return "دامنه فهرست مجاز نامعتبر است: \(rawValue)"
        }
    }

    var allowlistIPEmpty: String {
        language == .english ? "Allowlist IP is empty." : "IP فهرست مجاز خالی است."
    }

    var allowlistPortLabel: String {
        language == .english ? "Allowlist port" : "پورت فهرست مجاز"
    }

    var allowlistIPFormatError: String {
        language == .english ? "Allowlist IP format must be `IP` or `IP:PORT`." : "فرمت IP فهرست مجاز باید `IP` یا `IP:PORT` باشد."
    }

    func portRangeError(_ fieldName: String) -> String {
        switch language {
        case .english:
            return "\(fieldName) must be between 1 and 65535."
        case .persian:
            return "\(fieldName) باید بین 1 تا 65535 باشد."
        }
    }

    var waitingText: String {
        language == .english ? "Waiting" : "در انتظار"
    }

    var vlessParsingDetail: String {
        language == .english ? "Parsing the proxy config" : "در حال تجزیه تنظیمات پروکسی"
    }

    var privilegedHelperRunning: String {
        language == .english ? "Privileged helper running" : "helper با دسترسی مدیر در حال اجرا است"
    }

    func privilegedHelperRunningDescription(pid: Int32) -> String {
        switch language {
        case .english:
            return "Privileged helper running | pid=\(pid)"
        case .persian:
            return "helper با دسترسی مدیر در حال اجرا است | pid=\(pid)"
        }
    }

    var privilegedHelperStopped: String {
        language == .english ? "Privileged helper stopped" : "helper با دسترسی مدیر متوقف شد"
    }

    var helperDidNotStart: String {
        language == .english ? "The helper process did not start." : "فرآیند helper شروع نشد."
    }

    var administratorPrivilegesRequired: String {
        language == .english ? "Administrator Privileges Required" : "دسترسی مدیر لازم است"
    }

    var authenticationCancelled: String {
        language == .english ? "Authentication cancelled by user." : "احراز هویت توسط کاربر لغو شد."
    }

    var incorrectAdministratorPassword: String {
        language == .english ? "Incorrect administrator password. Please try again." : "رمز عبور مدیر اشتباه است. لطفاً دوباره تلاش کن."
    }

    var diagnosticDumpTitle: String {
        language == .english ? "=== SNI-Spoofing Client Diagnostic Dump ===" : "=== خروجی عیب‌یابی SNI-Spoofing Client ==="
    }

    var switchOnTitle: String {
        language == .english ? "ON" : "روشن"
    }

    var switchOffTitle: String {
        language == .english ? "OFF" : "خاموش"
    }
}
