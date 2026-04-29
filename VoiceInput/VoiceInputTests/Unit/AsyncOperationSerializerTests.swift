import XCTest
@testable import VoiceInput

final class AsyncOperationSerializerTests: XCTestCase {
    func testOperationsRunSeriallyInSubmissionOrder() async throws {
        let serializer = AsyncOperationSerializer()
        let recorder = OperationRecorder()

        let first = Task {
            try await serializer.run {
                await recorder.append("first-start")
                try await Task.sleep(nanoseconds: 30_000_000)
                await recorder.append("first-end")
            }
        }

        try await Task.sleep(nanoseconds: 1_000_000)

        let second = Task {
            try await serializer.run {
                await recorder.append("second")
            }
        }

        try await first.value
        try await second.value

        let events = await recorder.events
        XCTAssertEqual(events, ["first-start", "first-end", "second"])
    }
}

private actor OperationRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
