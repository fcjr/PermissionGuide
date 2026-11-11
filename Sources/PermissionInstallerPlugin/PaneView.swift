import AppKit

/// Layout shared by every pane, modeled on Installer's own Summary pane: a large symbol,
/// a bold title and centered text, with the pane's controls below. Sized for Installer's
/// content area, which is 418×329 pt.
@MainActor
final class PaneView {
    static let size = NSSize(width: 418, height: 329)
    private static let margin: CGFloat = 16

    let view = NSView(frame: NSRect(origin: .zero, size: PaneView.size))
    private let stack = NSStackView()
    private weak var scroller: NSScrollView?
    private static let textWidth: CGFloat = 360

    /// - Parameter compact: Shrinks the image and the gaps, for a pane with a lot to show.
    init(image: NSImage?, heading: String, message: String, compact: Bool = false) {
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.autoresizingMask = [.width, .height]
        view.addSubview(stack)
        // Centered, and never taller than the pane. Installer grows a pane's view to fit
        // content that asks for more and shows the bottom of it, which cuts off the top,
        // so content that's too tall has to shrink instead (see `addScrolling`).
        let centered = stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centered.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centered,
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: Self.margin),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -Self.margin),
            stack.heightAnchor.constraint(lessThanOrEqualToConstant: Self.size.height - 2 * Self.margin),
        ])

        if let image {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            let side: CGFloat = compact ? 40 : 56
            imageView.widthAnchor.constraint(equalToConstant: side).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: side).isActive = true
            stack.addArrangedSubview(imageView)
            stack.setCustomSpacing(compact ? 10 : 14, after: imageView)
        }

        let headingLabel = Self.label(heading)
        headingLabel.font = .boldSystemFont(ofSize: 17)
        stack.addArrangedSubview(headingLabel)

        if !message.isEmpty {
            let body = Self.label(message, color: .secondaryLabelColor)
            stack.addArrangedSubview(body)
            stack.setCustomSpacing(compact ? 12 : 18, after: body)
        }
    }

    func add(_ subview: NSView, spacingAfter: CGFloat? = nil) {
        stack.addArrangedSubview(subview)
        if let spacingAfter { stack.setCustomSpacing(spacingAfter, after: subview) }
    }

    /// Adds `content` at its own height when there's room, and in a scrolling area that
    /// takes the height left over when there isn't, such as a long list of steps.
    func addScrolling(_ content: NSView) {
        let scroll = NSScrollView()
        scroll.contentView = TopAlignedClipView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = content
        scroller = scroll
        content.translatesAutoresizingMaskIntoConstraints = false
        let fits = scroll.heightAnchor.constraint(equalTo: content.heightAnchor)
        fits.priority = .defaultLow
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroll.heightAnchor.constraint(lessThanOrEqualTo: content.heightAnchor),
            fits,
        ])
        stack.addArrangedSubview(scroll)
    }

    /// Shows the scroll bar for a moment when there's more than fits, so it's clear the
    /// content scrolls.
    func flashScrollers() {
        scroller?.flashScrollers()
    }

    static func label(_ text: String, small: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: small ? NSFont.smallSystemFontSize : NSFont.systemFontSize)
        label.textColor = color
        label.alignment = .center
        label.preferredMaxLayoutWidth = textWidth
        return label
    }

    /// An SF Symbol in the given color, sized for the top of a pane.
    static func symbol(_ name: String, color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .regular)
                .applying(.init(hierarchicalColor: color)))
    }
}

/// Starts a scroll view at the top of its content, like a list.
private final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
