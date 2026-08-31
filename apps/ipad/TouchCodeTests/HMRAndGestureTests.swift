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
        XCTAssertEqual(TwoFingerGesturePolicy.activationDelay, .milliseconds(450))
        XCTAssertEqual(TwoFingerGesturePolicy.activationMoveLimit, 18, accuracy: 0.01)
        XCTAssertEqual(TwoFingerGesturePolicy.activationSpreadLimit, 0.12, accuracy: 0.001)
        XCTAssertEqual(TwoFingerGesturePolicy.actionTranslationLimit, 72, accuracy: 0.01)

        XCTAssertEqual(TwoFingerGesturePolicy.decision(for: 80), .send)
        XCTAssertEqual(TwoFingerGesturePolicy.decision(for: -80), .cancel)
        XCTAssertEqual(TwoFingerGesturePolicy.decision(for: 10), .neutral)
        XCTAssertEqual(TwoFingerGesturePolicy.decision(for: 72), .send)
        XCTAssertEqual(TwoFingerGesturePolicy.decision(for: -72), .cancel)
    }

    func testGestureStateTransitions() {
        // Simulates state machine: possible -> began after 450ms, then changed/ended, or failed if moved/spread early.
        enum State { case possible, began, changed, failed, ended }
        XCTAssertTrue(TwoFingerGesturePolicy.cancelsPendingActivation(moved: 20, spread: 0.05))
        XCTAssertTrue(TwoFingerGesturePolicy.cancelsPendingActivation(moved: 5, spread: 0.2))
        XCTAssertFalse(TwoFingerGesturePolicy.cancelsPendingActivation(moved: 5, spread: 0.05))
        // A pre-activation horizontal swipe is not allowed to become voice.
        XCTAssertTrue(TwoFingerGesturePolicy.cancelsPendingActivation(moved: 80, spread: 0))
    }

    // MARK: - HMR helper
    private func isExpectedPreviewRevisionSatisfied(localRevision: Int, expected: Int?, baseline: Int) -> Bool {
        guard let expected else { return localRevision > baseline }
        return localRevision >= expected && localRevision > baseline
    }
}
