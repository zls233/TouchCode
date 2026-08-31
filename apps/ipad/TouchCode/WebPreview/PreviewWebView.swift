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
        webView.load(URLRequest(url: url))
        let container = TouchInputContainer(webView: webView, drawing: drawing,
                                            enabled: drawingEnabled)
        container.onDrawingChanged = { drawing = $0 }
        container.onStrokeEnded = onStrokeEnded
        container.onVoiceGesture = onVoiceGesture
        container.onViewportChange = {
            onViewportChange()
            controller.didReceiveViewportChange()
        }
        return container
    }

    func updateUIView(_ container: TouchInputContainer, context: Context) {
        let webView = container.webView
        if !container.isLoadingURL, webView.url?.absoluteString != url.absoluteString {
            container.isLoadingURL = true
            webView.load(URLRequest(url: url))
        }
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
                container.isLoadingURL = false
            }
            controller.didReceiveViewportChange()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if let container = webView.superview as? TouchInputContainer {
                container.isLoadingURL = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let container = webView.superview as? TouchInputContainer {
                container.isLoadingURL = false
            }
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
            try? await Task.sleep(for: .milliseconds(450))
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
        if !activated && (moved > 18 || spread > 0.12) { fail(); return }
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
        translation <= -72 ? .cancel : translation >= 72 ? .send : .neutral
    }
    private func directPoints(in view: UIView?, event: UIEvent) -> [CGPoint] {
        event.allTouches?.filter { $0.type == .direct }.map { $0.location(in: view) } ?? []
    }
    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
