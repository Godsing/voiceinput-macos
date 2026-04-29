import Foundation

final class AudioRestartPolicy {
    struct Checkpoint: Equatable {
        let chunkCount: Int
    }

    private let maxRestartAttempts: Int
    private var restartAttempts = 0

    init(maxRestartAttempts: Int) {
        self.maxRestartAttempts = maxRestartAttempts
    }

    func configurationChanged(currentChunkCount: Int) -> Checkpoint {
        Checkpoint(chunkCount: currentChunkCount)
    }

    func shouldRestart(from checkpoint: Checkpoint, currentChunkCount: Int) -> Bool {
        currentChunkCount <= checkpoint.chunkCount && restartAttempts < maxRestartAttempts
    }

    func recordRestartAttempt() {
        restartAttempts += 1
    }

    func recordChunk() {
        restartAttempts = 0
    }
}
