import AVFoundation
import Foundation

private func debugLogAudio(_ message: String) {
    let line = "\(Date()): [AUDIO] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/voiceinput_debug.log")
    if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        try? data.write(to: url)
    }
}

final class AudioCaptureEngine {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let processingQueue = DispatchQueue(label: "com.voiceinput.audio.processing", qos: .userInteractive)
    private var configurationObserver: NSObjectProtocol?
    private var healthCheckWorkItem: DispatchWorkItem?
    private var isCapturing = false
    private var capturedChunks = 0
    private var capturedBytes = 0
    private var tapInstalled = false
    private let restartPolicy = AudioRestartPolicy(maxRestartAttempts: 3)
    private let configurationHealthCheckDelay: TimeInterval = 0.35

    static let targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!
    }()

    static let frameBufferSize: AVAudioFrameCount = 1600

    var onRMSUpdate: ((Float) -> Void)?
    var onAudioChunk: ((String) -> Void)?

    func start() throws {
        isCapturing = true
        capturedChunks = 0
        capturedBytes = 0
        try startEngine()
    }

    func stop() {
        isCapturing = false
        healthCheckWorkItem?.cancel()
        healthCheckWorkItem = nil
        stopEngine()
        processingQueue.sync {}
        debugLogAudio("capture stopped chunks=\(capturedChunks), bytes=\(capturedBytes)")
    }

    private func startEngine() throws {
        stopEngine()

        let engine = AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        debugLogAudio(
            "starting engine inputFormat=\(hardwareFormat.sampleRate)Hz channels=\(hardwareFormat.channelCount) format=\(hardwareFormat.commonFormat.rawValue)"
        )

        guard let converter = AVAudioConverter(from: hardwareFormat, to: Self.targetFormat) else {
            throw AudioError.formatConversionFailed
        }
        self.converter = converter

        inputNode.installTap(onBus: 0, bufferSize: Self.frameBufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            self?.handlePCMBuffer(buffer)
        }
        tapInstalled = true

        observeConfigurationChanges(for: engine)
        engine.prepare()
        try engine.start()
        debugLogAudio("engine started")
    }

    private func handlePCMBuffer(_ buffer: AVAudioPCMBuffer) {
        let rms = computeRMS(from: buffer)

        guard let converter = converter,
              let pcmData = convertToPCM16(buffer: buffer, converter: converter) else { return }
        let base64 = pcmData.base64EncodedString()

        processingQueue.async { [weak self] in
            guard let self else { return }
            self.capturedChunks += 1
            self.capturedBytes += pcmData.count
            self.restartPolicy.recordChunk()
            if self.capturedChunks <= 3 || self.capturedChunks % 20 == 0 {
                debugLogAudio(
                    "captured chunk=\(self.capturedChunks), bytes=\(pcmData.count), totalBytes=\(self.capturedBytes), rms=\(rms)"
                )
            }
            self.onRMSUpdate?(rms)
            self.onAudioChunk?(base64)
        }
    }

    private func observeConfigurationChanges(for engine: AVAudioEngine) {
        removeConfigurationObserver()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        debugLogAudio("configuration changed")
        guard isCapturing else { return }
        scheduleConfigurationHealthCheck()
    }

    private func scheduleConfigurationHealthCheck() {
        healthCheckWorkItem?.cancel()
        let checkpoint = restartPolicy.configurationChanged(currentChunkCount: capturedChunks)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturing else { return }
            guard self.restartPolicy.shouldRestart(from: checkpoint, currentChunkCount: self.capturedChunks) else {
                debugLogAudio("configuration change ignored; audio is still flowing")
                return
            }
            self.restartPolicy.recordRestartAttempt()
            do {
                debugLogAudio("restarting engine after stalled configuration change")
                try self.startEngine()
            } catch {
                debugLogAudio("restart failed: \(error.localizedDescription)")
                self.scheduleConfigurationHealthCheck()
            }
        }
        healthCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + configurationHealthCheckDelay, execute: workItem)
    }

    private func stopEngine() {
        removeConfigurationObserver()
        if let engine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
        }
        engine = nil
        converter = nil
    }

    private func removeConfigurationObserver() {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        configurationObserver = nil
    }

    private func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        if let floatData = buffer.floatChannelData {
            let channelData = floatData[0]
            var sumSquares: Float = 0
            for i in 0..<frameLength {
                sumSquares += channelData[i] * channelData[i]
            }
            return min(1.0, sqrt(sumSquares / Float(frameLength)) * 3.0)
        }
        return 0
    }

    private func convertToPCM16(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> Data? {
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard targetFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: targetFrameCount) else { return nil }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else {
            debugLogAudio("conversion failed: \(error?.localizedDescription ?? "unknown error")")
            return nil
        }
        guard outputBuffer.frameLength > 0 else {
            debugLogAudio("conversion produced 0 frames, status=\(status)")
            return nil
        }

        guard let int16Data = outputBuffer.int16ChannelData else { return nil }
        let channelPtr = int16Data[0]
        let byteCount = Int(outputBuffer.frameLength) * 2
        return Data(bytes: channelPtr, count: byteCount)
    }
}

enum AudioError: LocalizedError {
    case formatConversionFailed
    var errorDescription: String? {
        switch self {
        case .formatConversionFailed: return "Audio format conversion failed"
        }
    }
}
