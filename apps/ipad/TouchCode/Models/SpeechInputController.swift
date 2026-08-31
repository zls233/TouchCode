import Accelerate
import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechInputController: ObservableObject {
    enum ModelStatus: Equatable { case idle, preparing, ready, unavailable, failed(String) }

    @Published private(set) var transcript = ""
    @Published private(set) var volatileTranscript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var modelStatus: ModelStatus = .idle
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var selectedLocale = Locale.current

    func prepareModel(locale: Locale = .current) async {
        selectedLocale = locale
        modelStatus = .preparing
        do {
            guard SpeechTranscriber.isAvailable,
                  let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                modelStatus = .unavailable
                return
            }
            let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            modelStatus = .ready
        } catch {
            modelStatus = .failed(error.localizedDescription)
        }
    }

    func toggle() async {
        if isRecording { await stopAndFinalize() } else { await start() }
    }

    func start() async {
        guard !isRecording else { return }
        operationGeneration &+= 1
        let generation = operationGeneration
        do {
            guard await requestSpeechAuthorization() else { throw SpeechError.speechDenied }
            guard await AVAudioApplication.requestRecordPermission() else { throw SpeechError.microphoneDenied }
            if modelStatus != .ready { await prepareModel(locale: selectedLocale) }
            guard modelStatus == .ready,
                  let locale = await SpeechTranscriber.supportedLocale(equivalentTo: selectedLocale) else {
                throw SpeechError.modelUnavailable
            }

            resetWithoutFinalizing()
            transcript = ""
            volatileTranscript = ""
            errorMessage = nil

            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let modules: [any SpeechModule] = [transcriber]
            let analyzer = SpeechAnalyzer(modules: modules)
            let (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.analyzer = analyzer
            inputContinuation = continuation

            resultTask = Task { [weak self] in
                do {
                    // Range-aware reconciliation: SpeechTranscriber yields incremental segments
                    // identified by `result.range`. Volatile segments are marked by
                    // `analyzer.volatileRange`. We keep finalized segments ordered by
                    // arrival (which matches range order) and replace volatile in place
                    // to avoid duplication or loss when results are cumulative vs incremental.
                    var finalizedSegments: [String] = []
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { break }
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        let volatileRange = await analyzer.volatileRange
                        let isVolatile = volatileRange != nil
                        // Also check if this specific result's range matches volatileRange when available.
                        // If the API provides per-result isFinal, that would be more precise, but volatileRange is the source of truth for iOS 26.
                        await MainActor.run {
                            guard let self, self.operationGeneration == generation else { return }
                            if isVolatile {
                                // Volatile: show latest hypothesis without committing to finalized transcript.
                                // If results are cumulative, volatile text already equals full transcript hypothesis.
                                // If incremental, volatile is just the tail segment.
                                self.volatileTranscript = text
                            } else {
                                // Finalized: commit to transcript. Handle both cumulative (text contains prior) and incremental (append).
                                if self.transcript.isEmpty {
                                    self.transcript = text
                                    finalizedSegments = [text]
                                } else if text.hasPrefix(self.transcript) {
                                    // Cumulative case: new text is superset of prior
                                    self.transcript = text
                                    finalizedSegments = [text]
                                } else if self.transcript.hasSuffix(text) || finalizedSegments.contains(text) {
                                    // Duplicate final emission, ignore
                                } else {
                                    // Incremental case: append new segment
                                    finalizedSegments.append(text)
                                    self.transcript = finalizedSegments.joined(separator: " ")
                                }
                                self.volatileTranscript = ""
                            }
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in self?.record(error, generation: generation) }
                }
            }
            analysisTask = Task { [weak self] in
                do { _ = try await analyzer.analyzeSequence(inputs) }
                catch { await MainActor.run { [weak self] in self?.record(error, generation: generation) } }
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                throw SpeechError.modelUnavailable
            }
            let converter = try AudioInputConverter(inputFormat: format, analyzerFormat: analyzerFormat)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, time in
                guard let self else { return }
                do {
                    continuation.yield(try converter.convert(buffer, at: time))
                    let level = Self.rms(buffer)
                    Task { @MainActor [weak self] in
                        guard let self, self.operationGeneration == generation else { return }
                        self.audioLevel = level
                    }
                } catch {
                    Task { @MainActor [weak self] in self?.record(error, generation: generation) }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            // A gesture can be cancelled while the async permission/model
            // setup is in flight. Do not leave an engine tap or active session
            // behind when that happens before `isRecording` becomes true.
            guard generation == operationGeneration else {
                await stopAndFinalize()
                return
            }
            isRecording = true
        } catch {
            resetWithoutFinalizing()
            errorMessage = error.localizedDescription
        }
    }

    func stop() { Task { await stopAndFinalize() } }

    func cancel() async {
        await stopAndFinalize()
        transcript = ""
        volatileTranscript = ""
    }

    func stopAndFinalize() async {
        guard isRecording || analyzer != nil else { return }
        operationGeneration &+= 1
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()
        inputContinuation = nil
        do { try await analyzer?.finalizeAndFinishThroughEndOfInput() }
        catch { errorMessage = error.localizedDescription }
        analysisTask?.cancel()
        resultTask?.cancel()
        analysisTask = nil
        resultTask = nil
        analyzer = nil
        if !volatileTranscript.isEmpty {
            let trimmed = volatileTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if transcript.isEmpty {
                    transcript = trimmed
                } else if !transcript.hasSuffix(trimmed) && !trimmed.hasPrefix(transcript) {
                    transcript += " " + trimmed
                } else if trimmed.hasPrefix(transcript) {
                    transcript = trimmed
                }
            }
            volatileTranscript = ""
        }
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetWithoutFinalizing() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()
        inputContinuation = nil
        analysisTask?.cancel()
        resultTask?.cancel()
        analysisTask = nil
        resultTask = nil
        analyzer = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func record(_ error: Error, generation: Int) {
        guard generation == operationGeneration else { return }
        errorMessage = error.localizedDescription
    }

    private func requestSpeechAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?.pointee else { return 0 }
        var value: Float = 0
        vDSP_rmsqv(samples, 1, &value, vDSP_Length(buffer.frameLength))
        return min(max(value * 8, 0), 1)
    }
}

private final class AudioInputConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat, analyzerFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw SpeechError.modelUnavailable
        }
        self.converter = converter
        outputFormat = analyzerFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) throws -> AnalyzerInput {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = max(AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1, 1)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SpeechError.modelUnavailable
        }
        var conversionError: NSError?
        var supplied = false
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if let conversionError { throw conversionError }
        guard status != .error else { throw SpeechError.modelUnavailable }
        return AnalyzerInput(buffer: output, bufferStartTime: time.map { $0.sampleTime == 0 ? nil : CMTime(value: $0.sampleTime, timescale: CMTimeScale($0.sampleRate)) } ?? nil)
    }
}

private enum SpeechError: LocalizedError {
    case speechDenied, microphoneDenied, modelUnavailable

    var errorDescription: String? {
        switch self {
        case .speechDenied: "Speech recognition permission is required."
        case .microphoneDenied: "Microphone permission is required."
        case .modelUnavailable: "The selected on-device speech model is not installed or supported."
        }
    }
}
