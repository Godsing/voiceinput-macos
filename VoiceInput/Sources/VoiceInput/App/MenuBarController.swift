import AppKit

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private weak var configStore: ConfigurationStore?
    private var settingsWindow: SettingsWindow?

    init(configStore: ConfigurationStore) {
        self.configStore = configStore
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoiceInput")
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let languageMenu = NSMenu()
        let currentLang = configStore?.language ?? .simplifiedChinese
        for lang in ConfigurationStore.Language.allCases {
            let item = languageMenu.addItem(
                withTitle: lang.displayName,
                action: #selector(languageSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang
            item.state = lang == currentLang ? .on : .off
        }

        let languageItem = menu.addItem(withTitle: "Language", action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu

        menu.addItem(NSMenuItem.separator())

        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit VoiceInput", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? ConfigurationStore.Language else { return }
        configStore?.language = lang
        rebuildMenu()
    }

    @objc private func openSettings() {
        guard let configStore else { return }
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(configStore: configStore)
        }
        settingsWindow?.show()
    }
}
