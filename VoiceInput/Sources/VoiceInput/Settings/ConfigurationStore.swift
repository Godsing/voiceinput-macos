import Foundation
import Security

final class ConfigurationStore {
    private let defaults: UserDefaults
    private let keychainService: String
    private let keychainAccount: String

    init(defaults: UserDefaults = .standard,
         keychainService: String = "com.voiceinput.app",
         keychainAccount: String = "api-key") {
        self.defaults = defaults
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }

    enum Language: String, CaseIterable {
        case simplifiedChinese = "zh-CN"
        case traditionalChinese = "zh-TW"
        case english = "en"
        case japanese = "ja"
        case korean = "ko"

        var displayName: String {
            switch self {
            case .simplifiedChinese: return "简体中文"
            case .traditionalChinese: return "繁体中文"
            case .english: return "English"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            }
        }

        var instructionsSuffix: String {
            switch self {
            case .simplifiedChinese: return ""
            case .traditionalChinese: return "，请使用繁体中文转写"
            case .english: return ". Transcribe in English."
            case .japanese: return "。日本語で転写してください。"
            case .korean: return ". 한국어로 전사해 주세요."
            }
        }
    }

    var apiKey: String {
        get { loadFromKeychain() ?? "" }
        set { saveToKeychain(newValue) }
    }

    var hasApiKey: Bool { !apiKey.isEmpty }

    var modelName: String {
        get { defaults.string(forKey: "modelName") ?? "qwen3.5-omni-plus-realtime" }
        set { defaults.set(newValue, forKey: "modelName") }
    }

    var language: Language {
        get {
            if let code = defaults.string(forKey: "language"),
               let lang = Language(rawValue: code) {
                return lang
            }
            return .simplifiedChinese
        }
        set { defaults.set(newValue.rawValue, forKey: "language") }
    }

    var apiEndpoint: String {
        get { defaults.string(forKey: "apiEndpoint") ?? "wss://dashscope.aliyuncs.com/api-ws/v1/realtime" }
        set { defaults.set(newValue, forKey: "apiEndpoint") }
    }

    var transcriptionInstructions: String {
        let base = "准确将用户的语音转写为文字，只修复明显的语音识别错误（如中文谐音错误、英文技术术语被错误转为中文如「配森」→「python」、「杰森」→「JSON」），绝对不要改写、润色或删除任何看起来正确的内容，绝对不要包含任何对话或解释"
        return base + language.instructionsSuffix
    }

    private func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)

        if value.isEmpty { return }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
