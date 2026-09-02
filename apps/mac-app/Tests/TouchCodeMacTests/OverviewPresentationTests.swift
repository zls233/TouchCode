import Testing
@testable import TouchCodeMac

@MainActor
struct OverviewPresentationTests {
    @Test
    func presentationStateTitlesAreUserFacing() {
        #expect(ConnectionPresentationState.starting.title == "Starting TouchCode…")
        #expect(ConnectionPresentationState.ready.title == "Ready for your iPad")
        #expect(ConnectionPresentationState.permissionRequired.title == "Local Network Access Required")
        #expect(ConnectionPresentationState.waiting.title == "Waiting for your iPad…")
        #expect(ConnectionPresentationState.pairing(deviceName: "Lishan's iPad").title == "Pairing with Lishan's iPad")
        #expect(ConnectionPresentationState.connecting(deviceName: "Lishan's iPad").title == "Connecting to Lishan's iPad…")
        #expect(ConnectionPresentationState.connected(deviceName: "Lishan's iPad").title == "Connected to Lishan's iPad")
        #expect(ConnectionPresentationState.reconnecting(deviceName: nil).title == "Reconnecting…")
        #expect(ConnectionPresentationState.unavailable(reason: "Connection lost").title == "Connection lost")
    }

    @Test
    func primaryActionRules() {
        #expect(ConnectionPresentationState.ready.primaryActionTitle == nil)
        #expect(ConnectionPresentationState.connected(deviceName: "iPad").primaryActionTitle == nil)
        #expect(ConnectionPresentationState.permissionRequired.primaryActionTitle == "Open System Settings")
        #expect(ConnectionPresentationState.waiting.primaryActionTitle == "Try Again")
        #expect(ConnectionPresentationState.unavailable(reason: "x").primaryActionTitle == "Try Again")
    }

    @Test
    func viewModelMapsWorkspaceToPresentationState() {
        let workspace = WorkspaceStore()
        let viewModel = OverviewViewModel()
        // Initial state is starting
        viewModel.update(from: workspace)
        #expect(viewModel.presentationState == .starting)
        // Simulate bridge connected, no session -> ready
        workspace.bridgeStatus = .connected(version: "0.1.0")
        viewModel.update(from: workspace)
        #expect(viewModel.presentationState == .ready)
        #expect(viewModel.statusRows.count >= 2)
    }

    @Test
    func statusRowsDoNotExposeTechnicalDetails() {
        let viewModel = OverviewViewModel()
        // Ensure status rows do not contain raw transport details
        for row in viewModel.statusRows {
            #expect(!row.detail.contains("generation"))
            #expect(!row.detail.contains("heartbeat"))
            #expect(!row.detail.contains("NWBrowser"))
        }
    }
}
