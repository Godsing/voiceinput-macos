final class RecordingLifecycle {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case finishing
    }

    enum StartDecision: Equatable {
        case beginPreparing
        case ignore
    }

    enum ReadyDecision: Equatable {
        case startRecording
        case abort
    }

    enum StopDecision: Equatable {
        case commitRecording
        case deferUntilReady
        case ignore
    }

    private(set) var phase: Phase = .idle
    private var stopRequestedWhilePreparing = false

    func requestStart() -> StartDecision {
        guard phase == .idle else { return .ignore }
        phase = .preparing
        stopRequestedWhilePreparing = false
        return .beginPreparing
    }

    func markReady() -> ReadyDecision {
        guard phase == .preparing else { return .abort }
        if stopRequestedWhilePreparing {
            phase = .idle
            stopRequestedWhilePreparing = false
            return .abort
        }
        phase = .recording
        return .startRecording
    }

    func requestStop() -> StopDecision {
        switch phase {
        case .preparing:
            stopRequestedWhilePreparing = true
            return .deferUntilReady
        case .recording:
            phase = .finishing
            return .commitRecording
        case .idle, .finishing:
            return .ignore
        }
    }

    func finish() {
        phase = .idle
        stopRequestedWhilePreparing = false
    }
}
