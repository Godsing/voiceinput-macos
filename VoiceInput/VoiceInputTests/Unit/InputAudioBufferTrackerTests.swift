import XCTest
@testable import VoiceInput

final class InputAudioBufferTrackerTests: XCTestCase {
    func testEmptyBufferIsNotReadyToCommit() {
        let tracker = InputAudioBufferTracker(minimumCommitBytes: 3_200)

        XCTAssertFalse(tracker.canCommit)
        XCTAssertEqual(tracker.pendingBytes, 0)
        XCTAssertEqual(tracker.pendingChunks, 0)
    }

    func testBufferBecomesReadyAfterEnoughPCMBytesAreRecorded() {
        var tracker = InputAudioBufferTracker(minimumCommitBytes: 3_200)
        let bytes = Data(repeating: 1, count: 3_200).base64EncodedString()

        tracker.recordAppend(base64PCM: bytes)

        XCTAssertTrue(tracker.canCommit)
        XCTAssertEqual(tracker.pendingBytes, 3_200)
        XCTAssertEqual(tracker.pendingChunks, 1)
    }

    func testResetClearsPendingAudio() {
        var tracker = InputAudioBufferTracker(minimumCommitBytes: 1)
        tracker.recordAppend(base64PCM: Data(repeating: 1, count: 4).base64EncodedString())

        tracker.reset()

        XCTAssertFalse(tracker.canCommit)
        XCTAssertEqual(tracker.pendingBytes, 0)
        XCTAssertEqual(tracker.pendingChunks, 0)
    }
}
