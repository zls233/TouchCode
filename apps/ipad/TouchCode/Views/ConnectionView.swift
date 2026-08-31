import SwiftUI

struct ConnectionView: View {
    @State private var bridgeAddress: String = {
        UserDefaults.standard.string(forKey: "bridgeAddress") ?? "http://127.0.0.1:4317"
    }()
    @State private var pairingCode = ""
    @State private var session: PairedWorkspaceSession?
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let session, let bridgeURL = URL(string: bridgeAddress) {
                WorkspaceView(session: session, bridgeURL: bridgeURL) {
                    self.session = nil
                }
            } else {
                VStack(spacing: 22) {
                    Image(systemName: "ipad.and.arrow.forward")
                        .font(.system(size: 54))
                        .foregroundStyle(.tint)
                    Text("Connect to TouchCode CLI")
                        .font(.largeTitle.bold())
                    Text("Enter the bridge address and six-digit code printed by the CLI on your Mac.")
                        .foregroundStyle(.secondary)
                    TextField("http://192.168.1.10:4317", text: $bridgeAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 440)
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
                    Button(isConnecting ? "Pairing…" : "Connect") {
                        Task { await connect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isConnecting || pairingCode.count != 6)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                .padding(40)
            }
        }
    }

    private func connect() async {
        guard let url = URL(string: bridgeAddress) else {
            errorMessage = "Invalid bridge address"
            return
        }
        UserDefaults.standard.set(bridgeAddress, forKey: "bridgeAddress")
        isConnecting = true
        defer { isConnecting = false }
        do {
            session = try await TouchCodeAPIClient(bridgeURL: url).pair(code: pairingCode)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
