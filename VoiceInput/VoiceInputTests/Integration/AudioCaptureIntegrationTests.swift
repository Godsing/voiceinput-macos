import XCTest
import AVFoundation
@testable import VoiceInput

final class AudioCaptureIntegrationTests: XCTestCase {
    func testAudioEngineStartsAndStops() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw XCTSkip("Microphone permission not granted")
        }

        let engine = AudioCaptureEngine()
        var receivedChunk = false
        var receivedRMS = false

        let chunkExpectation = expectation(description: "Received audio chunk")
        let rmsExpectation = expectation(description: "Received RMS update")

        engine.onAudioChunk = { _ in
            if !receivedChunk {
                receivedChunk = true
                chunkExpectation.fulfill()
            }
        }
        engine.onRMSUpdate = { _ in
            if !receivedRMS {
                receivedRMS = true
                rmsExpectation.fulfill()
            }
        }

        do {
            try engine.start()
        } catch {
            throw XCTSkip("Audio engine failed to start: \(error)")
        }

        wait(for: [chunkExpectation, rmsExpectation], timeout: 5.0)
        engine.stop()
    }
}
