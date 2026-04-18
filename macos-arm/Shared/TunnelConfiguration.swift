import Foundation

enum ProxyLogLevel: String, Codable, Equatable {
    case debug
    case info
    case error

    var priority: Int {
        switch self {
        case .debug:
            return 0
        case .info:
            return 1
        case .error:
            return 2
        }
    }

    static func parse(_ rawValue: String?) -> ProxyLogLevel {
        guard let rawValue else {
            return .info
        }
        return ProxyLogLevel(rawValue: rawValue.lowercased()) ?? .info
    }
}

enum AppConnectionMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case proxy
    case tunnel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proxy:
            return "Proxy"
        case .tunnel:
            return "Tunnel"
        }
    }

    static func parse(_ rawValue: String?) -> AppConnectionMode {
        guard let rawValue else {
            return .proxy
        }
        return AppConnectionMode(rawValue: rawValue.lowercased()) ?? .proxy
    }
}

struct TunnelConfiguration: Codable, Equatable {
    static let providerBundleIdentifier = "com.local.sni.macos.packet-tunnel"
    // Fallback only. Real helper port is chosen dynamically per connection attempt.
    static let stageOneProxyPort = 40443
    static let fixedSocksProxyPort = 20000
    static let fixedHTTPProxyPort = 30000
    static let defaultVlessURI = "vless://f9f1b2da-d02f-4da3-bc96-4903d23fab27@8.6.112.64:443?security=tls&type=ws&headerType=&path=%2Ftunnel&host=pw.haz.pw&sni=pw.haz.pw&fp=&allowInsecure=1#CLOUDFLARE"
    static let defaults = TunnelConfiguration(
        listenHost: "127.0.0.1",
        listenPort: stageOneProxyPort,
        connectIP: "104.19.229.21",
        connectPort: 443,
        upstreamIP: "127.0.0.1",
        upstreamPort: stageOneProxyPort,
        fakeSNI: "hcaptcha.com",
        logLevel: .info,
        connectionMode: .proxy,
        httpProxyPort: nil,
        socksProxyPort: nil,
        dnsServers: [],
        excludedIPv4Addresses: []
    )

    var listenHost: String
    var listenPort: Int
    var connectIP: String
    var connectPort: Int
    var upstreamIP: String
    var upstreamPort: Int
    var fakeSNI: String
    var logLevel: ProxyLogLevel
    var connectionMode: AppConnectionMode
    var httpProxyPort: Int?
    var socksProxyPort: Int?
    var dnsServers: [String]
    var excludedIPv4Addresses: [String]

    init(
        listenHost: String,
        listenPort: Int,
        connectIP: String,
        connectPort: Int,
        upstreamIP: String,
        upstreamPort: Int,
        fakeSNI: String,
        logLevel: ProxyLogLevel,
        connectionMode: AppConnectionMode,
        httpProxyPort: Int?,
        socksProxyPort: Int?,
        dnsServers: [String],
        excludedIPv4Addresses: [String]
    ) {
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.connectIP = connectIP
        self.connectPort = connectPort
        self.upstreamIP = upstreamIP
        self.upstreamPort = upstreamPort
        self.fakeSNI = fakeSNI
        self.logLevel = logLevel
        self.connectionMode = connectionMode
        self.httpProxyPort = httpProxyPort
        self.socksProxyPort = socksProxyPort
        self.dnsServers = dnsServers
        self.excludedIPv4Addresses = excludedIPv4Addresses
    }

    init(providerConfiguration: [String: Any]?) {
        let defaults = Self.defaults
        self.listenHost = providerConfiguration?["listenHost"] as? String ?? defaults.listenHost
        self.listenPort = (providerConfiguration?["listenPort"] as? NSNumber)?.intValue ?? defaults.listenPort
        self.connectIP = providerConfiguration?["connectIP"] as? String ?? defaults.connectIP
        self.connectPort = (providerConfiguration?["connectPort"] as? NSNumber)?.intValue ?? defaults.connectPort
        self.upstreamIP = providerConfiguration?["upstreamIP"] as? String ?? defaults.upstreamIP
        self.upstreamPort = (providerConfiguration?["upstreamPort"] as? NSNumber)?.intValue ?? defaults.upstreamPort
        self.fakeSNI = providerConfiguration?["fakeSNI"] as? String ?? defaults.fakeSNI
        self.logLevel = ProxyLogLevel.parse(providerConfiguration?["logLevel"] as? String)
        self.connectionMode = AppConnectionMode.parse(providerConfiguration?["connectionMode"] as? String)
        self.httpProxyPort = (providerConfiguration?["httpProxyPort"] as? NSNumber)?.intValue
        self.socksProxyPort = (providerConfiguration?["socksProxyPort"] as? NSNumber)?.intValue
        self.dnsServers = providerConfiguration?["dnsServers"] as? [String] ?? defaults.dnsServers
        self.excludedIPv4Addresses = providerConfiguration?["excludedIPv4Addresses"] as? [String] ?? defaults.excludedIPv4Addresses
    }

    func providerConfigurationDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "listenHost": listenHost as NSString,
            "listenPort": NSNumber(value: listenPort),
            "connectIP": connectIP as NSString,
            "connectPort": NSNumber(value: connectPort),
            "upstreamIP": upstreamIP as NSString,
            "upstreamPort": NSNumber(value: upstreamPort),
            "fakeSNI": fakeSNI as NSString,
            "logLevel": logLevel.rawValue as NSString,
            "connectionMode": connectionMode.rawValue as NSString,
        ]

        if let httpProxyPort {
            dictionary["httpProxyPort"] = NSNumber(value: httpProxyPort)
        }
        if let socksProxyPort {
            dictionary["socksProxyPort"] = NSNumber(value: socksProxyPort)
        }
        if !dnsServers.isEmpty {
            dictionary["dnsServers"] = dnsServers as NSArray
        }
        if !excludedIPv4Addresses.isEmpty {
            dictionary["excludedIPv4Addresses"] = excludedIPv4Addresses as NSArray
        }

        return dictionary
    }
}
