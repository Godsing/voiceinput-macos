# Tasks: macOS Menu Bar Voice Input App

**Input**: Design documents from `/specs/001-voice-input-app/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Single SPM project: `Sources/VoiceInput/` at repository root
- Tests: `VoiceInputTests/`
- Paths assume repository root as working directory

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create SPM project structure with Package.swift (executable target VoiceInput, test target VoiceInputTests, macOS 14+ platform, no external dependencies)
- [x] T002 Create Makefile with build/run/install/clean/test targets in repository root
- [x] T003 [P] Create Info.plist with LSUIElement=true, NSMicrophoneUsageDescription, NSAccessibilityUsageDescription keys
- [x] T004 [P] Create app entry point in Sources/VoiceInput/App/AppDelegate.swift (NSApplication delegate, activate LSUIElement policy, set up MenuBarController)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Implement ConfigurationStore in Sources/VoiceInput/Settings/ConfigurationStore.swift (UserDefaults for model/language/endpoint, Keychain for API key, save/load/validate methods)
- [x] T006 [P] Implement GlobalKeyMonitor in Sources/VoiceInput/Input/GlobalKeyMonitor.swift (CGEventTapCreate at kCGHIDEventTap, Fn key code 63, keyDown/keyUp/flagsChanged handling, event suppression via nil return, permission check via AXIsProcessTrusted)
- [x] T007 [P] Implement AudioCaptureEngine in Sources/VoiceInput/Audio/AudioCaptureEngine.swift (AVAudioEngine inputNode tap, AVAudioConverter to 16kHz/16-bit/mono, RMS computation, PCM→Base64 encoding, dispatch callbacks off real-time thread)
- [x] T008 [P] Implement RealtimeClient in Sources/VoiceInput/WebSocket/RealtimeClient.swift (URLSessionWebSocketTask with Bearer auth, actor-based, recursive receive loop, connection state machine, exponential backoff reconnect 1s–30s max 5 attempts)
- [x] T009 [P] Implement SessionConfig in Sources/VoiceInput/WebSocket/SessionConfig.swift (build session.update message with modalities=["text"], turn_detection=null, instructions with language suffix, input_audio_format="pcm")
- [x] T010 [P] Implement MenuBarController in Sources/VoiceInput/App/MenuBarController.swift (NSStatusBar button, menu with language submenu, Settings entry, Quit entry)

**Checkpoint**: Foundation ready — user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Hold-to-Record Voice Input (Priority: P1) 🎯 MVP

**Goal**: User holds Fn to record, sees capsule overlay with waveform and streaming text, releases Fn, text is inserted at cursor

**Independent Test**: Hold Fn in any text field, speak, release, verify transcribed text appears at cursor position

### Implementation for User Story 1

- [ ] T011 [US1] Implement CapsuleOverlayPanel in Sources/VoiceInput/Overlay/CapsuleOverlayPanel.swift (NSPanel with [.borderless, .nonactivatingPanel], .floating level, canBecomeKey=false, canBecomeMain=false, ignoresMouseEvents=true, positionAtBottomCenter method)
- [ ] T012 [P] [US1] Implement WaveformView in Sources/VoiceInput/Overlay/WaveformView.swift (NSView subclass, CADisplayLink animation, 5 bars with weights [0.5,0.8,1.0,0.75,0.55], attack 40%/release 15% envelope, ±4% jitter, min 4px bar height, updateRMS thread-safe setter dispatching to main)
- [ ] T013 [P] [US1] Implement TranscriptLabel in Sources/VoiceInput/Overlay/TranscriptLabel.swift (AutoSizing NSTextField, isEditable=false, white text on clear background, intrinsicContentSize override clamped 160–500px width, invalidateIntrinsicContentSize on text update)
- [ ] T014 [US1] Implement CapsuleContentView in Sources/VoiceInput/Overlay/CapsuleOverlayPanel.swift (NSVisualEffectView with .hudWindow material, .behindWindow blending, cornerRadius=28 on layer, Auto Layout: waveform left + transcript right, padding 16/10/16)
- [ ] T015 [US1] Add overlay animation methods to CapsuleOverlayPanel (show: spring 0.35s scale+fade in, hide: ease-in 0.22s scale+fade out with completion handler, animateWidthChange: ease-out 0.25s with bottom-center re-anchoring)
- [ ] T016 [US1] Implement TextInjector in Sources/VoiceInput/Input/TextInjector.swift (save clipboard via ClipboardSnapshot, detect CJK via TIS API, switch to ABC via TISSelectInputSource, write text to NSPasteboard, simulate Cmd+V via CGEvent, wait for paste completion via changeCount+timeout, restore input source, restore clipboard)
- [ ] T017 [US1] Implement InputMethodManager in Sources/VoiceInput/Input/InputMethodManager.swift (currentInputSource detection, CJK source ID matching, findASCIIInputSource preferring com.apple.keylayout.ABC, selectInputSource wrapper)
- [ ] T018 [US1] Implement recording session coordinator in Sources/VoiceInput/App/AppDelegate.swift (wire GlobalKeyMonitor.onHoldStart → start AudioCaptureEngine + show overlay + start WebSocket audio streaming; onHoldEnd → stop audio + commit + createResponse → wait for response.done → injectText → hide overlay)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently — hold Fn, speak, release, text appears at cursor

---

## Phase 4: User Story 2 - Multi-Language Recognition (Priority: P2)

**Goal**: User can select recognition language from menu bar, selection persists across restarts

**Independent Test**: Switch language in menu bar, record speech in that language, verify accurate transcription

### Implementation for User Story 2

- [ ] T019 [US2] Add Language enum to Sources/VoiceInput/Settings/ConfigurationStore.swift (cases: simplifiedChinese, traditionalChinese, english, japanese, korean; display names; codes zh-CN/zh-TW/en/ja/ko; instructions suffix mapping)
- [ ] T020 [US2] Add language submenu to MenuBarController in Sources/VoiceInput/App/MenuBarController.swift (5 language options with checkmark on selected, on selection save to ConfigurationStore and update active session instructions if connected)
- [ ] T021 [US2] Update SessionConfig in Sources/VoiceInput/WebSocket/SessionConfig.swift to include language-specific instructions suffix in session.update message based on selected Language enum

**Checkpoint**: Language switching works — select language, record, transcription uses correct language, persists across restarts

---

## Phase 5: User Story 3 - Clipboard-Preserving Text Injection (Priority: P2)

**Goal**: Original clipboard content is preserved after voice input text injection

**Independent Test**: Copy text to clipboard, perform voice input, paste to verify original clipboard content is intact

### Implementation for User Story 3

- [ ] T022 [US3] Implement ClipboardSnapshot in Sources/VoiceInput/Input/TextInjector.swift (static save() iterates NSPasteboard.general.pasteboardItems, saves all types per item as [[NSPasteboard.PasteboardType: Data]]; restore() clears pasteboard and writes back all items via NSPasteboardItem)
- [ ] T023 [US3] Update TextInjector.injectText to use ClipboardSnapshot (save clipboard before injection, restore after paste completion; handle empty clipboard; handle large clipboard content with Data objects in memory)
- [ ] T024 [US3] Add error recovery to TextInjector (if paste simulation fails or clipboard restore fails, attempt restore anyway; log error but do not crash; guard against clipboard content that cannot round-trip through NSPasteboard)

**Checkpoint**: Clipboard preservation works — copy content, voice input, paste original content, it's intact

---

## Phase 6: User Story 4 - Custom Cloud Service Configuration (Priority: P3)

**Goal**: User can configure API key and model selection from menu bar settings panel

**Independent Test**: Open settings, enter API key, select model, validate, save, verify transcription uses new config

### Implementation for User Story 4

- [ ] T025 [US4] Implement SettingsWindow in Sources/VoiceInput/Settings/SettingsWindow.swift (SwiftUI window with: API key SecureField, model name TextField defaulting to "qwen3.5-omni-plus-realtime", Test button that opens test WebSocket connection, Save button that persists to ConfigurationStore)
- [ ] T026 [US4] Add API key validation logic to SettingsWindow (on Test: create temporary RealtimeClient with entered key, attempt connect + session.update, show success/failure alert, disconnect test client)
- [ ] T027 [US4] Wire Settings menu item in MenuBarController to open SettingsWindow, load current values from ConfigurationStore on open

**Checkpoint**: Settings panel works — enter key, validate, save, config persists across restarts

---

## Phase 7: User Story 5 - Lightweight Menu Bar-Only Presence (Priority: P3)

**Goal**: App appears only in menu bar, no Dock icon, minimal resource usage when idle

**Independent Test**: Verify no Dock icon, check Activity Monitor for low CPU/memory

### Implementation for User Story 5

- [ ] T028 [US5] Verify LSUIElement=true in Info.plist hides Dock icon (test that app does not appear in Dock at launch)
- [ ] T029 [US5] Implement lazy WebSocket connection in RealtimeClient (connect on first Fn press, not at app launch; disconnect after idle timeout if no recording for 60s)
- [ ] T030 [US5] Add idle resource optimization to AudioCaptureEngine (do not initialize AVAudioEngine until first recording; release engine resources after recording stops; ensure no background timers or threads when idle)
- [ ] T031 [US5] Add app icon asset and menu bar button image in Assets.xcassets (microphone icon, 16x16/32x32 for standard/Retina)

**Checkpoint**: App runs as menu bar agent — no Dock icon, minimal idle resources, lazy connections

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T032 [P] Add error overlay state to CapsuleOverlayPanel (show error message in capsule when network fails or API key is invalid, auto-dismiss after 3s)
- [ ] T033 [P] Add permission check flow at app launch in AppDelegate (check AXIsProcessTrusted and AVAudioApplication.recordPermission; if not granted, show menu bar notification with "Grant Access" action that opens System Settings)
- [ ] T034 [P] Handle rapid Fn re-trigger in recording coordinator (if Fn pressed while previous response pending, send response.cancel before starting new recording; clear accumulated transcript)
- [ ] T035 [P] Add Fn key debounce to GlobalKeyMonitor (150ms hold threshold before starting recording to distinguish accidental tap from intentional hold; 50ms release debounce to filter key bounce)
- [ ] T036 Handle macOS sleep/wake in RealtimeClient (on wake, check connection state and reconnect if needed; discard any pending recording session that was interrupted by sleep)
- [ ] T037 [P] Add accessibility support to overlay (ensure VoiceOver can announce overlay state changes; set accessibilityLabel on waveform view and transcript label)
- [ ] T038 Validate .app bundle signing and Makefile install target (codesign the bundle, verify it launches correctly from /Applications)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Stories (Phase 3–7)**: All depend on Foundational phase completion
  - User Story 1 (Phase 3): Can start after Foundational — no dependencies on other stories
  - User Story 2 (Phase 4): Can start after Foundational — extends US1's SessionConfig and MenuBarController
  - User Story 3 (Phase 5): Can start after Foundational — extends US1's TextInjector
  - User Story 4 (Phase 6): Can start after Foundational — extends ConfigurationStore and MenuBarController
  - User Story 5 (Phase 7): Can start after Foundational — modifies Info.plist, RealtimeClient, AudioCaptureEngine
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **User Story 2 (P2)**: Extends US1's SessionConfig + MenuBarController — best after US1 is working
- **User Story 3 (P2)**: Extends US1's TextInjector — best after US1 is working
- **User Story 4 (P3)**: Independent of US1 but adds Settings panel — can be done in parallel
- **User Story 5 (P3)**: Cross-cutting optimization — best after core flow (US1) is working

### Within Each User Story

- Models/config before services
- Services before UI
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- T012 (WaveformView) and T013 (TranscriptLabel) can run in parallel
- T019 (Language enum) and T020 (Menu language submenu) can be parallelized
- US3 and US4 can be worked on in parallel by different developers
- All Polish tasks marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch overlay components together:
Task: "Implement WaveformView in Sources/VoiceInput/Overlay/WaveformView.swift"
Task: "Implement TranscriptLabel in Sources/VoiceInput/Overlay/TranscriptLabel.swift"

# Then sequential integration:
Task: "Implement CapsuleContentView (combines waveform + transcript)"
Task: "Add overlay animation methods"
Task: "Implement TextInjector"
Task: "Implement recording session coordinator (wires everything)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready — this is a working voice input app

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Language switching works
4. Add User Story 3 → Test independently → Clipboard preserved
5. Add User Story 4 → Test independently → Custom configuration
6. Add User Story 5 → Test independently → Lightweight presence
7. Polish → Error handling, permissions flow, accessibility

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (core flow — highest priority)
   - Developer B: User Story 4 (settings panel — independent)
3. After US1 complete:
   - Developer A: User Story 2 (language) or User Story 3 (clipboard)
   - Developer B: User Story 5 (optimization)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
