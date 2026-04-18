import AppKit
import SwiftUI

private enum LogFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case info = "Info"
    case error = "Error"
    case debug = "Debug"

    var id: String { rawValue }

    func matches(_ entry: ProxyLogEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .info:
            return entry.level == .info
        case .error:
            return entry.level == .error
        case .debug:
            return entry.level == .debug
        }
    }
}

extension Color {
    static let appBackground = Color(red: 244/255, green: 247/255, blue: 250/255)
    static let cardBackground = Color.white
    static let textPrimary = Color(red: 44/255, green: 62/255, blue: 80/255) // #2C3E50
    static let textSecondary = Color(red: 100/255, green: 116/255, blue: 139/255)
    static let primaryButton = Color(red: 44/255, green: 62/255, blue: 80/255) // #2C3E50
    static let inputBackground = Color.white
    static let inputBorder = Color(red: 226/255, green: 232/255, blue: 240/255)
    static let accentCyan = Color(red: 14/255, green: 165/255, blue: 233/255)
}

struct ContentView: View {
    @EnvironmentObject private var tunnelController: TunnelController
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Namespace private var selectionNamespace
    @State private var selectedLogFilter: LogFilter = .all
    @State private var isLogsPresented = false
    @State private var isDetailsExpanded = false
    @State private var isWorkflowExpanded = false
    @State private var isLanguageMenuExpanded = false
    @State private var isDetailsHovered = false
    @State private var isWorkflowHovered = false
    @State private var isVlessMasked = true

    private var visibleLogEntries: [ProxyLogEntry] {
        tunnelController.helperLogEntries.filter { selectedLogFilter.matches($0) }
    }

    private var copy: AppCopy {
        AppCopy(language: languageStore.selectedLanguage)
    }

    private enum StatusBadgeKind {
        case busy
        case connected
        case error
        case ready
        case disconnected
        case idle
    }

    private struct StatusBadgePresentation {
        let tint: Color
        let kind: StatusBadgeKind
        let isLive: Bool
    }

    private var inputsLocked: Bool {
        tunnelController.isBusy || tunnelController.isConnected
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 248/255, green: 250/255, blue: 252/255),
                    Color(red: 241/255, green: 245/255, blue: 249/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.appBackground
                .opacity(0.12)
                .ignoresSafeArea()

            ScrollView(showsIndicators: true) {
                VStack(spacing: 16) {
                    topBar
                    mainCard
                    
                    HStack(spacing: 8) {
                        infoPill(text: "v1.2.1", icon: "info.circle.fill")
                        infoPill(text: "by PK3NZO", icon: "person.fill")
                        
                        Spacer()
                        
                        infoPill(text: "Shoutout to patterniha for his great project", icon: "heart.fill")
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .sheet(isPresented: $isLogsPresented) {
            logsSheet
        }
        .onChange(of: tunnelController.configuration.logLevel) { _, _ in
            tunnelController.applyLogLevelChangeImmediately()
        }
        .onChange(of: languageStore.selectedLanguage) { _, _ in
            isLanguageMenuExpanded = false
            tunnelController.refreshLocalizedPresentation()
        }
        .frame(minWidth: 820, minHeight: 620)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(copy.appTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text(copy.appSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(alignment: .center, spacing: 10) {
                connectionModeSwitch
                languageSelector
            }
        }
    }

    private var mainCard: some View {
        CleanCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(copy.connectionTitle)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrimary)

                        Text(copy.connectionSubtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    statusBadge()
                }

                VStack(spacing: 18) {
                    HStack(spacing: 16) {
                        configField(title: copy.allowlistDomainTitle) {
                            TextField(copy.allowlistDomainPlaceholder, text: $tunnelController.whitelistDomainInput)
                                .opacity(inputsLocked ? 0.6 : 1.0)
                                .disabled(inputsLocked)
                        }

                        configField(title: copy.allowlistIPTitle) {
                            TextField(copy.allowlistIPPlaceholder, text: $tunnelController.whitelistIPInput)
                                .opacity(inputsLocked ? 0.6 : 1.0)
                                .disabled(inputsLocked)
                        }
                    }

                    configField(title: copy.vlessConfigTitle) {
                        ZStack(alignment: .topLeading) {
                            // The actual TextEditor (always present for layout, but invisible/blurred when masked)
                            TextEditor(text: $tunnelController.vlessConfigInput)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 12)
                                .padding(.top, 34) // Make space for the top-right buttons
                                .padding(.bottom, 10)
                                .frame(minHeight: 110)
                                .opacity(isVlessMasked ? 0.0 : (inputsLocked ? 0.6 : 1.0))
                                .disabled(inputsLocked || isVlessMasked)
                            
                            // The "Smooth" Masked View (only shows when masked)
                            if isVlessMasked {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 0) {
                                        maskedVlessText(tunnelController.vlessConfigInput)
                                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.textPrimary)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 38)
                                            .padding(.bottom, 14)
                                    }
                                }
                                .frame(height: 110)
                                .allowsHitTesting(false)
                            }
                            
                            // Top-Right Control Buttons Overlay
                            HStack(spacing: 6) {
                                Button {
                                    isVlessMasked.toggle()
                                } label: {
                                    Image(systemName: isVlessMasked ? "eye.slash" : "eye")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(isVlessMasked ? "Show Config" : "Hide Config")
                                
                                Button {
                                    let pasteboard = NSPasteboard.general
                                    if let content = pasteboard.string(forType: .string) {
                                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let validPrefixes = ["vless://", "vmess://", "trojan://", "ss://"]
                                        let isValidFormat = validPrefixes.contains { trimmed.lowercased().hasPrefix($0) }
                                        
                                        if isValidFormat && trimmed.count <= 10000 {
                                            tunnelController.vlessConfigInput = trimmed
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.square.dashed")
                                        Text("Paste")
                                    }
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(inputsLocked ? Color.textSecondary : Color.accentCyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(inputsLocked ? Color.textSecondary.opacity(0.1) : Color.accentCyan.opacity(0.1))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(inputsLocked)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                            
                            // Sharp Border (Always sharp, never blurred)
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.inputBorder, lineWidth: 1)
                                .allowsHitTesting(false)
                            
                            if inputsLocked && !isVlessMasked {
                                Color.white.opacity(0.01)
                                    .onTapGesture {}
                                    .onHover { _ in }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.inputBackground)
                        )
                        .animation(.easeInOut(duration: 0.2), value: isVlessMasked)
                    }
                }

                if tunnelController.isConnected || tunnelController.isPrivilegedHelperRunning {
                    ActiveProxyStatsView()
                }

                HStack(alignment: .top, spacing: 14) {
                    compactSectionButton(
                        title: copy.detailsTitle,
                        subtitle: tunnelController.connectionDetail,
                        isExpanded: isDetailsExpanded,
                        isHovered: isDetailsHovered,
                        action: { isDetailsExpanded.toggle() },
                        onHover: { hovering in isDetailsHovered = hovering }
                    )

                    compactSectionButton(
                        title: copy.workflowTitle,
                        subtitle: copy.workflowSubtitle(count: tunnelController.workflowSteps.count),
                        isExpanded: isWorkflowExpanded,
                        isHovered: isWorkflowHovered,
                        action: { isWorkflowExpanded.toggle() },
                        onHover: { hovering in isWorkflowHovered = hovering }
                    )
                }

                if isDetailsExpanded {
                    detailsSection
                }

                if isWorkflowExpanded {
                    workflowSection
                }

                if tunnelController.isBusy {
                    Label(copy.workingTitle, systemImage: "hourglass")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                }

                if !tunnelController.lastErrorDescription.isEmpty {
                    errorBanner(tunnelController.lastErrorDescription)
                }

                HStack(spacing: 12) {
                    actionButton(
                        title: tunnelController.isConnected ? copy.disconnectTitle : copy.connectTitle,
                        systemImage: tunnelController.isConnected ? "stop.fill" : "play.fill",
                        emphasis: .primary,
                        action: tunnelController.isConnected
                            ? tunnelController.disconnectEmbeddedFlow
                            : tunnelController.connectEmbeddedFlow
                    )

                    actionButton(
                        title: copy.logsTitle,
                        systemImage: "text.justify",
                        emphasis: .secondary,
                        action: { isLogsPresented = true }
                    )
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(spacing: 12) {
            infoRow(label: copy.modeLabel, value: copy.connectionModeTitle(tunnelController.selectedConnectionMode))
            infoRow(label: copy.connectionLabel, value: tunnelController.connectionDetail)
            infoRow(label: copy.allowlistLabel, value: tunnelController.activeConnectionSummary)
            infoRow(label: copy.systemRouteLabel, value: tunnelController.routeManagerSummary)
            infoRow(label: copy.originalServerLabel, value: tunnelController.originalServerSummary)
            infoRow(label: copy.probeLabel, value: tunnelController.lastProbeDescription)
        }
    }

    private var detailsSection: some View {
        VStack(spacing: 12) {
            summarySection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
    }

    private var connectionModeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(AppConnectionMode.allCases) { mode in
                Button {
                    guard !tunnelController.isBusy && !tunnelController.isConnected else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        tunnelController.selectedConnectionMode = mode
                    }
                } label: {
                    Text(copy.connectionModeTitle(mode))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(tunnelController.selectedConnectionMode == mode ? Color.white : Color.textSecondary)
                        .frame(width: 80, height: 32)
                        .background(
                            ZStack {
                                if tunnelController.selectedConnectionMode == mode {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Color(red: 30/255, green: 111/255, blue: 255/255))
                                        .matchedGeometryEffect(id: "connectionModeSelection", in: selectionNamespace)
                                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .disabled(tunnelController.isBusy || tunnelController.isConnected)
                .frame(maxHeight: .infinity)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
        .accessibilityElement(children: .contain)
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tunnelController.workflowSteps) { step in
                workflowRow(step)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
    }

    private func compactSectionButton(
        title: String,
        subtitle: String,
        isExpanded: Bool,
        isHovered: Bool,
        action: @escaping () -> Void,
        onHover: @escaping (Bool) -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(isExpanded ? "Hide" : "Show")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovered ? Color.white : Color(red: 248/255, green: 250/255, blue: 252/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHovered ? Color.accentCyan.opacity(0.3) : Color.inputBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0), radius: 10, x: 0, y: 5)
            .onHover(perform: onHover)
        }
        .buttonStyle(.plain)
    }

    private var logsSheet: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copy.logsHeader)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrimary)

                        Text(copy.logsDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    compactIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: copy.closeLogsLabel,
                        action: { isLogsPresented = false }
                    )
                }

                HStack(spacing: 12) {
                    Picker(copy.filterPickerLabel, selection: $selectedLogFilter) {
                        ForEach(LogFilter.allCases) { filter in
                            Text(copy.logFilterTitle(filter.rawValue)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                    .fixedSize()

                    Spacer()

                    HStack(spacing: 10) {
                        compactIconButton(
                            systemImage: "doc.on.doc",
                            accessibilityLabel: copy.copyVisibleLogsLabel,
                            action: copyVisibleLogs
                        )

                        compactIconButton(
                            systemImage: "doc.richtext",
                            accessibilityLabel: copy.copyDiagnosticDumpLabel,
                            action: copyDiagnosticDump
                        )

                        compactIconButton(
                            systemImage: "trash",
                            accessibilityLabel: copy.clearLogsLabel,
                            action: tunnelController.clearLogs
                        )
                    }
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CleanCard {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if visibleLogEntries.isEmpty {
                                Text(copy.noLogsAvailable)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 280)
                            } else {
                                ForEach(visibleLogEntries.reversed()) { entry in
                                    logRow(entry)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(28)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private func configField<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                
                Spacer()
                
                trailing()
            }

            content()
                .textFieldStyle(CleanTextFieldStyle())
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
    }

    private func workflowRow(_ step: ConnectionWorkflowStep) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: workflowIcon(for: step.state))
                .foregroundStyle(workflowTint(for: step.state))
                .font(.system(size: 15, weight: .bold))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(copy.workflowStepTitle(step.key))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text(step.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Text(copy.workflowStateTitle(step.state))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(workflowTint(for: step.state))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    private func workflowIcon(for state: ConnectionWorkflowStepState) -> String {
        switch state {
        case .pending:
            return "circle.dashed"
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    private func workflowTint(for state: ConnectionWorkflowStepState) -> Color {
        switch state {
        case .pending:
            return Color.textSecondary
        case .running:
            return Color.accentCyan
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    private func logRow(_ entry: ProxyLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.level.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(logTint(for: entry.level))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
    }

    private func compactIconButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.inputBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
    }

    private func copyVisibleLogs() {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none

        let text = visibleLogEntries.map { entry in
            "[\(entry.level.rawValue.uppercased())] \(formatter.string(from: entry.timestamp)) \(entry.message)"
        }.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copyDiagnosticDump() {
        let text = tunnelController.diagnosticDump()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    
    private func maskedVlessText(_ input: String) -> some View {
        guard !input.isEmpty else { return Text("") }
        
        var masked = input
        
        // Mask UUID (between vless:// and @)
        if let vlessRange = masked.range(of: "vless://"),
           let atRange = masked.range(of: "@"),
           vlessRange.upperBound < atRange.lowerBound {
            let uuidRange = vlessRange.upperBound..<atRange.lowerBound
            masked.replaceSubrange(uuidRange, with: "••••••••-••••-••••-••••-••••••••••••")
        }
        
        // Mask Host and SNI
        let sensitiveKeys = ["host=", "sni="]
        for key in sensitiveKeys {
            if let keyRange = masked.range(of: key) {
                let valueStart = keyRange.upperBound
                let valueEnd = masked[valueStart...].firstIndex(where: { $0 == "&" || $0 == "#" || $0 == " " }) ?? masked.endIndex
                if valueStart < valueEnd {
                    masked.replaceSubrange(valueStart..<valueEnd, with: "••••••••••••")
                }
            }
        }
        
        return Text(masked)
    }

    private func infoPill(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(Color.textSecondary.opacity(0.7))
        .background(
            Capsule()
                .fill(Color.cardBackground.opacity(0.5))
        )
        .overlay(
            Capsule()
                .stroke(Color.inputBorder.opacity(0.4), lineWidth: 1)
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        emphasis: ButtonEmphasis,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CleanButtonStyle(emphasis: emphasis))
    }

    private func statusBadge() -> some View {
        let title = tunnelController.connectionHeadline
        let isBusy = tunnelController.isBusy
        let hasError = !tunnelController.lastErrorDescription.isEmpty && !tunnelController.isConnected
        let isReady = title == copy.readyHeadline
        let isDisconnected = title == copy.disconnectedHeadline
        let badgeState = "\(title)|\(isBusy)|\(tunnelController.isConnected)|\(hasError)"
        let presentation: StatusBadgePresentation

        if isBusy {
            presentation = StatusBadgePresentation(
                tint: Color(red: 14/255, green: 165/255, blue: 233/255), // Sky Blue
                kind: .busy,
                isLive: true
            )
        } else if tunnelController.isConnected {
            presentation = StatusBadgePresentation(
                tint: Color(red: 34/255, green: 197/255, blue: 94/255), // Emerald Green
                kind: .connected,
                isLive: true
            )
        } else if hasError {
            presentation = StatusBadgePresentation(
                tint: Color(red: 239/255, green: 68/255, blue: 68/255), // Red
                kind: .error,
                isLive: false
            )
        } else if isDisconnected {
            presentation = StatusBadgePresentation(
                tint: Color(red: 100/255, green: 116/255, blue: 139/255), // Slate
                kind: .disconnected,
                isLive: false
            )
        } else if isReady {
            presentation = StatusBadgePresentation(
                tint: Color(red: 59/255, green: 130/255, blue: 246/255), // Blue
                kind: .ready,
                isLive: true
            )
        } else {
            presentation = StatusBadgePresentation(
                tint: Color(red: 59/255, green: 130/255, blue: 246/255), // Blue
                kind: .idle,
                isLive: false
            )
        }

        return HStack(alignment: .center, spacing: 10) {
            statusBadgeGlyph(
                tint: presentation.tint,
                kind: presentation.kind,
                isLive: presentation.isLive
            )

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(presentation.tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(presentation.tint.opacity(0.18), lineWidth: 1.2)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: badgeState)
    }

    private func statusBadgeGlyph(
        tint: Color,
        kind: StatusBadgeKind,
        isLive: Bool
    ) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let wave = 0.5 + 0.5 * sin(phase * 2.8)
            let pulse = 0.5 + 0.5 * sin(phase * 4.5)
            let slowWave = 0.5 + 0.5 * sin(phase * 1.5)
            
            let scale = 1.0 + (isLive ? wave * 0.06 : 0.0)
            let rotation = phase * 220.0
            
            ZStack {
                // Outer Glow / Ripple effect for "live" states
                if isLive {
                    Circle()
                        .stroke(tint.opacity(0.25 - (wave * 0.2)), lineWidth: 2)
                        .scaleEffect(1.1 + wave * 0.45)
                        .opacity(1.0 - wave)
                    
                    Circle()
                        .stroke(tint.opacity(0.15), lineWidth: 1)
                        .scaleEffect(1.05 + wave * 0.2)
                }
                
                // Main Circle Background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(scale)
                    .shadow(color: tint.opacity(isLive ? 0.45 : 0.2), radius: isLive ? 8 : 4, x: 0, y: 3)

                // Symbol Layer
                Group {
                    switch kind {
                    case .busy:
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(rotation))
                        
                    case .connected:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .scaleEffect(0.95 + wave * 0.1)
                        
                    case .error:
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 13, weight: .bold))
                            .scaleEffect(0.9 + pulse * 0.2)
                        
                    case .ready:
                        // Ready state: A pulsing bolt indicating "energy" available
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .scaleEffect(0.85 + pulse * 0.25)
                            .shadow(color: .white.opacity(0.6), radius: 4 * pulse)
                        
                    case .disconnected:
                        // Disconnected: A steady, slightly dimmed power icon with a slow breath
                        Image(systemName: "power")
                            .font(.system(size: 13, weight: .black))
                            .opacity(0.6 + slowWave * 0.4)
                            .scaleEffect(0.9 + slowWave * 0.05)
                        
                    case .idle:
                        Image(systemName: "circle.hexagonpath")
                            .font(.system(size: 14, weight: .bold))
                            .rotationEffect(.degrees(phase * 40))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
            }
            .frame(width: 28, height: 28)
        }
    }

    private func logTint(for level: ProxyLogLevel) -> Color {
        switch level {
        case .debug:
            return .blue
        case .info:
            return .green
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private func flagImage(for language: AppLanguage, size: CGFloat) -> some View {
        if let url = Bundle.main.url(forResource: language.flagResourceName, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            AsyncImage(url: language.flagURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                case .failure, .empty:
                    Text(language.flagEmoji)
                        .font(.system(size: size * 0.85))
                        .frame(width: size, height: size)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: size, height: size)
        }
    }

    private var languageSelector: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isLanguageMenuExpanded.toggle()
            }
        } label: {
            flagImage(for: languageStore.selectedLanguage, size: 26)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.inputBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isLanguageMenuExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        languageStore.selectedLanguage = language
                        isLanguageMenuExpanded = false
                    } label: {
                        HStack(spacing: 14) {
                            flagImage(for: language, size: 32)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.displayName(in: languageStore.selectedLanguage))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.textPrimary)
                                Text(language.subtitle(in: languageStore.selectedLanguage))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(language == languageStore.selectedLanguage ? Color(red: 236/255, green: 244/255, blue: 255/255) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.inputBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(width: 260)
            .background(Color.white)
        }
    }

    private func languageSelectorCard(
        title: String,
        subtitle: String,
        flag: String,
        chevronName: String?,
        isSelected: Bool,
        compact: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: compact ? 10 : 12) {
            if let chevronName {
                Image(systemName: chevronName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }

            Text(flag)
                .font(.system(size: compact ? 21 : 23))
                .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)

            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Text(title)
                    .font(.system(size: compact ? 14 : 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous)
                .fill(isSelected ? Color.white : Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.04 : 0), radius: 10, x: 0, y: 4)
    }
}


private struct CleanCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 8)
    }
}

private struct CleanTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.inputBorder, lineWidth: 1)
            )
    }
}

private enum ButtonEmphasis {
    case primary
    case secondary
    case ghost
}

private struct CleanButtonStyle: ButtonStyle {
    let emphasis: ButtonEmphasis

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(textColor(for: emphasis))
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(background(configuration: configuration))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor(for: emphasis), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> some View {
        let opacity = configuration.isPressed ? 0.9 : 1.0

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(fillColor(for: emphasis).opacity(opacity))
            .shadow(color: emphasis == .primary ? Color.primaryButton.opacity(0.2) : Color.clear, radius: 8, x: 0, y: 4)
    }

    private func fillColor(for emphasis: ButtonEmphasis) -> Color {
        switch emphasis {
        case .primary:
            return Color.primaryButton
        case .secondary:
            return Color.white
        case .ghost:
            return Color.clear
        }
    }
    
    private func textColor(for emphasis: ButtonEmphasis) -> Color {
        switch emphasis {
        case .primary:
            return .white
        case .secondary:
            return Color.textPrimary
        case .ghost:
            return Color.textPrimary
        }
    }
    
    private func borderColor(for emphasis: ButtonEmphasis) -> Color {
        switch emphasis {
        case .primary:
            return .clear
        case .secondary:
            return Color.inputBorder
        case .ghost:
            return .clear
        }
    }
}

struct ActiveProxyStatsView: View {
    @EnvironmentObject var tunnelController: TunnelController
    @EnvironmentObject var languageStore: AppLanguageStore

    private var copy: AppCopy {
        AppCopy(language: languageStore.selectedLanguage)
    }

    var body: some View {
        HStack(spacing: 8) {
            LiveStatCard(
                title: copy.downloadStatLabel,
                value: formatBytes(tunnelController.proxyDownloadSpeed) + "/s",
                icon: "arrow.down",
                color: Color(red: 34/255, green: 197/255, blue: 94/255), // Emerald Green
                speed: tunnelController.proxyDownloadSpeed
            )

            LiveStatCard(
                title: copy.uploadStatLabel,
                value: formatBytes(tunnelController.proxyUploadSpeed) + "/s",
                icon: "arrow.up",
                color: Color.blue,
                speed: tunnelController.proxyUploadSpeed
            )
            
            LiveStatCard(
                title: "Total Usage",
                value: formatTotalBytes(tunnelController.proxyTotalBytes),
                icon: "chart.bar.fill",
                color: Color.orange,
                speed: 0 // No flowing animation for total
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func formatTotalBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let exp = Int(log2(Double(bytes)) / 10)
        let units = ["KB", "MB", "GB", "TB", "PB"]
        let value = Double(bytes) / pow(1024, Double(exp))
        return String(format: "%.2f %@", value, units[exp - 1])
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let exp = Int(log2(Double(bytes)) / 10)
        let units = ["KB", "MB", "GB", "TB", "PB", "EB"]
        let value = Double(bytes) / pow(1024, Double(exp))
        return String(format: "%.1f %@", value, units[exp - 1])
    }
}

struct LiveStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let speed: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                LiveTrafficIcon(icon: icon, color: color, speed: speed)
                
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 248/255, green: 250/255, blue: 252/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.inputBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 4)
    }
}

struct LiveTrafficIcon: View {
    let icon: String
    let color: Color
    let speed: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            // Animation speed scales with traffic speed (max out at a reasonable visual rate)
            let baseSpeed = 1.5
            let trafficFactor = min(Double(speed) / 500_000.0, 5.0) // Scale up to 500KB/s
            let totalSpeed = baseSpeed + trafficFactor
            
            let offset = (phase * totalSpeed).truncatingRemainder(dividingBy: 1.0)
            
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 28, height: 28)
                
                // Animated arrows flowing
                VStack(spacing: -4) {
                    ForEach(0..<2) { i in
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(color)
                            .offset(y: CGFloat((Double(i) - offset) * 12))
                            .opacity(opacity(for: Double(i) - offset))
                    }
                }
                .frame(width: 20, height: 18)
                .clipped()
            }
        }
    }

    private func opacity(for offset: Double) -> Double {
        // Fade in at top, fade out at bottom
        if offset < 0 { return 1.0 + offset }
        if offset > 1.0 { return 2.0 - offset }
        return 1.0
    }
}
