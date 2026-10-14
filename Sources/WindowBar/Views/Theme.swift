import AppKit

var accent: NSColor { .controlAccentColor }

func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: text,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
            .paragraphStyle: style,
        ]
    ).draw(in: rect)
}
