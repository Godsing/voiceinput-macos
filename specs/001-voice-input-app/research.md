# Research: macOS Menu Bar Voice Input App

**Feature**: 001-voice-input-app | **Date**: 2026-04-23

## 1. CGEvent Tap for Fn Key Global Interception

**Decision**: Use `CGEventTapCreate` with `kCGEventTapOptionDefault` at `kCGHIDEventTap` to intercept Fn key (key code 63) globally. Return `nil` from the callback to suppress the event and prevent the emoji picker.

**Rationale**: CGEvent tap is the only API that allows global keyboard event interception and suppression on macOS. The `kCGEventTapOptionDefault` option (vs `kCGEventTapOptionListenOnly`) enables event modification/suppression. Placing the tap at `kCGHIDEventTap` catches events before they reach any application.

**Key implementation details**:
- Fn key code: `0x3F` (63)
- Detect key-down vs key-up: `CGEventType.keyDown` vs `CGEventType.keyUp`
- Suppress event: return `nil` from the callback
- Permissions required: Accessibility (System Settings > Privacy & Security > Accessibility)
- Permission check: `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions`
- Handle tap disabled by timeout: listen for `kCGEventTapDisabledByTimeout` and re-enable

**Gotchas**:
- Accessibility permission is REQUIRED — the app cannot intercept Fn without it
- macOS 14+ tightened TCC; must provide `NSAccessibilityUsageDescription` in Info.plist
- The Fn key event may fire twice (key-down for hold, key-up for release) — debounce accordingly
- If Accessibility is revoked while tap is active, receive `tapDisabledByTimeout` — re-register a test tap to check permission

**Alternatives considered**: IOKit HID (too low-level, requires kernel extension), NSEvent.addGlobalMonitorForEvents (listen-only, cannot suppress), Karabiner-Elements virtual device (requires third-party driver).

## 2. WebSocket Client for DashScope Qwen-Omni-Realtime API

**Decision**: Use `URLSessionWebSocketTask` with a `URLRequest` carrying the `Authorization: Bearer {key}` header. Implement as a Swift actor for thread-safe state management. Use recursive `receive()` callback loop for message consumption.

**Rationale**: URLSessionWebSocketTask is Apple's first-party WebSocket client in Foundation — no dependencies, handles TLS automatically, integrates with URLSession's delegate system. The actor pattern provides serial isolation for mutable state without manual locks.

**Protocol (Manual Mode)**:
- Connect: `wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model={model}`
- Auth: `Authorization: Bearer {api_key}`
- Session config: `session.update` with `modalities: ["text"]`, `turn_detection: null`
- Audio streaming: `input_audio_buffer.append` with Base64 PCM (16kHz/16-bit/mono, 3200-byte chunks = 100ms)
- End recording: `input_audio_buffer.commit` then `response.create`
- Listen for: `response.text.delta` (primary for text-only), `response.audio_transcript.delta`, `response.audio_transcript.done`, `response.done`
- Text injection gate: wait for `response.done` before injecting text

**Reconnection strategy**: Exponential backoff with jitter (1s–30s, max 5 attempts). Lazy reconnection on next Fn press rather than eager keepalive.

**Timeouts**: URLSession 30s request / 300s resource; application-level 10s connect timeout; 30s response timeout.

**Gotchas**:
- Delegate methods are `nonisolated` — must dispatch to actor with `Task { await ... }`
- `receive()` delivers ONE message — must call `receive()` again in the completion handler
- No built-in ping/pong — DashScope may close idle connections; handle via reconnection
- Always use `cancel(with: .normalClosure, reason: nil)` for clean WebSocket close
- With `modalities: ["text"]`, expect `response.text.delta` not `response.audio_transcript.delta`
- Session max duration: 120 minutes, max 100 audio rounds for qwen3.5-omni-plus-realtime

**Alternatives considered**: Starscream (adds dependency), Network.framework NWConnection (lower-level, manual TLS), swift-nio (overkill for single-connection desktop app).

## 3. NSPanel Capsule Overlay with Waveform Animation

**Decision**: Use `NSPanel` with `[.borderless, .nonactivatingPanel]` style, `.floating` level, `NSVisualEffectView` with `.hudWindow` material for the frosted-glass capsule. Custom `NSView` subclass with `CADisplayLink` for the 5-bar RMS-driven waveform.

**Rationale**: NSPanel's `.nonactivatingPanel` prevents focus stealing. `.hudWindow` material provides the dark semi-translucent HUD look. `CADisplayLink` synchronizes animation to display refresh for smooth 60fps+ rendering.

**Capsule dimensions**: 56px height, 28px corner radius. Waveform: 44x32px area (5 bars with weights [0.5, 0.8, 1.0, 0.75, 0.55]). Transcript: 160–500px elastic width. Padding: 16px left/right, 10px gap.

**Waveform animation**:
- Attack: 40% (rise quickly on speech), Release: 15% (slow decay)
- ±4% random jitter per bar for organic feel
- Minimum 4px bar height so bars are always visible
- RMS gain multiplier ~3.0 to make speech levels visually responsive

**Animations**: Entry spring 0.35s, width transition ease-out 0.25s, exit scale-down ease-in 0.22s.

**Gotchas**:
- Must override `canBecomeKey` returning `false` explicitly
- Use `orderFrontRegardless()` not `makeKeyAndOrderFront`
- `backgroundColor = .clear` + `isOpaque = false` required for frosted glass
- Corner radius on `layer` not the view; `wantsLayer = true` first
- "Reduce transparency" accessibility setting disables the frosted glass effect
- NSTextField label needs `invalidateIntrinsicContentSize()` on text change for Auto Layout
- Panel width changes must re-anchor to bottom-center (recalculate origin X)
- After `hide()`, reset layer transform and opacity for next `show()`

**Alternatives considered**: NSPopover (can't control shape/level), SwiftUI Window (macOS 15+ only), Timer-based animation (not display-synced), CAShapeLayer per bar (more overhead).

## 4. CJK Input Method Switching + Clipboard Save/Restore

**Decision**: Use Carbon TIS API (`TISCopyCurrentKeyboardInputSource`, `TISSelectInputSource`) for input source detection and switching. Use `NSPasteboard` for clipboard save/restore of all data types. Use `CGEvent` to simulate Cmd+V.

**Rationale**: Carbon TIS is the only global API for input source management — `NSTextInputContext` is tied to the responder chain and unsuitable for a menu-bar agent. `NSPasteboard` supports saving all data types (text, images, file references). CGEvent Cmd+V is universally understood across all apps.

**Text injection flow**:
1. Save clipboard via `ClipboardSnapshot.save()` (iterates `pasteboardItems`, saves all types per item)
2. Detect CJK input source via `TISInputSource` ID prefixes (com.apple.inputmethod.SCIM/TCIM/Japanese/Korean + third-party)
3. Switch to ASCII input source (prefer com.apple.keylayout.ABC) via `TISSelectInputSource`
4. Write transcribed text to clipboard
5. Simulate Cmd+V via `CGEvent(keyboardEventSource:virtualKey:9,keyDown:true)` with `.maskCommand`
6. Wait for paste completion (check `changeCount` + timeout)
7. Restore input source
8. Restore clipboard

**Gotchas**:
- `TISSelectInputSource` requires Accessibility permission (same as CGEvent tap)
- No ASCII source available: proceed with current source, Cmd+V may still work if composing buffer is empty
- Input source switch is async — 50ms delay required after `TISSelectInputSource`
- 20ms delay between clipboard write and Cmd+V to ensure propagation
- `changeCount` is not reliable for paste-completion detection — use timeout fallback (100–500ms)
- NSPasteboard must be accessed on the main thread
- Large clipboard content (10+ MB images) adds latency to save/restore cycle

**Alternatives considered**: Accessibility API AXTextInsertion (many apps don't support, replaces all text), AppleScript keystroke (too slow, can't type CJK), NSTextInputContext (tied to responder chain).

## 5. AVAudioEngine PCM Capture + RMS Computation

**Decision**: Use `AVAudioEngine` with `installTap(onBus:0)` on `inputNode`. Single tap serves dual purpose: compute RMS for waveform AND extract PCM for Base64 WebSocket encoding. Format conversion via `AVAudioConverter` from hardware format (typically 48kHz float) to 16kHz/16-bit/mono.

**Rationale**: Only one tap per bus is allowed, so a single tap must handle both RMS and PCM extraction. The tap callback runs on a real-time audio thread — dispatch all heavy work off-thread via a serial `DispatchQueue`.

**Buffer size**: 1600 frames at 16kHz = 100ms = 3200 bytes PCM. This matches the DashScope SDK's chunk size.

**RMS computation**: Sum squares of float samples, divide by frame count, take sqrt. Apply gain multiplier of ~3.0 for visual responsiveness (speech RMS is typically 0.01–0.3).

**PCM to Base64**: For interleaved Int16 format, `int16ChannelData[0]` is contiguous — extract directly as `Data(bytes:count:)` and call `.base64EncodedString()`.

**Gotchas**:
- Tap callback runs on REAL-TIME audio thread — NO allocations, locks, blocking, or Obj-C runtime calls
- Only one tap per bus — calling `installTap` twice crashes with `NSInvalidArgumentException`
- `bufferSize` is a hint, not guaranteed — always use `buffer.frameLength` at runtime
- `int16ChannelData` is nil for float-format buffers and vice versa — ensure format matches
- Always `removeTap(onBus:)` BEFORE `engine.stop()` to avoid inconsistent state
- macOS is little-endian — Int16 PCM is compatible with DashScope's expected format
- Microphone permission requires `NSMicrophoneUsageDescription` in Info.plist
- Hardware sample rate change (audio device switch) invalidates the tap — re-initialize

**Alternatives considered**: AudioUnit directly (more boilerplate, no benefit), AudioQueue (deprecated), AVCaptureSession (higher latency, designed for recording-to-file).

## 6. System Prompt for Transcription

**Decision**: Use a conservative system prompt that instructs the model to perform literal transcription with only obvious error correction.

**Prompt** (Chinese, matching the PRD):
```
准确将用户的语音转写为文字，只修复明显的语音识别错误（如中文谐音错误、英文技术术语被错误转为中文如「配森」→「python」、「杰森」→「JSON」），绝对不要改写、润色或删除任何看起来正确的内容，绝对不要包含任何对话或解释。
```

This goes in the `instructions` field of `session.update`.

## 7. App Distribution and Build

**Decision**: Use Swift Package Manager with a Makefile for build/run/install/clean. Output is a signed `.app` bundle. Run as `LSUIElement` (menu bar only, no Dock icon).

**Info.plist keys**:
- `LSUIElement = true` — hides Dock icon
- `NSMicrophoneUsageDescription` — required for microphone access
- `NSAccessibilityUsageDescription` — required for CGEvent tap and TIS input source switching

**SPM structure**: Single executable target `VoiceInput` + test target `VoiceInputTests`. All source under `Sources/VoiceInput/` with logical subdirectories.

## 8. Configuration Storage

**Decision**: Store API key in Keychain (security best practice per constitution), model name and language preference in UserDefaults. Settings panel validates API key by opening a test WebSocket connection before saving.

**Rationale**: API keys are secrets and must never be stored in UserDefaults (which is a plist file readable by any process with disk access). Keychain provides encrypted, access-controlled storage.

## 9. Language Support Mapping

| Language | Code | Instructions Suffix |
|----------|------|---------------------|
| Simplified Chinese (default) | zh-CN | (default, no suffix needed) |
| Traditional Chinese | zh-TW | 请使用繁体中文转写 |
| English | en | Transcribe in English |
| Japanese | ja | 日本語で転写してください |
| Korean | ko | 한국어로 전사해 주세요 |

Language preference is stored in `UserDefaults` and included in the `session.update` instructions when establishing a new WebSocket connection.
