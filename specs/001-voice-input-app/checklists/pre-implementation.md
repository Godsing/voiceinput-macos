# Pre-Implementation Requirements Checklist: macOS Menu Bar Voice Input App

**Purpose**: Validate requirement completeness, clarity, and consistency before implementation begins — focusing on high-risk areas: permissions/startup, network failure/recovery, text injection reliability, and real-time audio/UI performance
**Created**: 2026-04-23
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)
**Audience**: Author (pre-implementation) | **Depth**: Standard

## Permission & Startup Flows

- [ ] CHK001 Are requirements specified for what happens when the user denies Microphone permission after initial grant (mid-recording revocation)? [Edge Case, Gap, Spec §Edge Cases]
- [ ] CHK002 Are requirements defined for the app's behavior when Accessibility permission is denied or revoked while CGEvent tap is active? [Completeness, Gap]
- [ ] CHK003 Is the first-launch experience specified — what does the user see before any permissions are granted or API key is configured? [Gap]
- [ ] CHK004 Are requirements defined for how the app communicates permission requirements to the user (beyond the macOS system prompt)? [Clarity, Spec §FR-002]
- [ ] CHK005 Is the behavior specified when the user launches the app without ever granting Accessibility permission — can any functionality work? [Coverage, Gap]
- [ ] CHK006 Are requirements specified for re-prompting permissions after the user has previously denied them? [Gap]

## Network Failure & Recovery

- [ ] CHK007 Are requirements defined for what the user sees in the overlay when the WebSocket connection drops mid-transcription? [Completeness, Gap]
- [ ] CHK008 Is the behavior specified when the server returns a rate limit error during an active recording session? [Coverage, Spec §Edge Cases]
- [ ] CHK009 Are requirements defined for how much partial transcript (if any) to inject when the connection fails before `response.done`? [Gap, Ambiguity]
- [ ] CHK010 Is the maximum reconnection attempt count and failure behavior specified from the user's perspective (not just the retry algorithm)? [Clarity, Plan §Technical Context]
- [ ] CHK011 Are requirements defined for the overlay state during the reconnection process — does it show "reconnecting" or dismiss? [Gap]
- [ ] CHK012 Is the behavior specified when the user presses Fn while a previous transcription is still waiting for `response.done` (rapid re-trigger)? [Coverage, Spec §Edge Cases]
- [ ] CHK013 Are requirements defined for what happens to in-flight audio data when the user cancels a pending response (via `response.cancel`)? [Gap]
- [ ] CHK014 Is the maximum acceptable latency for the overlay to show a network error specified? [Measurability, Gap]

## Text Injection Reliability

- [ ] CHK015 Are requirements specified for text injection behavior when no ASCII input source is available on the system? [Edge Case, Gap]
- [ ] CHK016 Are requirements defined for clipboard restoration failure — what happens if the original clipboard content cannot be restored? [Exception Flow, Gap]
- [ ] CHK017 Is the behavior specified for text injection in applications with non-standard text fields (terminal emulators, games, password fields)? [Coverage, Spec §Edge Cases]
- [ ] CHK018 Are requirements defined for the minimum delay between input method switch and Cmd+V simulation to ensure reliability? [Clarity, Gap]
- [ ] CHK019 Is the expected behavior specified when the target application loses focus between transcription completion and text injection? [Edge Case, Gap]
- [ ] CHK020 Are requirements defined for how very long transcriptions (exceeding the transcript label's 500px max width) are handled during injection vs display? [Consistency, Spec §FR-016]
- [ ] CHK021 Is the behavior specified when the user's clipboard contains content in formats that cannot be fully round-tripped through NSPasteboard save/restore (e.g., UTI types not supported by NSPasteboardItem)? [Edge Case, Gap]
- [ ] CHK022 Are requirements defined for CJK input method detection when third-party IMEs are installed (beyond Apple's built-in ones)? [Coverage, Spec §FR-019]

## Real-Time Audio & UI Performance

- [ ] CHK023 Is the "overlay appear within 200ms" requirement defined as measured from Fn key-down event or from the first audio callback? [Clarity, Spec §SC-001]
- [ ] CHK024 Are performance requirements specified for the overlay waveform when the audio tap delivers data at a different rate than expected (e.g., hardware format change)? [Edge Case, Gap]
- [ ] CHK025 Is the behavior specified when AVAudioEngine fails to start (e.g., another app has exclusive audio access)? [Exception Flow, Gap]
- [ ] CHK026 Are memory budget requirements specified for the WebSocket receive buffer during long transcription responses? [Completeness, Gap]
- [ ] CHK027 Is the "less than 1% CPU while idle" requirement defined for what "idle" means — no WebSocket connection, or connected but not recording? [Clarity, Spec §SC-006]
- [ ] CHK028 Are requirements defined for the overlay's behavior during macOS Space switching or full-screen transitions? [Coverage, Gap]
- [ ] CHK029 Is the "first transcription token within 1 second" requirement specified as measured from Fn release or from `response.create` send? [Clarity, Spec §SC-002]
- [ ] CHK030 Are requirements defined for audio buffer underrun behavior — what does the user see/hear if the audio pipeline stalls? [Edge Case, Spec §Constitution IV]

## Cross-Cutting Requirement Quality

- [ ] CHK031 Are error message requirements consistently defined across all failure modes (network, permission, API, audio) — do they all follow the "actionable error" pattern from the constitution? [Consistency, Constitution §III]
- [ ] CHK032 Are the system prompt instructions for transcription accuracy (FR-010) defined with measurable acceptance criteria — what counts as an "obvious recognition error"? [Measurability, Spec §FR-010]
- [ ] CHK033 Is the language switching behavior specified for mid-session — does changing language require a new WebSocket connection or can it be updated via `session.update`? [Clarity, Gap]
- [ ] CHK034 Are requirements defined for the app's behavior when macOS enters sleep/wake during an active recording or pending transcription? [Coverage, Gap]
- [ ] CHK035 Is the API key validation requirement (FR-012) specified with clear criteria for what constitutes a "valid" key — successful WebSocket connection, or a specific test API call? [Clarity, Spec §FR-012]

## Notes

- Items marked [Gap] indicate requirements that are not currently addressed in spec or plan
- Items marked [Clarity] indicate existing requirements that are insufficiently specific for implementation
- Items marked [Consistency] flag potential conflicts between spec sections
- Items marked [Ambiguity] flag terms that could be interpreted multiple ways
- Author should resolve all [Gap] and [Clarity] items before beginning implementation
