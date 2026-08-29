import Foundation

struct TouchCodeAPIClient {
    let bridgeURL: URL

    func createDemoSession() async throws -> DemoSession {
        var request = URLRequest(url: bridgeURL.appending(path: "v1/demo-sessions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 201)
        return try JSONDecoder().decode(DemoSession.self, from: data)
    }

    func runVisual(
        session: DemoSession,
        capture: VisualCapture,
        instruction: String
    ) async throws -> CodingRunResult {
        var request = URLRequest(
            url: bridgeURL
                .appending(path: "v1/demo-sessions")
                .appending(path: session.sessionId)
                .appending(path: "visual-runs")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(VisualRunBody(
            instruction: instruction,
            inputMode: "text",
            annotatedImageBase64: capture.imageData.base64EncodedString(),
            viewportWidth: capture.viewportWidth,
            viewportHeight: capture.viewportHeight,
            elements: capture.elements,
            provider: "codex"
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 200)
        return try JSONDecoder().decode(CodingRunResult.self, from: data)
    }

    private func validate(_ response: URLResponse, data: Data, expectedStatus: Int) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == expectedStatus else {
            let message = String(data: data, encoding: .utf8) ?? "TouchCode Bridge returned an invalid response."
            throw BridgeError.requestFailed(message)
        }
    }
}

private struct VisualRunBody: Encodable {
    let instruction: String
    let inputMode: String
    let annotatedImageBase64: String
    let viewportWidth: Double
    let viewportHeight: Double
    let elements: [VisibleElementContext]
    let provider: String
}

private enum BridgeError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return message
        }
    }
}
