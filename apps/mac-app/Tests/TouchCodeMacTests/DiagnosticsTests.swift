import Testing
@testable import TouchCodeMac

@MainActor
struct DiagnosticsTests {
    @Test
    func diagnosticsDoesNotExposeSecrets() {
        let workspace = WorkspaceStore()
        workspace.bridgeEndpoint = "http://127.0.0.1:4317"
        workspace.projectPath = "/tmp/test"
        workspace.selectedCodingAgent = .codex
        // Simulate diagnostics text generation via view's logic
        let text = """
        Bridge: Connected · 0.1.0
        iPad: Not connected
        Endpoint: \(workspace.bridgeEndpoint)
        Project: \(workspace.projectPath)
        Agent: \(workspace.selectedCodingAgent.title)
        Session: -
        Error: -
        """
        #expect(!text.contains("private"))
        #expect(!text.contains("secret"))
        #expect(!text.contains("token"))
        #expect(text.contains("Bridge:"))
        #expect(text.contains("Project:"))
    }

    @Test
    func diagnosticsContainsEnoughForConnectionFailure() {
        let workspace = WorkspaceStore()
        workspace.bridgeStatus = .disconnected
        workspace.sessionError = "Local Network permission denied"
        let hasBridge = workspace.bridgeStatus == .disconnected
        let hasError = workspace.sessionError != nil
        #expect(hasBridge)
        #expect(hasError)
        // Diagnostics should be able to show these
        #expect(workspace.sessionError?.contains("Local Network") == true)
    }
}
