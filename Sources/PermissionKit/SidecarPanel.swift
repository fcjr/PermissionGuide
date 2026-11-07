import AppKit

/// Floating panel docked beside System Settings that shows the app icon (draggable when
/// `dragURL` is set) and instructions.
final class SidecarPanel: NSPanel {
    let iconView: DraggableIconView
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?

    /// Narrower than System Settings' sidebar so it can sit over it when there's no room beside the window.
    private static let width: CGFloat = 216
    private var size = NSSize(width: width, height: 300)
    private let arrow = NSImageView()
    private let titleLabel: NSTextField
    private let hint: NSTextField
    private let background = NSVisualEffectView()

    init(title: String, message: String, icon: NSImage, dragURL: URL?, showsDone: Bool, tint: NSColor) {
        iconView = DraggableIconView(image: icon, fileURL: dragURL)
        titleLabel = NSTextField(wrappingLabelWithString: title)
        hint = NSTextField(wrappingLabelWithString: message)
        super.init(contentRect: NSRect(origin: .zero, size: NSSize(width: Self.width, height: 300)),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false

        background.material = .hudWindow
        background.state = .active
        // maskImage clips the material itself (and the window shadow follows it);
        // a layer cornerRadius alone leaves square corners showing.
        background.maskImage = .roundedRectMask(radius: 16)
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.borderWidth = 1
        background.layer?.borderColor = tint.withAlphaComponent(0.6).cgColor
        contentView = background

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center

        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        arrow.contentTintColor = tint
        arrow.symbolConfiguration = .init(pointSize: 18, weight: .bold)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.controlSize = .small
        let buttons = NSStackView(views: [cancel])
        if showsDone {
            let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
            done.controlSize = .small
            done.keyEquivalent = "\r"
            buttons.addArrangedSubview(done)
        }

        let stack = NSStackView(views: [titleLabel, iconView, hint, arrow, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            titleLabel.widthAnchor.constraint(equalTo: hint.widthAnchor),
        ])
        // Wrapping labels need a max width before the stack can report its height.
        hint.preferredMaxLayoutWidth = Self.width - 32
        titleLabel.preferredMaxLayoutWidth = Self.width - 32
        size.height = ceil(background.fittingSize.height)
        setContentSize(size)
    }

    var instructionTitle: String { titleLabel.stringValue }
    var instructionMessage: String { hint.stringValue }

    /// Replaces the instructions, keeping the panel's top edge in place.
    func show(title: String, message: String) {
        titleLabel.stringValue = title
        hint.stringValue = message
        let top = frame.maxY
        size.height = ceil(background.fittingSize.height)
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    var iconScreenCenter: NSPoint {
        let rect = convertToScreen(iconView.convert(iconView.bounds, to: nil))
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    /// Docks to the right of the window, else the left, else over its sidebar.
    func position(beside window: NSRect, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let gap: CGFloat = 16
        let x: CGFloat
        let pointsLeft: Bool
        if window.maxX + gap + size.width <= visible.maxX {
            x = window.maxX + gap
            pointsLeft = true
        } else if window.minX - gap - size.width >= visible.minX {
            x = window.minX - gap - size.width
            pointsLeft = false
        } else {
            x = window.minX + (SystemSettings.sidebarWidth - size.width) / 2
            pointsLeft = false
        }
        let origin = NSPoint(
            x: min(max(x, visible.minX), visible.maxX - size.width),
            y: min(max(window.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
        arrow.image = NSImage(systemSymbolName: pointsLeft ? "arrow.left" : "arrow.right", accessibilityDescription: nil)
        layoutIfNeeded()
    }

    @objc private func cancelClicked() { onCancel?() }
    @objc private func doneClicked() { onDone?() }
}

/// The app icon, as a drag source when `fileURL` is set. Dropping an app's file URL into
/// a privacy list in System Settings adds it, skipping the "+" file picker.
final class DraggableIconView: NSView, NSDraggingSource {
    var onDragChanged: ((Bool) -> Void)?
    private let fileURL: URL?
    private let image: NSImage

    init(image: NSImage, fileURL: URL?) {
        self.image = image
        self.fileURL = fileURL
        super.init(frame: .zero)
        if fileURL != nil {
            toolTip = "Drag into the list in System Settings"
            setAccessibilityLabel("App icon. Drag into the list in System Settings to grant access.")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 88, height: 88) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        if fileURL != nil { addCursorRect(bounds, cursor: .openHand) }
    }
    override func draw(_ dirtyRect: NSRect) { image.draw(in: bounds) }
    override func mouseDown(with event: NSEvent) {
        if fileURL != nil { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fileURL else { return }
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        alphaValue = 0.35
        onDragChanged?(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        onDragChanged?(false)
    }
}

private extension NSImage {
    static func roundedRectMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
