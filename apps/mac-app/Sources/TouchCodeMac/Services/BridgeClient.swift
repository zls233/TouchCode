import Foundation

struct BridgeHealth: Decodable, Equatable {
    let status: String
    let service: String
    let role: String
    let version: String
}

struct DemoSession: Decodable, Equatable {
    let sessionId: String
    let projectId: String
    let worktreePath: String
    let previewURL: String
    let bridgeURL: String
    let port: Int
    let status: String
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
}
