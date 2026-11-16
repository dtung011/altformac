// Renders AltForMac's artwork. Run from the repo root after changing the design:
//
//   swift scripts/make-art.swift
//
// Writes packaging/AppIcon.icns, packaging/dmg-background.png and site/icon.png.
// The outputs are committed, so scripts/package.sh does not need to run this.
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

// Spreadsheet greens.
let darkGreen = hex(0x185C37), green = hex(0x107C41), midGreen = hex(0x21A366)

/// Draws `draw` (in `points` coordinates, origin bottom-left) into a bitmap `scale` times larger.
func render(_ points: NSSize, scale: CGFloat, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(points.width * scale),
                               pixelsHigh: Int(points.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = points  // 72 dpi at 1x, 144 dpi at 2x
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color])
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: icon (1024 x 1024 design space, macOS template: 824 tile inset 100)

func drawIcon() {
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = hex(0x000000, 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 22
    shadow.set()
    green.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: midGreen, ending: green)!.draw(in: tilePath, angle: -90)

    // Spreadsheet grid.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    hex(0xFFFFFF, 0.13).setStroke()
    let grid = NSBezierPath()
    grid.lineWidth = 4
    for i in 1..<6 { let x = tile.minX + CGFloat(i) * tile.width / 6; grid.move(to: NSPoint(x: x, y: tile.minY)); grid.line(to: NSPoint(x: x, y: tile.maxY)) }
    for i in 1..<8 { let y = tile.minY + CGFloat(i) * tile.height / 8; grid.move(to: NSPoint(x: tile.minX, y: y)); grid.line(to: NSPoint(x: tile.maxX, y: y)) }
    grid.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Keycap: dark base for depth, then the white face.
    let key = NSRect(x: 232, y: 250, width: 560, height: 540)
    darkGreen.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: key.offsetBy(dx: 0, dy: -26), xRadius: 92, yRadius: 92).fill()
    let face = NSBezierPath(roundedRect: key, xRadius: 92, yRadius: 92)
    NSGradient(starting: hex(0xFFFFFF), ending: hex(0xE9F1EC))!.draw(in: face, angle: -90)

    let option = text("⌥", size: 190, weight: .semibold, color: green)
    let os = option.size()
    option.draw(at: NSPoint(x: key.maxX - os.width - 62, y: key.maxY - os.height - 40))

    let alt = text("alt", size: 250, weight: .bold, color: darkGreen)
    alt.draw(at: NSPoint(x: key.minX + 58, y: key.minY + 30))
}

// MARK: DMG background (660 x 400 points; icons sit at x 170 and 490, y 200 from the top)

func drawBackground() {
    let size = NSSize(width: 660, height: 400)
    hex(0xF6F8F7).setFill()
    NSRect(origin: .zero, size: size).fill()
    green.setFill()
    NSRect(x: 0, y: size.height - 6, width: size.width, height: 6).fill()

    let title = text("Drag AltForMac to Applications", size: 20, weight: .semibold, color: hex(0x252423))
    title.draw(at: NSPoint(x: (size.width - title.size().width) / 2, y: 330))

    // Arrow between the two icons (icon centres are 200 pt from the top = y 200 here).
    let y: CGFloat = 200, x0: CGFloat = 262, x1: CGFloat = 398
    green.setStroke()
    let shaft = NSBezierPath()
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: x0, y: y))
    shaft.line(to: NSPoint(x: x1 - 14, y: y))
    shaft.stroke()
    green.setFill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: x1 + 6, y: y))
    head.line(to: NSPoint(x: x1 - 22, y: y + 18))
    head.line(to: NSPoint(x: x1 - 22, y: y - 18))
    head.close()
    head.fill()

    let hint = text("First launch: right-click AltForMac in Applications and choose Open.",
                    size: 12.5, weight: .regular, color: hex(0x605E5C))
    hint.draw(at: NSPoint(x: (size.width - hint.size().width) / 2, y: 40))
}

// MARK: write files

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for mult in [1, 2] {
        let px = CGFloat(base * mult)
        let rep = render(NSSize(width: px, height: px), scale: 1) {
            NSGraphicsContext.current!.cgContext.scaleBy(x: px / 1024, y: px / 1024)
            drawIcon()
        }
        writePNG(rep, "\(iconset)/icon_\(base)x\(base)\(mult == 2 ? "@2x" : "").png")
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "packaging/AppIcon.icns"]
try! iconutil.run(); iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

writePNG(render(NSSize(width: 256, height: 256), scale: 1) {
    NSGraphicsContext.current!.cgContext.scaleBy(x: 0.25, y: 0.25); drawIcon()
}, "site/icon.png")

// A single 1x image (660 x 400 px at 72 dpi). Finder on macOS 26 drew the 2x image of a multi-resolution
// TIFF at double size, pushing the heading and arrow out of the window, so only 1x is shipped.
writePNG(render(NSSize(width: 660, height: 400), scale: 1, drawBackground), "packaging/dmg-background.png")

print("wrote packaging/AppIcon.icns, packaging/dmg-background.png, site/icon.png")
