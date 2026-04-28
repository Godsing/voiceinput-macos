import Foundation

struct SessionConfig {
    static func buildUpdate(instructions: String) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "instructions": instructions,
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "turn_detection": NSNull()
            ]
        ]
    }

    static func buildAudioAppend(base64PCM: String) -> [String: Any] {
        ["type": "input_audio_buffer.append", "audio": base64PCM]
    }

    static func buildCommit() -> [String: Any] {
        ["type": "input_audio_buffer.commit"]
    }

    static func buildCreateResponse() -> [String: Any] {
        ["type": "response.create"]
    }

    static func buildCancelResponse() -> [String: Any] {
        ["type": "response.cancel"]
    }
}
