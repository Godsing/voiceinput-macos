import Foundation

actor AsyncOperationSerializer {
    private var previousOperation: Task<Void, Error> = Task {}

    func run(_ operation: @escaping () async throws -> Void) async throws {
        let dependency = previousOperation
        let current = Task {
            _ = try? await dependency.value
            try await operation()
        }
        previousOperation = current
        try await current.value
    }

    func reset() {
        previousOperation = Task {}
    }
}
