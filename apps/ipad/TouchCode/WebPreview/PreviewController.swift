import PencilKit
import SwiftUI
import UIKit
import WebKit

@MainActor
final class PreviewController: ObservableObject {
    @Published var errorMessage: String?
    weak var webView: WKWebView?

    func captureAnnotatedContext(drawing: PKDrawing) async throws -> VisualCapture {
        guard let webView else { throw CaptureError.previewUnavailable }

        let value = try await webView.callAsyncJavaScript(
            "return JSON.stringify(await window.touchCodeBridge?.visibleContext?.() ?? [])",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = (value as? String) ?? "[]"
        let elements = try JSONDecoder().decode(
            [VisibleElementContext].self,
            from: Data(json.utf8)
        )

        let bounds = webView.bounds
        let snapshot = try await webView.takeSnapshot(configuration: nil)
        let ink = drawing.image(from: bounds, scale: 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let composited = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            snapshot.draw(in: bounds)
            ink.draw(in: bounds)
        }
        let uploadImage = resizedForUpload(composited, maximumDimension: 1_600)
        guard let imageData = uploadImage.jpegData(compressionQuality: 0.74) else {
            throw CaptureError.encodingFailed
        }

        return VisualCapture(
            imageData: imageData,
            viewportWidth: bounds.width,
            viewportHeight: bounds.height,
            elements: elements
        )
    }

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
