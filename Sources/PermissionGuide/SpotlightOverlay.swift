import AppKit
import QuartzCore

/// Click-through panel covering one screen. Dims the System Settings window except for the
/// target (an app list or extension switches) and outlines it.
final class SpotlightOverlay: NSPanel {
    private let dimLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let tint: NSColor

    init(tint: NSColor) {
        self.tint = tint
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        let view = NSView()
        view.wantsLayer = true
        contentView = view
        let root = view.layer!

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        root.addSublayer(dimLayer)

        ringLayer.fillColor = tint.withAlphaComponent(0.08).cgColor
        ringLayer.strokeColor = tint.cgColor
        ringLayer.lineWidth = 3
        ringLayer.shadowColor = tint.cgColor
        ringLayer.shadowOpacity = 0.9
        ringLayer.shadowOffset = .zero
        root.addSublayer(ringLayer)

        let pulse = CABasicAnimation(keyPath: "shadowRadius")
        pulse.fromValue = 6
        pulse.toValue = 18
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ringLayer.add(pulse, forKey: "pulse")
    }

    func update(screen: NSScreen, window: NSRect, target: NSRect) {
        setFrame(screen.frame, display: false)
        let origin = screen.frame.origin
        let windowRect = window.offsetBy(dx: -origin.x, dy: -origin.y)
        let listRect = target.offsetBy(dx: -origin.x, dy: -origin.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dim = CGMutablePath()
        dim.addRoundedRect(in: windowRect, cornerWidth: 12, cornerHeight: 12)
        dim.addRoundedRect(in: listRect, cornerWidth: 10, cornerHeight: 10)
        dimLayer.path = dim
        ringLayer.path = CGPath(roundedRect: listRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
    }

    func setDragging(_ dragging: Bool) {
        ringLayer.lineWidth = dragging ? 5 : 3
        ringLayer.fillColor = tint.withAlphaComponent(dragging ? 0.18 : 0.08).cgColor
    }
}
