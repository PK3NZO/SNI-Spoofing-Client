import Foundation

struct NativeProxyStatus: Equatable {
    var phase: String
    var logLevel: ProxyLogLevel
    var activeConnections: Int
    var bytesUploaded: Int
    var bytesDownloaded: Int
    var interfaceName: String?
    var interfaceIPv4: String?
    var detail: String?
}

enum NativeProxyError: LocalizedError {
    case invalidListenPort(Int)
    case listenerCreateFailed(String)
    case listenerBindFailed(String)
    case listenerListenFailed(String)
    case connectFailed(String)
    case bypassFailed(String)
    case pcapFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidListenPort(port):
            return "Invalid listen port: \(port)"
        case let .listenerCreateFailed(message):
            return "Failed to create listener socket: \(message)"
        case let .listenerBindFailed(message):
            return "Listener bind failed: \(message)"
        case let .listenerListenFailed(message):
            return "Listen failed: \(message)"
        case let .connectFailed(message):
            return "Connect failed: \(message)"
        case let .bypassFailed(message):
            return "Bypass handshake failed: \(message)"
        case let .pcapFailed(message):
            return "pcap failed: \(message)"
        }
    }
}

final class LocalProxyService {
    private let statusHandler: @Sendable (NativeProxyStatus) -> Void
    private let syncQueue = DispatchQueue(label: "com.local.sni.macos.local-proxy.sync")
    private var listenerFD: Int32 = -1
    private var acceptThread: Thread?
    private var running = false
    private var currentConfiguration = TunnelConfiguration.defaults
    private var preferredEgressInterface: ResolvedInterface?
    private var activeSessions: [UUID: ProxyClientSession] = [:]
    private var lastInterface: ResolvedInterface?
    private var lastLogLevel: ProxyLogLevel = .info
    private var lastDetail = "idle"
    private var previousSessionsBytesUploaded: Int = 0
    private var previousSessionsBytesDownloaded: Int = 0
    private var statusTimer: DispatchSourceTimer?

    init(statusHandler: @escaping @Sendable (NativeProxyStatus) -> Void) {
        self.statusHandler = statusHandler
    }

    func start(configuration: TunnelConfiguration) throws {
        try syncQueue.sync {
            if running {
                stopLocked(detail: "restart")
            }

            guard let port = in_port_t(exactly: configuration.listenPort), port > 0 else {
                throw NativeProxyError.invalidListenPort(configuration.listenPort)
            }

            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw NativeProxyError.listenerCreateFailed(SystemNetworkUtils.errnoDescription())
            }

            do {
                try configureSocket(fd)
                var reuseValue: Int32 = 1
                Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseValue, socklen_t(MemoryLayout<Int32>.size))

                let bindHost = configuration.listenHost == "0.0.0.0" ? "0.0.0.0" : configuration.listenHost
                var listenAddress = try SystemNetworkUtils.sockaddrIn(ipv4: bindHost, port: port)
                let bindResult = withUnsafePointer(to: &listenAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard bindResult == 0 else {
                    throw NativeProxyError.listenerBindFailed(SystemNetworkUtils.errnoDescription())
                }

                guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                    throw NativeProxyError.listenerListenFailed(SystemNetworkUtils.errnoDescription())
                }
            } catch {
                Darwin.close(fd)
                throw error
            }

            listenerFD = fd
            running = true
            currentConfiguration = configuration
            preferredEgressInterface = try? SystemNetworkUtils.resolveBypassInterface(
                forRemoteIPv4: configuration.connectIP,
                remotePort: UInt16(configuration.connectPort)
            )
            lastInterface = nil
            if let preferredEgressInterface {
                lastInterface = preferredEgressInterface
                lastDetail = "Listener started on \(configuration.listenHost):\(configuration.listenPort) | egress=\(preferredEgressInterface.name) \(preferredEgressInterface.ipv4Address)"
            } else {
                lastDetail = "Listener started on \(configuration.listenHost):\(configuration.listenPort)"
            }
            lastLogLevel = .info
            emitStatusLocked(phase: "starting")

            let thread = Thread { [weak self] in
                self?.acceptLoop()
            }
            thread.name = "SNI Local Proxy Accept"
            acceptThread = thread
            thread.start()

            let timer = DispatchSource.makeTimerSource(queue: syncQueue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                self?.emitStatusLocked(phase: "running")
            }
            timer.resume()
            statusTimer = timer
        }
    }

    func stop() {
        syncQueue.sync {
            stopLocked(detail: "Manual stop")
        }
    }

    private func stopLocked(detail: String) {
        running = false
        statusTimer?.cancel()
        statusTimer = nil
        if listenerFD >= 0 {
            shutdown(listenerFD, SHUT_RDWR)
            Darwin.close(listenerFD)
            listenerFD = -1
        }
        let sessions = Array(activeSessions.values)
        activeSessions.removeAll()
        sessions.forEach { 
            previousSessionsBytesUploaded += $0.bytesUploaded
            previousSessionsBytesDownloaded += $0.bytesDownloaded
            $0.stop() 
        }
        lastLogLevel = .info
        lastDetail = detail
        emitStatusLocked(phase: "stopped")
    }

    private func acceptLoop() {
        while true {
            var remoteAddress = sockaddr_storage()
            var remoteLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &remoteAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.accept(listenerFD, sockaddrPointer, &remoteLength)
                }
            }

            if clientFD < 0 {
                let shouldBreak = syncQueue.sync { !running || listenerFD < 0 }
                if shouldBreak {
                    break
                }
                continue
            }

            do {
                try configureSocket(clientFD)
            } catch {
                Darwin.close(clientFD)
                syncQueue.sync {
                    self.lastLogLevel = .error
                    self.lastDetail = "Failed to configure client socket: \(error.localizedDescription)"
                    self.emitStatusLocked(phase: "running")
                }
                continue
            }

            let session = ProxyClientSession(
                incomingFD: clientFD,
                configuration: currentConfiguration,
                preferredEgressInterface: preferredEgressInterface
            ) { [weak self] interface, logLevel, detail in
                self?.syncQueue.async {
                    self?.lastInterface = interface
                    self?.lastLogLevel = logLevel
                    self?.lastDetail = detail
                    self?.emitStatusLocked(phase: "running")
                }
            } onFinish: { [weak self] identifier, sessionBytesUp, sessionBytesDown in
                self?.syncQueue.async {
                    self?.previousSessionsBytesUploaded += sessionBytesUp
                    self?.previousSessionsBytesDownloaded += sessionBytesDown
                    self?.activeSessions.removeValue(forKey: identifier)
                    self?.lastLogLevel = .debug
                    self?.lastDetail = "Session finished"
                    self?.emitStatusLocked(phase: self?.running == true ? "running" : "stopped")
                }
            }

            syncQueue.sync {
                self.activeSessions[session.id] = session
                self.lastLogLevel = .debug
                self.lastDetail = "Accepted new client"
                self.emitStatusLocked(phase: "running")
            }
            session.start()
        }

        syncQueue.async {
            if self.running {
                self.lastLogLevel = .info
                self.lastDetail = "Accept loop finished"
                self.emitStatusLocked(phase: "running")
            }
        }
    }

    private func emitStatusLocked(phase: String) {
        var up = previousSessionsBytesUploaded
        var down = previousSessionsBytesDownloaded
        for session in activeSessions.values {
            up += session.bytesUploaded
            down += session.bytesDownloaded
        }
        
        statusHandler(
            NativeProxyStatus(
                phase: phase,
                logLevel: lastLogLevel,
                activeConnections: activeSessions.count,
                bytesUploaded: up,
                bytesDownloaded: down,
                interfaceName: lastInterface?.name,
                interfaceIPv4: lastInterface?.ipv4Address,
                detail: lastDetail
            )
        )
    }

    private func configureSocket(_ fd: Int32) throws {
        var one: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
}

private final class ProxyClientSession {
    let id = UUID()

    private let incomingFD: Int32
    private let configuration: TunnelConfiguration
    private let preferredEgressInterface: ResolvedInterface?
    private let statusHandler: (ResolvedInterface?, ProxyLogLevel, String) -> Void
    private let onFinish: (UUID, Int, Int) -> Void
    private let queue = DispatchQueue(label: "com.local.sni.macos.session", qos: .userInitiated)
    private let lock = NSLock()
    private var stopped = false
    private var outgoingFD: Int32 = -1
    private(set) var bytesUploaded: Int = 0
    private(set) var bytesDownloaded: Int = 0

    init(
        incomingFD: Int32,
        configuration: TunnelConfiguration,
        preferredEgressInterface: ResolvedInterface?,
        statusHandler: @escaping (ResolvedInterface?, ProxyLogLevel, String) -> Void,
        onFinish: @escaping (UUID, Int, Int) -> Void
    ) {
        self.incomingFD = incomingFD
        self.configuration = configuration
        self.preferredEgressInterface = preferredEgressInterface
        self.statusHandler = statusHandler
        self.onFinish = onFinish
    }

    func start() {
        queue.async { [self] in
            run()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let outgoing = outgoingFD
        lock.unlock()

        shutdown(incomingFD, SHUT_RDWR)
        Darwin.close(incomingFD)
        if outgoing >= 0 {
            shutdown(outgoing, SHUT_RDWR)
            Darwin.close(outgoing)
        }
    }

    private func run() {
        defer {
            stop()
            onFinish(id, bytesUploaded, bytesDownloaded)
        }

        do {
            let remotePort = try portValue(configuration.connectPort)
            let resolvedInterface = try preferredEgressInterface
                ?? SystemNetworkUtils.resolveBypassInterface(
                    forRemoteIPv4: configuration.connectIP,
                    remotePort: remotePort
                )
            statusHandler(resolvedInterface, .debug, "Resolved interface: \(resolvedInterface.name) / \(resolvedInterface.ipv4Address)")

            let fakeClientHello = TLSClientHelloBuilder.build(
                random: randomData(length: 32),
                sessionID: randomData(length: 32),
                targetSNI: configuration.fakeSNI,
                keyShare: randomData(length: 32)
            )

            let remoteFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard remoteFD >= 0 else {
                throw NativeProxyError.connectFailed(SystemNetworkUtils.errnoDescription())
            }
            outgoingFD = remoteFD

            var one: Int32 = 1
            _ = Darwin.setsockopt(remoteFD, SOL_SOCKET, SO_KEEPALIVE, &one, socklen_t(MemoryLayout<Int32>.size))
            _ = Darwin.setsockopt(remoteFD, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            try SystemNetworkUtils.bindSocketToInterface(remoteFD, interface: resolvedInterface)
            statusHandler(resolvedInterface, .debug, "Bound socket to egress interface: \(resolvedInterface.name) (#\(resolvedInterface.index))")

            var localAddress = try SystemNetworkUtils.sockaddrIn(ipv4: resolvedInterface.ipv4Address, port: 0)
            let bindResult = withUnsafePointer(to: &localAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(remoteFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                throw NativeProxyError.connectFailed("Outgoing bind failed: \(SystemNetworkUtils.errnoDescription())")
            }
            statusHandler(resolvedInterface, .debug, "Bound outgoing socket on \(resolvedInterface.ipv4Address):0")

            var boundAddress = sockaddr_in()
            var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.getsockname(remoteFD, sockaddrPointer, &boundLength)
                }
            }
            guard nameResult == 0 else {
                throw NativeProxyError.connectFailed("Outgoing getsockname failed: \(SystemNetworkUtils.errnoDescription())")
            }

            let localPort = UInt16(bigEndian: boundAddress.sin_port)
            statusHandler(resolvedInterface, .debug, "Acquired local port: \(localPort)")
            let monitor = try PcapBypassMonitor(
                interface: resolvedInterface,
                localPort: localPort,
                remoteIP: configuration.connectIP,
                remotePort: remotePort,
                fakePayload: fakeClientHello,
                logger: { [statusHandler] level, message in
                    statusHandler(resolvedInterface, level, message)
                }
            )
            statusHandler(resolvedInterface, .debug, "Starting pcap monitor | filter=\(monitor.makeFilterExpression())")
            try monitor.start()
            statusHandler(resolvedInterface, .debug, "pcap monitor started")

            do {
                var remoteAddress = try SystemNetworkUtils.sockaddrIn(ipv4: configuration.connectIP, port: remotePort)
                let connectResult = withUnsafePointer(to: &remoteAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        Darwin.connect(remoteFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard connectResult == 0 else {
                    throw NativeProxyError.connectFailed(SystemNetworkUtils.errnoDescription())
                }
                statusHandler(resolvedInterface, .debug, "TCP connect completed, waiting for bypass ACK")

                try monitor.waitUntilReady(timeout: 2)
                statusHandler(resolvedInterface, .debug, "Bypass ready for \(resolvedInterface.ipv4Address):\(localPort) -> \(configuration.connectIP):\(configuration.connectPort)")
            } catch {
                monitor.stop()
                throw error
            }
            monitor.stop()

            let reverseRelay = Thread { [weak self] in
                guard let self else { return }
                self.relay(sourceFD: remoteFD, destinationFD: self.incomingFD, isUpload: false)
            }
            reverseRelay.name = "SNI Reverse Relay"
            reverseRelay.start()

            relay(sourceFD: incomingFD, destinationFD: remoteFD, isUpload: true)
        } catch {
            statusHandler(
                try? SystemNetworkUtils.resolveInterface(
                    forRemoteIPv4: configuration.connectIP,
                    remotePort: try portValue(configuration.connectPort)
                ),
                .error,
                error.localizedDescription
            )
        }
    }

    private func relay(sourceFD: Int32, destinationFD: Int32, isUpload: Bool) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while !isStopped {
            let received = Darwin.recv(sourceFD, &buffer, buffer.count, 0)
            if received <= 0 {
                break
            }

            var sent = 0
            while sent < received {
                let writeCount = buffer.withUnsafeBytes { rawBuffer in
                    let baseAddress = rawBuffer.baseAddress!.advanced(by: sent)
                    return Darwin.send(destinationFD, baseAddress, received - sent, 0)
                }
                if writeCount <= 0 {
                    return
                }
                sent += writeCount
            }
            
            if isUpload {
                bytesUploaded += received
            } else {
                bytesDownloaded += received
            }
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func randomData(length: Int) -> Data {
        Data((0 ..< length).map { _ in UInt8.random(in: 0 ... 255) })
    }

    private func portValue(_ value: Int) throws -> UInt16 {
        guard let port = UInt16(exactly: value) else {
            throw NativeProxyError.invalidListenPort(value)
        }
        return port
    }
}

private final class PcapBypassMonitor {
    private let interface: ResolvedInterface
    private let localPort: UInt16
    private let remoteIP: String
    private let remotePort: UInt16
    private let fakePayload: Data
    private let stateLock = NSLock()
    private var synSequence: UInt32?
    private var synAckSequence: UInt32?
    private var fakeSent = false
    private var session: LibpcapSession?
    private var captureThread: Thread?
    private var completion = DispatchSemaphore(value: 0)
    private var completionError: Error?
    private var running = false
    private var parsedPacketLogs = 0
    private var parseFailureLogs = 0
    private(set) var filterExpression = ""
    private let logger: (ProxyLogLevel, String) -> Void

    init(
        interface: ResolvedInterface,
        localPort: UInt16,
        remoteIP: String,
        remotePort: UInt16,
        fakePayload: Data,
        logger: @escaping (ProxyLogLevel, String) -> Void
    ) throws {
        self.interface = interface
        self.localPort = localPort
        self.remoteIP = remoteIP
        self.remotePort = remotePort
        self.fakePayload = fakePayload
        self.logger = logger
    }

    func makeFilterExpression() -> String {
        // localPort baraye har connection yektast, pas in filter sade baraye har do simt kafi ast.
        "ip and tcp and host \(remoteIP) and port \(localPort)"
    }

    func start() throws {
        let filter = makeFilterExpression()
        filterExpression = filter
        session = try LibpcapSession(device: interface.name, filter: filter)
        if let session {
            logger(.debug, "pcap datalink type: \(session.linkType.description)")
        }
        running = true

        let thread = Thread { [weak self] in
            self?.captureLoop()
        }
        thread.name = "SNI Pcap Monitor"
        captureThread = thread
        thread.start()
    }

    func waitUntilReady(timeout: TimeInterval) throws {
        let waitResult = completion.wait(timeout: .now() + timeout)
        if waitResult != .success {
            throw NativeProxyError.bypassFailed("Timed out waiting for ACK of fake payload")
        }
        if let completionError {
            throw completionError
        }
    }

    func stop() {
        running = false
        session?.stop()
    }

    private func captureLoop() {
        while running {
            do {
                guard let frameData = try session?.nextPacket() else {
                    continue
                }
                try handle(frameData)
            } catch {
                signal(error: error)
                break
            }
        }
    }

    private func handle(_ frameData: Data) throws {
        guard let session else {
            return
        }

        guard let frame = RawPacketSupport.parseIPv4TCPFrame(frameData, linkType: session.linkType) else {
            if parseFailureLogs < 5 {
                parseFailureLogs += 1
                logger(.debug, "Packet parse failed | len=\(frameData.count) | datalink=\(session.linkType.description)")
            }
            return
        }

        if parsedPacketLogs < 8 {
            parsedPacketLogs += 1
            logger(
                .debug,
                "Parsed packet | \(frame.sourceIP):\(frame.sourcePort) -> \(frame.destinationIP):\(frame.destinationPort) | flags=0x\(String(frame.flags, radix: 16)) | payload=\(frame.payload.count)"
            )
        }

        if frame.sourceIP == interface.ipv4Address, frame.destinationIP == remoteIP, frame.sourcePort == localPort, frame.destinationPort == remotePort {
            try handleOutbound(frame)
        } else if frame.sourceIP == remoteIP, frame.destinationIP == interface.ipv4Address, frame.sourcePort == remotePort, frame.destinationPort == localPort {
            try handleInbound(frame)
        }
    }

    private func handleOutbound(_ frame: ParsedEthernetIPv4TCPFrame) throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        if frame.syn, !frame.ack {
            synSequence = frame.sequenceNumber
            logger(.debug, "Captured SYN | seq=\(frame.sequenceNumber)")
            return
        }

        guard
            frame.ack,
            !frame.syn,
            !frame.fin,
            !frame.rst,
            frame.payload.isEmpty,
            let synSequence,
            let synAckSequence
        else {
            return
        }

        guard !fakeSent else {
            return
        }
        guard frame.sequenceNumber == synSequence &+ 1, frame.acknowledgementNumber == synAckSequence &+ 1 else {
            return
        }

        let forcedSequence = synSequence &+ 1 &- UInt32(fakePayload.count)
        logger(.debug, "Injecting fake payload | forcedSeq=\(forcedSequence) | bytes=\(fakePayload.count)")
        let fakeFrame = RawPacketSupport.buildFakePayloadFrame(
            from: frame,
            fakePayload: fakePayload,
            forcedSequenceNumber: forcedSequence
        )
        try session?.inject(frame: fakeFrame)
        logger(.debug, "Fake payload injected")
        fakeSent = true
    }

    private func handleInbound(_ frame: ParsedEthernetIPv4TCPFrame) throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        if frame.syn, frame.ack {
            synAckSequence = frame.sequenceNumber
            logger(.debug, "Captured SYN-ACK | seq=\(frame.sequenceNumber)")
            return
        }

        guard fakeSent else {
            return
        }

        guard frame.ack, !frame.syn, !frame.fin, !frame.rst, frame.payload.isEmpty else {
            return
        }

        guard let synSequence, let synAckSequence else {
            return
        }

        if frame.sequenceNumber == synAckSequence &+ 1, frame.acknowledgementNumber == synSequence &+ 1 {
            logger(.debug, "Captured ACK for fake payload")
            signal(error: nil)
        }
    }

    private func signal(error: Error?) {
        running = false
        completionError = error
        completion.signal()
    }
}

private final class LibpcapSession {
    private var handle: OpaquePointer?
    private var stopped = false
    private let filter: String
    let linkType: PcapDataLink

    init(device: String, filter: String) throws {
        self.filter = filter
        var errbuf = [CChar](repeating: 0, count: 512)
        guard let handle = device.withCString({
            sni_pcap_open_live($0, 65535, 1, 100, &errbuf, errbuf.count)
        }) else {
            throw NativeProxyError.pcapFailed(String(cString: errbuf))
        }

        self.handle = handle
        linkType = PcapDataLink(rawValue: sni_pcap_datalink(handle))

        let nonblockResult = sni_pcap_set_nonblock(handle, 1, &errbuf, errbuf.count)
        guard nonblockResult == 0 else {
            stop()
            throw NativeProxyError.pcapFailed(String(cString: errbuf))
        }

        let filterResult = filter.withCString {
            sni_pcap_set_filter(handle, $0, 1, PCAP_NETMASK_UNKNOWN, &errbuf, errbuf.count)
        }
        guard filterResult == 0 else {
            stop()
            throw NativeProxyError.pcapFailed("\(String(cString: errbuf)) | filter=\(filter)")
        }
    }

    func nextPacket() throws -> Data? {
        guard let handle, !stopped else {
            return nil
        }

        var packetPointer: UnsafeMutablePointer<UInt8>?
        var packetLength: Int32 = 0
        var errbuf = [CChar](repeating: 0, count: 512)
        let result = sni_pcap_next_packet(handle, &packetPointer, &packetLength, &errbuf, errbuf.count)
        switch result {
        case 0:
            return nil
        case 1:
            guard let packetPointer else {
                return nil
            }
            defer {
                sni_pcap_free_packet(packetPointer)
            }
            return Data(bytes: packetPointer, count: Int(packetLength))
        case -2:
            return nil
        default:
            throw NativeProxyError.pcapFailed(String(cString: errbuf))
        }
    }

    func inject(frame: Data) throws {
        guard let handle, !stopped else {
            throw NativeProxyError.pcapFailed("pcap session has been stopped")
        }

        var errbuf = [CChar](repeating: 0, count: 512)
        let written = frame.withUnsafeBytes { rawBuffer in
            sni_pcap_inject(
                handle,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                Int32(frame.count),
                &errbuf,
                errbuf.count
            )
        }
        guard written >= 0 else {
            throw NativeProxyError.pcapFailed(String(cString: errbuf))
        }
    }

    func stop() {
        guard !stopped, let handle else {
            return
        }
        stopped = true
        sni_pcap_breakloop(handle)
        sni_pcap_close(handle)
        self.handle = nil
    }

    deinit {
        stop()
    }
}
