import AppKit

let accent = NSColor(calibratedRed: 0.43, green: 0.68, blue: 1, alpha: 1)

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
