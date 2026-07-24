import Cocoa

// Renders the ChatterFix app icon (a keyboard with one misbehaving red key)
// to a 1024x1024 PNG. Usage: make_icon <output.png>

guard CommandLine.arguments.count == 2 else {
    print("usage: make_icon <output.png>")
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: rounded square with a subtle vertical gradient.
let bgRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
let top = NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.42, alpha: 1)
let bottom = NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.25, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: bgPath, angle: -90)

func drawKey(x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 110),
                 xRadius: 22, yRadius: 22).fill()
}

let keyWhite = NSColor(calibratedWhite: 0.95, alpha: 0.95)
let keyRed = NSColor(calibratedRed: 0.93, green: 0.33, blue: 0.31, alpha: 1)

// Three rows of five keys plus a space bar; one key drawn red (the chatterer),
// with a red "ghost" echo above it to suggest the double-press.
let keyWidth: CGFloat = 110
let gap: CGFloat = 30
let startX = (1024 - (5 * keyWidth + 4 * gap)) / 2
for (rowIndex, y) in [CGFloat(390), 530, 670].enumerated() {
    for column in 0..<5 {
        let x = startX + CGFloat(column) * (keyWidth + gap)
        let isBadKey = rowIndex == 1 && column == 3
        drawKey(x: x, y: y, width: keyWidth, color: isBadKey ? keyRed : keyWhite)
        if isBadKey {
            keyRed.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + 28,
                                             width: keyWidth, height: 110),
                         xRadius: 22, yRadius: 22).fill()
        }
    }
}
drawKey(x: (1024 - 450) / 2, y: 250, width: 450, color: keyWhite)

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
