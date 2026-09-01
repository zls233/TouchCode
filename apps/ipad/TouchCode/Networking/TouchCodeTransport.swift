import Foundation
import Network

enum TransportState: Equatable {
    case idle
    case connecting
    case ready
    case failed
}

struct TouchCodeHello: Decodable, Equatable {
    let protocolVersion: Int
    let role: String
    let platform: String
    let appVersion: String
    let capabilities: [String]
    let bridgeURL: String
}

protocol TouchCodeTransport: AnyObject {
    var states: AsyncStream<TransportState> { get }
    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello
    func disconnect() async
}

enum TouchCodeTransportError: Error {
    case connectionFailed
    case invalidResponse
    case unsupportedProtocol
    case responseTooLarge
}

/// Phase-0 transport: resolve the Bonjour endpoint with Network.framework and
/// negotiate the versioned hello over the existing Bridge HTTP connection.
/// It is intentionally replaceable; QUIC + TLS belongs to the secure transport phase.
final class PrototypeHTTPTransport: TouchCodeTransport, @unchecked Sendable {
    let states: AsyncStream<TransportState>
    private let continuation: AsyncStream<TransportState>.Continuation
    private let queue = DispatchQueue(label: "com.touchcode.ipad.prototype-transport")
    private var activeConnection: NWConnection?

    init() {
        let pair = AsyncStream<TransportState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        states = pair.stream
        continuation = pair.continuation
        continuation.yield(.idle)
    }

    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello {
        await disconnect()
        continuation.yield(.connecting)
        let connection = NWConnection(to: endpoint.networkEndpoint, using: .tcp)
        activeConnection = connection
        do {
            let data = try await receiveHello(over: connection)
            let hello = try Self.decodeHello(from: data)
            guard hello.protocolVersion == 1, hello.role == "host" else {
                throw TouchCodeTransportError.unsupportedProtocol
            }
            continuation.yield(.ready)
            return hello
        } catch {
            continuation.yield(.failed)
            connection.cancel()
            if activeConnection === connection { activeConnection = nil }
            throw error
        }
    }

    func disconnect() async {
        activeConnection?.cancel()
        activeConnection = nil
        continuation.yield(.idle)
    }

    private func receiveHello(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var response = Data()
            var finished = false

            func finish(_ result: Result<Data, Error>) {
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            var receiveNext: (() -> Void)!
            receiveNext = {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, complete, error in
                    if let data { response.append(data) }
                    if response.count > 64 * 1024 {
                        finish(.failure(TouchCodeTransportError.responseTooLarge))
                    } else if let error {
                        finish(.failure(error))
                    } else if complete {
                        finish(.success(response))
                    } else {
                        receiveNext()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = Data("GET /v1/hello HTTP/1.1\r\nHost: touchcode.local\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: request, completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) }
                        else { receiveNext() }
                    })
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(TouchCodeTransportError.connectionFailed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    static func decodeHello(from response: Data) throws -> TouchCodeHello {
        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: response[..<separator.lowerBound], encoding: .utf8),
              header.hasPrefix("HTTP/1.1 200") || header.hasPrefix("HTTP/1.0 200") else {
            throw TouchCodeTransportError.invalidResponse
        }
        let body = response[separator.upperBound...]
        return try JSONDecoder().decode(TouchCodeHello.self, from: body)
    }
}
