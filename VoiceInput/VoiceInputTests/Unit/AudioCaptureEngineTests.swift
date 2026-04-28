import XCTest
@testable import VoiceInput

final class AudioCaptureEngineTests: XCTestCase {
    func testTargetFormatIs16kMonoInt16() {
        let format = AudioCaptureEngine.targetFormat
        XCTAssertEqual(format.sampleRate, 16000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatInt16)
    }

    func testStopWithoutStartDoesNotCrash() {
        let engine = AudioCaptureEngine()
        engine.stop()
    }

    func testCallbacksAreNilByDefault() {
        let engine = AudioCaptureEngine()
        XCTAssertNil(engine.onRMSUpdate)
        XCTAssertNil(engine.onAudioChunk)
    }
}
