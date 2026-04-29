import XCTest
@testable import VoiceInput

final class AudioRestartPolicyTests: XCTestCase {
    func testConfigurationChangeDoesNotRequireRestartWhenChunksContinue() {
        let policy = AudioRestartPolicy(maxRestartAttempts: 3)
        let checkpoint = policy.configurationChanged(currentChunkCount: 10)

        XCTAssertFalse(policy.shouldRestart(from: checkpoint, currentChunkCount: 11))
    }

    func testConfigurationChangeRequiresRestartWhenChunksStop() {
        let policy = AudioRestartPolicy(maxRestartAttempts: 3)
        let checkpoint = policy.configurationChanged(currentChunkCount: 10)

        XCTAssertTrue(policy.shouldRestart(from: checkpoint, currentChunkCount: 10))
    }

    func testRestartAttemptsAreLimited() {
        let policy = AudioRestartPolicy(maxRestartAttempts: 1)
        let checkpoint = policy.configurationChanged(currentChunkCount: 0)

        XCTAssertTrue(policy.shouldRestart(from: checkpoint, currentChunkCount: 0))
        policy.recordRestartAttempt()
        XCTAssertFalse(policy.shouldRestart(from: checkpoint, currentChunkCount: 0))
    }

    func testSuccessfulChunkResetsRestartAttempts() {
        let policy = AudioRestartPolicy(maxRestartAttempts: 1)
        policy.recordRestartAttempt()
        policy.recordChunk()
        let checkpoint = policy.configurationChanged(currentChunkCount: 1)

        XCTAssertTrue(policy.shouldRestart(from: checkpoint, currentChunkCount: 1))
    }
}
