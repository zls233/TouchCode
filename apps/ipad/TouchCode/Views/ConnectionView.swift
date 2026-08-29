import SwiftUI

struct ConnectionView: View {
    @State private var bridgeAddress = "http://192.168.1.10:4317"
    @State private var session: DemoSession?
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let session, let bridgeURL = URL(string: bridgeAddress) {
                WorkspaceView(session: session, bridgeURL: bridgeURL)
            } else {
                VStack(spacing: 22) {
                    Image(systemName: "ipad.and.arrow.forward")
                        .font(.system(size: 54))
                        .foregroundStyle(.tint)
                    Text("Connect to TouchCode Mac")
                        .font(.largeTitle.bold())
                    Text("Enter the bridge address shown by the Mac app.")
                        .foregroundStyle(.secondary)
                    TextField("http://192.168.1.10:4317", text: $bridgeAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 440)
                    Button(isConnecting ? "Connecting…" : "Start MVP Session") {
                        Task { await connect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isConnecting)
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
        isConnecting = true
        defer { isConnecting = false }
        do {
            session = try await TouchCodeAPIClient(bridgeURL: url).createDemoSession()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

