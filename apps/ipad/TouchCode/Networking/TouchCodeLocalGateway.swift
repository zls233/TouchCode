import Foundation
import Network

/// iPad-local HTTP gateway that presents a stable 127.0.0.1 URL to WKWebView
/// and tunnels requests to the Mac. For Phase 4a it forwards via URLSession to
/// the Mac's previewURL (still over LAN but hidden from JavaScript). Future
/// phases will route via TouchCodeSession/QUIC without changing WebView code.
final class TouchCodeLocalGateway: @unchecked Sendable {
    enum GatewayError: Error, Equatable {
        case alreadyStarted
        case notStarted
        case invalidRequest
        case upstreamFailed
        case payloadTooLarge
        case forbiddenDestination
    }

    private let forwardBaseURL: URL
    private let sessionToken: String?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.touchcode.local-gateway")
    private(set) var localURL: URL?
    private var isStarted = false

    init(forwardBaseURL: URL, sessionToken: String? = nil) {
        self.forwardBaseURL = forwardBaseURL
        self.sessionToken = sessionToken
    }

    func start() throws -> URL {
        guard !isStarted else { throw GatewayError.alreadyStarted }
        // Validate forward base is http(s) and not arbitrary (only http for now, and host must be set)
        guard let scheme = forwardBaseURL.scheme, (scheme == "http" || scheme == "https"),
              forwardBaseURL.host != nil else {
            throw GatewayError.forbiddenDestination
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: 0)
        listener.newConnectionHandler = { [weak self] (conn: NWConnection) in self?.handle(connection: conn) }
        listener.stateUpdateHandler = { (_: NWListener.State) in }
        listener.start(queue: queue)
        // NWListener port is assigned asynchronously; use listener.port or wait briefly.
        // For tests, we synchronously derive via NWListener.port after start.
        var port: UInt16 = 0
        // NWListener.port is available after start, but may be nil immediately; poll briefly.
        for _ in 0..<20 {
            if let p = listener.port, p.rawValue != 0 {
                port = p.rawValue
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if port == 0 { throw GatewayError.upstreamFailed }
        self.listener = listener
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        self.localURL = url
        self.isStarted = true
        return url
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for c in connections { c.cancel() }
        connections.removeAll()
        localURL = nil
        isStarted = false
    }

    private func handle(connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            if case .cancelled = state { self?.connections.removeAll { $0 === connection } }
            if case .failed = state { self?.connections.removeAll { $0 === connection } }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] (data: Data?, _: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            guard let self else { return }
            var combined = buffer
            if let data { combined.append(data) }
            if combined.count > 64 * 1024 {
                self.sendError(431, message: "header too large", on: connection)
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            if let headerEnd = combined.range(of: Data("\r\n\r\n".utf8)) {
                self.handleHTTPRequest(headerData: combined[..<headerEnd.upperBound], bodyPrefix: Data(combined[headerEnd.upperBound...]), on: connection)
            } else if isComplete {
                self.sendError(400, message: "bad request", on: connection)
            } else {
                self.receiveRequest(on: connection, buffer: combined)
            }
        }
    }

    private func handleHTTPRequest(headerData: Data, bodyPrefix: Data, on connection: NWConnection) {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            sendError(400, message: "bad request", on: connection)
            return
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(400, message: "bad request", on: connection)
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendError(400, message: "bad request", on: connection)
            return
        }
        let method = String(parts[0])
        var path = String(parts[1])
        // Only allow GET/HEAD for Phase 4a; reject others as 405
        guard method == "GET" || method == "HEAD" else {
            sendError(405, message: "method not allowed", on: connection)
            return
        }
        // Prevent directory traversal and arbitrary host via path
        if path.contains("..") || path.contains("\0") {
            sendError(403, message: "forbidden", on: connection)
            return
        }
        // Strip query for forwarding but keep it
        // Build upstream URL by appending path to forwardBaseURL
        // Ensure we don't allow absolute URL in path (proxy-style)
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            sendError(403, message: "forbidden", on: connection)
            return
        }
        // Normalize path: ensure leading /
        if !path.hasPrefix("/") { path = "/" + path }
        // Validate forwardBaseURL is still allowed (only http(s) and host already checked)
        // For Phase 4a, we only allow forwarding to the same host/port as forwardBaseURL's host
        // i.e., we don't allow arbitrary destinations.
        let upstreamString = forwardBaseURL.absoluteString.hasSuffix("/") ? String(forwardBaseURL.absoluteString.dropLast()) + path : forwardBaseURL.absoluteString + path
        guard let upstreamURL = URL(string: upstreamString) else {
            sendError(400, message: "bad request", on: connection)
            return
        }
        // Enforce that upstream host matches forwardBaseURL host (no open proxy)
        guard upstreamURL.host?.lowercased() == forwardBaseURL.host?.lowercased(),
              upstreamURL.port == forwardBaseURL.port else {
            sendError(403, message: "forbidden", on: connection)
            return
        }
        // Check payload size guard for request (header already limited)
        if bodyPrefix.count > TransportFrameLimits.maxEnvelopeBytes {
            sendError(413, message: "payload too large", on: connection)
            return
        }
        // Forward via URLSession
        var request = URLRequest(url: upstreamURL)
        request.httpMethod = method
        if let token = sessionToken {
            request.setValue(token, forHTTPHeaderField: "x-touchcode-session-token")
        }
        request.setValue("TouchCodeLocalGateway/1.0", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                self.sendError(502, message: error.localizedDescription, on: connection)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data else {
                self.sendError(502, message: "upstream failed", on: connection)
                return
            }
            self.sendResponse(status: httpResponse.statusCode, headers: httpResponse.allHeaderFields, body: data, on: connection)
        }
        task.resume()
    }

    private func sendResponse(status: Int, headers: [AnyHashable: Any], body: Data, on connection: NWConnection) {
        var headerLines = ["HTTP/1.1 \(status) \(statusText(for: status))\r\n"]
        // Pass through content-type and cache-control if present, else default
        if let ct = headers["Content-Type"] as? String {
            headerLines.append("Content-Type: \(ct)\r\n")
        } else {
            headerLines.append("Content-Type: application/octet-stream\r\n")
        }
        headerLines.append("Content-Length: \(body.count)\r\n")
        headerLines.append("Connection: close\r\n")
        headerLines.append("\r\n")
        let headerData = Data(headerLines.joined().utf8)
        let combined = headerData + body
        if combined.count > TransportFrameLimits.maxEnvelopeBytes + 64 * 1024 {
            sendError(413, message: "payload too large", on: connection)
            return
        }
        connection.send(content: combined, completion: .contentProcessed { (_: NWError?) in connection.cancel() })
    }

    private func sendError(_ status: Int, message: String, on connection: NWConnection) {
        let body = Data(message.utf8)
        sendResponse(status: status, headers: ["Content-Type": "text/plain"], body: body, on: connection)
    }

    private func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
        case 502: return "Bad Gateway"
        default: return "Error"
        }
    }
}

/// Controllable fake for deterministic tests.
final class FakeLocalGateway {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var localURL: URL?
    var shouldFailStart = false
    var fakePort: UInt16 = 54321

    func start(with base: URL) throws -> URL {
        startCount += 1
        if shouldFailStart { throw TouchCodeLocalGateway.GatewayError.upstreamFailed }
        let url = URL(string: "http://127.0.0.1:\(fakePort)/")!
        localURL = url
        return url
    }

    func stop() {
        stopCount += 1
        localURL = nil
    }
}
