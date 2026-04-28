import XCTest
@testable import VoiceInput

final class TranscriptResolverTests: XCTestCase {
    func testFinalTranscriptPrefersResponseTranscript() {
        let transcript = TranscriptResolver.finalTranscript(
            inputTranscript: "21",
            responseTranscript: "是的，这是一个测试。"
        )

        XCTAssertEqual(transcript, "是的，这是一个测试。")
    }

    func testFinalTranscriptFallsBackToInputTranscriptWhenResponseIsEmpty() {
        let transcript = TranscriptResolver.finalTranscript(
            inputTranscript: "fallback",
            responseTranscript: ""
        )

        XCTAssertEqual(transcript, "fallback")
    }
}
