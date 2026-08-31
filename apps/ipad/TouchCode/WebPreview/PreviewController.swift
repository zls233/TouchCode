import PencilKit
import SwiftUI
import UIKit
import WebKit

@MainActor
final class PreviewController: ObservableObject {
    @Published var errorMessage: String?
    @Published private(set) var previewRevision = 0
    @Published private(set) var viewportGeneration = 0
    @Published private(set) var viewportReady = false
    @Published private(set) var readyFrame: ReadyViewportFrame?
    weak var webView: WKWebView?
    var onViewportChange: (() -> Void)?

    func didReceiveViewportChange() {
        viewportGeneration &+= 1
        viewportReady = false
        readyFrame = nil
        let generation = viewportGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard generation == viewportGeneration else { return }
            do {
                guard let frame = try await prepareReadyFrame(generation: generation) else {
                    guard generation == viewportGeneration else { return }
                    didReceiveViewportChange()
                    return
                }
                guard generation == viewportGeneration else { return }
                readyFrame = frame
                viewportReady = true
                onViewportChange?()
            } catch {
                guard generation == viewportGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareReadyFrame(generation: Int) async throws -> ReadyViewportFrame? {
        guard let webView else { throw CaptureError.previewUnavailable }
        let before = try await readPageContext(from: webView)
        guard generation == viewportGeneration else { return nil }
        let snapshot = try await webView.takeSnapshot(configuration: nil)
        guard generation == viewportGeneration else { return nil }
        guard let data = resizedForUpload(snapshot, maximumDimension: 1_600).jpegData(compressionQuality: 0.74) else { throw CaptureError.encodingFailed }
        let after = try await readPageContext(from: webView)
        guard generation == viewportGeneration,
              before.sequence == after.sequence, before.url == after.url,
              before.width == after.width, before.height == after.height,
              before.zoomScale == after.zoomScale, before.scrollX == after.scrollX,
              before.scrollY == after.scrollY else { return nil }
        return ReadyViewportFrame(generation: generation, sequence: before.sequence,
                                  url: before.url, width: before.width, height: before.height,
                                  scale: before.zoomScale, pageLeft: before.scrollX, pageTop: before.scrollY,
                                  cleanImageData: data, devicePixelRatio: before.devicePixelRatio,
                                  elements: before.elements)
    }

    private func readPageContext(from webView: WKWebView) async throws -> PageContext {
        let value = try await webView.callAsyncJavaScript("""
        const v = window.visualViewport;
        return JSON.stringify({elements: await window.touchCodeBridge?.visibleContext?.() ?? [], url: location.href,
          width: v?.width ?? innerWidth, height: v?.height ?? innerHeight, scrollX: v?.pageLeft ?? scrollX,
          scrollY: v?.pageTop ?? scrollY, zoomScale: v?.scale ?? 1, devicePixelRatio: devicePixelRatio,
          sequence: window.__touchCodeViewportSequence ?? 0});
        """, arguments: [:], in: nil, contentWorld: .page)
        return try JSONDecoder().decode(PageContext.self, from: Data(((value as? String) ?? "{}").utf8))
    }

    func annotatedCapture(drawing: PKDrawing, frame: ReadyViewportFrame) throws -> AnnotationCapture {
        guard let base = UIImage(data: frame.cleanImageData), let webView else { throw CaptureError.encodingFailed }
        let bounds = webView.bounds
        let ink = drawing.image(from: bounds, scale: 1)
        let image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            base.draw(in: bounds); ink.draw(in: bounds)
        }
        guard let data = image.jpegData(compressionQuality: 0.74) else { throw CaptureError.encodingFailed }
        let b = drawing.bounds; let scale = max(Double(frame.scale) / 100, 0.0001)
        return AnnotationCapture(imageData: data, url: frame.url, viewportWidth: Double(frame.width) / 10,
          viewportHeight: Double(frame.height) / 10, scrollX: Double(frame.pageLeft) / 10,
          scrollY: Double(frame.pageTop) / 10, zoomScale: scale, devicePixelRatio: frame.devicePixelRatio,
          annotationBounds: CGRect(x: b.minX / scale + Double(frame.pageLeft) / 10,
            y: b.minY / scale + Double(frame.pageTop) / 10, width: b.width / scale, height: b.height / scale), elements: frame.elements)
    }

    func cleanCapture(frame: ReadyViewportFrame) -> AnnotationCapture {
        AnnotationCapture(
            imageData: frame.cleanImageData,
            url: frame.url,
            viewportWidth: Double(frame.width) / 10,
            viewportHeight: Double(frame.height) / 10,
            scrollX: Double(frame.pageLeft) / 10,
            scrollY: Double(frame.pageTop) / 10,
            zoomScale: max(Double(frame.scale) / 100, 0.0001),
            devicePixelRatio: frame.devicePixelRatio,
            annotationBounds: .zero,
            elements: frame.elements
        )
    }

    func didReceivePreviewRevision(_ value: Any? = nil) {
        if let number = value as? NSNumber {
            let precise = number.intValue
            if precise > previewRevision {
                previewRevision = precise
                return
            }
        } else if let string = value as? String, let precise = Int(string), precise > previewRevision {
            previewRevision = precise
            return
        } else if let dict = value as? [String: Any] {
            if let rev = dict["revision"] as? NSNumber, rev.intValue > previewRevision {
                previewRevision = rev.intValue
                return
            }
            if let revStr = dict["revision"] as? String, let precise = Int(revStr), precise > previewRevision {
                previewRevision = precise
                return
            }
        }
        previewRevision += 1
    }
    func reload() { webView?.reload() }

    private func resizedForUpload(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maximumDimension else { return image }
        let scale = maximumDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct PageContext: Decodable {
    let elements: [VisibleElementContext]
    let url: String
    let width: Double
    let height: Double
    let scrollX: Double
    let scrollY: Double
    let zoomScale: Double
    let devicePixelRatio: Double
    let sequence: Int
}

private enum CaptureError: LocalizedError {
    case previewUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .previewUnavailable: return "The live preview is not ready."
        case .encodingFailed: return "The annotated screenshot could not be encoded."
        }
    }
}
