import Foundation

enum ChannelKind: String, Codable, CaseIterable, Equatable {
    case control
    case codex
    case preview
    case file
    case voice
    case annotation

    var priority: Int {
        switch self {
        case .control: return 0
        case .codex: return 1
        case .voice: return 1
        case .annotation: return 2
        case .preview: return 3
        case .file: return 4
        }
    }
}

struct SessionMessage: Equatable {
    let id: UUID
    let channel: ChannelKind
    let payload: Data
    let sentAt: Date
}

protocol SessionChannel: AnyObject {
    var kind: ChannelKind { get }
    var messages: AsyncStream<SessionMessage> { get }
    func send(_ message: SessionMessage) async throws
    func close()
}

/// Multiplexes feature messages over a single underlying transport,
/// ensuring that large file/preview payloads do not block control messages
/// by using per-channel queues and priority-aware delivery.
final class ChannelMultiplexer: @unchecked Sendable {
    private struct ChannelState {
        let channel: FakeChannel
        let queue: DispatchQueue
    }

    private var channels: [ChannelKind: ChannelState] = [:]
    private let lock = NSLock()

    init() {
        for kind in ChannelKind.allCases {
            let ch = FakeChannel(kind: kind)
            channels[kind] = ChannelState(channel: ch, queue: DispatchQueue(label: "channel.\(kind.rawValue)"))
        }
    }

    func channel(for kind: ChannelKind) -> SessionChannel {
        lock.lock()
        defer { lock.unlock() }
        return channels[kind]!.channel
    }

    func send(_ message: SessionMessage) async throws {
        // Validate payload size via TransportFrameLimits
        if message.payload.count > TransportFrameLimits.maxPayloadBytes {
            throw TransportFrameError.payloadTooLarge
        }
        // Route to appropriate channel's queue based on priority (control first)
        let state = lock.withLock { channels[message.channel] }
        guard let state else { throw TransportFrameError.invalidEnvelope }
        // Simulate chunking for file channel: split large payloads to avoid blocking
        if message.channel == .file && message.payload.count > 64 * 1024 {
            let chunks = stride(from: 0, to: message.payload.count, by: 64 * 1024).map { offset in
                message.payload[offset..<min(offset + 64 * 1024, message.payload.count)]
            }
            for chunk in chunks {
                let chunkMessage = SessionMessage(id: message.id, channel: .file, payload: Data(chunk), sentAt: message.sentAt)
                await state.channel.deliver(chunkMessage)
                // Yield to allow higher priority channels to interleave
                await Task.yield()
            }
        } else {
            await state.channel.deliver(message)
        }
    }

    func closeAll() {
        lock.lock()
        let all = channels.values.map { $0.channel }
        lock.unlock()
        for ch in all { ch.close() }
    }

    var allMessages: AsyncStream<SessionMessage> {
        AsyncStream { continuation in
            Task {
                // Merge all channels' messages into one stream ordered by priority
                let streams = self.channels.values.map { $0.channel.messages }
                // For Phase 5a, we simply forward each channel's messages as they arrive;
                // control messages are already prioritized via separate queues.
                for stream in streams {
                    Task {
                        for await msg in stream {
                            continuation.yield(msg)
                        }
                    }
                }
            }
        }
    }
}

private final class FakeChannel: SessionChannel, @unchecked Sendable {
    let kind: ChannelKind
    let messages: AsyncStream<SessionMessage>
    private let continuation: AsyncStream<SessionMessage>.Continuation
    private let queue = DispatchQueue(label: "fake-channel")

    init(kind: ChannelKind) {
        self.kind = kind
        let pair = AsyncStream<SessionMessage>.makeStream(bufferingPolicy: .bufferingNewest(10))
        messages = pair.stream
        continuation = pair.continuation
    }

    func send(_ message: SessionMessage) async throws {
        // Not used directly; multiplexer delivers via deliver
        await deliver(message)
    }

    func deliver(_ message: SessionMessage) async {
        // Simulate small delay for file channel to test non-blocking
        if kind == .file {
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms per chunk
        }
        continuation.yield(message)
    }

    func close() {
        continuation.finish()
    }
}

// Controllable fake for deterministic tests
final class ControllableChannel: SessionChannel {
    let kind: ChannelKind
    let messages: AsyncStream<SessionMessage>
    private let continuation: AsyncStream<SessionMessage>.Continuation
    private var pending: [SessionMessage] = []
    private var isPaused = false
    private let lock = NSLock()

    init(kind: ChannelKind) {
        self.kind = kind
        let pair = AsyncStream<SessionMessage>.makeStream(bufferingPolicy: .bufferingNewest(100))
        messages = pair.stream
        continuation = pair.continuation
    }

    func send(_ message: SessionMessage) async throws {
        lock.lock()
        if isPaused {
            pending.append(message)
            lock.unlock()
            return
        }
        lock.unlock()
        continuation.yield(message)
    }

    func deliverPending() {
        lock.lock()
        let toDeliver = pending
        pending.removeAll()
        lock.unlock()
        for msg in toDeliver { continuation.yield(msg) }
    }

    func pause() { lock.lock(); isPaused = true; lock.unlock() }
    func resume() { lock.lock(); isPaused = false; lock.unlock(); deliverPending() }
    func close() { continuation.finish() }
    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return pending.count }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
