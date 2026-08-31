import Foundation

struct DemoSession: Codable {
    let sessionId: String
    let projectId: String?
    let worktreePath: String?
    let previewURL: String
    let bridgeURL: String
    let port: Int?
    let status: String?
}

struct PairedWorkspaceSession: Codable {
    let sessionId: String
    let previewURL: String
    let bridgeURL: String
    let pairingCode: String
    let ipadConnected: Bool
    let latestRunId: String?
    let errorMessage: String?
    let clientToken: String
    let status: String
}

enum BridgeConnectionState: Equatable {
    case connected, unreachable, stopped, credentialsRejected
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
    let captures: [AnnotationCapture]
}

struct AnnotationCapture {
    let imageData: Data
    let url: String
    let viewportWidth: Double
    let viewportHeight: Double
    let scrollX: Double
    let scrollY: Double
    let zoomScale: Double
    let devicePixelRatio: Double
    let annotationBounds: CGRect
    let elements: [VisibleElementContext]
}

enum WorkspaceState: Equatable {
    case browsing, drafting, composing, recording, voiceConfirmation
    case submitting, awaitingPreview, needsClarification(String), failed(String)

    var preservesDraft: Bool {
        switch self {
        case .needsClarification, .failed: true
        default: false
        }
    }
}

struct CodingRunSnapshot: Codable {
    let runId: String
    let sessionId: String
    let provider: String
    let stage: String
    let status: String
    let decision: String
    let message: String
    let summary: String
    let diff: String
    let changedFiles: [String]
    let previewRevision: String?
    let outcome: String
    let clarificationQuestion: String?
    let startedAt: String
    let updatedAt: String
}
