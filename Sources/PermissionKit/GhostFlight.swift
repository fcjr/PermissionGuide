import AppKit
import QuartzCore

/// Click-through panel above the sidecar that loops a hand grabbing a copy of the icon,
/// carrying it in an arc to the target and dropping it in.
final class GhostFlight: NSPanel {
    private let carrier = CALayer()
    private let ghost = CALayer()
    private let hand = CALayer()
    private let openHand = NSCursor.openHand.image
    private let closedHand = NSCursor.closedHand.image
    private var start: CGPoint?
    private var end: CGPoint?

    init(icon: NSImage) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        let view = NSView()
        view.wantsLayer = true
        contentView = view
        carrier.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
        carrier.opacity = 0
        view.layer!.addSublayer(carrier)

        ghost.contents = icon
        ghost.frame = carrier.bounds
        ghost.shadowOpacity = 0.35
        ghost.shadowRadius = 10
        ghost.shadowOffset = CGSize(width: 0, height: -4)
        carrier.addSublayer(ghost)

        // The hand grips the icon just below its center, like the pointer mid-drag.
        let handSize = NSSize(width: openHand.size.width * 1.4, height: openHand.size.height * 1.4)
        hand.contents = openHand
        hand.bounds = CGRect(origin: .zero, size: handSize)
        hand.position = CGPoint(x: carrier.bounds.midX + 6, y: carrier.bounds.midY - 10)
        hand.shadowOpacity = 0.3
        hand.shadowRadius = 2
        hand.shadowOffset = CGSize(width: 0, height: -1)
        carrier.addSublayer(hand)
    }

    /// Flies from `start` to `end` (screen coordinates), restarting only when they move.
    func fly(from start: NSPoint, to end: NSPoint, on screen: NSScreen) {
        if frame != screen.frame { setFrame(screen.frame, display: false) }
        let origin = screen.frame.origin
        let start = CGPoint(x: start.x - origin.x, y: start.y - origin.y)
        let end = CGPoint(x: end.x - origin.x, y: end.y - origin.y)
        if let s = self.start, let e = self.end, s.distance(to: start) < 2, e.distance(to: end) < 2 { return }
        self.start = start
        self.end = end
        animate(from: start, to: end)
    }

    private func animate(from start: CGPoint, to end: CGPoint) {
        let lift = 0.35, travel = 1.2, drop = 0.4, rest = 1.1
        let total = lift + travel + drop + rest
        func t(_ seconds: Double) -> NSNumber { NSNumber(value: seconds / total) }

        let arc = min(140, start.distance(to: end) * 0.3)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + arc))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.beginTime = lift
        move.duration = travel
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.fillMode = .both

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.9, 0.9, 0, 0]
        opacity.keyTimes = [0, t(lift), t(lift + travel), t(lift + travel + drop), 1]
        opacity.duration = total

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.15, 1, 0.7, 0.7]
        scale.keyTimes = opacity.keyTimes
        scale.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.3, 1.6, 0.5, 1),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .linear),
        ]
        scale.duration = total

        let carry = CAAnimationGroup()
        carry.animations = [move, opacity]
        carry.duration = total
        carry.repeatCount = .infinity

        scale.repeatCount = .infinity

        // Open hand while reaching for the icon, closed while carrying, open again to drop.
        let grip = CAKeyframeAnimation(keyPath: "contents")
        grip.values = [openHand, closedHand, openHand]
        grip.keyTimes = [0, t(lift * 0.6), t(lift + travel), 1]
        grip.calculationMode = .discrete
        grip.duration = total
        grip.repeatCount = .infinity

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        carrier.position = start
        removeAnimations()
        carrier.add(carry, forKey: "flight")
        ghost.add(scale, forKey: "flight")
        hand.add(grip, forKey: "flight")
        CATransaction.commit()
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        start = nil
        end = nil
        removeAnimations()
    }

    private func removeAnimations() {
        [carrier, ghost, hand].forEach { $0.removeAllAnimations() }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
