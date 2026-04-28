import XCTest
@testable import VoiceInput

final class SessionConfigTests: XCTestCase {
    func testBuildUpdateContainsRequiredFields() {
        let config = SessionConfig.buildUpdate(instructions: "Test instructions")
        XCTAssertEqual(config["type"] as? String, "session.update")

        guard let session = config["session"] as? [String: Any] else {
            XCTFail("Missing session dict")
            return
        }

        XCTAssertEqual(session["input_audio_format"] as? String, "pcm")
        XCTAssertEqual(session["instructions"] as? String, "Test instructions")
        XCTAssertNotNil(session["turn_detection"] as? NSNull)

        guard let modalities = session["modalities"] as? [String] else {
            XCTFail("Missing modalities")
            return
        }
        XCTAssertEqual(modalities, ["text"])
    }

    func testBuildAudioAppend() {
        let config = SessionConfig.buildAudioAppend(base64PCM: "dGVzdA==")
        XCTAssertEqual(config["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(config["audio"] as? String, "dGVzdA==")
    }

    func testBuildCommit() {
        let config = SessionConfig.buildCommit()
        XCTAssertEqual(config["type"] as? String, "input_audio_buffer.commit")
    }

    func testBuildCreateResponse() {
        let config = SessionConfig.buildCreateResponse()
        XCTAssertEqual(config["type"] as? String, "response.create")
    }

    func testBuildCancelResponse() {
        let config = SessionConfig.buildCancelResponse()
        XCTAssertEqual(config["type"] as? String, "response.cancel")
    }
}
