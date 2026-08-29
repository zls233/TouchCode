import Foundation

@MainActor
final class BridgeProcessController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    private var process: Process?
    private var outputPipe: Pipe?

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
        child.environment = environment
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        child.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.process = nil
                self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self?.outputPipe = nil
                if process.terminationStatus == 0 {
                    self?.state = .stopped
                } else {
                    self?.state = .failed("Bridge exited with status \(process.terminationStatus)")
                }
            }
        }

        do {
            state = .starting
            try child.run()
            process = child
            outputPipe = pipe
            state = .running
        } catch {
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
