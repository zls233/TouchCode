import SwiftUI

struct ConnectionView: View {
    @StateObject private var touchCodeSession = TouchCodeSession()
    @Environment(\.scenePhase) private var scenePhase
    @State private var bridgeAddress: String = {
        UserDefaults.standard.string(forKey: "bridgeAddress") ?? "http://127.0.0.1:4317"
    }()
    @State private var pairingCode = ""
    @State private var pairedSession: PairedWorkspaceSession?
    @State private var pairedBridgeURL: URL?
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var manualConnectionPresented = false
    @State private var diagnosticsPresented = false

    var body: some View {
        Group {
            if let pairedSession, let bridgeURL = pairedBridgeURL {
                WorkspaceView(session: pairedSession, bridgeURL: bridgeURL) {
                    self.pairedSession = nil
                    self.pairedBridgeURL = nil
                }
            } else {
                connectionContent
            }
        }
        .onAppear {
            // Phase 6: auto-connect last trusted Mac without user tap
            if touchCodeSession.state == .idle {
                Task { await touchCodeSession.findMac() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                touchCodeSession.handleForeground()
            }
        }
        .onDisappear { touchCodeSession.stop() }
        .sheet(isPresented: $diagnosticsPresented) {
            NavigationStack {
                DiagnosticsView(session: touchCodeSession, gatewayURL: nil, previewURL: pairedSession?.previewURL)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { diagnosticsPresented = false } } }
            }
        }
    }

    private var connectionContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: connectionSymbol)
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: isSearching)
                Text(connectionTitle)
                    .font(.largeTitle.bold())
                Text(connectionExplanation)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

                if activeBridgeURL != nil {
                    pairingControls
                } else {
                    discoveryControls
                    if touchCodeSession.discoveredHosts.count > 1 {
                        multiMacSwitcher
                    }
                }

                DisclosureGroup("Connect manually", isExpanded: $manualConnectionPresented) {
                    manualControls.padding(.top, 12)
                }
                .frame(maxWidth: 440)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Button("Diagnostics") { diagnosticsPresented = true }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var discoveryControls: some View {
        VStack(spacing: 12) {
            Button(discoveryButtonTitle) {
                Task {
                    errorMessage = nil
                    if touchCodeSession.state == .idle {
                        await touchCodeSession.findMac()
                    } else {
                        await touchCodeSession.retry()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSearching)

            if isSearching { ProgressView().controlSize(.small) }
        }
    }

    private var multiMacSwitcher: some View {
        VStack(spacing: 8) {
            Text("My Macs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(touchCodeSession.discoveredHosts, id: \.id) { host in
                Button {
                    Task {
                        // Selecting a host triggers direct connect via session's ordered priority;
                        // For Phase 6a we simply retry and let lastTrustedStore prioritize,
                        // but we also allow explicit selection by saving to store.
                        UserDefaults.standard.set(host.id, forKey: "com.touchcode.lastTrustedHostID")
                        await touchCodeSession.retry()
                    }
                } label: {
                    HStack {
                        Text(host.name)
                        Spacer()
                        if touchCodeSession.selectedHostIDForDiagnostics == host.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: 440)
    }

    private var pairingControls: some View {
        VStack(spacing: 14) {
            Text("Enter the six-digit code shown by TouchCode on your Mac.")
                .foregroundStyle(.secondary)
            pairingCodeField
            Button(isPairing ? "Pairing…" : "Pair") {
                Task { await pair(using: activeBridgeURL) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPairing || pairingCode.count != 6)
        }
    }

    private var manualControls: some View {
        VStack(spacing: 12) {
            TextField("http://192.168.1.10:4317", text: $bridgeAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            pairingCodeField
            Button(isPairing ? "Pairing…" : "Connect") {
                Task { await pair(using: TouchCodeAPIClient.validatedBridgeURL(from: bridgeAddress)) }
            }
            .buttonStyle(.bordered)
            .disabled(isPairing || pairingCode.count != 6)
        }
    }

    private var pairingCodeField: some View {
        TextField("6-digit pairing code", text: $pairingCode)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.title2.monospacedDigit().weight(.semibold))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 240)
            .onChange(of: pairingCode) { _, newValue in
                let filtered = String(newValue.filter(\.isNumber).prefix(6))
                if pairingCode != filtered { pairingCode = filtered }
            }
    }

    private var activeBridgeURL: URL? { touchCodeSession.bridgeURL }

    private var isSearching: Bool {
        switch touchCodeSession.state {
        case .discovering, .connecting, .reconnecting: true
        default: false
        }
    }

    private var connectionSymbol: String {
        switch touchCodeSession.state {
        case .connected: "macbook.and.ipad"
        case .permissionRequired: "lock.trianglebadge.exclamationmark"
        default: "ipad.and.arrow.forward"
        }
    }

    private var connectionTitle: String {
        switch touchCodeSession.state {
        case .idle: "Connect TouchCode to your Mac"
        case .discovering: "Looking for your Mac…"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): "Connected to \(name)"
        case .unavailable: "Mac unavailable"
        case .permissionRequired: "Enable Local Network Access"
        case .reconnecting: "Reconnecting…"
        }
    }

    private var connectionExplanation: String {
        switch touchCodeSession.state {
        case .idle:
            "TouchCode finds your Mac nearby — no IP or pairing code needed after first time."
        case .discovering, .connecting, .reconnecting:
            "Keep TouchCode running on your Mac and make sure both devices are on the same trusted network."
        case .connected:
            "Your Mac is ready. Pair once to open its workspace — next time it reconnects automatically."
        case .unavailable:
            "Open TouchCode on your Mac, check that both devices are on the same local network, then try again."
        case .permissionRequired:
            "TouchCode needs Local Network access to find your Mac automatically. Enable it in Settings → Privacy → Local Network, then tap Try Again."
        }
    }

    private var discoveryButtonTitle: String {
        switch touchCodeSession.state {
        case .idle: "Find My Mac"
        case .permissionRequired: "Try Again"
        default: "Retry"
        }
    }

    private func pair(using url: URL?) async {
        guard let url else {
            errorMessage = "Enter a valid TouchCode Bridge address."
            return
        }
        bridgeAddress = url.absoluteString
        isPairing = true
        defer { isPairing = false }
        do {
            UserDefaults.standard.set(bridgeAddress, forKey: "bridgeAddress")
            let session = try await TouchCodeAPIClient(bridgeURL: url).pair(code: pairingCode)
            pairedBridgeURL = url
            pairedSession = session
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
