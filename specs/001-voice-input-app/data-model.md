# Data Model: macOS Menu Bar Voice Input App

**Feature**: 001-voice-input-app | **Date**: 2026-04-23

## Entities

### Configuration

Stores user preferences and credentials. Persisted to UserDefaults + Keychain.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| apiKey | String | "" | Stored in Keychain, not UserDefaults |
| modelName | String | "qwen3.5-omni-plus-realtime" | Model identifier for WebSocket URL |
| language | Language | .simplifiedChinese | Current recognition language |
| apiEndpoint | String | "wss://dashscope.aliyuncs.com/api-ws/v1/realtime" | WebSocket base URL |

**State transitions**: Unconfigured (no API key) → Configured (API key validated) → Ready

### Language (Enum)

| Case | Code | Display Name |
|------|------|-------------|
| simplifiedChinese | zh-CN | 简体中文 |
| traditionalChinese | zh-TW | 繁体中文 |
| english | en | English |
| japanese | ja | 日本語 |
| korean | ko | 한국어 |

### RecordingSession

Represents a single hold-to-record interaction. Ephemeral — not persisted.

| Field | Type | Notes |
|-------|------|-------|
| state | RecordingState | Current session lifecycle state |
| startTime | Date | When Fn key was pressed |
| endTime | Date? | When Fn key was released |
| selectedLanguage | Language | Language used for this session |
| accumulatedTranscript | String | Streaming transcript text |
| finalTranscript | String? | Complete transcript from response.done |

**State transitions**:

```
idle → recording (Fn key down)
recording → transcribing (Fn key up, commit sent)
transcribing → injecting (response.done received)
injecting → idle (text injected, clipboard restored)
recording → idle (Fn released too quickly, <1s, no speech detected)
any → idle (error: network failure, permission revoked, etc.)
```

### RecordingState (Enum)

| Case | Description |
|------|-------------|
| idle | No recording in progress |
| recording | Fn key held, audio streaming, overlay visible |
| transcribing | Fn released, awaiting response.done from server |
| injecting | Transcription complete, injecting text at cursor |

### OverlayState

Manages the visual state of the capsule overlay. Ephemeral — not persisted.

| Field | Type | Notes |
|-------|------|-------|
| visibility | OverlayVisibility | Current visibility state |
| displayedText | String | Current transcript shown in overlay |
| waveformLevels | [Float] | 5 RMS-smoothed bar levels (0.0–1.0) |
| panelWidth | CGFloat | Current panel width (clamped 246–586px) |

### OverlayVisibility (Enum)

| Case | Description |
|------|-------------|
| hidden | Overlay not visible |
| appearing | Entry spring animation in progress |
| visible | Overlay fully visible, showing waveform + transcript |
| disappearing | Exit scale-down animation in progress |

### ClipboardSnapshot

Temporary storage of clipboard content for save/restore during text injection. Ephemeral — not persisted.

| Field | Type | Notes |
|-------|------|-------|
| items | [[NSPasteboard.PasteboardType: Data]] | All pasteboard items with their type-data mappings |
| savedAt | Date | Timestamp when clipboard was saved |

### ConnectionState (Enum)

WebSocket connection state machine.

| Case | Description |
|------|-------------|
| disconnected | No active connection |
| connecting | TCP/TLS handshake in progress |
| connected | WebSocket open, session.created received |
| reconnecting | Connection lost, retrying with backoff |

## Relationships

```
Configuration 1──1 RecordingSession (language selection feeds into each session)
RecordingSession 1──1 OverlayState (session drives overlay visibility and content)
RecordingSession *──1 ConnectionState (multiple sessions share one connection)
TextInjector uses ClipboardSnapshot (created per injection, discarded after)
```
