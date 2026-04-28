# WebSocket Protocol Contract: DashScope Qwen-Omni-Realtime API

**Feature**: 001-voice-input-app | **Date**: 2026-04-23

## Connection

- **URL**: `wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model={modelName}`
- **Auth**: `Authorization: Bearer {apiKey}` header
- **Protocol**: WebSocket (RFC 6455)
- **Idle timeout**: Server may close after ~60s inactivity (120s max session)

## Client → Server Events

### session.update

Sent after connection is established. Configures the session for Manual mode, text-only output.

```json
{
  "type": "session.update",
  "session": {
    "modalities": ["text"],
    "instructions": "{system_prompt_with_language}",
    "input_audio_format": "pcm",
    "output_audio_format": "pcm",
    "turn_detection": null
  }
}
```

### input_audio_buffer.append

Sent during recording, ~10 times per second. Each chunk = 100ms of audio.

```json
{
  "type": "input_audio_buffer.append",
  "audio": "{base64_pcm_16kHz_16bit_mono}"
}
```

- PCM: 16-bit signed integer, 16000 Hz sample rate, 1 channel, little-endian
- Chunk size: 3200 bytes PCM → ~4267 chars Base64

### input_audio_buffer.commit

Sent when user releases Fn key. Signals end of audio input.

```json
{
  "type": "input_audio_buffer.commit"
}
```

### response.create

Sent after commit. Requests the model to generate a transcription response.

```json
{
  "type": "response.create"
}
```

### response.cancel

Sent if user presses Fn again while a response is pending.

```json
{
  "type": "response.cancel"
}
```

## Server → Client Events

### session.created

Confirms session establishment.

```json
{
  "type": "session.created",
  "session": { "id": "sess_xxx" }
}
```

### response.text.delta

Streaming transcription text (primary event for text-only modalities).

```json
{
  "type": "response.text.delta",
  "delta": "增量文本"
}
```

### response.audio_transcript.delta

Alternative streaming transcription (when modalities include audio).

```json
{
  "type": "response.audio_transcript.delta",
  "delta": "增量文本"
}
```

### response.audio_transcript.done

Complete transcript of the response. Authoritative final text.

```json
{
  "type": "response.audio_transcript.done",
  "transcript": "完整的转录结果"
}
```

### response.text.done

Text generation complete (no payload).

```json
{
  "type": "response.text.done"
}
```

### response.done

Entire response cycle complete. **Gate signal for text injection.**

```json
{
  "type": "response.done",
  "response": {
    "id": "resp_xxx",
    "usage": { "total_tokens": N, "input_tokens": N, "output_tokens": N }
  }
}
```

### error

```json
{
  "type": "error",
  "error": { "type": "error_type", "code": "error_code", "message": "description" }
}
```

## Session Lifecycle

```
1. Connect WebSocket
2. Receive session.created
3. Send session.update (configure manual mode, text output, language instructions)
4. [User holds Fn] → Start sending input_audio_buffer.append (~10Hz)
5. [User releases Fn] → Send input_audio_buffer.commit
6. Send response.create
7. Receive response.text.delta (streaming) → Update overlay
8. Receive response.audio_transcript.done → Capture final transcript
9. Receive response.done → Inject text at cursor
```
