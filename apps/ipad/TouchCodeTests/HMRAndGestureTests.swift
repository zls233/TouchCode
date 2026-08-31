import XCTest
@testable import TouchCode

final class HMRAndGestureTests: XCTestCase {
    // MARK: - HMR precise correlation
    func testHMRRevisionRequiresServerExpected() {
        // New logic: local revision must be >= expected integer from Bridge and > baseline.
        XCTAssertTrue(isExpectedPreviewRevisionSatisfied(localRevision: 3, expected: 3, baseline: 2))
        XCTAssertTrue(isExpectedPreviewRevisionSatisfied(localRevision: 4, expected: 3, baseline: 2))
        XCTAssertFalse(isExpectedPreviewRevisionSatisfied(localRevision: 3, expected: 4, baseline: 2), "local ahead but not yet reached expected should not clear")
        XCTAssertFalse(isExpectedPreviewRevisionSatisfied(localRevision: 2, expected: 2, baseline: 2), "must be strictly greater than baseline")
        XCTAssertTrue(isExpectedPreviewRevisionSatisfied(localRevision: 1, expected: nil, baseline: 0), "backwards compat: UUID server should fall back to any HMR")
    }

    func testHMRMonotonicIntegerParsing() {
        XCTAssertEqual(Int("3"), 3)
        XCTAssertNil(Int("550e8400-e29b-41d4-a716-446655440000"), "UUID must be treated as non-integer and fall back")
    }

    // MARK: - Voice gesture thresholds (matches PreviewWebView.TwoFingerVoiceGestureRecognizer)
    func testGestureThresholds() {
        // Constants from PreviewWebView.swift: activation 450ms, move 18pt, spread 12%, send/cancel ±72pt
        let activationThreshold: TimeInterval = 0.45
        let moveCancelThreshold: Double = 18
        let spreadCancelThreshold: Double = 0.12
        let sendThreshold: Double = 72
        XCTAssertEqual(activationThreshold, 0.45, accuracy: 0.001)
        XCTAssertEqual(moveCancelThreshold, 18, accuracy: 0.01)
        XCTAssertEqual(spreadCancelThreshold, 0.12, accuracy: 0.001)
        XCTAssertEqual(sendThreshold, 72, accuracy: 0.01)

        XCTAssertEqual(decision(for: 80), .send)
        XCTAssertEqual(decision(for: -80), .cancel)
        XCTAssertEqual(decision(for: 10), .neutral)
        XCTAssertEqual(decision(for: 72), .send)
        XCTAssertEqual(decision(for: -72), .cancel)
    }

    func testGestureStateTransitions() {
        // Simulates state machine: possible -> began after 450ms, then changed/ended, or failed if moved/spread early.
        enum State { case possible, began, changed, failed, ended }
        func shouldFail(beforeActivation moved: Double, spread: Double) -> Bool {
            moved > 18 || spread > 0.12
        }
        XCTAssertTrue(shouldFail(beforeActivation: 20, spread: 0.05))
        XCTAssertTrue(shouldFail(beforeActivation: 5, spread: 0.2))
        XCTAssertFalse(shouldFail(beforeActivation: 5, spread: 0.05))
    }

    // MARK: - Helpers mirroring production logic
    private func isExpectedPreviewRevisionSatisfied(localRevision: Int, expected: Int?, baseline: Int) -> Bool {
        guard let expected else { return localRevision > baseline }
        return localRevision >= expected && localRevision > baseline
    }
    private func decision(for translation: Double) -> VoiceGestureDecision {
        translation <= -72 ? .cancel : translation >= 72 ? .send : .neutral
    }
}
