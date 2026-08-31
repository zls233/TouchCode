import Foundation

struct TouchCodeAPIClient {
    let bridgeURL: URL

    func pair(code: String) async throws -> PairedWorkspaceSession {
        var request = URLRequest(url: bridgeURL.appending(path: "v1/sessions/pair"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PairingBody(pairingCode: code))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 200)
        return try JSONDecoder().decode(PairedWorkspaceSession.self, from: data)
    }

    func createDemoSession() async throws -> DemoSession {
        var request = URLRequest(url: bridgeURL.appending(path: "v1/demo-sessions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 201)
        return try JSONDecoder().decode(DemoSession.self, from: data)
    }

    func runVisual(
        session: PairedWorkspaceSession,
        capture: VisualCapture,
        instruction: String,
        inputMode: String = "text"
    ) async throws -> CodingRunSnapshot {
        var request = URLRequest(
            url: bridgeURL
                .appending(path: "v1/sessions")
                .appending(path: session.sessionId)
                .appending(path: "edits")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session.clientToken, forHTTPHeaderField: "x-touchcode-session-token")
        request.httpBody = try JSONEncoder().encode(VisualRunBody(
            type: "visual.run.v2",
            draftId: UUID().uuidString,
            instruction: instruction.isEmpty ? nil : instruction,
            inputMode: inputMode,
            captures: capture.captures.map(VisualRunBody.Capture.init),
            provider: "codex"
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        // The Bridge accepts the edit request before the run completes.
        // Treat any successful 2xx response (including 202 Accepted) as valid.
        try validate(response, data: data, status: { 200...299 ~= $0 })
        return try JSONDecoder().decode(CodingRunSnapshot.self, from: data)
    }

    func awaitTerminalRun(
        session: PairedWorkspaceSession,
        runId: String
    ) async throws -> CodingRunSnapshot {
        // Prefer SSE, but reconnect with backoff and fall back to polling so a transient TCP reset
        // does not orphan a run that already completed on the Mac.
        var lastEventId: String?
        var attempt = 0
        let deadline = Date(timeIntervalSinceNow: 300)
        while Date() < deadline {
            do {
                if let terminal = try await pollTerminalRun(session: session, runId: runId) {
                    return terminal
                }
                if let terminal = try await streamTerminalRun(session: session, runId: runId, lastEventId: &lastEventId, deadline: deadline) {
                    return terminal
                }
            } catch {
                // Retry on transient network errors; propagate validation failures immediately.
                if let bridge = error as? BridgeError, case .requestFailed(let message) = bridge, message.contains("Unknown coding run") {
                    throw error
                }
            }
            attempt += 1
            let backoffMs = min(200 * (1 << min(attempt, 5)), 4000)
            let jitter = Int.random(in: 0...150)
            try await Task.sleep(for: .milliseconds(backoffMs + jitter))
            // Compensate via polling in case the event was missed while disconnected.
            if let terminal = try? await pollTerminalRun(session: session, runId: runId), ["succeeded", "failed", "cancelled"].contains(terminal.status) {
                return terminal
            }
        }
        throw BridgeError.requestFailed("The Bridge event stream ended before the coding run completed.")
    }

    private func pollTerminalRun(session: PairedWorkspaceSession, runId: String) async throws -> CodingRunSnapshot? {
        var request = URLRequest(
            url: bridgeURL
                .appending(path: "v1/sessions")
                .appending(path: session.sessionId)
                .appending(path: "runs")
                .appending(path: runId)
        )
        request.setValue(session.clientToken, forHTTPHeaderField: "x-touchcode-session-token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data, status: { 200...299 ~= $0 })
            let snapshot = try JSONDecoder().decode(CodingRunSnapshot.self, from: data)
            if ["succeeded", "failed", "cancelled"].contains(snapshot.status) {
                return snapshot
            }
            return nil
        } catch {
            return nil
        }
    }

    private func streamTerminalRun(
        session: PairedWorkspaceSession,
        runId: String,
        lastEventId: inout String?,
        deadline: Date
    ) async throws -> CodingRunSnapshot? {
        var request = URLRequest(
            url: bridgeURL
                .appending(path: "v1/sessions")
                .appending(path: session.sessionId)
                .appending(path: "runs")
                .appending(path: runId)
                .appending(path: "events")
        )
        request.setValue(session.clientToken, forHTTPHeaderField: "x-touchcode-session-token")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let lastEventId { request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID") }
        request.timeoutInterval = 90
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            let message = "TouchCode Bridge returned an invalid response."
            throw BridgeError.requestFailed(message)
        }
        for try await rawLine in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if Date() >= deadline { return nil }
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix(":") { continue } // heartbeat/comment
            if line.hasPrefix("id:") {
                lastEventId = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                continue
            }
            if line.hasPrefix("data:") {
                let payload = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                guard let data = payload.data(using: .utf8) else { continue }
                if let snapshot = try? JSONDecoder().decode(CodingRunSnapshot.self, from: data),
                   ["succeeded", "failed", "cancelled"].contains(snapshot.status) {
                    return snapshot
                }
                continue
            }
        }
        return nil
    }

    private func validate(_ response: URLResponse, data: Data, expectedStatus: Int) throws {
        try validate(response, data: data, status: { $0 == expectedStatus })
    }

    private func validate(
        _ response: URLResponse,
        data: Data,
        status: (Int) -> Bool
    ) throws {
        guard let http = response as? HTTPURLResponse, status(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "TouchCode Bridge returned an invalid response."
            throw BridgeError.requestFailed(message)
        }
    }
}

private struct PairingBody: Encodable {
    let pairingCode: String
}

private struct VisualRunBody: Encodable {
    let type: String
    let draftId: String
    let instruction: String?
    let inputMode: String
    let captures: [Capture]
    let provider: String

    struct Capture: Encodable {
        let annotatedImageBase64: String
        let viewport: Viewport
        let annotationBounds: Bounds
        let elements: [VisibleElementContext]

        init(_ capture: AnnotationCapture) {
            annotatedImageBase64 = capture.imageData.base64EncodedString()
            viewport = Viewport(capture)
            annotationBounds = Bounds(capture.annotationBounds)
            elements = capture.elements
        }
    }

    struct Viewport: Encodable {
        let url: String; let width: Double; let height: Double
        let scrollX: Double; let scrollY: Double; let zoomScale: Double; let devicePixelRatio: Double
        init(_ capture: AnnotationCapture) {
            url = capture.url; width = capture.viewportWidth; height = capture.viewportHeight
            scrollX = capture.scrollX; scrollY = capture.scrollY; zoomScale = capture.zoomScale; devicePixelRatio = capture.devicePixelRatio
        }
    }

    struct Bounds: Encodable {
        let x: Double; let y: Double; let width: Double; let height: Double
        init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    }
}

private enum BridgeError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return message
        }
    }
}
