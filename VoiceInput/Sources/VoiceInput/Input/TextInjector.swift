import AppKit
import Carbon
import CoreGraphics

final class TextInjector {
    private var clipboardSnapshot: ClipboardSnapshot?
    private let inputMethodManager = InputMethodManager()
    private let injectionHandler: ((String) -> Void)?

    init(injectionHandler: ((String) -> Void)? = nil) {
        self.injectionHandler = injectionHandler
    }

    func injectText(_ text: String) {
        guard !text.isEmpty else { return }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.injectText(text)
            }
            return
        }

        performInjection(text)
    }

    private func performInjection(_ text: String) {
        if let injectionHandler {
            injectionHandler(text)
            return
        }

        clipboardSnapshot = ClipboardSnapshot.save()
        var previousInputSource: TISInputSource?

        do {
            previousInputSource = inputMethodManager.switchToASCIIIfNeeded()
            Thread.sleep(forTimeInterval: 0.05)

            setTextOnClipboard(text)
            Thread.sleep(forTimeInterval: 0.05)

            simulatePaste()
            Thread.sleep(forTimeInterval: 0.3)
        }

        if let prev = previousInputSource {
            inputMethodManager.restoreInputSource(prev)
        }

        // Delay clipboard restore to ensure paste completes first
        let snapshot = clipboardSnapshot
        clipboardSnapshot = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            snapshot?.restore()
        }
    }

    private func setTextOnClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(text, forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        pb.writeObjects([item])
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        if let down = keyDown, let up = keyUp {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func waitForPasteCompletion() {
        let changeCountAtWrite = NSPasteboard.general.changeCount
        let startTime = Date()

        RunLoop.current.run(until: Date().addingTimeInterval(0.08))

        while Date().timeIntervalSince(startTime) < 0.4 {
            if NSPasteboard.general.changeCount != changeCountAtWrite { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func save() -> ClipboardSnapshot {
        let pasteboardItems = NSPasteboard.general.pasteboardItems ?? []
        var savedItems: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboardItems {
            var typeData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData[type] = data
                }
            }
            savedItems.append(typeData)
        }
        return ClipboardSnapshot(items: savedItems)
    }

    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pb.writeObjects([item])
        }
    }
}
