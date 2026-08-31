import XCTest
import PencilKit
@testable import TouchCode

final class AnnotationDraftTests: XCTestCase {
    func testAppendSingleViewport() {
        var draft = AnnotationDraft()
        let capture = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 0, scrollY: 0)
        let drawing = PKDrawing()
        XCTAssertTrue(draft.append(capture, drawing: drawing))
        XCTAssertEqual(draft.captures.count, 1)
        XCTAssertEqual(draft.revision, 1)
    }

    func testAppendSameViewportCoalescesAndUnionsBounds() {
        var draft = AnnotationDraft()
        let drawingA = PKDrawing()
        let captureA = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 10, scrollY: 20, bounds: CGRect(x: 0, y: 0, width: 10, height: 10))
        let captureB = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 10, scrollY: 20, bounds: CGRect(x: 5, y: 5, width: 10, height: 10))
        XCTAssertTrue(draft.append(captureA, drawing: drawingA))
        let revAfterFirst = draft.revision
        XCTAssertTrue(draft.append(captureB, drawing: PKDrawing()))
        XCTAssertEqual(draft.captures.count, 1, "same viewport must coalesce, not consume extra slot")
        XCTAssertEqual(draft.revision, revAfterFirst + 1)
        XCTAssertEqual(draft.captures.first?.annotationBounds, CGRect(x: 0, y: 0, width: 15, height: 15))
    }

    func testAppendUpToEightViewportsThenReject() {
        var draft = AnnotationDraft()
        for i in 0..<AnnotationDraft.maximumCaptures {
            let cap = makeCapture(url: "http://127.0.0.1:5173/", scrollX: Double(i * 100), scrollY: 0)
            XCTAssertTrue(draft.append(cap, drawing: PKDrawing()), "slot \(i) should succeed")
        }
        XCTAssertEqual(draft.captures.count, 8)
        let extra = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 9999, scrollY: 9999)
        XCTAssertFalse(draft.append(extra, drawing: PKDrawing()))
        XCTAssertEqual(draft.captures.count, 8)
    }

    func testQuantizedViewportKeyToleratesJitter() {
        // ReadyViewportFrame quantizes to 0.1pt, so 0.04 jitter should not create new slot.
        var draft = AnnotationDraft()
        let a = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 10.04, scrollY: 20.04)
        let b = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 10.06, scrollY: 20.06)
        XCTAssertTrue(draft.append(a, drawing: PKDrawing()))
        XCTAssertTrue(draft.append(b, drawing: PKDrawing()))
        XCTAssertEqual(draft.captures.count, 1, "quantized key should coalesce jittered viewports")
    }

    func testRemoveAllClearsAndIncrementsRevision() {
        var draft = AnnotationDraft()
        XCTAssertTrue(draft.append(makeCapture(url: "http://127.0.0.1:5173/", scrollX: 0, scrollY: 0), drawing: PKDrawing()))
        let rev = draft.revision
        draft.removeAll()
        XCTAssertTrue(draft.captures.isEmpty)
        XCTAssertEqual(draft.revision, rev + 1)
    }

    func testSubmittedDraftRevisionGuardsAgainstClearingNewAnnotations() {
        // Simulates WorkspaceView.clearAppliedDraft guard: only clear if revision unchanged since submit.
        var draft = AnnotationDraft()
        XCTAssertTrue(draft.append(makeCapture(url: "http://127.0.0.1:5173/", scrollX: 0, scrollY: 0), drawing: PKDrawing()))
        let submittedRevision = draft.revision
        // User draws again after submit, before HMR arrives
        XCTAssertTrue(draft.append(makeCapture(url: "http://127.0.0.1:5173/", scrollX: 100, scrollY: 0), drawing: PKDrawing()))
        XCTAssertNotEqual(draft.revision, submittedRevision, "new annotation must bump revision")
        // Clearing should be suppressed because revision changed
        let shouldClear = (submittedRevision == draft.revision)
        XCTAssertFalse(shouldClear)
    }

    func testDrawingRoundTripsPerViewportKey() {
        var draft = AnnotationDraft()
        let cap = makeCapture(url: "http://127.0.0.1:5173/", scrollX: 12, scrollY: 34)
        let drawing = PKDrawing()
        XCTAssertTrue(draft.append(cap, drawing: drawing))
        XCTAssertNotNil(draft.drawing(for: cap.viewportKey))
    }

    // MARK: - Helper
    private func makeCapture(url: String, scrollX: Double, scrollY: Double, bounds: CGRect = .zero) -> AnnotationCapture {
        AnnotationCapture(
            imageData: Data([0xFF, 0xD8, 0xFF, 0x00]),
            url: url,
            viewportWidth: 1024,
            viewportHeight: 768,
            scrollX: scrollX,
            scrollY: scrollY,
            zoomScale: 1,
            devicePixelRatio: 2,
            annotationBounds: bounds,
            elements: []
        )
    }
}
