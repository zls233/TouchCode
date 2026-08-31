import PencilKit
import SwiftUI
import WebKit

struct PreviewWebView: UIViewRepresentable {
    let url: URL
    let controller: PreviewController
    @Binding var drawing: PKDrawing
    let drawingEnabled: Bool
    let onViewportChange: () -> Void
    let onStrokeEnded: () -> Void
    let onVoiceGesture: (VoiceGestureEvent) -> Void

    func makeUIView(context: Context) -> TouchInputContainer {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "touchCodePreview")
        configuration.userContentController.add(context.coordinator, name: "touchCodeViewport")
        configuration.userContentController.addUserScript(WKUserScript(source: "window.__touchCodeViewportSequence=0; const t=()=>{window.__touchCodeViewportSequence++; window.webkit.messageHandlers.touchCodeViewport.postMessage('viewport')}; window.addEventListener('scroll',t,{passive:true}); window.addEventListener('resize',t); window.visualViewport?.addEventListener('scroll',t,{passive:true}); window.visualViewport?.addEventListener('resize',t);", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        controller.webView = webView
        let container = TouchInputContainer(webView: webView, drawing: drawing,
                                            enabled: drawingEnabled)
        container.onDrawingChanged = { drawing = $0 }
        container.onStrokeEnded = onStrokeEnded
        container.onVoiceGesture = onVoiceGesture
        container.onViewportChange = {
            onViewportChange()
            controller.didReceiveViewportChange()
        }
        container.navigate(to: url)
        return container
    }

    func updateUIView(_ container: TouchInputContainer, context: Context) {
        container.navigate(to: url)
        container.enabled = drawingEnabled
        if container.drawing != drawing {
            container.syncingDrawing = true
            container.drawing = drawing
            container.syncingDrawing = false
        }
        container.onViewportChange = {
            onViewportChange()
            controller.didReceiveViewportChange()
        }
        container.onStrokeEnded = onStrokeEnded
        container.onVoiceGesture = onVoiceGesture
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    static func dismantleUIView(_ container: TouchInputContainer, coordinator: Coordinator) {
        container.teardown()
        coordinator.controller.webView = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let controller: PreviewController

        init(controller: PreviewController) { self.controller = controller }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "touchCodePreview": controller.didReceivePreviewRevision(message.body)
            case "touchCodeViewport": controller.didReceiveViewportChange()
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let container = webView.superview as? TouchInputContainer {
                container.navigationDidFinish()
            }
            controller.didReceiveViewportChange()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if let container = webView.superview as? TouchInputContainer {
                container.navigationDidFail()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let container = webView.superview as? TouchInputContainer {
                container.navigationDidFail()
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            (webView.superview as? TouchInputContainer)?.recoverFromWebContentTermination()
        }
    }
}

/// A single hit-test boundary keeps finger scrolling in WebKit while Pencil
/// strokes are routed to PencilKit.  Returning nil for non-Pencil touches is
/// important: an enabled canvas must not become a transparent finger shield.
private final class PencilCanvasView: PKCanvasView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard event?.allTouches?.contains(where: { $0.type == .pencil }) == true else {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

final class TouchInputContainer: UIView {
    let webView: WKWebView
    private let canvas: PencilCanvasView
    var onDrawingChanged: ((PKDrawing) -> Void)?
    var onStrokeEnded: (() -> Void)?
    var onVoiceGesture: ((VoiceGestureEvent) -> Void)?
    var onViewportChange: (() -> Void)?
    var enabled = true { didSet { canvas.isUserInteractionEnabled = enabled } }
    var syncingDrawing = false
    var isLoadingURL = false
    private var requestedURL: URL?
    private var didFinishNavigation = false
    private var terminationRecoveryAttempted = false
    var drawing: PKDrawing {
        didSet {
            guard !syncingDrawing, canvas.drawing != drawing else { return }
            canvas.drawing = drawing
        }
    }
    private weak var originalScrollDelegate: UIScrollViewDelegate?

    init(webView: WKWebView, drawing: PKDrawing, enabled: Bool) {
        self.webView = webView
        self.drawing = drawing
        canvas = PencilCanvasView(frame: .zero)
        super.init(frame: .zero)
        self.enabled = enabled
        webView.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 4)
        canvas.isScrollEnabled = false
        canvas.delegate = self
        // Preserve WKWebView's internal scroll delegate to avoid breaking its
        // internal scroll handling. Forward delegate calls via forwardingTarget.
        originalScrollDelegate = webView.scrollView.delegate
        webView.scrollView.delegate = self
        let voiceGesture = TwoFingerVoiceGestureRecognizer(target: self, action: #selector(handleVoiceGesture(_:)))
        voiceGesture.cancelsTouchesInView = false
        voiceGesture.delegate = self
        addGestureRecognizer(voiceGesture)
        addSubview(webView)
        addSubview(canvas)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor), webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor), webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor), canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor), canvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return originalScrollDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return originalScrollDelegate
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func navigate(to url: URL) {
        guard requestedURL != url else { return }
        requestedURL = url
        didFinishNavigation = false
        isLoadingURL = true
        webView.load(URLRequest(url: url))
    }

    func navigationDidFinish() {
        isLoadingURL = false
        didFinishNavigation = true
        terminationRecoveryAttempted = false
    }

    func navigationDidFail() {
        isLoadingURL = false
    }

    func recoverFromWebContentTermination() {
        guard didFinishNavigation, !terminationRecoveryAttempted,
              let url = requestedURL, webView.window != nil else { return }
        terminationRecoveryAttempted = true
        isLoadingURL = true
        // Give WebKit a run-loop turn to tear down the old content process.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.webView.window != nil, self.requestedURL == url else { return }
            self.webView.load(URLRequest(url: url))
        }
    }

    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.scrollView.delegate = originalScrollDelegate
        canvas.delegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "touchCodePreview")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "touchCodeViewport")
        onDrawingChanged = nil
        onStrokeEnded = nil
        onVoiceGesture = nil
        onViewportChange = nil
    }

    @objc private func handleVoiceGesture(_ gesture: TwoFingerVoiceGestureRecognizer) {
        guard let event = gesture.event else { return }
        let handler = onVoiceGesture
        DispatchQueue.main.async { handler?(event) }
    }
}

extension TouchInputContainer: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !syncingDrawing else { return }
        let d = canvasView.drawing
        DispatchQueue.main.async { [weak self] in
            guard let self, self.drawing != d else { return }
            self.drawing = d
            self.onDrawingChanged?(d)
        }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        let handler = onStrokeEnded
        DispatchQueue.main.async { handler?() }
    }
}

extension TouchInputContainer: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        originalScrollDelegate?.scrollViewDidScroll?(scrollView)
        let handler = onViewportChange
        DispatchQueue.main.async { handler?() }
    }
}

extension TouchInputContainer: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

enum VoiceGestureDecision { case neutral, cancel, send }

enum VoiceGestureEvent {
    case started(CGPoint)
    case changed(CGPoint, CGFloat, VoiceGestureDecision)
    case ended(CGPoint, VoiceGestureDecision)
    case cancelled
}

/// The policy is kept separate from UIKit so threshold and decision behavior
/// can be regression-tested without synthesizing touch events.
enum TwoFingerGesturePolicy {
    static let activationDelay: Duration = .milliseconds(450)
    static let activationMoveLimit: CGFloat = 18
    static let activationSpreadLimit: CGFloat = 0.12
    static let actionTranslationLimit: CGFloat = 72

    static func cancelsPendingActivation(moved: CGFloat, spread: CGFloat) -> Bool {
        moved > activationMoveLimit || spread > activationSpreadLimit
    }

    static func decision(for translation: CGFloat) -> VoiceGestureDecision {
        translation <= -actionTranslationLimit ? .cancel :
            translation >= actionTranslationLimit ? .send : .neutral
    }
}

final class TwoFingerVoiceGestureRecognizer: UIGestureRecognizer {
    private(set) var event: VoiceGestureEvent?
    private var initialCenter = CGPoint.zero
    private var initialDistance: CGFloat = 0
    private var currentCenter = CGPoint.zero
    private var activationTask: Task<Void, Never>?
    private var activated = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard event.allTouches?.filter({ $0.type == .direct }).count == 2 else { return }
        let points = directPoints(in: view, event: event)
        guard points.count == 2 else { return }
        initialCenter = midpoint(points[0], points[1])
        currentCenter = initialCenter
        initialDistance = distance(points[0], points[1])
        activationTask?.cancel()
        activationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: TwoFingerGesturePolicy.activationDelay)
            guard let self, self.state == .possible else { return }
            self.activated = true
            self.event = .started(self.currentCenter)
            self.state = .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        let points = directPoints(in: view, event: event)
        guard points.count == 2 else { fail() ; return }
        currentCenter = midpoint(points[0], points[1])
        let moved = distance(initialCenter, currentCenter)
        let spread = initialDistance > 0 ? abs(distance(points[0], points[1]) - initialDistance) / initialDistance : 0
        if !activated && TwoFingerGesturePolicy.cancelsPendingActivation(moved: moved, spread: spread) { fail(); return }
        // Keep the recognizer in `.possible` while the hold is pending. UIKit
        // can deliver small touch-move batches during a stationary hold; moving
        // to `.changed` here would make the activation task's possible-state
        // guard fail before 450 ms elapse.
        guard activated else { return }
        let translation = currentCenter.x - initialCenter.x
        self.event = .changed(currentCenter, translation, decision(for: translation))
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        activationTask?.cancel()
        guard activated else { fail(); return }
        let translation = currentCenter.x - initialCenter.x
        self.event = .ended(currentCenter, decision(for: translation))
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        self.event = .cancelled
        state = .cancelled
    }

    override func reset() {
        activationTask?.cancel(); activationTask = nil
        event = nil; activated = false; initialDistance = 0
        super.reset()
    }

    private func fail() { activationTask?.cancel(); state = .failed }
    private func decision(for translation: CGFloat) -> VoiceGestureDecision {
        TwoFingerGesturePolicy.decision(for: translation)
    }
    private func directPoints(in view: UIView?, event: UIEvent) -> [CGPoint] {
        event.allTouches?.filter { $0.type == .direct }.map { $0.location(in: view) } ?? []
    }
    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
