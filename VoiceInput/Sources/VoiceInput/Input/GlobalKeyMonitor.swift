import CoreGraphics
import ApplicationServices
import Foundation

private func debugLogKey(_ message: String) {
    let line = "\(Date()): [KEY] \(message)\n"
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

final class GlobalKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnPressed = false
    private var holdTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?

    private let holdThreshold: TimeInterval = 0.15
    private let releaseDebounce: TimeInterval = 0.05

    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard AXIsProcessTrusted() else {
            debugLogKey("Accessibility permission not granted — Fn key will not work")
            return
        }
        debugLogKey("Starting event tap for Fn key detection")

        guard let tap = CGEvent.tapCreate(

            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalKeyMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                if let result = monitor.handleEvent(proxy: proxy, type: type, event: event) {
                    return Unmanaged.passUnretained(result)
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLogKey("Failed to create CGEvent tap — Fn key will not work")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLogKey("Event tap created and enabled successfully")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            debugLogKey("Event tap was disabled and has been re-enabled")
            return event
        }

        switch type {
        case .keyDown, .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == 63 else { return event }
            debugLogKey("Fn keyDown/keyUp keyCode=63, type=\(type == .keyDown ? "down" : "up")")
            if type == .keyDown {
                handleFnDown()
            } else {
                handleFnUp()
            }
            return nil

        case .flagsChanged:
            let flags = event.flags
            let fnFlagChanged = flags.contains(.maskSecondaryFn) != isFnPressed
            if fnFlagChanged {
                debugLogKey("Fn flagsChanged, maskSecondaryFn=\(flags.contains(.maskSecondaryFn)), wasPressed=\(isFnPressed)")
                if flags.contains(.maskSecondaryFn) && !isFnPressed {
                    handleFnDown()
                } else if !flags.contains(.maskSecondaryFn) && isFnPressed {
                    handleFnUp()
                }
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func handleFnDown() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        guard !isFnPressed else { return }
        isFnPressed = true

        holdTimer = Timer.scheduledTimer(
            timeInterval: holdThreshold,
            target: self,
            selector: #selector(holdThresholdReached),
            userInfo: nil,
            repeats: false
        )
    }

    private func handleFnUp() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.confirmFnKeyUp()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDebounce, execute: workItem)
    }

    @objc private func holdThresholdReached() {
        if isFnPressed {
            debugLogKey("Fn hold threshold reached — triggering onHoldStart")
            onHoldStart?()
        }
    }

    private func confirmFnKeyUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        if isFnPressed {
            isFnPressed = false
            debugLogKey("Fn key released — triggering onHoldEnd")
            onHoldEnd?()
        }
    }
}
