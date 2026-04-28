import AVFoundation
import Foundation

final class AudioCaptureEngine {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let processingQueue = DispatchQueue(label: "com.voiceinput.audio.processing", qos: .userInteractive)

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
        let engine = AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hardwareFormat, to: Self.targetFormat) else {
            throw AudioError.formatConversionFailed
        }
        self.converter = converter

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
            self?.handlePCMBuffer(buffer)
        }

        try engine.start()
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
    }

    private func handlePCMBuffer(_ buffer: AVAudioPCMBuffer) {
        let rms = computeRMS(from: buffer)

        guard let converter = converter,
              let pcmData = convertToPCM16(buffer: buffer, converter: converter) else { return }
        let base64 = pcmData.base64EncodedString()

        processingQueue.async { [weak self] in
            self?.onRMSUpdate?(rms)
            self?.onAudioChunk?(base64)
        }
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
        guard status != .error else { return nil }

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
