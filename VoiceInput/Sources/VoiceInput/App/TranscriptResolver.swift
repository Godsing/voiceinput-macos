import Foundation

enum TranscriptResolver {
    static func finalTranscript(inputTranscript: String, responseTranscript: String) -> String {
        if !responseTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return responseTranscript
        }
        return inputTranscript
    }
}
