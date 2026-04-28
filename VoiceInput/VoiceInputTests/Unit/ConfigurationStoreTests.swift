import XCTest
@testable import VoiceInput

final class ConfigurationStoreTests: XCTestCase {
    private var store: ConfigurationStore!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private let keychainService = "com.voiceinput.app.tests"
    private let keychainAccount = "api-key-tests"

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "VoiceInputTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        store = ConfigurationStore(
            defaults: defaults,
            keychainService: keychainService,
            keychainAccount: keychainAccount
        )
    }

    override func tearDown() {
        store.apiKey = ""
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        store = nil
        super.tearDown()
    }

    func testDefaultModelName() {
        XCTAssertEqual(store.modelName, "qwen3.5-omni-plus-realtime")
    }

    func testSetAndGetModelName() {
        store.modelName = "custom-model"
        XCTAssertEqual(store.modelName, "custom-model")
    }

    func testDefaultLanguage() {
        XCTAssertEqual(store.language, .simplifiedChinese)
    }

    func testSetAndGetLanguage() {
        store.language = .english
        XCTAssertEqual(store.language, .english)
    }

    func testLanguagePersistsAcrossInstances() {
        store.language = .japanese
        let newStore = ConfigurationStore(
            defaults: defaults,
            keychainService: keychainService,
            keychainAccount: keychainAccount
        )
        XCTAssertEqual(newStore.language, .japanese)
        newStore.language = .simplifiedChinese
    }

    func testDefaultApiEndpoint() {
        XCTAssertEqual(store.apiEndpoint, "wss://dashscope.aliyuncs.com/api-ws/v1/realtime")
    }

    func testHasApiKeyIsFalseWhenEmpty() {
        store.apiKey = ""
        XCTAssertFalse(store.hasApiKey)
    }

    func testHasApiKeyIsTrueWhenSet() {
        store.apiKey = "sk-test-key"
        XCTAssertTrue(store.hasApiKey)
        store.apiKey = ""
    }

    func testApiKeyPersistsInKeychain() {
        store.apiKey = "sk-persist-test"
        let newStore = ConfigurationStore(
            defaults: defaults,
            keychainService: keychainService,
            keychainAccount: keychainAccount
        )
        XCTAssertEqual(newStore.apiKey, "sk-persist-test")
        newStore.apiKey = ""
    }

    func testTranscriptionInstructionsContainsBaseAndSuffix() {
        store.language = .english
        let instructions = store.transcriptionInstructions
        XCTAssertTrue(instructions.contains("Transcribe in English"))
    }

    func testLanguageDisplayNames() {
        XCTAssertEqual(ConfigurationStore.Language.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(ConfigurationStore.Language.english.displayName, "English")
        XCTAssertEqual(ConfigurationStore.Language.japanese.displayName, "日本語")
        XCTAssertEqual(ConfigurationStore.Language.korean.displayName, "한국어")
        XCTAssertEqual(ConfigurationStore.Language.traditionalChinese.displayName, "繁体中文")
    }

    func testLanguageRawValues() {
        XCTAssertEqual(ConfigurationStore.Language.simplifiedChinese.rawValue, "zh-CN")
        XCTAssertEqual(ConfigurationStore.Language.traditionalChinese.rawValue, "zh-TW")
        XCTAssertEqual(ConfigurationStore.Language.english.rawValue, "en")
        XCTAssertEqual(ConfigurationStore.Language.japanese.rawValue, "ja")
        XCTAssertEqual(ConfigurationStore.Language.korean.rawValue, "ko")
    }
}
