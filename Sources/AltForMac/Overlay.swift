import AppKit

struct HUDItem {
    let key: Character
    let label: String
}

/// Borderless, non-activating panel that shows the typed keys and the letters that can follow.
/// It never takes focus, so Excel stays the key window.
final class Overlay {
    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    /// Focused Excel window frame in screen coordinates (top-left origin). Geometry only.
    var anchor: CGRect?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // The HUD is always dark. Pin the appearance, otherwise the text colors follow the system theme and
        // come out dark-on-dark (unreadable) when macOS is in Light mode.
        effect.appearance = NSAppearance(named: .vibrantDark)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byClipping
        effect.addSubview(label)
        panel.contentView = effect
    }

    /// Builds the window server resources once, invisibly, so the first real HUD appears instantly.
    func prewarm() {
        panel.alphaValue = 0
        present(NSAttributedString(string: "\u{2325}  W V\nG  Gridlines"))
        DispatchQueue.main.async { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        }
    }

    func show(typed: String, items: [HUDItem]) {
        cancelHide()
        let text = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        let body = NSFont.systemFont(ofSize: 14, weight: .medium)
        text.append(NSAttributedString(string: "\u{2325}  " + typed.map(String.init).joined(separator: " "),
                                       attributes: [.font: mono, .foregroundColor: NSColor.white]))
        for item in items {
            text.append(NSAttributedString(string: "\n"))
            text.append(NSAttributedString(string: String(item.key) + "  ",
                                           attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                                                        .foregroundColor: NSColor(calibratedRed: 0.40, green: 0.78, blue: 1.0, alpha: 1)]))
            text.append(NSAttributedString(string: item.label,
                                           attributes: [.font: body, .foregroundColor: NSColor(white: 0.96, alpha: 1)]))
        }
        present(text)
    }

    func flash(_ message: String, isError: Bool, duration: TimeInterval = 1.2) {
        cancelHide()
        let color: NSColor = isError ? NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.42, alpha: 1) : .white
        present(NSAttributedString(string: message,
                                   attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                .foregroundColor: color]))
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        cancelHide()
        panel.orderOut(nil)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func present(_ text: NSAttributedString) {
        label.attributedStringValue = text
        let pad: CGFloat = 14
        let size = label.sizeThatFits(NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude))
        let content = NSSize(width: max(size.width + pad * 2, 160), height: size.height + pad * 2)
        label.frame = NSRect(x: pad, y: pad, width: content.width - pad * 2, height: size.height)
        panel.setContentSize(content)
        panel.setFrameOrigin(origin(for: content))
        panel.orderFrontRegardless()
    }

    private func origin(for size: NSSize) -> NSPoint {
        if let anchor, let primary = NSScreen.screens.first {
            // Screen coordinates here have a top-left origin; Cocoa's have bottom-left.
            let x = anchor.midX - size.width / 2
            let topY = anchor.minY + 150
            return NSPoint(x: x, y: primary.frame.height - topY - size.height)
        }
        let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - 200 - size.height)
    }
}
