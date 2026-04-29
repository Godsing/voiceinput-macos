import AppKit
import AVFoundation
import ApplicationServices

@main
struct VoiceInputApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

private func debugLog(_ message: String) {
    let line = "\(Date()): \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/voiceinput_debug.log")
    if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        try? data.write(to: url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var globalKeyMonitor: GlobalKeyMonitor?
    private var audioEngine: AudioCaptureEngine?
    private var realtimeClient: RealtimeClient?
    private var overlayPanel: CapsuleOverlayPanel?
    private var textInjector: TextInjector?
    private var configStore: ConfigurationStore?
    private let recordingLifecycle = RecordingLifecycle()
    private var inputTranscript: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        configStore = ConfigurationStore()
        textInjector = TextInjector()
        menuBarController = MenuBarController(configStore: configStore!)

        setupMainMenu()
        checkPermissions()
        setupGlobalKeyMonitor()
        setupOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalKeyMonitor?.stop()
        audioEngine?.stop()
        realtimeClient?.disconnect()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About VoiceInput", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit VoiceInput", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func checkPermissions() {
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "VoiceInput needs accessibility access to detect the Fn key. Please grant access in System Settings > Privacy & Security > Accessibility."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }

        if AVAudioApplication.shared.recordPermission != .granted {
            AVAudioApplication.requestRecordPermission { granted in
                if !granted {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Microphone Access Required"
                        alert.informativeText = "VoiceInput needs microphone access for voice input. Please grant access in System Settings > Privacy & Security > Microphone."
                        alert.addButton(withTitle: "Open System Settings")
                        alert.addButton(withTitle: "Later")
                        if alert.runModal() == .alertFirstButtonReturn {
                            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func setupGlobalKeyMonitor() {
        globalKeyMonitor = GlobalKeyMonitor()
        globalKeyMonitor?.onHoldStart = { [weak self] in
            self?.startRecording()
        }
        globalKeyMonitor?.onHoldEnd = { [weak self] in
            self?.stopRecording()
        }
        globalKeyMonitor?.start()
    }

    private func setupOverlay() {
        overlayPanel = CapsuleOverlayPanel()
    }

    @MainActor
    private func showOverlay() {
        overlayPanel?.show()
    }

    @MainActor
    private func showErrorAndHide(_ message: String) {
        overlayPanel?.showError(message)
        overlayPanel?.hide(delay: 3.0)
    }

    @MainActor
    private func hideOverlay() {
        overlayPanel?.hide()
    }

    private func startRecording() {
        guard let config = configStore, config.hasApiKey else {
            debugLog("startRecording skipped — no API key configured")
            Task { await showErrorAndHide("Configure API Key in Settings") }
            return
        }
        debugLog("startRecording called")

        guard recordingLifecycle.requestStart() == .beginPreparing else {
            debugLog("startRecording ignored — lifecycle phase=\(recordingLifecycle.phase)")
            return
        }
        inputTranscript = ""
        Task { await showOverlay() }

        audioEngine = AudioCaptureEngine()

        audioEngine?.onRMSUpdate = { [weak self] rms in
            DispatchQueue.main.async {
                self?.overlayPanel?.updateWaveform(rms: rms)
            }
        }

        audioEngine?.onAudioChunk = { [weak self] base64PCM in
            Task { [weak self] in
                try? await self?.realtimeClient?.appendAudioBuffer(base64PCM)
            }
        }

        if realtimeClient == nil || realtimeClient?.state != .connected {
            realtimeClient = RealtimeClient(
                apiKey: config.apiKey,
                model: config.modelName,
                baseURL: config.apiEndpoint
            )
            realtimeClient?.onTranscriptDelta = { [weak self] delta in
                DispatchQueue.main.async {
                    self?.overlayPanel?.appendTranscript(delta)
                }
            }
            realtimeClient?.onInputTranscriptDone = { [weak self] transcript in
                self?.inputTranscript = transcript
            }
            realtimeClient?.onError = { [weak self] error in
                DispatchQueue.main.async {
                    self?.overlayPanel?.showError(error)
                }
            }
            Task {
                do {
                    try await realtimeClient?.connect()
                    try await realtimeClient?.updateSession(
                        instructions: config.transcriptionInstructions
                    )
                    guard recordingLifecycle.markReady() == .startRecording else {
                        debugLog("recording preparation aborted before audio start")
                        await hideOverlay()
                        return
                    }
                    try audioEngine?.start()
                    debugLog("audio engine started")
                } catch {
                    recordingLifecycle.finish()
                    debugLog("startRecording failed: \(error.localizedDescription)")
                    await showErrorAndHide(error.localizedDescription)
                }
            }
        } else {
            Task {
                do {
                    try await realtimeClient?.updateSession(
                        instructions: config.transcriptionInstructions
                    )
                    guard recordingLifecycle.markReady() == .startRecording else {
                        debugLog("recording preparation aborted before audio start")
                        await hideOverlay()
                        return
                    }
                    try audioEngine?.start()
                    debugLog("audio engine started")
                } catch {
                    recordingLifecycle.finish()
                    debugLog("startRecording failed: \(error.localizedDescription)")
                    await showErrorAndHide(error.localizedDescription)
                }
            }
        }
    }

    private func stopRecording() {
        let stopDecision = recordingLifecycle.requestStop()
        guard stopDecision != .ignore else {
            debugLog("stopRecording ignored — lifecycle phase=\(recordingLifecycle.phase)")
            return
        }
        debugLog("stopRecording called")

        guard stopDecision == .commitRecording else {
            debugLog("stopRecording deferred until preparation finishes")
            overlayPanel?.stopWaveform()
            return
        }

        audioEngine?.stop()
        overlayPanel?.stopWaveform()
        realtimeClient?.resetIdleTimer()

        Task {
            guard let client = realtimeClient else {
                recordingLifecycle.finish()
                await hideOverlay()
                return
            }

            do {
                try await client.commitAudioBuffer()
                debugLog("audio buffer committed")
                try await client.createResponse()
                debugLog("response.create sent")
                try await client.waitForResponseDone(timeout: 30)
                debugLog("response done received")

                let transcript = TranscriptResolver.finalTranscript(
                    inputTranscript: inputTranscript,
                    responseTranscript: client.accumulatedTranscript
                )
                debugLog("inputTranscript='\(inputTranscript)', accumulatedTranscript='\(client.accumulatedTranscript)', final transcript='\(transcript)'")
                inputTranscript = ""
                recordingLifecycle.finish()
                await hideOverlay()
                if !transcript.isEmpty {
                    debugLog("injecting text '\(transcript)'")
                    textInjector?.injectText(transcript)
                } else {
                    debugLog("transcript is empty, skipping injection")
                }

                await hideOverlay()
            } catch {
                recordingLifecycle.finish()
                debugLog("stopRecording failed: \(error.localizedDescription)")
                await showErrorAndHide(error.localizedDescription)
            }
        }
    }
}
