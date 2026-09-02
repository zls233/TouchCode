import Testing
@testable import TouchCodeMac

struct PolishTests {
    @Test
    func navigationShortcutsAreStableAndUnique() {
        let destinations = SidebarDestination.allCases
        #expect(destinations.map(\.keyboardShortcut) == ["1", "2", "3", "4"])
        #expect(Set(destinations.map(\.keyboardShortcut)).count == destinations.count)
    }

    @Test
    func everyStatusSeverityHasAUserFacingAccessibilityValue() {
        let severities: [StatusRowModel.Severity] = [
            .normal, .active, .waiting, .warning, .error, .unavailable,
        ]

        for severity in severities {
            #expect(!severity.accessibilityLabel.isEmpty)
        }
    }
}
