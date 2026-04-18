import Foundation

@main
struct SniProxyHelperMain {
    static func main() {
        do {
            let options = try HelperOptions.parse(arguments: CommandLine.arguments)
            if options.showHelp {
                print(HelperOptions.usageText)
                return
            }
            if geteuid() != 0 {
                fputs("This helper must be run with sudo/root.\n", stderr)
                Foundation.exit(1)
            }

            let configuration = try options.loadConfiguration()
            print("SNI proxy helper starting on \(configuration.listenHost):\(configuration.listenPort)")
            print("target=\(configuration.connectIP):\(configuration.connectPort) fakeSNI=\(configuration.fakeSNI)")
            print("logLevel=\(configuration.logLevel.rawValue)")

            let semaphore = DispatchSemaphore(value: 0)
            var lastPrintedProxySnapshot: (phase: String, connections: Int, up: Int, down: Int)?
            let service = LocalProxyService { status in
                let previousSnapshot = lastPrintedProxySnapshot
                let shouldEmitProxyStatus: Bool
                if let previousSnapshot {
                    shouldEmitProxyStatus =
                        previousSnapshot.phase != status.phase ||
                        previousSnapshot.connections != status.activeConnections ||
                        previousSnapshot.up != status.bytesUploaded ||
                        previousSnapshot.down != status.bytesDownloaded
                } else {
                    shouldEmitProxyStatus = true
                }

                guard shouldEmitProxyStatus || status.logLevel.priority >= configuration.logLevel.priority else {
                    return
                }
                let detail = status.detail ?? "-"
                let interfaceText: String
                if let interfaceName = status.interfaceName, let interfaceIPv4 = status.interfaceIPv4 {
                    interfaceText = "\(interfaceName)(\(interfaceIPv4))"
                } else {
                    interfaceText = "-"
                }
                print("[\(status.logLevel.rawValue)] [proxy] phase=\(status.phase) connections=\(status.activeConnections) bytesUp=\(status.bytesUploaded) bytesDown=\(status.bytesDownloaded) iface=\(interfaceText) detail=\(detail)")
                fflush(stdout)
                lastPrintedProxySnapshot = (
                    phase: status.phase,
                    connections: status.activeConnections,
                    up: status.bytesUploaded,
                    down: status.bytesDownloaded
                )
            }

            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)

            let signalQueue = DispatchQueue(label: "com.local.sni.macos.helper.signals")
            let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
            interruptSource.setEventHandler {
                print("SIGINT received, stopping helper...")
                service.stop()
                semaphore.signal()
            }
            interruptSource.resume()

            let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
            terminateSource.setEventHandler {
                print("SIGTERM received, stopping helper...")
                service.stop()
                semaphore.signal()
            }
            terminateSource.resume()

            try service.start(configuration: configuration)
            print("Helper is ready. Press Ctrl+C to stop.")
            semaphore.wait()
        } catch let error as HelperUsageError {
            fputs("\(error.localizedDescription)\n", stderr)
            fputs(HelperOptions.usageText + "\n", stderr)
            Foundation.exit(2)
        } catch {
            fputs("Helper failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private enum HelperUsageError: LocalizedError {
    case missingValue(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(flag):
            return "Missing value for \(flag)."
        case let .invalidArgument(argument):
            return "Unknown argument: \(argument)"
        }
    }
}

private struct HelperOptions {
    let showHelp: Bool
    let configPath: String?
    let listenHost: String?
    let listenPort: Int?
    let connectIP: String?
    let connectPort: Int?
    let fakeSNI: String?
    let logLevel: ProxyLogLevel?

    static let usageText = """
    Usage:
      sudo ./sni-proxy-helper --config /path/to/config.json
      sudo ./sni-proxy-helper --listen-host 0.0.0.0 --listen-port <dynamic-port> --connect-ip 104.19.229.21 --connect-port 443 --fake-sni hcaptcha.com --log-level info
    """

    static func parse(arguments: [String]) throws -> HelperOptions {
        var showHelp = false
        var configPath: String?
        var listenHost: String?
        var listenPort: Int?
        var connectIP: String?
        var connectPort: Int?
        var fakeSNI: String?
        var logLevel: ProxyLogLevel?

        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--config":
                guard let value = iterator.next() else {
                    throw HelperUsageError.missingValue(argument)
                }
                configPath = value
            case "--listen-host":
                guard let value = iterator.next() else {
                    throw HelperUsageError.missingValue(argument)
                }
                listenHost = value
            case "--listen-port":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    throw HelperUsageError.missingValue(argument)
                }
                listenPort = parsed
            case "--connect-ip":
                guard let value = iterator.next() else {
                    throw HelperUsageError.missingValue(argument)
                }
                connectIP = value
            case "--connect-port":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    throw HelperUsageError.missingValue(argument)
                }
                connectPort = parsed
            case "--fake-sni":
                guard let value = iterator.next() else {
                    throw HelperUsageError.missingValue(argument)
                }
                fakeSNI = value
            case "--log-level":
                guard let value = iterator.next() else {
                    throw HelperUsageError.missingValue(argument)
                }
                logLevel = ProxyLogLevel.parse(value)
            case "--help", "-h":
                showHelp = true
            default:
                throw HelperUsageError.invalidArgument(argument)
            }
        }

        return HelperOptions(
            showHelp: showHelp,
            configPath: configPath,
            listenHost: listenHost,
            listenPort: listenPort,
            connectIP: connectIP,
            connectPort: connectPort,
            fakeSNI: fakeSNI,
            logLevel: logLevel
        )
    }

    func loadConfiguration() throws -> TunnelConfiguration {
        let base: TunnelConfiguration
        if let configPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            base = TunnelConfiguration(
                listenHost: raw["LISTEN_HOST"] as? String ?? TunnelConfiguration.defaults.listenHost,
                listenPort: (raw["LISTEN_PORT"] as? NSNumber)?.intValue ?? TunnelConfiguration.defaults.listenPort,
                connectIP: raw["CONNECT_IP"] as? String ?? TunnelConfiguration.defaults.connectIP,
                connectPort: (raw["CONNECT_PORT"] as? NSNumber)?.intValue ?? TunnelConfiguration.defaults.connectPort,
                upstreamIP: raw["UPSTREAM_IP"] as? String ?? TunnelConfiguration.defaults.upstreamIP,
                upstreamPort: (raw["UPSTREAM_PORT"] as? NSNumber)?.intValue ?? TunnelConfiguration.defaults.upstreamPort,
                fakeSNI: raw["FAKE_SNI"] as? String ?? TunnelConfiguration.defaults.fakeSNI,
                logLevel: ProxyLogLevel.parse(raw["LOG_LEVEL"] as? String),
                connectionMode: .proxy,
                httpProxyPort: nil,
                socksProxyPort: nil,
                dnsServers: [],
                excludedIPv4Addresses: []
            )
        } else {
            base = .defaults
        }

        return TunnelConfiguration(
            listenHost: listenHost ?? base.listenHost,
            listenPort: listenPort ?? base.listenPort,
            connectIP: connectIP ?? base.connectIP,
            connectPort: connectPort ?? base.connectPort,
            upstreamIP: base.upstreamIP,
            upstreamPort: base.upstreamPort,
            fakeSNI: fakeSNI ?? base.fakeSNI,
            logLevel: logLevel ?? base.logLevel,
            connectionMode: base.connectionMode,
            httpProxyPort: base.httpProxyPort,
            socksProxyPort: base.socksProxyPort,
            dnsServers: [],
            excludedIPv4Addresses: base.excludedIPv4Addresses
        )
    }
}
