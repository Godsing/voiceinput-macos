import XCTest
@testable import VoiceInput

final class RecordingLifecycleTests: XCTestCase {
    func testStopWhilePreparingDefersAndAbortsWhenReady() {
        let lifecycle = RecordingLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginPreparing)
        XCTAssertEqual(lifecycle.phase, .preparing)
        XCTAssertEqual(lifecycle.requestStop(), .deferUntilReady)

        XCTAssertEqual(lifecycle.markReady(), .abort)
        XCTAssertEqual(lifecycle.phase, .idle)
    }

    func testStopWhileRecordingCommitsOnce() {
        let lifecycle = RecordingLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginPreparing)
        XCTAssertEqual(lifecycle.markReady(), .startRecording)
        XCTAssertEqual(lifecycle.phase, .recording)

        XCTAssertEqual(lifecycle.requestStop(), .commitRecording)
        XCTAssertEqual(lifecycle.phase, .finishing)
        XCTAssertEqual(lifecycle.requestStop(), .ignore)
    }
}
