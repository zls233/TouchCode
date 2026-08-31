import CoreGraphics
import Foundation
import PencilKit
import UIKit

/// Stable identity for a browser viewport.  It deliberately excludes the
/// annotation itself so consecutive marks in the same viewport coalesce.
struct AnnotationViewportKey: Hashable {
    let url: String
    let width: Double
    let height: Double
    let scrollX: Double
    let scrollY: Double
    let zoomScale: Double

    /// Micro-jitter from visualViewport should not allocate a new capture slot.
    /// 0.5 CSS px for scroll and 0.02 for zoom keeps intentional scrolls distinct.
    func isNearlyEqual(to other: Self, scrollTolerance: Double = 0.5, zoomTolerance: Double = 0.02, sizeTolerance: Double = 0.5) -> Bool {
        url == other.url
        && abs(width - other.width) < sizeTolerance
        && abs(height - other.height) < sizeTolerance
        && abs(scrollX - other.scrollX) < scrollTolerance
        && abs(scrollY - other.scrollY) < scrollTolerance
        && abs(zoomScale - other.zoomScale) < zoomTolerance
    }
}

/// Quantized identity used while a WebKit visual viewport settles.  Small
/// floating-point jitter must not create a new capture for every scroll tick.
struct ReadyViewportFrame {
    let generation: Int
    let sequence: Int
    let url: String
    let width: Int
    let height: Int
    let scale: Int
    let pageLeft: Int
    let pageTop: Int
    let cleanImageData: Data
    let devicePixelRatio: Double
    let elements: [VisibleElementContext]

    init(generation: Int, sequence: Int, url: String, width: Double, height: Double,
         scale: Double, pageLeft: Double, pageTop: Double,
         cleanImageData: Data = Data(), devicePixelRatio: Double = 1,
         elements: [VisibleElementContext] = []) {
        self.generation = generation; self.sequence = sequence; self.url = url
        self.width = Int((width * 10).rounded()); self.height = Int((height * 10).rounded())
        self.scale = Int((scale * 100).rounded()); self.pageLeft = Int((pageLeft * 10).rounded()); self.pageTop = Int((pageTop * 10).rounded())
        self.cleanImageData = cleanImageData; self.devicePixelRatio = devicePixelRatio; self.elements = elements
    }
}

extension ReadyViewportFrame {
    var viewportKey: AnnotationViewportKey {
        AnnotationViewportKey(
            url: url,
            width: Double(width) / 10,
            height: Double(height) / 10,
            scrollX: Double(pageLeft) / 10,
            scrollY: Double(pageTop) / 10,
            zoomScale: Double(scale) / 100
        )
    }
}

extension AnnotationCapture {
    var viewportKey: AnnotationViewportKey {
        let origin = URL(string: url).flatMap { value in
            guard let scheme = value.scheme, let host = value.host else { return nil }
            return "\(scheme)://\(host)\(value.port.map { ":\($0)" } ?? "")"
        } ?? url
        return AnnotationViewportKey(url: origin, width: (viewportWidth * 10).rounded() / 10,
                              height: (viewportHeight * 10).rounded() / 10,
                              scrollX: (scrollX * 10).rounded() / 10,
                              scrollY: (scrollY * 10).rounded() / 10,
                              zoomScale: (zoomScale * 100).rounded() / 100)
    }
}

/// Canonical stroke in CSS page coordinates with a stable identity.
/// The ID survives scroll/zoom re-projection so the same physical mark
/// does not duplicate across viewports.
struct CanonicalStroke: Hashable {
    let id: UUID
    var cssPoints: [CGPoint]
    var color: UIColor
    var width: CGFloat
    var createdAt: Date

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// Approximate hash for cross-viewport deduplication: quantized CSS bounds + color/width.
    var dedupeKey: String {
        guard let first = cssPoints.first else { return id.uuidString }
        let qx = Int((first.x * 10).rounded())
        let qy = Int((first.y * 10).rounded())
        let c = color.hexString ?? "unknown"
        return "\(qx)_\(qy)_\(c)_\(Int(width*10))_\(cssPoints.count)"
    }
}

private extension UIColor {
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

/// Local, bounded draft model.  Captures are ordered by first appearance and
/// a viewport can never consume more than one slot in the eight-capture cap.
struct AnnotationDraft {
    static let maximumCaptures = 8
    private(set) var captures: [AnnotationCapture] = []
    private(set) var revision = 0
    private var drawings: [AnnotationViewportKey: PKDrawing] = [:]
    /// Canonical strokes keyed by stable ID; viewport -> IDs for reprojection.
    private var canonicalStrokes: [UUID: CanonicalStroke] = [:]
    private var viewportStrokeIDs: [AnnotationViewportKey: Set<UUID>] = [:]
    /// Dedupe fingerprint -> ID for cross-viewport coalescing.
    private var dedupeIndex: [String: UUID] = [:]

    @discardableResult
    mutating func append(_ capture: AnnotationCapture, drawing: PKDrawing) -> Bool {
        // Tolerate micro jitter: treat nearly-equal viewports as same slot.
        let targetKey = capture.viewportKey
        let existingIndex = captures.firstIndex(where: { $0.viewportKey.isNearlyEqual(to: targetKey) })
        let viewportKeyForStorage = existingIndex.map { captures[$0].viewportKey } ?? targetKey

        // Canonicalize incoming drawing into CSS space.
        let incomingCanonical = canonicalize(drawing: drawing, viewportKey: viewportKeyForStorage)
        for stroke in incomingCanonical {
            let key = stroke.dedupeKey
            if let existingID = dedupeIndex[key], var existing = canonicalStrokes[existingID] {
                // Merge points: keep existing ID, append new points if distinct
                if !existing.cssPoints.elementsEqual(stroke.cssPoints, by: { $0.distance(to: $1) < 1 }) {
                    existing.cssPoints.append(contentsOf: stroke.cssPoints)
                    canonicalStrokes[existingID] = existing
                }
                viewportStrokeIDs[viewportKeyForStorage, default: []].insert(existingID)
            } else {
                canonicalStrokes[stroke.id] = stroke
                dedupeIndex[key] = stroke.id
                viewportStrokeIDs[viewportKeyForStorage, default: []].insert(stroke.id)
            }
        }

        if let index = existingIndex {
            let old = captures[index]
            captures[index] = AnnotationCapture(
                imageData: capture.imageData,
                url: capture.url,
                viewportWidth: capture.viewportWidth,
                viewportHeight: capture.viewportHeight,
                scrollX: capture.scrollX,
                scrollY: capture.scrollY,
                zoomScale: capture.zoomScale,
                devicePixelRatio: capture.devicePixelRatio,
                annotationBounds: old.annotationBounds.union(capture.annotationBounds),
                elements: capture.elements
            )
            drawings[viewportKeyForStorage] = drawing
            revision &+= 1
            return true
        } else if captures.count < Self.maximumCaptures {
            captures.append(capture)
            drawings[viewportKeyForStorage] = drawing
            revision &+= 1
            return true
        }
        return false
    }

    func drawing(for key: AnnotationViewportKey) -> PKDrawing? {
        // Prefer direct storage for exact key, else try nearly-equal and reproject.
        if let direct = drawings[key] { return direct }
        if let nearKey = drawings.keys.first(where: { $0.isNearlyEqual(to: key) }) {
            return reprojectedDrawing(for: key, from: nearKey)
        }
        // Fallback: reconstruct from canonical strokes that belong to this viewport.
        return reprojectedDrawing(for: key, from: key)
    }

    /// Returns captures recompressed to stay within the Bridge 12 MiB budget.
    /// Each capture is individually capped at 3 MiB (protocol max 4M base64) and the
    /// total is capped at 12 MiB decoded. Uses quality/size ladder to avoid server rejection.
    func compressedCaptures(budgetBytes: Int = 12 * 1024 * 1024) -> [AnnotationCapture] {
        let perCaptureLimit = 3 * 1024 * 1024
        let total = captures.reduce(0) { $0 + $1.imageData.count }
        guard total > budgetBytes || captures.contains(where: { $0.imageData.count > perCaptureLimit }) else {
            return captures
        }
        let qualities: [CGFloat] = [0.74, 0.6, 0.5, 0.35, 0.22, 0.12]
        let dimensions: [CGFloat] = [1_600, 1_200, 900, 700, 500]
        // Proportional target per capture
        let count = max(captures.count, 1)
        let targetPerCapture = min(perCaptureLimit, budgetBytes / count)

        return captures.map { cap in
            var data = cap.imageData
            if data.count <= targetPerCapture { return cap }
            // Try recompression ladder
            guard let image = UIImage(data: data) else { return cap }
            var best = data
            outer: for dim in dimensions {
                for q in qualities {
                    guard let resized = resizedForUpload(image, maximumDimension: dim),
                          let candidate = resized.jpegData(compressionQuality: q) else { continue }
                    best = candidate
                    if candidate.count <= targetPerCapture { break outer }
                }
            }
            // If still over budget, keep smallest attempt
            return AnnotationCapture(
                imageData: best,
                url: cap.url,
                viewportWidth: cap.viewportWidth,
                viewportHeight: cap.viewportHeight,
                scrollX: cap.scrollX,
                scrollY: cap.scrollY,
                zoomScale: cap.zoomScale,
                devicePixelRatio: cap.devicePixelRatio,
                annotationBounds: cap.annotationBounds,
                elements: cap.elements
            )
        }
    }

    private func resizedForUpload(_ image: UIImage, maximumDimension: CGFloat) -> UIImage? {
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

    mutating func removeAll() {
        captures.removeAll(keepingCapacity: true)
        drawings.removeAll(keepingCapacity: true)
        canonicalStrokes.removeAll(keepingCapacity: true)
        viewportStrokeIDs.removeAll(keepingCapacity: true)
        dedupeIndex.removeAll(keepingCapacity: true)
        revision &+= 1
    }

    // MARK: - Canonical helpers

    func allCanonicalStrokes() -> [CanonicalStroke] { Array(canonicalStrokes.values) }

    private func canonicalize(drawing: PKDrawing, viewportKey: AnnotationViewportKey) -> [CanonicalStroke] {
        drawing.strokes.map { stroke in
            var cssPoints: [CGPoint] = []
            let path = stroke.path
            for i in 0..<path.count {
                let viewPoint = path[i].location
                let cssX = viewPoint.x / max(viewportKey.zoomScale, 0.0001) + viewportKey.scrollX
                let cssY = viewPoint.y / max(viewportKey.zoomScale, 0.0001) + viewportKey.scrollY
                cssPoints.append(CGPoint(x: cssX, y: cssY))
            }
            return CanonicalStroke(
                id: UUID(),
                cssPoints: cssPoints,
                color: stroke.ink.color,
                width: 4,
                createdAt: Date()
            )
        }
    }

    private func reprojectedDrawing(for target: AnnotationViewportKey, from source: AnnotationViewportKey) -> PKDrawing? {
        guard let ids = viewportStrokeIDs[source] else { return drawings[source] }
        var strokes: [PKStroke] = []
        for id in ids {
            guard let canonical = canonicalStrokes[id] else { continue }
            let viewPoints = canonical.cssPoints.map { css in
                CGPoint(
                    x: (css.x - target.scrollX) * max(target.zoomScale, 0.0001),
                    y: (css.y - target.scrollY) * max(target.zoomScale, 0.0001)
                )
            }
            // Rebuild PKStroke via interpolated points. Use default ink.
            let ink = PKInk(.pen, color: canonical.color)
            var strokePoints: [PKStrokePoint] = []
            for (i, pt) in viewPoints.enumerated() {
                let t = Double(i) / max(Double(viewPoints.count - 1), 1)
                strokePoints.append(PKStrokePoint(location: pt, timeOffset: t, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi/2))
            }
            if strokePoints.isEmpty { continue }
            let path = PKStrokePath(controlPoints: strokePoints, creationDate: canonical.createdAt)
            strokes.append(PKStroke(ink: ink, path: path))
        }
        return strokes.isEmpty ? drawings[source] : PKDrawing(strokes: strokes)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
