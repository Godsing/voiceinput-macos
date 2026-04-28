import AppKit

final class CapsuleOverlayPanel: NSPanel {
    private let waveformView = WaveformView()
    private let transcriptLabel = AutoSizingLabel()
    private let containerBox = NSBox()

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true

        setupContentView()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Setup

    private func setupContentView() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 28
        visualEffect.layer?.masksToBounds = true

        // Semi-transparent dark overlay for stronger contrast
        let tintView = NSView()
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.55).cgColor

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.setAccessibilityLabel("Voice waveform animation")
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false
        transcriptLabel.isEditable = false
        transcriptLabel.isSelectable = false
        transcriptLabel.backgroundColor = .clear
        transcriptLabel.textColor = .white
        transcriptLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        transcriptLabel.lineBreakMode = .byTruncatingTail
        transcriptLabel.maximumNumberOfLines = 1
        transcriptLabel.setAccessibilityLabel("Transcription text")

        tintView.addSubview(waveformView)
        tintView.addSubview(transcriptLabel)
        visualEffect.addSubview(tintView)

        // Tint view fills visual effect
        tintView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        // Separator line between waveform and text
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        tintView.addSubview(separator)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: 44),
            waveformView.heightAnchor.constraint(equalToConstant: 32),
            waveformView.leadingAnchor.constraint(equalTo: tintView.leadingAnchor, constant: 16),
            waveformView.centerYAnchor.constraint(equalTo: tintView.centerYAnchor),

            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 20),
            separator.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 8),
            separator.centerYAnchor.constraint(equalTo: tintView.centerYAnchor),

            transcriptLabel.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 10),
            transcriptLabel.trailingAnchor.constraint(equalTo: tintView.trailingAnchor, constant: -16),
            transcriptLabel.centerYAnchor.constraint(equalTo: tintView.centerYAnchor),
            transcriptLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            transcriptLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])

        contentView = visualEffect
    }

    // MARK: - Public API

    func show() {
        let initialRect = NSRect(x: 0, y: 0, width: 280, height: 56)
        setFrame(initialRect, display: false)
        positionAtBottomCenter()
        transcriptLabel.textColor = .white

        setAccessibilityLabel("Voice input recording")
        setAccessibilityElement(true)

        contentView?.wantsLayer = true
        contentView?.layer?.transform = CATransform3DScale(CATransform3DIdentity, 0.5, 0.5, 1)
        contentView?.layer?.opacity = 0
        alphaValue = 0
        orderFrontRegardless()

        waveformView.startAnimation()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            context.allowsImplicitAnimation = true
            self.contentView?.layer?.transform = CATransform3DIdentity
            self.contentView?.layer?.opacity = 1.0
            self.alphaValue = 1.0
        }
    }

    func hide(delay: TimeInterval = 0) {
        waveformView.stopAnimation()

        guard delay > 0 else {
            performHide()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performHide()
        }
    }

    private func performHide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.contentView?.layer?.transform = CATransform3DScale(CATransform3DIdentity, 0.5, 0.5, 1)
            self.contentView?.layer?.opacity = 0
            self.alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.contentView?.layer?.transform = CATransform3DIdentity
            self.contentView?.layer?.opacity = 1.0
            self.alphaValue = 1.0
            self.transcriptLabel.stringValue = ""
        })
    }

    func updateWaveform(rms: Float) {
        waveformView.updateRMS(rms)
    }

    func stopWaveform() {
        waveformView.stopAnimation()
    }

    func appendTranscript(_ text: String) {
        transcriptLabel.stringValue += text
        transcriptLabel.invalidateIntrinsicContentSize()
        recalculateWidth()
    }

    func showError(_ message: String) {
        if !isVisible {
            show()
        }
        transcriptLabel.textColor = NSColor.systemRed.withAlphaComponent(0.9)
        transcriptLabel.stringValue = "⚠︎ \(message)"
        transcriptLabel.invalidateIntrinsicContentSize()
        recalculateWidth()
    }

    // MARK: - Private

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelWidth = frame.width
        let x = visibleFrame.midX - panelWidth / 2
        let y = visibleFrame.minY + 20
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func recalculateWidth() {
        let labelWidth = transcriptLabel.intrinsicContentSize.width
        let clampedLabel = max(160, min(500, labelWidth))
        let newWidth: CGFloat = 16 + 44 + 8 + 1 + 10 + clampedLabel + 16

        var newFrame = frame
        let centerX = newFrame.midX
        newFrame.size.width = newWidth
        newFrame.origin.x = centerX - newWidth / 2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.setFrame(newFrame, display: true)
        }
    }
}

final class AutoSizingLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        guard let cell = self.cell else { return super.intrinsicContentSize }
        let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 500, height: 56))
        return NSSize(width: min(max(size.width, 160), 500), height: 24)
    }
}
