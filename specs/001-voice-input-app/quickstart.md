# Quickstart: macOS Menu Bar Voice Input App

**Feature**: 001-voice-input-app | **Date**: 2026-04-23

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+ with Swift 5.9+
- DashScope API key (from Alibaba Cloud)

## Build

```bash
make build
```

This runs `swift build -c release` and produces the executable at `.build/release/VoiceInput`.

## Run (Development)

```bash
make run
```

Builds and launches the app. On first launch:
1. macOS prompts for **Microphone** access — grant it
2. macOS prompts for **Accessibility** access — grant it (required for Fn key interception and text injection)
3. Click the menu bar icon and open **Settings**
4. Enter your DashScope API Key and click **Test**
5. On success, click **Save**

## Install

```bash
make install
```

Copies the signed `.app` bundle to `/Applications/VoiceInput.app`.

## Usage

1. **Hold Fn key** — recording starts, capsule overlay appears with live waveform and streaming text
2. **Release Fn key** — transcription completes, text is inserted at cursor position
3. **Language** — click menu bar icon → select language (default: Simplified Chinese)
4. **Settings** — click menu bar icon → Settings → configure API key and model

## Makefile Targets

| Target | Description |
|--------|-------------|
| `build` | Build release binary |
| `run` | Build and run the app |
| `install` | Install .app bundle to /Applications |
| `clean` | Clean build artifacts |
| `test` | Run XCTest suite |

## Key Configuration

| Setting | Storage | Default |
|---------|---------|---------|
| API Key | Keychain | (none) |
| Model | UserDefaults | qwen3.5-omni-plus-realtime |
| Language | UserDefaults | zh-CN |

## Permissions Required

| Permission | Purpose | When Prompted |
|------------|---------|---------------|
| Microphone | Audio capture for transcription | First recording |
| Accessibility | Fn key interception, text injection, input method switching | First launch |
