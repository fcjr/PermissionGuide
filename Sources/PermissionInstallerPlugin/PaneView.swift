import AppKit

/// Layout shared by every pane, modeled on Installer's own Summary pane: a large symbol,
/// a bold title and centered text, with the pane's controls below. Sized for Installer's
/// content area, which is 418×329 pt.
@MainActor
final class PaneView {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 418, height: 329))
    private let stack = NSStackView()
    private static let textWidth: CGFloat = 360

    init(image: NSImage?, heading: String, message: String) {
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.autoresizingMask = [.width, .height]
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 16),
        ])

        if let image {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.widthAnchor.constraint(equalToConstant: 56).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 56).isActive = true
            stack.addArrangedSubview(imageView)
            stack.setCustomSpacing(14, after: imageView)
        }

        let headingLabel = Self.label(heading)
        headingLabel.font = .boldSystemFont(ofSize: 17)
        stack.addArrangedSubview(headingLabel)

        if !message.isEmpty {
            let body = Self.label(message, color: .secondaryLabelColor)
            stack.addArrangedSubview(body)
            stack.setCustomSpacing(18, after: body)
        }
    }

    func add(_ subview: NSView, spacingAfter: CGFloat? = nil) {
        stack.addArrangedSubview(subview)
        if let spacingAfter { stack.setCustomSpacing(spacingAfter, after: subview) }
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
