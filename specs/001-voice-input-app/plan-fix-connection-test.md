# Fix: Settings "Test" Button Always Shows "Connection Failed"

## Root Cause

`RealtimeClient.connect()` is not truly async — it starts the WebSocket task and returns immediately without waiting for the handshake. The `testConnection()` flow:

1. `connect()` sets state to `.connecting`, calls `webSocketTask.resume()`, returns immediately
2. `updateSession()` checks `state == .connected` → false (delegate callback `handleDidOpen()` hasn't fired yet)
3. Throws `RealtimeError.notConnected` → catch block displays "Connection failed"

## Secondary Issue

`testConnection()` doesn't pass `configStore.apiEndpoint` to `RealtimeClient`, so the test always uses the default endpoint even if the user configured a custom one.

## Plan

### Step 1: Make `connect()` await the WebSocket handshake

In `RealtimeClient.swift`:
- Add a `connectContinuation: CheckedContinuation<Void, Error>?` property
- In `connect()`: after starting the WebSocket task, `await` on the continuation
- In `handleDidOpen()`: resume the continuation with success
- In `handleDidClose()` (if closed before opening): resume the continuation with failure
- In `disconnect()`: cancel the continuation if still pending
- Add a connection timeout (e.g., 15s) so it doesn't hang forever

### Step 2: Pass `apiEndpoint` in testConnection

In `SettingsWindow.swift`:
- Change `RealtimeClient(apiKey: key, model: model)` to `RealtimeClient(apiKey: key, model: model, baseURL: configStore.apiEndpoint)`

### Step 3: Show actual error message on failure

In `SettingsWindow.swift`:
- Change `TestStatus.failure` to hold an optional error message
- Display the actual error in the failure label for better debugging

## Files to Modify

1. `VoiceInput/Sources/VoiceInput/WebSocket/RealtimeClient.swift` — await handshake in `connect()`
2. `VoiceInput/Sources/VoiceInput/Settings/SettingsWindow.swift` — pass apiEndpoint, show error details
