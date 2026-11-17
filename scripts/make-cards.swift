// Renders the intro and outro cards of the promo video and GIF. Run from the repo root:
//
//   swift scripts/make-cards.swift
//
// Writes packaging/promo-intro.png and packaging/promo-outro.png (1600 x 894, same size as the video).
// The logo is the app icon (packaging/AppIcon.icns). scripts/make-promo-clips.py puts the cards around the clips.
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let size = NSSize(width: 1600, height: 894)
let green = hex(0x107C41), midGreen = hex(0x21A366)

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color, .kern: kern])
}

/// Draws a string centered on x, with its baseline box centered at y (bottom-left origin).
func center(_ s: NSAttributedString, y: CGFloat) {
    let w = s.size().width, h = s.size().height
    s.draw(at: NSPoint(x: (size.width - w) / 2, y: y - h / 2))
}

func render(_ path: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    // Dark ground like Excel's dark mode, with a soft green glow behind the logo.
    hex(0x1B1B1C).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSGradient(colors: [green.withAlphaComponent(0.55), green.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: size.width / 2, y: size.height * 0.60), radius: 0,
              toCenter: NSPoint(x: size.width / 2, y: size.height * 0.60), radius: 560, options: [])
    // Faint spreadsheet grid, the same idea as the icon.
    hex(0xFFFFFF, 0.045).setStroke()
    let grid = NSBezierPath()
    var x: CGFloat = 0
    while x <= size.width { grid.move(to: NSPoint(x: x, y: 0)); grid.line(to: NSPoint(x: x, y: size.height)); x += 80 }
    var y: CGFloat = 0
    while y <= size.height { grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: size.width, y: y)); y += 80 }
    grid.lineWidth = 1
    grid.stroke()

    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

guard let logo = NSImage(contentsOfFile: "packaging/AppIcon.icns") else { fatalError("run from the repo root") }

func drawLogo(side: CGFloat, centerY: CGFloat) {
    logo.draw(in: NSRect(x: (size.width - side) / 2, y: centerY - side / 2, width: side, height: side),
              from: .zero, operation: .sourceOver, fraction: 1)
}

render("packaging/promo-intro.png") {
    drawLogo(side: 340, centerY: 560)
    center(text("AltForMac", size: 118, weight: .bold, color: .white, kern: -1.5), y: 320)
    center(text("Windows Alt shortcuts for Excel, Word and PowerPoint on Mac", size: 38, weight: .regular,
                color: hex(0xC8C8C8)), y: 235)
    center(text("\u{2325}  H  O  I", size: 34, weight: .semibold, color: midGreen, kern: 4), y: 150)
}

render("packaging/promo-outro.png") {
    drawLogo(side: 270, centerY: 600)
    center(text("AltForMac", size: 104, weight: .bold, color: .white, kern: -1.2), y: 395)
    center(text("Free and open source", size: 36, weight: .regular, color: hex(0xC8C8C8)), y: 320)

    // Address in a green pill, like the site's download button.
    let label = text("dtung011.github.io/altformac", size: 42, weight: .semibold, color: .white)
    let w = label.size().width + 90, h: CGFloat = 86
    let pill = NSRect(x: (size.width - w) / 2, y: 190, width: w, height: h)
    let path = NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2)
    green.setFill()
    path.fill()
    label.draw(at: NSPoint(x: pill.minX + 45, y: pill.midY - label.size().height / 2))

    center(text("Not affiliated with Microsoft. Excel, Word and PowerPoint are trademarks of Microsoft.", size: 22,
                weight: .regular, color: hex(0x8C8C8C)), y: 75)
}
