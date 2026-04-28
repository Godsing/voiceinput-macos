import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private weak var configStore: ConfigurationStore?

    init(configStore: ConfigurationStore) {
        self.configStore = configStore
    }

    func show() {
        if let existing = window, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        guard let configStore else { return }

        let hostingView = NSHostingView(rootView: SettingsView(configStore: configStore))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 260)

        let newWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "VoiceInput Settings"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }
}

struct SettingsView: View {
    @ObservedObject var configStore: ConfigurationStore

    @State private var apiKeyInput: String = ""
    @State private var modelInput: String = ""
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle, testing, success, failure(String)
        var label: String {
            switch self {
            case .idle: return ""
            case .testing: return "Testing…"
            case .success: return "✓ Connection successful"
            case .failure(let msg): return "✗ \(msg)"
            }
        }
        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Qwen-Omni Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("DashScope API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("sk-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Model name", text: $modelInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Test") {
                    testConnection()
                }
                .disabled(testStatus == .testing || apiKeyInput.isEmpty)

                Button("Save") {
                    saveConfig()
                }
                .disabled(apiKeyInput.isEmpty)

                if testStatus != .idle {
                    Text(testStatus.label)
                        .font(.caption)
                        .foregroundColor(testStatus == .success ? .green : (testStatus.isFailure ? .red : .primary))
                }
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            apiKeyInput = configStore.apiKey
            modelInput = configStore.modelName
        }
    }

    private func testConnection() {
        testStatus = .testing
        let key = apiKeyInput
        let model = modelInput
        let endpoint = configStore.apiEndpoint

        Task {
            do {
                let client = RealtimeClient(apiKey: key, model: model, baseURL: endpoint)
                try await client.connect()
                try await client.updateSession(instructions: "Test connection")
                try await Task.sleep(nanoseconds: 500_000_000)
                client.disconnect()
                await MainActor.run { testStatus = .success }
            } catch {
                await MainActor.run { testStatus = .failure(error.localizedDescription) }
            }
        }
    }

    private func saveConfig() {
        configStore.apiKey = apiKeyInput
        configStore.modelName = modelInput
    }
}

extension ConfigurationStore: ObservableObject {}
