# Feature Specification: macOS Menu Bar Voice Input App

**Feature Branch**: `001-voice-input-app`
**Created**: 2026-04-23
**Status**: Draft
**Input**: User description: "研发一款macOS 14 及以上专属菜单栏轻量语音输入法应用，基于云端大模型能力，实现全局高效语音转文字输入"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hold-to-Record Voice Input (Priority: P1)

A user is typing in any application (email, chat, document editor). They hold down the Fn key and begin speaking. A sleek capsule overlay appears at the bottom of the screen showing a live audio waveform and streaming transcription text. When they release the Fn key, the final transcribed text is automatically inserted at the current cursor position, as if they had typed it themselves.

**Why this priority**: This is the core value proposition — the entire app exists to deliver this interaction. Without it, nothing else matters.

**Independent Test**: Can be fully tested by holding Fn in any text field, speaking, releasing, and verifying the transcribed text appears at the cursor position.

**Acceptance Scenarios**:

1. **Given** a text input field is focused in any application, **When** the user holds the Fn key and speaks, **Then** a capsule overlay appears with live waveform animation and streaming transcription text
2. **Given** the user is recording via Fn hold, **When** they release the Fn key, **Then** the transcription completes and the full text is inserted at the cursor position
3. **Given** no text field is focused, **When** the user holds Fn and speaks, **Then** the overlay still appears and transcription works, with text available for manual paste
4. **Given** the user holds Fn but speaks very briefly (under 1 second), **When** they release, **Then** the app handles this gracefully without error or empty insertion

---

### User Story 2 - Multi-Language Recognition (Priority: P2)

A user who frequently switches between languages (e.g., Chinese and English) can select their desired recognition language from the menu bar icon. The selected language persists across app restarts. When they hold Fn to record, the transcription uses the selected language model.

**Why this priority**: Multi-language support differentiates this from system-native dictation and is critical for bilingual/multilingual users. It builds directly on P1 but is not required for the core flow.

**Independent Test**: Can be tested by switching language in menu bar, recording speech in that language, and verifying accurate transcription.

**Acceptance Scenarios**:

1. **Given** the app is running, **When** the user clicks the menu bar icon, **Then** a language selection menu appears with options: Simplified Chinese, Traditional Chinese, English, Japanese, Korean
2. **Given** the user selects a language, **When** they next record via Fn hold, **Then** the transcription uses the selected language model
3. **Given** the user selects a language, **When** they quit and restart the app, **Then** the previously selected language is still active
4. **Given** the app is first installed, **When** no language has been selected, **Then** Simplified Chinese is used by default

---

### User Story 3 - Clipboard-Preserving Text Injection (Priority: P2)

A user has important content on their clipboard. They hold Fn to record a voice message, and after transcription, the text is inserted into the active field. Their original clipboard content remains intact — the app silently saves and restores it.

**Why this priority**: Clipboard preservation is essential for a seamless user experience. Without it, the app would destroy clipboard data on every use, which is a significant disruption to daily workflow.

**Independent Test**: Can be tested by copying text to clipboard, performing a voice input, then pasting to verify original clipboard content is preserved.

**Acceptance Scenarios**:

1. **Given** the user has content "ABC" on their clipboard, **When** they use voice input and text "XYZ" is transcribed, **Then** "XYZ" is inserted at the cursor and the clipboard still contains "ABC"
2. **Given** the clipboard is empty, **When** voice input is used, **Then** text is inserted normally and the clipboard is restored to empty
3. **Given** the clipboard contains a large image or formatted content, **When** voice input is used, **Then** the clipboard content is preserved after text injection

---

### User Story 4 - Custom Cloud Service Configuration (Priority: P3)

A user wants to use their own cloud API key and preferred model. They open the settings panel from the menu bar icon, enter their API key, select a model version, and validate the configuration. The app uses these credentials for all subsequent transcriptions.

**Why this priority**: Configuration management enables personalization and is necessary for users who bring their own API access. It's important but the app can function with default or pre-configured credentials initially.

**Independent Test**: Can be tested by opening settings, entering an API key, selecting a model, validating, and performing a transcription to confirm the custom configuration is used.

**Acceptance Scenarios**:

1. **Given** the menu bar icon is visible, **When** the user clicks it and selects "Settings", **Then** a settings panel opens with fields for API key, model selection, and a validate button
2. **Given** the user enters an API key and selects a model, **When** they click "Validate", **Then** the app verifies the credentials and shows success or failure feedback
3. **Given** valid credentials are saved, **When** the user restarts the app, **Then** the saved configuration is still in effect
4. **Given** invalid credentials are entered, **When** the user attempts to use voice input, **Then** a clear error message indicates the configuration issue

---

### User Story 5 - Lightweight Menu Bar-Only Presence (Priority: P3)

The user installs the app and it appears only as a small icon in the macOS menu bar. There is no Dock icon, no main window, and no interruption to normal system operation. The app runs silently in the background with minimal resource usage until the Fn key is pressed.

**Why this priority**: The lightweight, non-intrusive nature is a key differentiator but does not affect core transcription functionality. It's a polish requirement.

**Independent Test**: Can be tested by verifying the app appears only in the menu bar, not in the Dock, and checking CPU/memory usage while idle.

**Acceptance Scenarios**:

1. **Given** the app is running, **When** the user views the Dock, **Then** no app icon appears
2. **Given** the app is running idle, **When** the user checks Activity Monitor, **Then** CPU usage is near 0% and memory usage is minimal
3. **Given** the app is launched, **When** it starts, **Then** it appears only in the menu bar and does not steal focus from the current application

---

### Edge Cases

- What happens when the Fn key is pressed during an active system dictation session?
- How does the app handle rapid Fn key press/release sequences (debouncing)?
- What happens if the network connection drops mid-transcription?
- How does the app behave when the selected cloud model returns an error or rate limit response?
- What happens if multiple input sources are active simultaneously (e.g., physical keyboard + voice input)?
- How does the app handle very long recording sessions (e.g., 5+ minutes)?
- What happens when macOS revokes microphone permission mid-recording?
- How does text injection work in applications with non-standard text fields (e.g., terminal emulators, games)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST capture audio when the user holds the Fn key and stop recording upon release
- **FR-002**: The app MUST globally intercept the Fn key event without conflicting with the system's native Fn key behavior
- **FR-003**: The app MUST display a capsule overlay at the bottom of the screen during recording with live audio waveform animation
- **FR-004**: The app MUST stream incremental transcription results in real-time within the overlay during recording
- **FR-005**: The app MUST automatically insert the final transcribed text at the current cursor position in the active application
- **FR-006**: The app MUST preserve the user's original clipboard content when inserting transcribed text
- **FR-007**: The app MUST support transcription in Simplified Chinese (default), Traditional Chinese, English, Japanese, and Korean
- **FR-008**: The app MUST persist the user's language selection across app restarts
- **FR-009**: The app MUST use cloud-based large model transcription (not the system's native speech recognition)
- **FR-010**: The app MUST follow a strict literal transcription rule — only correcting obvious recognition errors, with no rewriting, embellishment, or redundant output
- **FR-011**: The app MUST provide a settings panel accessible from the menu bar icon for configuring API key and model selection
- **FR-012**: The app MUST validate API credentials and provide clear success/failure feedback
- **FR-013**: The app MUST persist configuration (API key, model selection) across app restarts
- **FR-014**: The app MUST run as a menu bar-only application with no Dock icon
- **FR-015**: The app MUST run silently in the background with minimal resource consumption when idle
- **FR-016**: The capsule overlay MUST resize adaptively based on transcription content length
- **FR-017**: The capsule overlay MUST include smooth transition animations for appearance, content updates, and dismissal
- **FR-018**: The app MUST handle mixed Chinese-English input with high accuracy, including professional terminology
- **FR-019**: The app MUST be compatible with various mainstream input method environments on macOS
- **FR-020**: The app MUST require macOS 14 (Sonoma) or later

### Key Entities

- **Recording Session**: Represents a single hold-to-record interaction, containing audio stream data, streaming transcription state, selected language, and session lifecycle (started, recording, transcribing, completed)
- **Configuration**: Stores user preferences including API credentials, selected model, selected language, and any other persistent settings
- **Overlay State**: Manages the visual state of the capsule overlay including visibility, waveform data, displayed text, size, and animation progress
- **Clipboard Snapshot**: Temporary storage of the user's original clipboard content, used for save-and-restore during text injection

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can trigger voice input and see the overlay appear within 200ms of pressing the Fn key
- **SC-002**: Streaming transcription results appear in the overlay within 1 second of starting to speak (first token latency)
- **SC-003**: Final transcribed text is inserted at the cursor position within 500ms of releasing the Fn key
- **SC-004**: Clipboard content is preserved in 100% of voice input interactions
- **SC-005**: The app uses less than 50MB of memory while idle
- **SC-006**: The app uses less than 1% CPU while idle
- **SC-007**: Chinese-English mixed text recognition achieves over 95% accuracy on standard test sets
- **SC-008**: Language switching takes effect immediately and persists across restarts without requiring re-selection
- **SC-009**: First-time users can complete their first voice input within 30 seconds of launching the app (including any permission grants)

## Assumptions

- Users have macOS 14 (Sonoma) or later installed
- Users have a stable internet connection for cloud-based transcription
- Users grant microphone accessibility permission when prompted by macOS
- The cloud LLM service provides a streaming real-time transcription API
- Users will provide their own API key for the cloud service (BYOK model)
- The Fn key can be intercepted globally on macOS 14+ without requiring additional system-level drivers
- The paste-based method of text injection works in all target applications; for non-standard text fields (terminal emulators, games), accessibility-based insertion will be used as a fallback
- The app does not need to support offline transcription in the initial version
- Professional terminology accuracy depends on the cloud model's capabilities — the app forwards audio and prompts without custom dictionary management
- The app will use accessibility APIs as a secondary text injection method when clipboard paste is not feasible
