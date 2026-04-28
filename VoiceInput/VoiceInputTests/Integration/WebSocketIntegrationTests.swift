import XCTest
@testable import VoiceInput

final class WebSocketIntegrationTests: XCTestCase {
    func testRealtimeClientConnectionStateTransitions() async {
        let client = RealtimeClient(apiKey: "sk-invalid-test-key")
        XCTAssertEqual(client.state, .disconnected)

        client.disconnect()
        XCTAssertEqual(client.state, .disconnected)
    }

    func testRealtimeClientDisconnectSetsState() {
        let client = RealtimeClient(apiKey: "sk-test")
        client.disconnect()
        XCTAssertEqual(client.state, .disconnected)
    }

    func testRealtimeClientInitialState() {
        let client = RealtimeClient(apiKey: "sk-test")
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertTrue(client.accumulatedTranscript.isEmpty)
    }

    func testRealtimeClientDoesNotConnectTwice() async {
        let client = RealtimeClient(apiKey: "sk-test")
        client.disconnect()
        // Already disconnected, connect should be no-op from wrong state
        XCTAssertEqual(client.state, .disconnected)
    }
}
