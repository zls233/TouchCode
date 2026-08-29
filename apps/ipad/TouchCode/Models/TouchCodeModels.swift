import Foundation

struct DemoSession: Codable {
    let sessionId: String
    let projectId: String
    let worktreePath: String
    let previewURL: String
    let bridgeURL: String
    let port: Int
    let status: String
}

struct VisibleElementContext: Codable {
    let elementId: String
    let tag: String
    let text: String
    let rect: Rect
    let componentName: String?
    let source: SourceReference?

    struct Rect: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct SourceReference: Codable {
        let file: String
        let line: Int
        let column: Int
    }
}

struct VisualCapture {
    let imageData: Data
    let viewportWidth: Double
    let viewportHeight: Double
    let elements: [VisibleElementContext]
}

struct CodingRunResult: Codable {
    let runId: String
    let provider: String
    let providerThreadId: String?
    let status: String
    let summary: String
}
