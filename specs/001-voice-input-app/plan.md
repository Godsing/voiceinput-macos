# Implementation Plan: macOS Menu Bar Voice Input App

**Branch**: `001-voice-input-app` | **Date**: 2026-04-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-voice-input-app/spec.md`

## Summary

Build a macOS 14+ menu-bar-only voice input app that uses the Fn key as a hold-to-record trigger, streams audio to Alibaba Cloud DashScope Qwen-Omni-Realtime API via WebSocket for real-time transcription, displays results in a sleek capsule overlay with live waveform animation, and injects the final text at the cursor position while preserving the original clipboard content.

## Technical Context

**Language/Version**: Swift 5.9+ (macOS 14+ SDK)
**Primary Dependencies**: AVFoundation (audio capture), Network.framework / URLSessionWebSocketTask (WebSocket), SwiftUI (settings panel), AppKit (NSPanel, NSStatusBar, NSVisualEffectView)
**Storage**: UserDefaults (language selection, API key, model name); Keychain (API key storage — security best practice per constitution)
**Testing**: XCTest (unit + integration tests)
**Target Platform**: macOS 14 (Sonoma) and later
**Project Type**: Desktop app (menu bar agent / LSUIElement)
**Performance Goals**: Overlay appear <200ms, first transcription token <1s, text injection <500ms post-release
**Constraints**: <50MB memory idle, <1% CPU idle, no Dock icon, real-time audio pipeline with zero buffer underruns
**Scale/Scope**: Single-user desktop app, 1 concurrent WebSocket session, ~5 UI surfaces (menu, overlay, settings, waveform, language picker)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Modules self-contained, functions <40 lines, zero linter warnings | PASS — Swift SPM modular structure planned |
| II. Test-First (NON-NEGOTIABLE) | TDD mandatory, Red-Green-Refactor, 80% coverage floor | PASS — XCTest framework selected; tests written before impl |
| III. UX Consistency | Unified design system, actionable errors, WCAG 2.1 AA, first-class loading/empty/failure states | PASS — Capsule overlay has defined states (idle/recording/transcribing/error); menu bar UI follows HIG |
| IV. Performance | <200ms overlay appear, <1s first token, <500ms injection, <50MB idle, real-time audio pipeline | PASS — Budgets defined in spec; audio pipeline uses AVAudioEngine tap for zero-copy PCM |
| V. Simplicity | YAGNI, no premature abstractions, composition over inheritance | PASS — No over-engineering; single SPM package, flat module structure |
| Security & Reliability | Input validation at boundaries, secrets never committed/logged, API calls have timeouts/retries/circuit breakers, graceful degradation | PASS — API key in Keychain, WebSocket with timeout/reconnect, error overlay for network failures |

**Pre-Phase 0 Result**: ALL GATES PASS. Proceed to research.

**Post-Phase 1 Re-evaluation**: ALL GATES PASS. Design artifacts confirm:
- Code Quality: Modules map to single responsibilities (AudioCapture, RealtimeClient, TextInjector, etc.)
- Test-First: XCTest targets defined; test structure mirrors source modules
- UX Consistency: OverlayState enum defines all visual states; error overlay for network failures; actionable permission prompts
- Performance: AVAudioEngine tap provides zero-copy PCM; WebSocket reconnect with backoff; clipboard save/restore within 500ms budget
- Simplicity: No premature abstractions; flat module structure; single SPM package
- Security: API key in Keychain; WebSocket auth via Bearer token; no secrets logged

## Project Structure

### Documentation (this feature)

```text
specs/001-voice-input-app/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
VoiceInput/
├── Package.swift
├── Makefile
├── Sources/
│   └── VoiceInput/
│       ├── App/
│       │   ├── AppDelegate.swift          # NSApplication delegate, LSUIElement setup
│       │   └── MenuBarController.swift    # NSStatusBar menu construction
│       ├── Audio/
│       │   ├── AudioCaptureEngine.swift   # AVAudioEngine tap, PCM extraction, RMS calc
│       │   └── AudioBuffer.swift          # Thread-safe circular buffer for PCM chunks
│       ├── Input/
│       │   ├── GlobalKeyMonitor.swift     # CGEvent tap for Fn key, event suppression
│       │   ├── TextInjector.swift         # Clipboard save/restore, Cmd+V simulation
│       │   └── InputMethodManager.swift   # CJK→ASCII switch + restore
│       ├── Overlay/
│       │   ├── CapsuleOverlayPanel.swift  # NSPanel (.nonactivatingPanel), positioning
│       │   ├── WaveformView.swift         # NSView with 5-bar RMS-driven animation
│       │   └── TranscriptLabel.swift      # Streaming text label, auto-resize
│       ├── Settings/
│       │   ├── SettingsWindow.swift       # SwiftUI settings with API key, model fields
│       │   └── ConfigurationStore.swift   # UserDefaults + Keychain persistence
│       └── WebSocket/
│           ├── RealtimeClient.swift       # URLSessionWebSocketTask, Manual mode protocol
│           └── SessionConfig.swift        # session.update message builder
VoiceInputTests/
├── Unit/
│   ├── AudioBufferTests.swift
│   ├── TextInjectorTests.swift
│   ├── ConfigurationStoreTests.swift
│   └── SessionConfigTests.swift
└── Integration/
    ├── AudioCaptureIntegrationTests.swift
    └── WebSocketIntegrationTests.swift
```

**Structure Decision**: Single SPM package with logical module groupings under `Sources/VoiceInput/`. Tests mirror source structure. Flat hierarchy — no nested packages or targets beyond the main executable and test target.

## Complexity Tracking

> No constitution violations to justify.
