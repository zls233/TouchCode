import Foundation

struct BridgeHealth: Decodable, Equatable {
    let status: String
    let service: String
    let role: String
    let version: String
}

struct TrustedPeer: Decodable, Equatable, Identifiable {
    let relationshipId: String
    let peerDeviceId: String
    let displayName: String
    let firstPairedAt: Int64
    let lastSeenAt: Int64

    var id: String { peerDeviceId }
}

private struct TrustedPeersResponse: Decodable {
    let peers: [TrustedPeer]
}

struct DemoSession: Decodable, Equatable {
    let sessionId: String
    let projectId: String?
    let worktreePath: String?
    let previewURL: String
    let bridgeURL: String
    let port: Int?
    let status: String?
    let pairingCode: String
    let ipadConnected: Bool
    let latestRunId: String?
    let errorMessage: String?
}

struct CodingRunSnapshot: Decodable, Equatable {
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
    let outcome: String?
    let clarificationQuestion: String?
    let startedAt: String
    let updatedAt: String

    var isActive: Bool { status == "queued" || status == "running" }
    var isReviewable: Bool { status == "succeeded" && decision == "pending" && !changedFiles.isEmpty }
    var needsClarification: Bool { outcome == "needs_clarification" }
    var decisionLabel: String? {
        switch decision {
        case "approved": return "Changes kept"
        case "rejected": return "Changes undone"
        default: return nil
        }
    }
    var decisionIcon: String {
        decision == "approved" ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill"
    }
}

struct BridgeClient {
    var endpoint: URL

    func health() async throws -> BridgeHealth {
        let url = endpoint.appending(path: "health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(BridgeHealth.self, from: data)
    }

    func createDemoSession() async throws -> DemoSession {
        let url = endpoint.appending(path: "v1/demo-sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DemoSession.self, from: data)
    }

    func trustedPeers() async throws -> [TrustedPeer] {
        let url = endpoint
            .appending(path: "v1")
            .appending(path: "device-trust")
            .appending(path: "peers")
        return try await get(url, as: TrustedPeersResponse.self).peers
    }

    func forgetTrustedPeer(deviceId: String) async throws {
        let url = endpoint
            .appending(path: "v1")
            .appending(path: "device-trust")
            .appending(path: "peers")
            .appending(path: deviceId)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 204)
    }

    func demoSession(_ sessionId: String) async throws -> DemoSession {
        let url = endpoint
            .appending(path: "v1/demo-sessions")
            .appending(path: sessionId)
        return try await get(url, as: DemoSession.self)
    }

    func codingRun(sessionId: String, runId: String) async throws -> CodingRunSnapshot {
        let url = endpoint
            .appending(path: "v1/demo-sessions")
            .appending(path: sessionId)
            .appending(path: "runs")
            .appending(path: runId)
        return try await get(url, as: CodingRunSnapshot.self)
    }

    func decide(sessionId: String, runId: String, action: String) async throws -> CodingRunSnapshot {
        let url = endpoint
            .appending(path: "v1/demo-sessions")
            .appending(path: sessionId)
            .appending(path: "runs")
            .appending(path: runId)
            .appending(path: action)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 200)
        return try JSONDecoder().decode(CodingRunSnapshot.self, from: data)
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, expectedStatus: 200)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validate(_ response: URLResponse, data: Data, expectedStatus: Int) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == expectedStatus else {
            let message = (try? JSONDecoder().decode(BridgeErrorBody.self, from: data).message)
                ?? "TouchCode Bridge returned an invalid response."
            throw BridgeClientError.requestFailed(message)
        }
    }
}

private struct BridgeErrorBody: Decodable { let message: String? }

private enum BridgeClientError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): message
        }
    }
}
