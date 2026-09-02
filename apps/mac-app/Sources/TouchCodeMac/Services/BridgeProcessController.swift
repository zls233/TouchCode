import Foundation
import TouchCodeIdentity

@MainActor
final class BridgeProcessController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    private let identityStore: DeviceIdentityStore
    private var process: Process?
    private var outputPipe: Pipe?

    init(identityStore: DeviceIdentityStore = DeviceIdentityStore()) {
        self.identityStore = identityStore
    }

    func start() {
        guard process == nil else { return }
        guard let root = ProcessInfo.processInfo.environment["TOUCHCODE_ROOT"],
              let pnpm = ProcessInfo.processInfo.environment["TOUCHCODE_PNPM"] else {
            state = .failed("TouchCode development runtime is not configured")
            return
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: pnpm)
        child.arguments = ["--dir", root, "dev:bridge"]
        child.currentDirectoryURL = URL(fileURLWithPath: root)
        var environment = ProcessInfo.processInfo.environment
        let toolDirectory = URL(fileURLWithPath: pnpm).deletingLastPathComponent().path
        environment["PATH"] = "\(toolDirectory):\(environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")"
        do {
            let displayName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            let identity = try identityStore.loadOrCreate(displayName: displayName)
            environment[BridgeIdentityEnvironment.variableName] = try BridgeIdentityEnvironment.encode(identity)
        } catch {
            state = .failed("Device identity is unavailable: \(error)")
            return
        }
        child.environment = environment
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        child.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.process === process else { return }
                self.process = nil
                pipe.fileHandleForReading.readabilityHandler = nil
                if self.outputPipe === pipe {
                    self.outputPipe = nil
                }
                self.state = process.terminationStatus == 0
                    ? .stopped
                    : .failed("Bridge exited with status \(process.terminationStatus)")
            }
        }

        // Publish ownership before launching. Process termination can race the
        // return from run(), and assigning afterwards can resurrect a dead child.
        process = child
        outputPipe = pipe
        state = .starting
        do {
            try child.run()
            state = .running
        } catch {
            process = nil
            outputPipe = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
    }

    deinit {
        process?.terminate()
    }
}
