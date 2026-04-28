import XCTest
@testable import VoiceInput

final class TextInjectorTests: XCTestCase {
    func testInjectEmptyTextDoesNothing() {
        let injector = TextInjector()
        injector.injectText("")
    }

    func testInjectTextCalledOffMainThreadRunsInjectionOnMainThread() {
        let injectionCompleted = expectation(description: "injection completed")
        let injector = TextInjector(injectionHandler: { text in
            XCTAssertEqual(text, "hello")
            XCTAssertTrue(Thread.isMainThread)
            injectionCompleted.fulfill()
        })

        DispatchQueue.global(qos: .userInitiated).async {
            injector.injectText("hello")
        }

        wait(for: [injectionCompleted], timeout: 1.0)
    }

    func testClipboardSnapshotSaveAndRestoreEmptyPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()

        let snapshot = ClipboardSnapshot.save()
        XCTAssertTrue(snapshot.items.isEmpty)

        snapshot.restore()
    }

    func testClipboardSnapshotPreservesStringContent() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let original = "test-clipboard-content-\(UUID().uuidString)"
        pb.setString(original, forType: .string)

        let snapshot = ClipboardSnapshot.save()
        XCTAssertFalse(snapshot.items.isEmpty)

        pb.clearContents()
        pb.setString("overwritten", forType: .string)

        snapshot.restore()

        let restored = pb.string(forType: .string)
        XCTAssertEqual(restored, original)
    }
}
