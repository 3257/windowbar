import AppKit

final class WindowGroupButton: NSButton {
    var onToggle: (() -> Void)?
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 11, weight: .medium)
        lineBreakMode = .byTruncatingTail
        target = self
        action = #selector(toggle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func toggle() { onToggle?() }
}
