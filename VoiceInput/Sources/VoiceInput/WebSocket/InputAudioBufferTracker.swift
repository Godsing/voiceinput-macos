import Foundation

struct InputAudioBufferTracker {
    static let defaultMinimumCommitBytes = 3_200

    let minimumCommitBytes: Int
    private(set) var pendingBytes = 0
    private(set) var pendingChunks = 0

    var canCommit: Bool {
        pendingBytes >= minimumCommitBytes
    }

    init(minimumCommitBytes: Int = Self.defaultMinimumCommitBytes) {
        self.minimumCommitBytes = minimumCommitBytes
    }

    mutating func recordAppend(base64PCM: String) {
        pendingChunks += 1
        pendingBytes += Data(base64Encoded: base64PCM)?.count ?? 0
    }

    mutating func reset() {
        pendingBytes = 0
        pendingChunks = 0
    }
}
