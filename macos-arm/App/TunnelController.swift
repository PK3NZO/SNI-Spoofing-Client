import Foundation
import NetworkExtension
import AppKit
import Darwin

struct ProxyLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: ProxyLogLevel
    let source: String
    let message: String
}

enum ConnectionWorkflowStepKey: String, CaseIterable, Identifiable {
    case whitelist = "Whitelist"
    case vless = "VLESS"
    case localProxy = "Local Proxy"
    case xray = "Xray Core"
    case systemProxy = "System Route"
    case probe = "Internet Probe"

    var id: String { rawValue }
}

enum ConnectionWorkflowStepState: String, Equatable {
    case pending
    case running
    case success
    case failure
}

struct ConnectionWorkflowStep: Identifiable, Equatable {
    let key: ConnectionWorkflowStepKey
    var state: ConnectionWorkflowStepState
    var detail: String

    var id: String { key.id }
}

private struct ConnectionDraft {
    let whitelistDomain: String
    let whitelistIP: String
    let whitelistPort: Int
    let vless: VlessConfig
}

private struct ActiveConnectionContext {
    let mode: AppConnectionMode
    let systemProxyEnabled: Bool
    let localProxyPort: Int
    let socksPort: Int
    let httpPort: Int
    let networkServices: [String]
    let whitelistDomain: String
    let whitelistIP: String
    let whitelistPort: Int
    let vless: VlessConfig
    let connectedAt: Date
}

private struct DNSServiceSnapshot {
    let service: String
    let servers: [String]?
}

private struct DNSConfigurationSnapshot {
    let services: [DNSServiceSnapshot]
}

private struct ConnectionResourceState {
    var mode: AppConnectionMode
    var helperStarted = false
    var xrayStarted = false
    var systemProxyEnabled = false
    var tunnelStarted = false
    var dnsApplied = false
}

private enum ConnectionWorkflowError: LocalizedError {
    case validation(String)
    case localProxy(String)
    case xray(String)
    case systemProxy(String)
    case connectivityProbe(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message):
            return "Validation failed: \(message)"
        case let .localProxy(message):
            return "Local proxy failed: \(message)"
        case let .xray(message):
            return "Xray failed: \(message)"
        case let .systemProxy(message):
            return "System proxy failed: \(message)"
        case let .connectivityProbe(message):
            return "Connectivity check failed: \(message)"
        }
    }
}

@MainActor
final class TunnelController: ObservableObject {
    private static let connectivityProbeURLs = [
        URL(string: "https://www.facebook.com/"),
        URL(string: "https://www.apple.com/library/test/success.html"),
        URL(string: "https://www.cloudflare.com/cdn-cgi/trace"),
    ].compactMap { $0 }
    private static let systemProxyPreferenceKey = "app.proxy.enableSystemProxy"

    enum ConnectionOperationState {
        case idle
        case connecting
        case cancellingConnect
        case disconnecting
    }

    struct DiagnosticDumpArtifact {
        let text: String
        let fileURL: URL
    }

    @Published var configuration: TunnelConfiguration = .defaults
    @Published var selectedConnectionMode: AppConnectionMode = .proxy
    @Published var enableSystemProxyInProxyMode: Bool = true {
        didSet {
            UserDefaults.standard.set(enableSystemProxyInProxyMode, forKey: Self.systemProxyPreferenceKey)
        }
    }
    @Published var whitelistDomainInput = ""
    @Published var whitelistIPInput = ""
    @Published var vlessConfigInput = ""
    @Published var workflowSteps = TunnelController.makeDefaultWorkflowSteps()
    @Published var connectionHeadline = AppCopy(language: AppLanguageStore.shared.selectedLanguage).readyHeadline
    @Published var connectionDetail = AppCopy(language: AppLanguageStore.shared.selectedLanguage).connectionSubtitle
    @Published var isConnected = false
    @Published var activeConnectionSummary = "-"
    @Published var activeProxySummary = "-"
    @Published var lastProbeDescription = "-"
    @Published var originalServerSummary = "-"
    @Published var routeManagerSummary = "-"
    @Published var managerStatusDescription = AppCopy(language: AppLanguageStore.shared.selectedLanguage).managerNotLoaded
    @Published var providerStatusDescription = AppCopy(language: AppLanguageStore.shared.selectedLanguage).providerStatusUnknown
    @Published var proxyStatusDescription = AppCopy(language: AppLanguageStore.shared.selectedLanguage).helperIdle
    @Published var proxyPhase = "idle"
    @Published var proxyConnectionCount = 0
    @Published var proxyBytesUploaded = 0
    @Published var proxyBytesDownloaded = 0
    @Published var proxyTotalBytes = 0
    @Published var proxyUploadSpeed = 0
    @Published var proxyDownloadSpeed = 0
    @Published var proxyInterfaceDescription = "-"
    @Published var proxyLastDetail = AppCopy(language: AppLanguageStore.shared.selectedLanguage).noEventsRecorded
    @Published var helperStateDescription = AppCopy(language: AppLanguageStore.shared.selectedLanguage).privilegedHelperStopped
    @Published var helperLogEntries: [ProxyLogEntry] = []
    @Published var helperLogPathDescription = "-"
    @Published var lastErrorDescription = ""
    @Published var isBusy = false
    @Published private(set) var connectionOperation: ConnectionOperationState = .idle
    @Published var isPrivilegedHelperRunning = false

    private let xrayManager = XrayManager.shared
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private lazy var localProxyService = LocalProxyService { [weak self] status in
        Task { @MainActor in
            self?.consumeNativeStatus(status, source: "embedded")
        }
    }
    private var helperLogTimer: Timer?
    private var helperLogOffset: UInt64 = 0
    private var helperLogRemainder = Data()
    private let maxLogEntries = 240
    private var activeConnectionContext: ActiveConnectionContext?
    private var activeDNSConfigurationSnapshot: DNSConfigurationSnapshot?
    private var connectionWorkflowTask: Task<Void, Never>?
    
    private var lastSpeedUpdate = Date()
    private var lastTrafficUpdate = Date()
    private var lastBytesUploaded = 0
    private var lastBytesDownloaded = 0
    private var hasSpeedBaseline = false
    private var pendingUploadedBytes = 0
    private var pendingDownloadedBytes = 0
    private var smoothedUploadSpeed = 0.0
    private var smoothedDownloadSpeed = 0.0
    private var copy: AppCopy {
        AppCopy(language: AppLanguageStore.shared.selectedLanguage)
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.systemProxyPreferenceKey) != nil {
            enableSystemProxyInProxyMode = UserDefaults.standard.bool(forKey: Self.systemProxyPreferenceKey)
        }
        helperLogPathDescription = Self.helperLogURL.path
        resetLogStateForFreshStart() // Ensure we start with a clean log view
        refreshHelperState()
        startHelperLogPolling()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bestEffortShutdownForTermination()
            }
        }
        Task {
            await reloadManager()
        }
        refreshLocalizedPresentation()
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        helperLogTimer?.invalidate()
    }

    func reloadManager() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let managers = try await Self.loadManagedManagers()
            appendLog(level: .debug, source: "provider", message: "Reload managers | matched=\(managers.count)")
            if let existing = managers.first {
                manager = existing
                applyManagerConfiguration(existing)
                managerStatusDescription = copy.configurationLoaded
                if managers.count > 1 {
                    try? await Self.removeManagers(Array(managers.dropFirst()))
                    appendLog(level: .info, source: "provider", message: "Duplicate VPN profiles cleaned up")
                }
            } else {
                let freshManager = NETunnelProviderManager()
                manager = freshManager
                managerStatusDescription = copy.createdNewManager
            }
            installStatusObserver()
            updateConnectionStatus()
            lastErrorDescription = ""
        } catch {
            fail("Failed to reload manager: \(error.localizedDescription)")
        }
    }

    func saveConfiguration() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let preparedManager = try await prepareManagerForUse()
            try await Self.saveManager(preparedManager)
            try await Self.loadManager(preparedManager)
            manager = preparedManager
            applyManagerConfiguration(preparedManager)
            installStatusObserver()
            updateConnectionStatus()
            try writeHelperConfiguration()
            providerStatusDescription = copy.configurationSaved
            appendLog(level: .info, source: "app", message: "Configuration saved")
            lastErrorDescription = ""
        } catch {
            fail("Failed to save configuration: \(error.localizedDescription)")
        }
    }

    func startTunnel() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let preparedManager = try await prepareManagerForUse()
            try await Self.saveManager(preparedManager)
            try await Self.loadManager(preparedManager)
            manager = preparedManager
            installStatusObserver()
            try (preparedManager.connection as? NETunnelProviderSession)?.startVPNTunnel()
            updateConnectionStatus()
            providerStatusDescription = copy.startRequestSent
            appendLog(level: .info, source: "provider", message: "Tunnel start request sent")
            lastErrorDescription = ""
        } catch {
            fail("Failed to start tunnel: \(error.localizedDescription)")
        }
    }

    func stopTunnel() {
        guard let manager else {
            fail(copy.managerNotLoaded)
            return
        }

        manager.connection.stopVPNTunnel()
        updateConnectionStatus()
        providerStatusDescription = copy.stopRequestSent
        appendLog(level: .info, source: "provider", message: "Tunnel stop request sent")
        lastErrorDescription = ""
    }

    func refreshProviderStatus() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let session = try requireSession()
            let responseData = try await Self.sendMessage(
                TunnelAppMessage(command: .getStatus),
                using: session
            )
            let status = try TunnelIPC.decode(TunnelProviderStatus.self, from: responseData)
            providerStatusDescription = Self.describeProviderStatus(status)
            consumeTunnelStatus(status, source: "provider")
            appendLog(level: .info, source: "provider", message: "Provider status refreshed")
            lastErrorDescription = ""
        } catch {
            fail("Failed to refresh provider status: \(error.localizedDescription)")
        }
    }

    func reloadProviderConfiguration() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let session = try requireSession()
            let responseData = try await Self.sendMessage(
                TunnelAppMessage(command: .reloadConfiguration),
                using: session
            )
            let status = try TunnelIPC.decode(TunnelProviderStatus.self, from: responseData)
            providerStatusDescription = Self.describeProviderStatus(status)
            consumeTunnelStatus(status, source: "provider")
            appendLog(level: .info, source: "provider", message: "Provider configuration reloaded")
            lastErrorDescription = ""
        } catch {
            fail("Failed to reload provider configuration: \(error.localizedDescription)")
        }
    }

    func startProxy() {
        Task { await startPrivilegedHelper() }
    }

    func stopProxy() {
        Task { await stopPrivilegedHelper() }
    }

    func startEmbeddedProxy() {
        do {
            try localProxyService.start(configuration: configuration)
            appendLog(level: .info, source: "embedded", message: "Embedded proxy started")
            lastErrorDescription = ""
        } catch {
            fail("Failed to start embedded proxy: \(error.localizedDescription)")
        }
    }

    func stopEmbeddedProxy() {
        localProxyService.stop()
        appendLog(level: .info, source: "embedded", message: "Embedded proxy stopped")
    }

    func startPrivilegedHelper() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await startPrivilegedHelperInternal()
            lastErrorDescription = ""
        } catch {
            fail("Failed to start helper: \(error.localizedDescription)")
        }
    }

    func stopPrivilegedHelper() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await stopPrivilegedHelperInternal()
            appendLog(level: .info, source: "app", message: copy.stopRequestSent)
            lastErrorDescription = ""
        } catch {
            refreshHelperState()
            if !isPrivilegedHelperRunning {
                clearProxyRuntimeState(detail: copy.privilegedHelperStopped)
                appendLog(level: .info, source: "app", message: copy.privilegedHelperStopped)
                lastErrorDescription = ""
            } else {
                fail("Failed to stop helper: \(error.localizedDescription)")
            }
        }
    }

    func connectEmbeddedFlow() {
        guard !isBusy, connectionWorkflowTask == nil else { return }
        isBusy = true
        connectionOperation = .connecting
        let task = Task { [weak self] in
            guard let self else { return }
            await performEmbeddedConnection()
        }
        connectionWorkflowTask = task
    }

    func disconnectEmbeddedFlow() {
        guard !isBusy else { return }
        isBusy = true
        connectionOperation = .disconnecting
        Task {
            await disconnectWorkflow(preserveStatusMessage: false)
        }
    }

    func cancelConnectAttempt() {
        guard connectionOperation == .connecting, let connectionWorkflowTask else { return }
        connectionOperation = .cancellingConnect
        connectionHeadline = copy.cancellingConnectionHeadline
        connectionDetail = copy.cancellingConnectionDetail
        lastErrorDescription = ""
        appendLog(level: .info, source: "app", message: "Connection cancel requested")
        connectionWorkflowTask.cancel()
    }

    private func performEmbeddedConnection() async {
        isBusy = true
        defer {
            isBusy = false
            connectionWorkflowTask = nil
            connectionOperation = .idle
        }

        let connectionMode = selectedConnectionMode
        lastErrorDescription = ""
        connectionHeadline = copy.validatingHeadline
        connectionDetail = copy.validatingDetail
        workflowSteps = Self.makeDefaultWorkflowSteps()
        activeConnectionSummary = "-"
        activeProxySummary = "-"
        lastProbeDescription = "-"
        originalServerSummary = "-"
        routeManagerSummary = "-"
        var startedResources = ConnectionResourceState(mode: connectionMode)

        do {
            if isConnected || isPrivilegedHelperRunning || xrayManager.isRunning {
                try await disconnectWorkflowResources()
            }
            try Task.checkCancellation()

            let draft = try validateConnectionDraft()
            updateWorkflowStep(.whitelist, state: .success, detail: "\(draft.whitelistDomain) -> \(draft.whitelistIP):\(draft.whitelistPort)")
            updateWorkflowStep(.vless, state: .success, detail: "\(draft.vless.remark) | \(draft.vless.network.uppercased())/\(draft.vless.security.uppercased())")
            let dnsServers = try await Self.discoverDNSServers()
            try Task.checkCancellation()

            let localProxyPort = try Self.reserveAvailableLocalTCPPort()
            let socksPort = TunnelConfiguration.fixedSocksProxyPort
            let httpPort = TunnelConfiguration.fixedHTTPProxyPort

            configuration = TunnelConfiguration(
                listenHost: "127.0.0.1",
                listenPort: localProxyPort,
                connectIP: draft.whitelistIP,
                connectPort: draft.whitelistPort,
                upstreamIP: "127.0.0.1",
                upstreamPort: localProxyPort,
                fakeSNI: draft.whitelistDomain,
                logLevel: configuration.logLevel,
                connectionMode: connectionMode,
                httpProxyPort: httpPort,
                socksProxyPort: socksPort,
                dnsServers: dnsServers,
                excludedIPv4Addresses: connectionMode == .tunnel ? [draft.whitelistIP] : []
            )
            activeConnectionSummary = "\(copy.connectionModeTitle(connectionMode)): \(draft.whitelistDomain) -> \(draft.whitelistIP):\(draft.whitelistPort)"
            activeProxySummary = "Local \(configuration.listenHost):\(localProxyPort) | SOCKS 127.0.0.1:\(socksPort) | HTTP 127.0.0.1:\(httpPort)"
            originalServerSummary = "\(draft.vless.originalAddress):\(draft.vless.originalPort) | \(draft.vless.remark)"
            let dnsSummary = dnsServers.isEmpty ? "none" : dnsServers.joined(separator: ",")
            appendLog(level: .debug, source: "provider", message: "Discovered DNS servers | \(dnsSummary)")

            updateWorkflowStep(.xray, state: .running, detail: "Starting Xray with the embedded config")
            connectionHeadline = copy.startingXrayHeadline
            connectionDetail = copy.xrayConnectingDetail
            do {
                try await xrayManager.ensureXrayInstalled()
                let xrayOutboundAddress = configuration.listenHost
                let xrayOutboundPort = configuration.listenPort
                let xrayConfig = try draft.vless.generateXrayConfig(
                    inboundSocksPort: socksPort,
                    inboundHttpPort: httpPort,
                    outboundAddress: xrayOutboundAddress,
                    outboundPort: xrayOutboundPort,
                    logLevel: configuration.logLevel
                )
                appendLog(
                    level: .debug,
                    source: "xray",
                    message: "Xray config prepared | mode=\(connectionMode.rawValue) | outbound=\(xrayOutboundAddress):\(xrayOutboundPort) | original=\(draft.vless.originalAddress):\(draft.vless.originalPort) | spoofTarget=\(draft.whitelistIP):\(draft.whitelistPort) | network=\(draft.vless.network) | security=\(draft.vless.security) | sni=\(draft.vless.sni) | host=\(draft.vless.host) | path=\(draft.vless.path) | logLevel=\(configuration.logLevel.rawValue)"
                )
                try await xrayManager.start(configString: xrayConfig)
            } catch {
                let xrayOutput = xrayManager.recentOutputSnapshot().trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = xrayOutput.isEmpty ? error.localizedDescription : xrayOutput
                throw ConnectionWorkflowError.xray(detail)
            }
            startedResources.xrayStarted = true
            try Task.checkCancellation()
            appendLog(level: .info, source: "xray", message: "Embedded Xray started | socks=127.0.0.1:\(socksPort) | http=127.0.0.1:\(httpPort)")
            updateWorkflowStep(.xray, state: .success, detail: copy.xrayStartedDetail(httpPort: httpPort, socksPort: socksPort))

            updateWorkflowStep(.localProxy, state: .running, detail: "Starting helper on \(configuration.listenHost):\(localProxyPort)")
            connectionHeadline = copy.startingLocalProxyHeadline
            connectionDetail = copy.localProxyStartingDetail
            do {
                try await startPrivilegedHelperInternal()
                startedResources.helperStarted = true
                try await waitForHelperReadiness()
            } catch {
                throw ConnectionWorkflowError.localProxy(error.localizedDescription)
            }
            try Task.checkCancellation()
            updateWorkflowStep(.localProxy, state: .success, detail: copy.helperStartedDetail(host: configuration.listenHost, port: localProxyPort))

            let routeContext: [String]
            switch connectionMode {
            case .proxy:
                if enableSystemProxyInProxyMode {
                    updateWorkflowStep(.systemProxy, state: .running, detail: copy.configuringSystemProxyDetail)
                    connectionHeadline = copy.enablingProxyRouteHeadline
                    connectionDetail = copy.systemProxyDetail
                    routeContext = try await enableSystemProxy(httpPort: httpPort, socksPort: socksPort)
                    startedResources.systemProxyEnabled = true
                    routeManagerSummary = "System proxy | \(routeContext.joined(separator: ", "))"
                    updateWorkflowStep(.systemProxy, state: .success, detail: routeContext.joined(separator: ", "))
                } else {
                    routeContext = []
                    routeManagerSummary = copy.manualProxyRouteSummary
                    updateWorkflowStep(.systemProxy, state: .success, detail: copy.systemProxySkippedDetail)
                }
            case .tunnel:
                updateWorkflowStep(.systemProxy, state: .running, detail: "Starting a VPN-style tunnel session")
                connectionHeadline = copy.startingTunnelHeadline
                connectionDetail = copy.packetTunnelStartingDetail
                let providerStatus = try await startManagedTunnelSession()
                startedResources.tunnelStarted = true
                try Task.checkCancellation()
                if !configuration.dnsServers.isEmpty {
                    do {
                        let dnsSnapshot = try await applySystemDNSServers(configuration.dnsServers)
                        activeDNSConfigurationSnapshot = dnsSnapshot
                        startedResources.dnsApplied = true
                        appendLog(level: .info, source: "system", message: "System DNS enabled for tunnel: \(configuration.dnsServers.joined(separator: ", "))")
                    } catch {
                        appendLog(level: .error, source: "system", message: "Failed to apply system DNS for tunnel: \(error.localizedDescription)")
                    }
                }
                routeContext = []
                routeManagerSummary = "Packet tunnel | \(providerStatus.phase)"
                providerStatusDescription = Self.describeProviderStatus(providerStatus)
                consumeTunnelStatus(providerStatus, source: "provider")
                updateWorkflowStep(.systemProxy, state: .success, detail: providerStatus.detail ?? "Tunnel session connected")
            }
            try Task.checkCancellation()

            activeConnectionContext = ActiveConnectionContext(
                mode: connectionMode,
                systemProxyEnabled: connectionMode == .proxy ? enableSystemProxyInProxyMode : false,
                localProxyPort: localProxyPort,
                socksPort: socksPort,
                httpPort: httpPort,
                networkServices: routeContext,
                whitelistDomain: draft.whitelistDomain,
                whitelistIP: draft.whitelistIP,
                whitelistPort: draft.whitelistPort,
                vless: draft.vless,
                connectedAt: Date()
            )
            isConnected = true
            applyConnectedStatusPresentation(
                for: connectionMode,
                socksPort: socksPort,
                isProbeRunning: false,
                systemProxyEnabled: connectionMode == .proxy ? enableSystemProxyInProxyMode : nil
            )

            updateWorkflowStep(
                .probe,
                state: .running,
                detail: connectionMode == .proxy
                    ? copy.proxyProbeDetail
                    : copy.tunnelProbeDetail
            )
            applyConnectedStatusPresentation(
                for: connectionMode,
                socksPort: socksPort,
                isProbeRunning: true,
                systemProxyEnabled: connectionMode == .proxy ? enableSystemProxyInProxyMode : nil
            )
            let reachableURL = try await runConnectivityProbe(httpPort: httpPort, mode: connectionMode)
            lastProbeDescription = reachableURL.absoluteString
            updateWorkflowStep(.probe, state: .success, detail: "Probe success: \(reachableURL.host ?? reachableURL.absoluteString)")
            applyConnectedStatusPresentation(
                for: connectionMode,
                socksPort: socksPort,
                isProbeRunning: false,
                systemProxyEnabled: connectionMode == .proxy ? enableSystemProxyInProxyMode : nil
            )
            appendLog(level: .info, source: "app", message: "Connection workflow completed successfully")
        } catch is CancellationError {
            workflowSteps = Self.makeDefaultWorkflowSteps()
            connectionHeadline = copy.connectionCancelledHeadline
            connectionDetail = copy.connectionCancelledDetail
            lastErrorDescription = ""
            appendLog(level: .info, source: "app", message: "Connection workflow cancelled")
            try? await disconnectWorkflowResources(cleanupState: startedResources)
            isConnected = false
        } catch {
            let description = error.localizedDescription
            if connectionMode == .tunnel, case ConnectionWorkflowError.connectivityProbe = error {
                lastProbeDescription = description
                updateWorkflowStep(.probe, state: .failure, detail: description)
                connectionHeadline = copy.vpnIsOnHeadline
                connectionDetail = copy.probeFailedDetail
                appendLog(level: .error, source: "probe", message: description)
                appendLog(level: .info, source: "app", message: "Tunnel kept alive despite probe failure")
                return
            }
            if selectedConnectionMode == .tunnel {
                let snapshot = xrayManager.recentOutputSnapshot().trimmingCharacters(in: .whitespacesAndNewlines)
                if !snapshot.isEmpty {
                    appendLog(level: .debug, source: "xray", message: "Xray output snapshot | \(snapshot.prefix(4000))")
                }
                if let manager {
                    appendLog(level: .debug, source: "provider", message: Self.describeManager(manager, label: "tunnel-failure-state"))
                }
            }
            recordWorkflowFailure(error, description: description)
            lastErrorDescription = description
            connectionHeadline = copy.connectionFailedHeadline
            connectionDetail = description
            appendLog(level: .error, source: "app", message: description)
            try? await disconnectWorkflowResources(cleanupState: startedResources)
            isConnected = false
        }
    }

    private func disconnectWorkflow(preserveStatusMessage: Bool) async {
        isBusy = true
        defer {
            isBusy = false
            connectionOperation = .idle
        }

        do {
            try await disconnectWorkflowResources()
            if !preserveStatusMessage {
                workflowSteps = Self.makeDefaultWorkflowSteps()
                connectionHeadline = copy.disconnectedHeadline
                connectionDetail = copy.disconnectedDetail
                lastErrorDescription = ""
            }
            appendLog(level: .info, source: "app", message: "Connection workflow stopped")
        } catch {
            fail("Failed to disconnect cleanly: \(error.localizedDescription)")
        }
    }

    private func validateConnectionDraft() throws -> ConnectionDraft {
        do {
            updateWorkflowStep(.whitelist, state: .running, detail: copy.validatingDetail)
            let whitelistDomain = try Self.normalizeDomain(whitelistDomainInput)
            let endpoint = try Self.parseWhitelistEndpoint(whitelistIPInput)

            updateWorkflowStep(.vless, state: .running, detail: copy.vlessParsingDetail)
            let vless = try VlessParser.parse(uri: vlessConfigInput)
            return ConnectionDraft(
                whitelistDomain: whitelistDomain,
                whitelistIP: endpoint.ip,
                whitelistPort: endpoint.port,
                vless: vless
            )
        } catch {
            throw ConnectionWorkflowError.validation(error.localizedDescription)
        }
    }

    private func startPrivilegedHelperInternal() async throws {
        resetLogStateForFreshStart()
        try writeHelperConfiguration()
        try await Self.runPrivilegedShell(helperStartCommand())
        isPrivilegedHelperRunning = true
        helperStateDescription = copy.privilegedHelperRunning
        appendLog(level: .info, source: "app", message: "Helper start request sent")
        startHelperLogPolling()
    }

    private func stopPrivilegedHelperInternal() async throws {
        try await Self.runPrivilegedShell(helperStopCommand())
        isPrivilegedHelperRunning = false
        helperStateDescription = copy.privilegedHelperStopped
        clearProxyRuntimeState(detail: "Helper stopped")
    }

    private func clearProxyRuntimeState(detail: String) {
        proxyPhase = "stopped"
        proxyConnectionCount = 0
        proxyUploadSpeed = 0
        proxyDownloadSpeed = 0
        proxyBytesUploaded = 0
        proxyBytesDownloaded = 0
        proxyLastDetail = detail
        proxyStatusDescription = detail
        proxyInterfaceDescription = "-"
        lastBytesUploaded = 0
        lastBytesDownloaded = 0
        hasSpeedBaseline = false
        pendingUploadedBytes = 0
        pendingDownloadedBytes = 0
        smoothedUploadSpeed = 0
        smoothedDownloadSpeed = 0
        lastSpeedUpdate = Date()
        lastTrafficUpdate = Date()
    }

    private func waitForHelperReadiness(timeout: TimeInterval = 6) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            refreshHelperState()
            consumeHelperLogUpdates()

            if !isPrivilegedHelperRunning {
                let excerpt = latestHelperLogExcerpt()
                throw ConnectionWorkflowError.localProxy(
                    excerpt.isEmpty ? copy.helperDidNotStart : excerpt
                )
            }

            if helperLogEntries.contains(where: { $0.message.contains("Helper is ready") }) || proxyPhase == "running" || proxyPhase == "starting" {
                return
            }

            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let excerpt = latestHelperLogExcerpt()
        throw ConnectionWorkflowError.localProxy(
            excerpt.isEmpty ? "Timed out waiting for helper readiness." : excerpt
        )
    }

    private func latestHelperLogExcerpt() -> String {
        helperLogEntries.suffix(6).map(\.message).joined(separator: " | ")
    }

    private func updateWorkflowStep(_ key: ConnectionWorkflowStepKey, state: ConnectionWorkflowStepState, detail: String) {
        if let index = workflowSteps.firstIndex(where: { $0.key == key }) {
            workflowSteps[index].state = state
            workflowSteps[index].detail = detail
        }
    }

    private func recordWorkflowFailure(_ error: Error, description: String) {
        if error is VlessParserError {
            updateWorkflowStep(.vless, state: .failure, detail: description)
            return
        }

        if let workflowError = error as? ConnectionWorkflowError {
            switch workflowError {
            case .validation:
                updateWorkflowStep(.whitelist, state: .failure, detail: description)
            case .localProxy:
                updateWorkflowStep(.localProxy, state: .failure, detail: description)
            case .xray:
                updateWorkflowStep(.xray, state: .failure, detail: description)
            case .systemProxy:
                updateWorkflowStep(.systemProxy, state: .failure, detail: description)
            case .connectivityProbe:
                updateWorkflowStep(.probe, state: .failure, detail: description)
            }
            return
        }

        for index in workflowSteps.indices where workflowSteps[index].state == .running {
            workflowSteps[index].state = .failure
            workflowSteps[index].detail = description
        }
    }

    private func startManagedTunnelSession() async throws -> TunnelProviderStatus {
        do {
            return try await startManagedTunnelSessionAttempt(allowManagerResetRetry: true)
        } catch {
            appendLog(level: .error, source: "provider", message: "Tunnel startup failed | \(Self.debugDescription(for: error))")
            throw ConnectionWorkflowError.systemProxy(Self.describeTunnelStartupError(error))
        }
    }

    private func startManagedTunnelSessionAttempt(allowManagerResetRetry: Bool) async throws -> TunnelProviderStatus {
        appendLog(level: .debug, source: "provider", message: "Preparing NETunnelProviderManager | retryAllowed=\(allowManagerResetRetry)")
        let preparedManager = try await prepareManagerForUse()
        appendLog(level: .debug, source: "provider", message: Self.describeManager(preparedManager, label: "before-save"))
        try await Self.saveManager(preparedManager)
        appendLog(level: .debug, source: "provider", message: "Manager saveToPreferences completed")
        try await Self.loadManager(preparedManager)
        appendLog(level: .debug, source: "provider", message: "Manager loadFromPreferences completed")
        manager = preparedManager
        applyManagerConfiguration(preparedManager)
        installStatusObserver()
        appendLog(level: .debug, source: "provider", message: Self.describeManager(preparedManager, label: "after-load"))

        if preparedManager.connection.status == .connected || preparedManager.connection.status == .connecting {
            appendLog(level: .info, source: "provider", message: "Existing tunnel status=\(Self.describeConnectionStatus(preparedManager.connection.status)); stopping before restart")
            preparedManager.connection.stopVPNTunnel()
            try await waitForTunnelDisconnect(on: preparedManager, timeout: 5)
        }

        guard let session = preparedManager.connection as? NETunnelProviderSession else {
            throw TunnelControllerError.invalidSession
        }

        do {
            appendLog(level: .info, source: "provider", message: "Calling startVPNTunnel | bundle=\(TunnelConfiguration.providerBundleIdentifier)")
            try session.startVPNTunnel()
            appendLog(level: .debug, source: "provider", message: "startVPNTunnel returned without throwing")
            updateConnectionStatus()
            let status = try await waitForTunnelConnection(on: preparedManager, timeout: 12)
            appendLog(level: .info, source: "provider", message: "Tunnel session connected")
            return status
        } catch {
            appendLog(level: .error, source: "provider", message: "startVPNTunnel/wait failed | \(Self.debugDescription(for: error))")
            if allowManagerResetRetry, Self.shouldRetryTunnelStartupAfterManagerReset(error) {
                appendLog(level: .info, source: "provider", message: "Resetting stale VPN manager and retrying tunnel startup once")
                try await resetManagedPreferences()
                return try await startManagedTunnelSessionAttempt(allowManagerResetRetry: false)
            }
            throw error
        }
    }

    private func stopManagedTunnelIfNeeded() async throws {
        guard let manager else {
            return
        }

        let status = manager.connection.status
        guard status == .connected || status == .connecting || status == .reasserting || status == .disconnecting else {
            return
        }

        manager.connection.stopVPNTunnel()
        try await waitForTunnelDisconnect(on: manager, timeout: 8)
        providerStatusDescription = "Tunnel stopped"
        appendLog(level: .info, source: "provider", message: "Tunnel session stopped")
    }

    private func waitForTunnelConnection(on manager: NETunnelProviderManager, timeout: TimeInterval) async throws -> TunnelProviderStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var lastObservedStatus = manager.connection.status
        var lastProviderFetchError: Error?
        var sawTransitionalOrConnectedState = false
        let disconnectedGraceDeadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            updateConnectionStatus()
            let currentStatus = manager.connection.status
            if currentStatus != lastObservedStatus {
                appendLog(level: .debug, source: "provider", message: "Tunnel status changed -> \(Self.describeConnectionStatus(currentStatus))")
                lastObservedStatus = currentStatus
            }

            switch currentStatus {
            case .connected:
                sawTransitionalOrConnectedState = true
                do {
                    let status = try await fetchProviderStatus()
                    appendLog(level: .debug, source: "provider", message: "Provider status fetched | \(Self.describeProviderStatus(status))")
                    return status
                } catch {
                    lastProviderFetchError = error
                    appendLog(level: .debug, source: "provider", message: "Provider status fetch failed | \(Self.debugDescription(for: error))")
                }
            case .connecting, .reasserting, .disconnecting:
                sawTransitionalOrConnectedState = true
            case .invalid, .disconnected:
                if !sawTransitionalOrConnectedState && Date() < disconnectedGraceDeadline {
                    break
                }
                let providerErrorSuffix: String
                if let lastProviderFetchError {
                    providerErrorSuffix = " | providerMessage=\(Self.debugDescription(for: lastProviderFetchError))"
                } else {
                    providerErrorSuffix = ""
                }
                throw ConnectionWorkflowError.systemProxy("The packet tunnel could not connect. status=\(Self.describeConnectionStatus(currentStatus))\(providerErrorSuffix)")
            default:
                break
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        let timeoutSuffix: String
        if let lastProviderFetchError {
            timeoutSuffix = " | providerMessage=\(Self.debugDescription(for: lastProviderFetchError))"
        } else {
            timeoutSuffix = ""
        }
        throw ConnectionWorkflowError.systemProxy("Timed out waiting for packet tunnel connection. lastStatus=\(Self.describeConnectionStatus(lastObservedStatus))\(timeoutSuffix)")
    }

    private func waitForTunnelDisconnect(on manager: NETunnelProviderManager, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            updateConnectionStatus()
            let status = manager.connection.status
            if status == .disconnected || status == .invalid {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ConnectionWorkflowError.systemProxy("Timed out waiting for packet tunnel stop.")
    }

    private func fetchProviderStatus() async throws -> TunnelProviderStatus {
        let session = try requireSession()
        let responseData = try await Self.sendMessage(
            TunnelAppMessage(command: .getStatus),
            using: session
        )
        return try TunnelIPC.decode(TunnelProviderStatus.self, from: responseData)
    }

    private func enableSystemProxy(httpPort: Int, socksPort: Int) async throws -> [String] {
        let services = try await Self.listActiveNetworkServices()
        guard !services.isEmpty else {
            throw ConnectionWorkflowError.systemProxy("No active macOS network service was found.")
        }

        let commands = services.flatMap { service in
            [
                "/usr/sbin/networksetup -setproxybypassdomains \(Self.shellQuote(service)) localhost 127.0.0.1 ::1",
                "/usr/sbin/networksetup -setwebproxy \(Self.shellQuote(service)) 127.0.0.1 \(httpPort)",
                "/usr/sbin/networksetup -setsecurewebproxy \(Self.shellQuote(service)) 127.0.0.1 \(httpPort)",
                "/usr/sbin/networksetup -setsocksfirewallproxy \(Self.shellQuote(service)) 127.0.0.1 \(socksPort)",
                "/usr/sbin/networksetup -setwebproxystate \(Self.shellQuote(service)) on",
                "/usr/sbin/networksetup -setsecurewebproxystate \(Self.shellQuote(service)) on",
                "/usr/sbin/networksetup -setsocksfirewallproxystate \(Self.shellQuote(service)) on",
            ]
        }
        do {
            try await Self.runPrivilegedShell(commands.joined(separator: "; "))
        } catch {
            throw ConnectionWorkflowError.systemProxy(error.localizedDescription)
        }
        appendLog(level: .info, source: "system", message: "System proxy enabled for: \(services.joined(separator: ", "))")
        return services
    }

    private func disableSystemProxy() async throws {
        let services = try await Self.listActiveNetworkServices()
        guard !services.isEmpty else {
            return
        }

        let commands = services.flatMap { service in
            [
                "/usr/sbin/networksetup -setwebproxystate \(Self.shellQuote(service)) off",
                "/usr/sbin/networksetup -setsecurewebproxystate \(Self.shellQuote(service)) off",
                "/usr/sbin/networksetup -setsocksfirewallproxystate \(Self.shellQuote(service)) off",
            ]
        }
        try await Self.runPrivilegedShell(commands.joined(separator: "; "))
        appendLog(level: .info, source: "system", message: "System proxy disabled")
    }

    private func runConnectivityProbe(httpPort: Int, mode: AppConnectionMode) async throws -> URL {
        if mode == .tunnel {
            appendLog(level: .debug, source: "probe", message: "Tunnel probe warmup started")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        let attempts = mode == .tunnel ? 2 : 1
        var lastError: Error?
        for attempt in 1 ... attempts {
            for url in Self.connectivityProbeURLs {
                do {
                    try await Self.probe(url: url, httpPort: httpPort, mode: mode)
                    appendLog(level: .info, source: "probe", message: "Connectivity probe succeeded: \(url.absoluteString)")
                    return url
                } catch {
                    lastError = error
                    appendLog(level: .debug, source: "probe", message: "Probe attempt \(attempt) failed for \(url.absoluteString): \(error.localizedDescription)")
                }
            }

            if attempt < attempts {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        throw ConnectionWorkflowError.connectivityProbe(lastError?.localizedDescription ?? "All probe URLs failed.")
    }

    private func shouldSurfaceProxyError(
        detail: String,
        activeConnections: Int,
        bytesUploaded: Int,
        bytesDownloaded: Int,
        phase: String
    ) -> Bool {
        let normalized = detail.lowercased()
        let isTransientBypassTimeout = normalized.contains("timed out waiting for ack of fake payload")
        let hasHealthyTraffic = phase == "running" && (activeConnections > 0 || bytesUploaded > 0 || bytesDownloaded > 0)
        return !(isTransientBypassTimeout && hasHealthyTraffic)
    }

    private func clearTransientProxyErrorIfHealthy(
        activeConnections: Int,
        bytesUploaded: Int,
        bytesDownloaded: Int,
        phase: String
    ) {
        let hasHealthyTraffic = phase == "running" && (activeConnections > 0 || bytesUploaded > 0 || bytesDownloaded > 0)
        guard hasHealthyTraffic else { return }

        let normalized = lastErrorDescription.lowercased()
        if normalized.contains("bypass handshake failed") || normalized.contains("timed out waiting for ack of fake payload") {
            lastErrorDescription = ""
        }
    }

    private func disconnectWorkflowResources(cleanupState: ConnectionResourceState? = nil) async throws {
        var failures: [String] = []
        let cleanupMode = cleanupState?.mode ?? activeConnectionContext?.mode ?? selectedConnectionMode
        let shouldStopTunnel = cleanupState?.tunnelStarted ?? (manager?.connection.status == .connected || manager?.connection.status == .connecting || manager?.connection.status == .reasserting || manager?.connection.status == .disconnecting)
        let shouldDisableProxy = cleanupState?.systemProxyEnabled ?? (cleanupMode == .proxy && activeConnectionContext?.systemProxyEnabled == true)
        let shouldRestoreDNS = cleanupState?.dnsApplied ?? (cleanupMode == .tunnel && activeDNSConfigurationSnapshot != nil)
        let shouldStopXray = cleanupState?.xrayStarted ?? xrayManager.isRunning
        let shouldStopHelper = cleanupState?.helperStarted ?? isPrivilegedHelperRunning

        if shouldStopTunnel {
            do {
                try await stopManagedTunnelIfNeeded()
            } catch {
                failures.append("tunnel: \(error.localizedDescription)")
            }
        }

        if cleanupMode == .proxy, shouldDisableProxy {
            do {
                try await disableSystemProxy()
            } catch {
                failures.append("system proxy: \(error.localizedDescription)")
            }
        } else if cleanupMode == .tunnel, shouldRestoreDNS {
            do {
                try await restoreSystemDNSIfNeeded()
            } catch {
                failures.append("system dns: \(error.localizedDescription)")
            }
        }

        if shouldStopXray {
            xrayManager.stop()
        }

        if shouldStopHelper {
            do {
                try await stopPrivilegedHelperInternal()
            } catch {
                failures.append("helper: \(error.localizedDescription)")
            }
        } else {
            clearProxyRuntimeState(detail: "Helper stopped")
        }

        activeConnectionContext = nil
        isConnected = false
        activeConnectionSummary = "-"
        activeProxySummary = "-"
        lastProbeDescription = "-"
        originalServerSummary = "-"
        routeManagerSummary = "-"

        if !failures.isEmpty {
            throw NSError(
                domain: "TunnelController",
                code: 91,
                userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: " | ")]
            )
        }
    }

    private func bestEffortShutdownForTermination() {
        if isConnected || isPrivilegedHelperRunning || xrayManager.isRunning {
            manager?.connection.stopVPNTunnel()
            if (activeConnectionContext?.mode ?? selectedConnectionMode) == .proxy {
                Task { [weak self] in
                    try? await self?.disableSystemProxy()
                }
            } else if (activeConnectionContext?.mode ?? selectedConnectionMode) == .tunnel {
                Task { [weak self] in
                    try? await self?.restoreSystemDNSIfNeeded()
                }
            }
            xrayManager.stop()
            Task { [weak self] in
                try? await self?.stopPrivilegedHelperInternal()
            }
        }
    }

    func clearLogs() {
        helperLogEntries.removeAll()
        helperLogOffset = 0
        helperLogRemainder = Data()
        try? FileManager.default.removeItem(at: Self.helperLogURL)
        appendLog(level: .info, source: "app", message: "Local logs cleared")
    }

    func saveHelperConfigOnly() {
        do {
            try writeHelperConfiguration()
            appendLog(level: .info, source: "app", message: "Helper configuration written to disk")
            lastErrorDescription = ""
        } catch {
            fail("Failed to save helper configuration: \(error.localizedDescription)")
        }
    }

    func persistHelperConfigurationSilently() {
        do {
            try writeHelperConfiguration()
            lastErrorDescription = ""
        } catch {
            fail("Failed to update configuration: \(error.localizedDescription)")
        }
    }

    func applyLogLevelChangeImmediately() async {
        do {
            try writeHelperConfiguration()
            guard isPrivilegedHelperRunning else {
                lastErrorDescription = ""
                return
            }

            do {
                try await Self.runPrivilegedShell(helperRestartCommand())
                isPrivilegedHelperRunning = true
                helperStateDescription = copy.privilegedHelperRunning
                appendLog(level: .info, source: "app", message: "Log level updated")
                lastErrorDescription = ""
            } catch {
                fail("Failed to apply log level change: \(error.localizedDescription)")
            }
        } catch {
            fail("Failed to apply log level change: \(error.localizedDescription)")
        }
    }

    func refreshLocalizedPresentation() {
        if !isBusy && !isConnected {
            connectionHeadline = copy.readyHeadline
            connectionDetail = copy.connectionSubtitle
        }

        if isConnected, let context = activeConnectionContext {
            applyConnectedStatusPresentation(for: context.mode, socksPort: context.socksPort, isProbeRunning: false)
        }

        if manager == nil {
            managerStatusDescription = copy.managerNotLoaded
        }

        if !isPrivilegedHelperRunning {
            helperStateDescription = copy.privilegedHelperStopped
        }

        if proxyPhase == "idle" || proxyPhase == "stopped" {
            proxyStatusDescription = copy.helperIdle
            if proxyLastDetail == "-" || proxyLastDetail == copy.noEventsRecorded {
                proxyLastDetail = copy.noEventsRecorded
            }
        }

        if !isConnected && !isBusy {
            providerStatusDescription = copy.providerStatusUnknown
        }
    }

    var localEndpointDescription: String {
        "\(configuration.listenHost):\(configuration.listenPort)"
    }

    var upstreamDescription: String {
        "\(configuration.connectIP):\(configuration.connectPort)"
    }

    var selectedLogLevelDescription: String {
        configuration.logLevel.rawValue.uppercased()
    }

    private func applyConnectedStatusPresentation(for mode: AppConnectionMode, socksPort: Int? = nil, isProbeRunning: Bool, systemProxyEnabled: Bool? = nil) {
        switch mode {
        case .proxy:
            let resolvedPort = socksPort ?? activeConnectionContext?.socksPort ?? configuration.socksProxyPort
            let proxyIsSystemWide = systemProxyEnabled ?? activeConnectionContext?.systemProxyEnabled ?? false
            if let resolvedPort {
                connectionHeadline = copy.socksProxyUpHeadline(host: "127.0.0.1", port: resolvedPort)
            } else {
                connectionHeadline = copy.proxyConnectedHeadline
            }
            connectionDetail = isProbeRunning
                ? copy.probingProxyDetail
                : (proxyIsSystemWide ? copy.proxyCompleteDetail : copy.manualProxyCompleteDetail)
        case .tunnel:
            connectionHeadline = copy.vpnIsOnHeadline
            connectionDetail = isProbeRunning ? copy.probingTunnelDetail : copy.tunnelCompleteDetail
        }
    }

    private func prepareManagerForUse() async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = TunnelConfiguration.providerBundleIdentifier
        tunnelProtocol.serverAddress = configuration.connectIP
        tunnelProtocol.providerConfiguration = configuration.providerConfigurationDictionary()

        manager.localizedDescription = "SNI-Spoofing Client"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        return manager
    }

    private func resetManagedPreferences() async throws {
        let managers = try await Self.loadManagedManagers()
        if !managers.isEmpty {
            appendLog(level: .debug, source: "provider", message: "Removing managed VPN profiles | count=\(managers.count)")
            try await Self.removeManagers(managers)
        }
        manager = NETunnelProviderManager()
        managerStatusDescription = copy.vpnPreferencesReset
    }

    private func applyManagerConfiguration(_ manager: NETunnelProviderManager) {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return
        }

        configuration = TunnelConfiguration(providerConfiguration: tunnelProtocol.providerConfiguration)
        selectedConnectionMode = .proxy
    }

    private func requireSession() throws -> NETunnelProviderSession {
        guard let manager else {
            throw TunnelControllerError.managerUnavailable
        }
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw TunnelControllerError.invalidSession
        }
        return session
    }

    private func installStatusObserver() {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if let manager = self?.manager {
                    self?.appendLog(level: .debug, source: "provider", message: "NEVPNStatusDidChange | \(Self.describeConnectionStatus(manager.connection.status))")
                }
                self?.updateConnectionStatus()
            }
        }
    }

    private func updateConnectionStatus() {
        guard let manager else {
            managerStatusDescription = copy.managerNotLoaded
            return
        }

        managerStatusDescription = copy.connectionStatusDescription(Self.describeConnectionStatus(manager.connection.status))
    }

    private func consumeNativeStatus(_ status: NativeProxyStatus, source: String) {
        proxyPhase = status.phase
        proxyConnectionCount = status.activeConnections
        updateSpeeds(up: status.bytesUploaded, down: status.bytesDownloaded)
        proxyInterfaceDescription = status.interfaceName.flatMap { name in
            status.interfaceIPv4.map { "\(name)(\($0))" }
        } ?? "-"
        proxyLastDetail = status.detail ?? "-"
        proxyStatusDescription = Self.describeNativeProxyStatus(status)
        if status.logLevel == .error {
            let detail = status.detail ?? copy.proxyError
            if shouldSurfaceProxyError(
                detail: detail,
                activeConnections: status.activeConnections,
                bytesUploaded: status.bytesUploaded,
                bytesDownloaded: status.bytesDownloaded,
                phase: status.phase
            ) {
                lastErrorDescription = detail
            }
        } else {
            clearTransientProxyErrorIfHealthy(
                activeConnections: status.activeConnections,
                bytesUploaded: status.bytesUploaded,
                bytesDownloaded: status.bytesDownloaded,
                phase: status.phase
            )
        }
        appendLog(level: status.logLevel, source: source, message: Self.describeNativeProxyStatus(status))
    }

    private func consumeTunnelStatus(_ status: TunnelProviderStatus, source: String) {
        providerStatusDescription = Self.describeProviderStatus(status)
        updateSpeeds(up: status.bytesUploaded, down: status.bytesDownloaded)
        appendLog(level: .debug, source: source, message: Self.describeProviderStatus(status))
    }

    func noteDiagnosticDumpCopied(byteCount: Int, path: String) {
        appendLog(level: .info, source: "app", message: "Diagnostic dump copied to clipboard | bytes=\(byteCount) | path=\(path)")
    }

    func noteDiagnosticDumpCopyFailed(path: String) {
        appendLog(level: .error, source: "app", message: "Failed to copy diagnostic dump to clipboard | saved=\(path)")
    }

    func noteVisibleLogsCopied() {
        appendLog(level: .info, source: "app", message: "Visible logs copied to clipboard")
    }

    func noteVisibleLogsCopyFailed() {
        appendLog(level: .error, source: "app", message: "Failed to copy visible logs to clipboard")
    }

    func failDiagnosticDumpPreparation(_ description: String) {
        appendLog(level: .error, source: "app", message: "Diagnostic dump preparation failed | \(description)")
    }

    func prepareDiagnosticDumpArtifact() async throws -> DiagnosticDumpArtifact {
        let text = await diagnosticDump()
        try FileManager.default.createDirectory(
            at: Self.helperSupportDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = Self.diagnosticDumpURL
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return DiagnosticDumpArtifact(text: text, fileURL: fileURL)
    }

    private func startHelperLogPolling() {
        helperLogTimer?.invalidate()
        helperLogTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollHelperLogs()
            }
        }
        helperLogTimer?.tolerance = 0.2
        pollHelperLogs()
    }

    private func pollHelperLogs() {
        refreshHelperState()
        consumeHelperLogUpdates()
    }

    private func refreshHelperState() {
        helperLogPathDescription = Self.helperLogURL.path
        guard
            let pidText = try? String(contentsOf: Self.helperPIDURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(pidText),
            pid > 0
        else {
            if !isPrivilegedHelperRunning {
                helperStateDescription = copy.privilegedHelperStopped
            }
            return
        }

        let result = Darwin.kill(pid, 0)
        if result == 0 || errno == EPERM {
            isPrivilegedHelperRunning = true
            helperStateDescription = copy.privilegedHelperRunningDescription(pid: pid)
        } else {
            isPrivilegedHelperRunning = false
            helperStateDescription = copy.privilegedHelperStopped
        }
    }

    private func consumeHelperLogUpdates() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.helperLogURL.path) else {
            return
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: Self.helperLogURL.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            if size < helperLogOffset {
                helperLogOffset = 0
                helperLogRemainder = Data()
            }

            let handle = try FileHandle(forReadingFrom: Self.helperLogURL)
            defer {
                try? handle.close()
            }

            try handle.seek(toOffset: helperLogOffset)
            let freshData = try handle.readToEnd() ?? Data()
            guard !freshData.isEmpty else {
                return
            }
            helperLogOffset += UInt64(freshData.count)

            var combined = helperLogRemainder
            combined.append(freshData)
            let newline = Data([0x0a])
            let chunks = combined.split(separator: newline[0], omittingEmptySubsequences: false)
            let endsWithNewline = combined.last == newline[0]
            helperLogRemainder = Data()

            for (index, rawChunk) in chunks.enumerated() {
                if index == chunks.count - 1, !endsWithNewline {
                    helperLogRemainder = Data(rawChunk)
                    continue
                }
                guard let line = String(data: rawChunk, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !line.isEmpty
                else {
                    continue
                }
                consumeHelperLogLine(line)
            }
        } catch {
            fail("Failed to read helper log: \(error.localizedDescription)")
        }
    }

    private func consumeHelperLogLine(_ line: String) {
        let level = Self.extractLevel(from: line)
        let normalizedMessage = line.replacingOccurrences(of: "[\(level.rawValue)] ", with: "")
        appendLog(level: level, source: "helper", message: normalizedMessage)

        guard line.contains("[proxy]") else {
            return
        }

        if let phase = Self.extractValue(for: "phase", in: line) {
            proxyPhase = phase
        }
        if let connectionsText = Self.extractValue(for: "connections", in: line),
           let connections = Int(connectionsText) {
            proxyConnectionCount = connections
        }
        if let upText = Self.extractValue(for: "bytesUp", in: line), let up = Int(upText),
           let downText = Self.extractValue(for: "bytesDown", in: line), let down = Int(downText) {
            updateSpeeds(up: up, down: down)
        }
        if let interface = Self.extractValue(for: "iface", in: line) {
            proxyInterfaceDescription = interface
        }
        if let detail = Self.extractDetail(in: line) {
            proxyLastDetail = detail
            proxyStatusDescription = detail
            if level == .error {
                if shouldSurfaceProxyError(
                    detail: detail,
                    activeConnections: proxyConnectionCount,
                    bytesUploaded: proxyBytesUploaded,
                    bytesDownloaded: proxyBytesDownloaded,
                    phase: proxyPhase
                ) {
                    lastErrorDescription = detail
                }
            }
        } else {
            proxyStatusDescription = line
        }

        if level != .error {
            clearTransientProxyErrorIfHealthy(
                activeConnections: proxyConnectionCount,
                bytesUploaded: proxyBytesUploaded,
                bytesDownloaded: proxyBytesDownloaded,
                phase: proxyPhase
            )
        }

        if proxyPhase == "stopped" {
            isPrivilegedHelperRunning = false
            helperStateDescription = copy.privilegedHelperStopped
        } else if isPrivilegedHelperRunning {
            helperStateDescription = copy.privilegedHelperRunning
        }
    }

    private func appendLog(level: ProxyLogLevel, source: String, message: String) {
        helperLogEntries.append(
            ProxyLogEntry(
                timestamp: Date(),
                level: level,
                source: source,
                message: message
            )
        )
        if helperLogEntries.count > maxLogEntries {
            helperLogEntries.removeFirst(helperLogEntries.count - maxLogEntries)
        }
    }

    func diagnosticDump() async -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let logFormatter = DateFormatter()
        logFormatter.dateStyle = .none
        logFormatter.timeStyle = .medium

        var lines: [String] = []
        lines.append("=== SNI-Spoofing Client Diagnostic Dump ===")
        lines.append("Generated at: \(formatter.string(from: Date()))")
        lines.append("Mode: \(copy.connectionModeTitle(selectedConnectionMode))")
        lines.append("Proxy auto-config enabled: \(enableSystemProxyInProxyMode)")
        lines.append("Headline: \(connectionHeadline)")
        lines.append("Detail: \(connectionDetail)")
        lines.append("Connected: \(isConnected)")
        lines.append("Busy: \(isBusy)")
        lines.append("Helper running: \(isPrivilegedHelperRunning)")
        lines.append("Helper state: \(helperStateDescription)")
        lines.append("Manager status: \(managerStatusDescription)")
        lines.append("Provider status: \(providerStatusDescription)")
        lines.append("Proxy status: \(proxyStatusDescription)")
        lines.append("Proxy phase: \(proxyPhase)")
        lines.append("Proxy connections: \(proxyConnectionCount)")
        lines.append("Proxy bytes up: \(proxyBytesUploaded)")
        lines.append("Proxy bytes down: \(proxyBytesDownloaded)")
        lines.append("Proxy interface: \(proxyInterfaceDescription)")
        lines.append("Proxy detail: \(proxyLastDetail)")
        lines.append("Last probe: \(lastProbeDescription)")
        lines.append("Original server: \(originalServerSummary)")
        lines.append("Route manager: \(routeManagerSummary)")
        lines.append("Active connection summary: \(activeConnectionSummary)")
        lines.append("Active proxy summary: \(activeProxySummary)")
        lines.append("Allowlist domain input: \(whitelistDomainInput)")
        lines.append("Allowlist IP input: \(whitelistIPInput)")
        lines.append("Config input: \(vlessConfigInput)")
        lines.append("Log level: \(configuration.logLevel.rawValue)")
        lines.append("Configuration:")
        lines.append("  listenHost=\(configuration.listenHost)")
        lines.append("  listenPort=\(configuration.listenPort)")
        lines.append("  connectIP=\(configuration.connectIP)")
        lines.append("  connectPort=\(configuration.connectPort)")
        lines.append("  upstreamIP=\(configuration.upstreamIP)")
        lines.append("  upstreamPort=\(configuration.upstreamPort)")
        lines.append("  fakeSNI=\(configuration.fakeSNI)")
        lines.append("  connectionMode=\(configuration.connectionMode.rawValue)")
        lines.append("  httpProxyPort=\(configuration.httpProxyPort.map(String.init) ?? "-")")
        lines.append("  socksProxyPort=\(configuration.socksProxyPort.map(String.init) ?? "-")")
        lines.append("  dnsServers=\(configuration.dnsServers.isEmpty ? "none" : configuration.dnsServers.joined(separator: ","))")
        lines.append("  excludedIPv4Addresses=\(configuration.excludedIPv4Addresses.isEmpty ? "none" : configuration.excludedIPv4Addresses.joined(separator: ","))")

        if let context = activeConnectionContext {
            lines.append("Active context:")
            lines.append("  mode=\(context.mode.rawValue)")
            lines.append("  localProxyPort=\(context.localProxyPort)")
            lines.append("  socksPort=\(context.socksPort)")
            lines.append("  httpPort=\(context.httpPort)")
            lines.append("  services=\(context.networkServices.joined(separator: ","))")
            lines.append("  whitelist=\(context.whitelistDomain) -> \(context.whitelistIP):\(context.whitelistPort)")
            lines.append("  vlessRemark=\(context.vless.remark)")
            lines.append("  vlessTarget=\(context.vless.originalAddress):\(context.vless.originalPort)")
            lines.append("  connectedAt=\(formatter.string(from: context.connectedAt))")
        }

        lines.append("Workflow steps:")
        for step in workflowSteps {
            lines.append("  - \(step.key.rawValue) [\(step.state.rawValue)]: \(step.detail)")
        }

        lines.append("Recent app logs (last 500):")
        for entry in helperLogEntries.suffix(500) {
            lines.append("  [\(entry.level.rawValue.uppercased())] \(logFormatter.string(from: entry.timestamp)) [\(entry.source)] \(entry.message)")
        }

        let xraySnapshot = xrayManager.recentOutputSnapshot().trimmingCharacters(in: .whitespacesAndNewlines)
        async let helperLogTailTask: String? = try? await Self.runProcess(
            launchPath: "/usr/bin/tail",
            arguments: ["-n", "50", Self.helperLogURL.path],
            timeout: 2
        )
        async let psSnapshotTask: String? = try? await Self.runProcess(
            launchPath: "/bin/ps",
            arguments: ["aux", "-c"],
            timeout: 2
        )
        async let proxySnapshotTask: String? = try? await Self.runProcess(
            launchPath: "/usr/sbin/scutil",
            arguments: ["--proxy"],
            timeout: 3
        )
        async let dnsSnapshotTask: String? = try? await Self.runProcess(
            launchPath: "/usr/sbin/scutil",
            arguments: ["--dns"],
            timeout: 3
        )

        lines.append("Xray snapshot (last 8KB):")
        lines.append(xraySnapshot.isEmpty ? "  (empty)" : "  \(xraySnapshot.replacingOccurrences(of: "\n", with: "\n  "))")

        let helperLogPath = Self.helperLogURL.path
        lines.append("Helper log path: \(helperLogPath)")
        
        lines.append("Raw Helper log tail (last 50 lines):")
        if let logTail = await helperLogTailTask {
             lines.append(logTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "  (empty)" : "  \(logTail.replacingOccurrences(of: "\n", with: "\n  "))")
        } else {
             lines.append("  (failed to read log file)")
        }

        lines.append("Process status:")
        if let psHelper = await psSnapshotTask {
            let helperLines = psHelper.split(separator: "\n").filter { $0.contains("helper") || $0.contains("xray") }
            lines.append(helperLines.isEmpty ? "  (no helper/xray found in ps)" : "  \(helperLines.joined(separator: "\n  "))")
        }

        lines.append("scutil --proxy:")
        if let proxySnapshot = await proxySnapshotTask {
            lines.append(proxySnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "  (empty)" : "  \(proxySnapshot.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "\n  "))")
        } else {
            lines.append("  (failed)")
        }
        lines.append("System DNS snapshot:")
        if let snapshot = activeDNSConfigurationSnapshot {
            let rendered = snapshot.services.map { service in
                if let servers = service.servers, !servers.isEmpty {
                    return "\(service.service)=\(servers.joined(separator: ","))"
                }
                return "\(service.service)=Empty"
            }
            lines.append(rendered.isEmpty ? "  (empty)" : "  \(rendered.joined(separator: " | "))")
        } else {
            lines.append("  (none)")
        }
        lines.append("scutil --dns (first 120 lines):")
        if let dnsSnapshot = await dnsSnapshotTask {
            let compact = dnsSnapshot
                .split(whereSeparator: \.isNewline)
                .prefix(120)
                .joined(separator: "\n")
            lines.append(compact.isEmpty ? "  (empty)" : "  \(compact.replacingOccurrences(of: "\n", with: "\n  "))")
        } else {
            lines.append("  (failed)")
        }
        lines.append("=== End Diagnostic Dump ===")
        return lines.joined(separator: "\n")
    }

    private func writeHelperConfiguration() throws {
        guard FileManager.default.fileExists(atPath: Self.helperBinaryURL.path) else {
            throw TunnelControllerError.helperBinaryMissing(Self.helperBinaryURL.path)
        }

        try FileManager.default.createDirectory(
            at: Self.helperSupportDirectoryURL,
            withIntermediateDirectories: true
        )

        let rawConfig: [String: Any] = [
            "LISTEN_HOST": configuration.listenHost,
            "LISTEN_PORT": configuration.listenPort,
            "CONNECT_IP": configuration.connectIP,
            "CONNECT_PORT": configuration.connectPort,
            "FAKE_SNI": configuration.fakeSNI,
            "LOG_LEVEL": configuration.logLevel.rawValue,
            "BACKEND": NSNull(),
        ]
        let data = try JSONSerialization.data(withJSONObject: rawConfig, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.helperConfigURL, options: .atomic)
    }

    private func resetLogStateForFreshStart() {
        helperLogEntries.removeAll()
        helperLogOffset = 0
        helperLogRemainder = Data()
        try? FileManager.default.removeItem(at: Self.helperLogURL)
    }

    private func helperStartCommand() -> String {
        [
            "mkdir -p \(Self.shellQuote(Self.helperSupportDirectoryURL.path))",
            ": > \(Self.shellQuote(Self.helperLogURL.path))",
            "if [ -f \(Self.shellQuote(Self.helperPIDURL.path)) ] && kill -0 \"$(cat \(Self.shellQuote(Self.helperPIDURL.path)))\" 2>/dev/null; then exit 0; fi",
            "\(Self.shellQuote(Self.helperBinaryURL.path)) --config \(Self.shellQuote(Self.helperConfigURL.path)) >> \(Self.shellQuote(Self.helperLogURL.path)) 2>&1 < /dev/null & echo $! > \(Self.shellQuote(Self.helperPIDURL.path))",
        ].joined(separator: "; ")
    }

    private func helperStopCommand() -> String {
        [
            "if [ -f \(Self.shellQuote(Self.helperPIDURL.path)) ]; then pid=\"$(cat \(Self.shellQuote(Self.helperPIDURL.path)))\"; kill -TERM \"$pid\" 2>/dev/null || true; for _ in 1 2 3 4 5; do kill -0 \"$pid\" 2>/dev/null || break; sleep 0.2; done; kill -KILL \"$pid\" 2>/dev/null || true; rm -f \(Self.shellQuote(Self.helperPIDURL.path)); fi",
            "pkill -TERM -f \(Self.shellQuote("\(Self.helperBinaryURL.path) --config \(Self.helperConfigURL.path)")) 2>/dev/null || true",
            "sleep 0.2",
            "pkill -KILL -f \(Self.shellQuote("\(Self.helperBinaryURL.path) --config \(Self.helperConfigURL.path)")) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    private func helperRestartCommand() -> String {
        [
            "mkdir -p \(Self.shellQuote(Self.helperSupportDirectoryURL.path))",
            "if [ -f \(Self.shellQuote(Self.helperPIDURL.path)) ]; then pid=\"$(cat \(Self.shellQuote(Self.helperPIDURL.path)))\"; kill \"$pid\" 2>/dev/null || true; rm -f \(Self.shellQuote(Self.helperPIDURL.path)); fi",
            "pkill -f \(Self.shellQuote("\(Self.helperBinaryURL.path) --config \(Self.helperConfigURL.path)")) 2>/dev/null || true",
            "sleep 0.2",
            "\(Self.shellQuote(Self.helperBinaryURL.path)) --config \(Self.shellQuote(Self.helperConfigURL.path)) >> \(Self.shellQuote(Self.helperLogURL.path)) 2>&1 < /dev/null & echo $! > \(Self.shellQuote(Self.helperPIDURL.path))",
        ].joined(separator: "; ")
    }

    private func fail(_ message: String) {
        lastErrorDescription = message
        appendLog(level: .error, source: "app", message: message)
    }

    private func updateSpeeds(up: Int, down: Int) {
        let now = Date()
        proxyBytesUploaded = up
        proxyBytesDownloaded = down
        proxyTotalBytes = up + down

        guard hasSpeedBaseline else {
            hasSpeedBaseline = true
            lastBytesUploaded = up
            lastBytesDownloaded = down
            lastSpeedUpdate = now
            lastTrafficUpdate = now
            return
        }

        if up < lastBytesUploaded || down < lastBytesDownloaded {
            lastBytesUploaded = up
            lastBytesDownloaded = down
            pendingUploadedBytes = 0
            pendingDownloadedBytes = 0
            smoothedUploadSpeed = 0
            smoothedDownloadSpeed = 0
            proxyUploadSpeed = 0
            proxyDownloadSpeed = 0
            lastSpeedUpdate = now
            lastTrafficUpdate = now
            return
        }

        pendingUploadedBytes += max(0, up - lastBytesUploaded)
        pendingDownloadedBytes += max(0, down - lastBytesDownloaded)
        lastBytesUploaded = up
        lastBytesDownloaded = down

        let dt = now.timeIntervalSince(lastSpeedUpdate)
        guard dt >= 0.45 else { return }

        let hasTrafficChange = pendingUploadedBytes != 0 || pendingDownloadedBytes != 0
        if hasTrafficChange {
            let rawUploadSpeed = Double(pendingUploadedBytes) / dt
            let rawDownloadSpeed = Double(pendingDownloadedBytes) / dt
            let smoothing = min(max(dt / 1.1, 0.16), 0.34)

            smoothedUploadSpeed += (rawUploadSpeed - smoothedUploadSpeed) * smoothing
            smoothedDownloadSpeed += (rawDownloadSpeed - smoothedDownloadSpeed) * smoothing
            proxyUploadSpeed = Int(smoothedUploadSpeed.rounded())
            proxyDownloadSpeed = Int(smoothedDownloadSpeed.rounded())
            pendingUploadedBytes = 0
            pendingDownloadedBytes = 0
            lastTrafficUpdate = now
        } else if now.timeIntervalSince(lastTrafficUpdate) >= 1.2 {
            smoothedUploadSpeed *= 0.72
            smoothedDownloadSpeed *= 0.72

            if smoothedUploadSpeed < 24 {
                smoothedUploadSpeed = 0
            }
            if smoothedDownloadSpeed < 24 {
                smoothedDownloadSpeed = 0
            }

            proxyUploadSpeed = Int(smoothedUploadSpeed.rounded())
            proxyDownloadSpeed = Int(smoothedDownloadSpeed.rounded())
        }
        lastSpeedUpdate = now
    }

    private static func describeConnectionStatus(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:
            return "invalid"
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reasserting:
            return "reasserting"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "unknown"
        }
    }

    private static func reserveAvailableLocalTCPPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ConnectionWorkflowError.localProxy("Failed to allocate a local TCP port.")
        }
        defer { close(fd) }

        var value: Int32 = 1
        _ = withUnsafePointer(to: &value) {
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw ConnectionWorkflowError.localProxy("Failed to bind an available local TCP port.")
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw ConnectionWorkflowError.localProxy("Failed to resolve the allocated local TCP port.")
        }

        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }

    private static func describeProviderStatus(_ status: TunnelProviderStatus) -> String {
        var parts = [
            "phase=\(status.phase)",
            "packets=\(status.packetCount)",
            "up=\(status.bytesUploaded)",
            "down=\(status.bytesDownloaded)",
            "target=\(status.connectIP):\(status.connectPort)",
            "sni=\(status.fakeSNI)",
        ]
        if let detail = status.detail, !detail.isEmpty {
            parts.append("detail=\(detail)")
        }
        if let startedAtISO8601 = status.startedAtISO8601, !startedAtISO8601.isEmpty {
            parts.append("started=\(startedAtISO8601)")
        }
        return parts.joined(separator: " | ")
    }

    private static func describeManager(_ manager: NETunnelProviderManager, label: String) -> String {
        let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
        let providerBundleID = proto?.providerBundleIdentifier ?? "-"
        let serverAddress = proto?.serverAddress ?? "-"
        let keys = (proto?.providerConfiguration?.keys.map { "\($0)" }.sorted() ?? []).joined(separator: ",")
        return "\(label) | enabled=\(manager.isEnabled) | status=\(describeConnectionStatus(manager.connection.status)) | localizedDescription=\(manager.localizedDescription ?? "-") | bundle=\(providerBundleID) | server=\(serverAddress) | providerConfigKeys=[\(keys)]"
    }

    private static func isManagedManager(_ manager: NETunnelProviderManager) -> Bool {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }

        if tunnelProtocol.providerBundleIdentifier == TunnelConfiguration.providerBundleIdentifier {
            return true
        }

        return manager.localizedDescription == "SNI-Spoofing Client"
    }

    private static func loadManagedManagers() async throws -> [NETunnelProviderManager] {
        try await loadManagers().filter(Self.isManagedManager)
    }

    private static func describeNativeProxyStatus(_ status: NativeProxyStatus) -> String {
        var parts = [
            "phase=\(status.phase)",
            "connections=\(status.activeConnections)",
            "up=\(status.bytesUploaded)",
            "down=\(status.bytesDownloaded)",
        ]
        if let interfaceName = status.interfaceName, let interfaceIPv4 = status.interfaceIPv4 {
            parts.append("iface=\(interfaceName)(\(interfaceIPv4))")
        }
        if let detail = status.detail, !detail.isEmpty {
            parts.append("detail=\(detail)")
        }
        return parts.joined(separator: " | ")
    }

    private static func loadManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: managers ?? [])
            }
        }
    }

    private static func loadManager(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private static func saveManager(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private static func removeManager(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private static func removeManagers(_ managers: [NETunnelProviderManager]) async throws {
        for manager in managers {
            try await removeManager(manager)
        }
    }

    private static func sendMessage(
        _ message: TunnelAppMessage,
        using session: NETunnelProviderSession
    ) async throws -> Data {
        let encoded = try TunnelIPC.encode(message)
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(encoded) { responseData in
                    guard let responseData else {
                        continuation.resume(throwing: TunnelControllerError.emptyProviderResponse)
                        return
                    }
                    continuation.resume(returning: responseData)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func makeDefaultWorkflowSteps() -> [ConnectionWorkflowStep] {
        ConnectionWorkflowStepKey.allCases.map { key in
            ConnectionWorkflowStep(
                key: key,
                state: .pending,
                detail: "Waiting"
            )
        }
    }

    private static func normalizeDomain(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            throw ConnectionWorkflowError.validation(AppCopy(language: AppLanguageStore.shared.selectedLanguage).allowlistDomainEmpty)
        }

        let candidate: String
        if trimmed.contains("://"), let host = URL(string: trimmed)?.host {
            candidate = host.lowercased()
        } else {
            candidate = trimmed
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard candidate.rangeOfCharacter(from: allowed.inverted) == nil, candidate.contains(".") else {
            throw ConnectionWorkflowError.validation(AppCopy(language: AppLanguageStore.shared.selectedLanguage).invalidAllowlistDomain(rawValue))
        }
        return candidate
    }

    private static func normalizeIPv4(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try SystemNetworkUtils.sockaddrIn(ipv4: trimmed, port: 443)
        return trimmed
    }

    private static func parseWhitelistEndpoint(_ rawValue: String) throws -> (ip: String, port: Int) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConnectionWorkflowError.validation(AppCopy(language: AppLanguageStore.shared.selectedLanguage).allowlistIPEmpty)
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            let ip = try normalizeIPv4(String(parts[0]))
            return (ip, 443)
        case 2:
            let ip = try normalizeIPv4(String(parts[0]))
            let port = try parsePort(String(parts[1]), fieldName: AppCopy(language: AppLanguageStore.shared.selectedLanguage).allowlistPortLabel)
            return (ip, port)
        default:
            throw ConnectionWorkflowError.validation(AppCopy(language: AppLanguageStore.shared.selectedLanguage).allowlistIPFormatError)
        }
    }

    private static func parsePort(_ rawValue: String, fieldName: String) throws -> Int {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1 ... 65535).contains(port) else {
            throw ConnectionWorkflowError.validation(AppCopy(language: AppLanguageStore.shared.selectedLanguage).portRangeError(fieldName))
        }
        return port
    }

    private static func listActiveNetworkServices() async throws -> [String] {
        let output = try await runProcess(
            launchPath: "/usr/sbin/networksetup",
            arguments: ["-listallnetworkservices"]
        )
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    private static func discoverDNSServers() async throws -> [String] {
        let services = try await listActiveNetworkServices()
        var servers = Set<String>()

        for service in services {
            let output = try? await runProcess(
                launchPath: "/usr/sbin/networksetup",
                arguments: ["-getdnsservers", service]
            )

            guard let output else {
                continue
            }

            for line in output.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isValidIPv4Address else {
                    continue
                }
                servers.insert(trimmed)
            }
        }

        return servers.sorted()
    }

    private func applySystemDNSServers(_ servers: [String]) async throws -> DNSConfigurationSnapshot {
        let services = try await Self.listActiveNetworkServices()
        guard !services.isEmpty else {
            throw ConnectionWorkflowError.systemProxy("No active macOS network service was found.")
        }

        let snapshot = try await captureSystemDNSConfiguration(services: services)
        let quotedServers = servers.map(Self.shellQuote).joined(separator: " ")
        let commands = services.map { service in
            "/usr/sbin/networksetup -setdnsservers \(Self.shellQuote(service)) \(quotedServers)"
        }
        try await Self.runPrivilegedShell(commands.joined(separator: "; "))
        appendLog(level: .debug, source: "system", message: "System DNS applied to: \(services.joined(separator: ", "))")
        return snapshot
    }

    private func restoreSystemDNSIfNeeded() async throws {
        guard let snapshot = activeDNSConfigurationSnapshot else {
            return
        }

        try await restoreSystemDNSConfiguration(snapshot)
        activeDNSConfigurationSnapshot = nil
        appendLog(level: .info, source: "system", message: "System DNS restored")
    }

    private func captureSystemDNSConfiguration(services: [String]) async throws -> DNSConfigurationSnapshot {
        var snapshots: [DNSServiceSnapshot] = []
        snapshots.reserveCapacity(services.count)

        for service in services {
            guard let output = try? await Self.runProcess(
                launchPath: "/usr/sbin/networksetup",
                arguments: ["-getdnsservers", service]
            ) else {
                snapshots.append(DNSServiceSnapshot(service: service, servers: nil))
                continue
            }

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("There aren't any DNS Servers set") {
                snapshots.append(DNSServiceSnapshot(service: service, servers: nil))
                continue
            }

            let servers = trimmed
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isValidIPv4Address }
            snapshots.append(DNSServiceSnapshot(service: service, servers: servers.isEmpty ? nil : servers))
        }

        return DNSConfigurationSnapshot(services: snapshots)
    }

    private func restoreSystemDNSConfiguration(_ snapshot: DNSConfigurationSnapshot) async throws {
        guard !snapshot.services.isEmpty else { return }

        let commands = snapshot.services.map { serviceSnapshot in
            if let servers = serviceSnapshot.servers, !servers.isEmpty {
                let quotedServers = servers.map(Self.shellQuote).joined(separator: " ")
                return "/usr/sbin/networksetup -setdnsservers \(Self.shellQuote(serviceSnapshot.service)) \(quotedServers)"
            } else {
                return "/usr/sbin/networksetup -setdnsservers \(Self.shellQuote(serviceSnapshot.service)) Empty"
            }
        }
        try await Self.runPrivilegedShell(commands.joined(separator: "; "))
    }

    private static func probe(url: URL, httpPort: Int, mode: AppConnectionMode) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = mode == .tunnel ? 12 : 8
        config.timeoutIntervalForResource = mode == .tunnel ? 18 : 12
        // In proxy mode we probe through explicit local proxy.
        // In tunnel mode we intentionally probe without explicit proxy dictionary
        // so the check reflects real system route/tunnel behavior.
        if mode == .proxy {
            config.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": "127.0.0.1",
                "HTTPPort": httpPort,
                "HTTPSEnable": 1,
                "HTTPSProxy": "127.0.0.1",
                "HTTPSPort": httpPort,
            ]
        }

        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
        }

        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 399).contains(httpResponse.statusCode) else {
            throw ConnectionWorkflowError.connectivityProbe("Probe response was not successful for \(url.absoluteString)")
        }
    }

    private static func runProcess(launchPath: String, arguments: [String], timeout: TimeInterval = 8) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            final class CompletionState: @unchecked Sendable {
                let lock = NSLock()
                var finished = false
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let completionState = CompletionState()

            @Sendable func finish(_ result: Result<String, Error>) {
                completionState.lock.lock()
                defer { completionState.lock.unlock() }
                guard !completionState.finished else { return }
                completionState.finished = true
                process.terminationHandler = nil
                continuation.resume(with: result)
            }

            process.terminationHandler = { terminatedProcess in
                let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if terminatedProcess.terminationStatus == 0 {
                    finish(.success(output))
                    return
                }

                let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                finish(.failure(NSError(
                    domain: "TunnelController.Process",
                    code: Int(terminatedProcess.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText]
                )))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.interrupt()
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                finish(.failure(NSError(
                    domain: "TunnelController.Process",
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: "Process timed out after \(Int(timeout))s: \(launchPath) \(arguments.joined(separator: " "))"]
                )))
            }
        }
    }

    private static func shouldRetryTunnelStartupAfterManagerReset(_ error: Error) -> Bool {
        let nsError = error as NSError
        let loweredDescription = nsError.localizedDescription.lowercased()
        let loweredDomain = nsError.domain.lowercased()

        if loweredDescription.contains("not installed") || loweredDescription.contains("plugin") {
            return true
        }

        return loweredDomain.contains("networkextension") && nsError.code == 1
    }

    private static func debugDescription(for error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "desc=\(nsError.localizedDescription)",
        ]

        if !nsError.userInfo.isEmpty {
            let userInfoText = nsError.userInfo
                .map { key, value in "\(key)=\(value)" }
                .sorted()
                .joined(separator: ", ")
            parts.append("userInfo={\(userInfoText)}")
        }

        return parts.joined(separator: " | ")
    }

    private static func describeTunnelStartupError(_ error: Error) -> String {
        let nsError = error as NSError
        let loweredDescription = nsError.localizedDescription.lowercased()
        let loweredDomain = nsError.domain.lowercased()

        let looksLikePermissionDenied =
            loweredDescription.contains("permission denied") ||
            (nsError.code == 5 && (loweredDomain.contains("nevpn") || loweredDomain.contains("networkextension")))

        if looksLikePermissionDenied {
            return "Tunnel mode requires a signed app with the `packet-tunnel-provider` entitlement. This build is likely unsigned, the team/signing configuration is missing, or the VPN prompt has not been approved."
        }

        if loweredDescription.contains("configuration disabled") {
            return "The VPN configuration is disabled. Run the app with valid signing and approve the tunnel permission again."
        }

        if loweredDescription.contains("not installed") {
            return "The VPN provider is not installed, or the app extension package did not load correctly. Check the build and install process again."
        }

        return nsError.localizedDescription
    }

    @MainActor
    private static var cachedAdminPassword: String? = nil

    @MainActor
    private static func promptForPassword() -> String? {
        if let cached = cachedAdminPassword { return cached }
        let alert = NSAlert()
        alert.messageText = AppCopy(language: AppLanguageStore.shared.selectedLanguage).administratorPrivilegesRequired
        alert.informativeText = AppCopy(language: AppLanguageStore.shared.selectedLanguage).helperPrivilegesMessage
        let secureTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        alert.accessoryView = secureTextField
        let promptCopy = AppCopy(language: AppLanguageStore.shared.selectedLanguage)
        alert.addButton(withTitle: promptCopy.helperPrivilegesOK)
        alert.addButton(withTitle: promptCopy.helperPrivilegesCancel)
        alert.window.initialFirstResponder = secureTextField
        NSApp.activate(ignoringOtherApps: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            cachedAdminPassword = secureTextField.stringValue
            return cachedAdminPassword
        }
        return nil
    }

    @MainActor
    private static func runPrivilegedShell(_ command: String) async throws {
        guard let password = promptForPassword() else {
            throw TunnelControllerError.commandFailed(AppCopy(language: AppLanguageStore.shared.selectedLanguage).helperStartCancelled)
        }

        do {
            try await runPrivilegedShell(command: command, password: password)
        } catch {
            let lowered = error.localizedDescription.lowercased()
            if lowered.contains("incorrect password") || lowered.contains("try again") {
                cachedAdminPassword = nil
                throw TunnelControllerError.commandFailed(AppCopy(language: AppLanguageStore.shared.selectedLanguage).incorrectPassword)
            }
            throw error
        }
    }

    private static func runPrivilegedShell(command: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                
                let escapedPassword = password.replacingOccurrences(of: "'", with: "'\"'\"'")
                let bashCommand = "echo '\(escapedPassword)' | sudo -S bash -c '\(command.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
                process.arguments = ["-c", bashCommand]

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        continuation.resume(throwing: NSError(
                            domain: "TunnelController.Process",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errorText]
                        ))
                        return
                    }

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func extractLevel(from line: String) -> ProxyLogLevel {
        guard line.hasPrefix("[") else {
            return .info
        }
        guard let closing = line.firstIndex(of: "]") else {
            return .info
        }
        let raw = String(line[line.index(after: line.startIndex) ..< closing])
        return ProxyLogLevel.parse(raw)
    }

    private static func extractValue(for key: String, in line: String) -> String? {
        // More robust parsing: look for key=value or key: value
        let patterns = ["\(key)=", "\(key): "]
        for pattern in patterns {
            if let range = line.range(of: pattern) {
                let tail = line[range.upperBound...]
                // Stop at space, comma, or end of string
                let splitIndex = tail.firstIndex(where: { $0 == " " || $0 == "," }) ?? tail.endIndex
                return String(tail[..<splitIndex])
            }
        }
        return nil
    }

    private static func extractDetail(in line: String) -> String? {
        guard let range = line.range(of: "detail=") else {
            return nil
        }
        return String(line[range.upperBound...])
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let projectRootURL =
        URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let helperSupportDirectoryURL =
        FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SniSpoofingMac", isDirectory: true)

    private static var buildArchitectureFolderName: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static var helperBinaryURL: URL {
        if let bundledHelperURL = Bundle.main.url(forResource: "sni-proxy-helper", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundledHelperURL.path) {
            return bundledHelperURL
        }

        let repoBuildCandidates = [
            projectRootURL.appendingPathComponent("macos-arm/build/\(buildArchitectureFolderName)/Debug/sni-proxy-helper"),
            projectRootURL.appendingPathComponent("macos-arm/build/Debug/sni-proxy-helper")
        ]

        for candidate in repoBuildCandidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        if let derivedDataURL = latestDerivedDataHelperBinaryURL() {
            return derivedDataURL
        }

        return repoBuildCandidates[0]
    }

    private static let helperConfigURL =
        helperSupportDirectoryURL.appendingPathComponent("helper-config.json")

    private static let helperLogURL =
        helperSupportDirectoryURL.appendingPathComponent("proxy-helper.log")

    private static let helperPIDURL =
        helperSupportDirectoryURL.appendingPathComponent("proxy-helper.pid")

    private static let diagnosticDumpURL =
        helperSupportDirectoryURL.appendingPathComponent("last-diagnostic-dump.txt")

    private static func latestDerivedDataHelperBinaryURL() -> URL? {
        let derivedDataRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: derivedDataRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestMatch: (url: URL, date: Date)?
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "sni-proxy-helper" else {
                continue
            }
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = values?.contentModificationDate ?? .distantPast
            if bestMatch == nil || date > bestMatch!.date {
                bestMatch = (url, date)
            }
        }

        return bestMatch?.url
    }
}

private extension String {
    var isValidIPv4Address: Bool {
        var address = in_addr()
        return withCString { inet_pton(AF_INET, $0, &address) } == 1
    }
}

enum TunnelControllerError: LocalizedError {
    case managerUnavailable
    case invalidSession
    case emptyProviderResponse
    case commandFailed(String)
    case helperBinaryMissing(String)

    var errorDescription: String? {
        switch self {
        case .managerUnavailable:
            return "Manager is unavailable"
        case .invalidSession:
            return "Packet tunnel session is invalid"
        case .emptyProviderResponse:
            return "No response was received from the provider"
        case let .commandFailed(message):
            return "Command execution failed: \(message)"
        case let .helperBinaryMissing(path):
            return "Helper binary not found: \(path)"
        }
    }
}
