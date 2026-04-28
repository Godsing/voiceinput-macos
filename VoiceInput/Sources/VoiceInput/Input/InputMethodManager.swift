import Carbon
import AppKit

final class InputMethodManager {
    private let cjkPrefixes = [
        "com.apple.inputmethod.SCIM.",
        "com.apple.inputmethod.TCIM.",
        "com.apple.inputmethod.Japanese.",
        "com.apple.inputmethod.Korean.",
        "com.sogou.inputmethod.",
        "com.baidu.inputmethod.",
        "com.qq.inputmethod.",
        "com.iflytek.inputmethod.",
        "com.google.inputmethod.Japanese.",
        "org.fcitx.inputmethod.",
    ]

    func currentInputSource() -> (source: TISInputSource, id: String, isCJK: Bool)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        let isCJK = isCJKSourceID(id)
        return (source: source, id: id, isCJK: isCJK)
    }

    func isCJKSourceID(_ id: String) -> Bool {
        cjkPrefixes.contains(where: { id.hasPrefix($0) }) ||
        id.contains("inputmethod.SCIM") ||
        id.contains("inputmethod.TCIM") ||
        id.contains("inputmethod.Japanese") ||
        id.contains("inputmethod.Korean")
    }

    func findASCIIInputSource() -> TISInputSource? {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return nil }

        var usLayout: TISInputSource?
        var anyASCII: TISInputSource?

        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            guard let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let selectable = Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue()
            guard CFBooleanGetValue(selectable) else { continue }

            guard let asciiPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { continue }
            let isASCII = Unmanaged<CFBoolean>.fromOpaque(asciiPtr).takeUnretainedValue()
            guard CFBooleanGetValue(isASCII) else { continue }

            if id == "com.apple.keylayout.ABC" { return source }
            if id == "com.apple.keylayout.US" { usLayout = source }
            if anyASCII == nil && id.hasPrefix("com.apple.keylayout.") { anyASCII = source }
        }
        return usLayout ?? anyASCII
    }

    @discardableResult
    func selectInputSource(_ source: TISInputSource) -> OSStatus {
        TISSelectInputSource(source)
    }

    func switchToASCIIIfNeeded() -> TISInputSource? {
        guard let current = currentInputSource(), current.isCJK else { return nil }
        let previous = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()

        guard let asciiSource = findASCIIInputSource() else { return previous }
        _ = selectInputSource(asciiSource)
        return previous
    }

    func restoreInputSource(_ source: TISInputSource?) {
        guard let source = source else { return }
        _ = selectInputSource(source)
    }
}
