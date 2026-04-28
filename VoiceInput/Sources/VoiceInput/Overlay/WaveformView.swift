import AppKit

final class WaveformView: NSView {
    private var displayLink: CVDisplayLink?
    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let barCount = 5
    private let barWidth: CGFloat = 5
    private let barGap: CGFloat = 3
    private let barMaxHeight: CGFloat = 28

    private var smoothedLevels: [CGFloat] = [0, 0, 0, 0, 0]
    private var targetLevels: [CGFloat] = [0, 0, 0, 0, 0]
    private let attackFactor: CGFloat = 0.4
    private let releaseFactor: CGFloat = 0.15

    private var currentRMS: Float = 0 {
        didSet {
            for i in 0..<barCount {
                let jitter = CGFloat.random(in: -0.04...0.04)
                let weighted = CGFloat(currentRMS) * barWeights[i] * (1.0 + jitter)
                targetLevels[i] = max(0, min(1, weighted))
            }
        }
    }

    func updateRMS(_ rms: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.currentRMS = rms
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for i in 0..<barCount {
            if targetLevels[i] > smoothedLevels[i] {
                smoothedLevels[i] += (targetLevels[i] - smoothedLevels[i]) * attackFactor
            } else {
                smoothedLevels[i] += (targetLevels[i] - smoothedLevels[i]) * releaseFactor
            }

            let barHeight = max(5, smoothedLevels[i] * barMaxHeight)
            let x = bounds.minX + CGFloat(i) * (barWidth + barGap)
            let y = bounds.midY - barHeight / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)

            // Bright cyan accent for active bars, dim for idle
            let alpha: CGFloat = smoothedLevels[i] > 0.02 ? 1.0 : 0.3
            let color: NSColor
            if smoothedLevels[i] > 0.02 {
                color = NSColor(red: 0.35, green: 0.92, blue: 0.95, alpha: alpha)
            } else {
                color = NSColor.white.withAlphaComponent(alpha)
            }
            context.setFillColor(color.cgColor)
            path.fill()
        }
    }

    func startAnimation() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let displayLink = link else { return }
        self.displayLink = displayLink

        CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, userInfo in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<WaveformView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { view.needsDisplay = true }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(displayLink)
    }

    func stopAnimation() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
        smoothedLevels = [0, 0, 0, 0, 0]
        targetLevels = [0, 0, 0, 0, 0]
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 32) }
}
