import SwiftUI

struct ConnectionView: View {
    @StateObject private var touchCodeSession = TouchCodeSession()
    @State private var bridgeAddress: String = {
        UserDefaults.standard.string(forKey: "bridgeAddress") ?? "http://127.0.0.1:4317"
    }()
    @State private var pairingCode = ""
    @State private var pairedSession: PairedWorkspaceSession?
    @State private var pairedBridgeURL: URL?
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var manualConnectionPresented = false

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
        .onDisappear { touchCodeSession.stop() }
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
                }

                DisclosureGroup("Connect manually", isExpanded: $manualConnectionPresented) {
                    manualControls.padding(.top, 12)
                }
                .frame(maxWidth: 440)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
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
        case .discovering, .connecting: true
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
        case .permissionRequired: "Local Network access required"
        }
    }

    private var connectionExplanation: String {
        switch touchCodeSession.state {
        case .idle:
            "TouchCode uses your local network to find the Mac running your workspace."
        case .discovering, .connecting:
            "Keep TouchCode running on your Mac and make sure both devices are nearby."
        case .connected:
            "Your Mac is ready. Pair once to open its workspace."
        case .unavailable:
            "Open TouchCode on your Mac, check that both devices are on the same local network, then try again."
        case .permissionRequired:
            "Allow Local Network access in Settings so TouchCode can find your Mac."
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
