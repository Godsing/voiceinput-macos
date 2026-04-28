import AppKit
import Foundation

private func debugLogWS(_ message: String) {
    let line = "\(Date()): [WS] \(message)\n"
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

final class RealtimeClient: NSObject, URLSessionWebSocketDelegate {
    enum ConnectionState {
        case disconnected, connecting, connected, reconnecting
    }

    private let apiKey: String
    private let model: String
    private let baseURL: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private(set) var state: ConnectionState = .disconnected

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let baseReconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    private var isResponding = false
    private var responseDoneContinuation: CheckedContinuation<Void, Error>?
    private(set) var accumulatedTranscript = ""
    private var responseAlreadyDone = false

    private var connectContinuation: CheckedContinuation<Void, Error>?
    private let connectTimeout: TimeInterval = 15

    private var idleTimer: DispatchWorkItem?
    private let idleTimeout: TimeInterval = 60

    var onStateChanged: ((ConnectionState) -> Void)?
    var onTranscriptDelta: ((String) -> Void)?
    var onTranscriptDone: ((String) -> Void)?
    var onInputTranscriptDone: ((String) -> Void)?
    var onResponseDone: (() -> Void)?
    var onError: ((String) -> Void)?

    init(apiKey: String, model: String = "qwen3.5-omni-plus-realtime",
         baseURL: String = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        observeSleepWake()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func observeSleepWake() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.state == .disconnected else { return }
            Task { try? await self.connect() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.disconnect()
        }
    }

    func connect() async throws {
        guard state == .disconnected else { return }
        state = .connecting
        onStateChanged?(.connecting)

        guard let url = URL(string: "\(baseURL)?model=\(model)") else {
            state = .disconnected
            throw RealtimeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessages()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            DispatchQueue.global().asyncAfter(deadline: .now() + connectTimeout) { [weak self] in
                guard let self, let cont = self.connectContinuation else { return }
                self.connectContinuation = nil
                self.disconnect()
                cont.resume(throwing: RealtimeError.timeout)
            }
        }
    }

    func updateSession(instructions: String) async throws {
        let sessionConfig: [String: Any] = [
            "modalities": ["text"],
            "instructions": instructions,
            "input_audio_format": "pcm",
            "output_audio_format": "pcm",
            "input_audio_transcription": ["model": "gummy-realtime-v1"],
            "turn_detection": NSNull()
        ]
        try await sendEvent(["type": "session.update", "session": sessionConfig])
    }

    func appendAudioBuffer(_ base64PCM: String) async throws {
        try await sendEvent(["type": "input_audio_buffer.append", "audio": base64PCM])
    }

    func commitAudioBuffer() async throws {
        try await sendEvent(["type": "input_audio_buffer.commit"])
    }

    func createResponse() async throws {
        accumulatedTranscript = ""
        responseAlreadyDone = false
        try await sendEvent(["type": "response.create"])
    }

    func cancelResponse() async throws {
        isResponding = false
        responseDoneContinuation?.resume(throwing: RealtimeError.notConnected)
        responseDoneContinuation = nil
        accumulatedTranscript = ""
        try await sendEvent(["type": "response.cancel"])
    }

    func waitForResponseDone(timeout: TimeInterval = 30) async throws {
        if responseAlreadyDone {
            responseAlreadyDone = false
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.responseDoneContinuation = continuation
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let cont = self.responseDoneContinuation else { return }
                self.responseDoneContinuation = nil
                cont.resume(throwing: RealtimeError.timeout)
            }
        }
    }

    func disconnect() {
        cancelIdleTimer()
        connectContinuation?.resume(throwing: RealtimeError.notConnected)
        connectContinuation = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        onStateChanged?(.disconnected)
    }

    func resetIdleTimer() {
        cancelIdleTimer()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .connected, !self.isResponding else { return }
            self.disconnect()
        }
        idleTimer = item
        DispatchQueue.global().asyncAfter(deadline: .now() + idleTimeout, execute: item)
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                 didOpenWithProtocol protocol: String?) {
        Task { @MainActor in handleDidOpen() }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                 didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in handleDidClose(code: closeCode) }
    }

    private func handleDidOpen() {
        state = .connected
        reconnectAttempts = 0
        onStateChanged?(.connected)
        connectContinuation?.resume()
        connectContinuation = nil
    }

    private func handleDidClose(code: URLSessionWebSocketTask.CloseCode) {
        let wasConnecting = state == .connecting
        state = .disconnected
        onStateChanged?(.disconnected)

        if wasConnecting {
            connectContinuation?.resume(throwing: RealtimeError.connectionRefused)
            connectContinuation = nil
        } else if code != .normalClosure && code != .goingAway {
            scheduleReconnect()
        }
    }

    // MARK: - Receive Loop

    private func receiveMessages() {
        guard let ws = webSocketTask else { return }
        ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleEvent(text) }
                if case .data(let data) = message,
                   let text = String(data: data, encoding: .utf8) { self.handleEvent(text) }
            case .failure(let error):
                if self.state == .connected {
                    self.onError?(error.localizedDescription)
                    self.scheduleReconnect()
                }
            }
            self.receiveMessages()
        }
    }

    private func handleEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            debugLogWS("handleEvent: failed to parse JSON or missing 'type'")
            return
        }

        debugLogWS("handleEvent: type=\(type)")

        switch type {
        case "response.text.delta":
            if let delta = json["delta"] as? String {
                accumulatedTranscript += delta
                onTranscriptDelta?(delta)
            }
        case "response.audio_transcript.delta":
            break
        case "response.audio_transcript.done":
            break
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                onInputTranscriptDone?(transcript)
            }
        case "response.created":
            isResponding = true
        case "response.done":
            isResponding = false
            onResponseDone?()
            if let cont = responseDoneContinuation {
                responseDoneContinuation = nil
                cont.resume()
            } else {
                responseAlreadyDone = true
            }
        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            onError?(msg)
        default: break
        }
    }

    // MARK: - Send

    private func sendEvent(_ event: [String: Any]) async throws {
        guard let ws = webSocketTask, state == .connected else {
            throw RealtimeError.notConnected
        }
        let jsonData = try JSONSerialization.data(withJSONObject: event)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw RealtimeError.encodingFailed
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ws.send(.string(jsonString)) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            onError?("Max reconnection attempts reached")
            return
        }
        state = .reconnecting
        onStateChanged?(.reconnecting)
        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        let jittered = delay * Double.random(in: 0.5...1.5)
        reconnectAttempts += 1
        DispatchQueue.global().asyncAfter(deadline: .now() + jittered) { [weak self] in
            Task { await self?.attemptReconnect() }
        }
    }

    private func attemptReconnect() async {
        disconnect()
        do { try await connect() } catch { scheduleReconnect() }
    }
}

enum RealtimeError: LocalizedError {
    case invalidURL, notConnected, encodingFailed, timeout, connectionRefused
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebSocket URL"
        case .notConnected: return "WebSocket not connected"
        case .encodingFailed: return "Failed to encode message"
        case .timeout: return "Operation timed out"
        case .connectionRefused: return "Connection refused by server"
        }
    }
}
