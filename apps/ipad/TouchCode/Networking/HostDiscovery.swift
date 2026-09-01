import Foundation
import Network

struct TouchCodeEndpoint: @unchecked Sendable {
    let networkEndpoint: NWEndpoint
}

struct DiscoveredHost: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let endpoint: TouchCodeEndpoint
}

enum HostDiscoveryEvent {
    case hosts([DiscoveredHost])
    case permissionRequired
}

@MainActor
protocol HostDiscovery: AnyObject {
    var events: AsyncStream<HostDiscoveryEvent> { get }
    func start() async throws
    func stop()
}

@MainActor
final class BonjourHostDiscovery: HostDiscovery {
    let events: AsyncStream<HostDiscoveryEvent>
    private let continuation: AsyncStream<HostDiscoveryEvent>.Continuation
    private var browser: NWBrowser?

    init() {
        let pair = AsyncStream<HostDiscoveryEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pair.stream
        continuation = pair.continuation
    }

    func start() async throws {
        guard browser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_touchcode._tcp", domain: "local."),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.publish(results)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard case let .waiting(error) = state else {
                guard case let .failed(error) = state else { return }
                Task { @MainActor in
                    if Self.isLocalNetworkPermissionError(error) {
                        self?.continuation.yield(.permissionRequired)
                    } else {
                        self?.continuation.yield(.hosts([]))
                    }
                }
                return
            }
            Task { @MainActor in
                if Self.isLocalNetworkPermissionError(error) {
                    self?.continuation.yield(.permissionRequired)
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        continuation.yield(.hosts([]))
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        let discovered = results.compactMap { result -> DiscoveredHost? in
            guard case let .service(name, type, domain, _) = result.endpoint,
                  type == "_touchcode._tcp" else { return nil }
            let id = "\(name).\(type).\(domain)"
            return DiscoveredHost(
                id: id,
                name: name.replacingOccurrences(of: " TouchCode", with: ""),
                endpoint: TouchCodeEndpoint(networkEndpoint: result.endpoint)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        continuation.yield(.hosts(discovered))
    }

    private static func isLocalNetworkPermissionError(_ error: NWError) -> Bool {
        guard case let .posix(code) = error else { return false }
        return code == .EPERM || code == .EACCES
    }
}
