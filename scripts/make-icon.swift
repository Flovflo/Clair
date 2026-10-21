import AppKit

let output = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.33, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.075, green: 0.12, blue: 0.09, alpha: 1))!
    gradient.draw(in: shape, angle: -60)
    NSColor(calibratedRed: 0.72, green: 0.91, blue: 0.64, alpha: 0.18).setStroke()
    shape.lineWidth = 3
    shape.stroke()

    func sparkle(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: center.x, y: center.y + radius))
        p.curve(to: NSPoint(x: center.x + radius, y: center.y), controlPoint1: NSPoint(x: center.x + radius * 0.20, y: center.y + radius * 0.20), controlPoint2: NSPoint(x: center.x + radius * 0.20, y: center.y + radius * 0.20))
        p.curve(to: NSPoint(x: center.x, y: center.y - radius), controlPoint1: NSPoint(x: center.x + radius * 0.20, y: center.y - radius * 0.20), controlPoint2: NSPoint(x: center.x + radius * 0.20, y: center.y - radius * 0.20))
        p.curve(to: NSPoint(x: center.x - radius, y: center.y), controlPoint1: NSPoint(x: center.x - radius * 0.20, y: center.y - radius * 0.20), controlPoint2: NSPoint(x: center.x - radius * 0.20, y: center.y - radius * 0.20))
        p.curve(to: NSPoint(x: center.x, y: center.y + radius), controlPoint1: NSPoint(x: center.x - radius * 0.20, y: center.y + radius * 0.20), controlPoint2: NSPoint(x: center.x - radius * 0.20, y: center.y + radius * 0.20))
        p.close()
        color.setFill()
        p.fill()
    }
    let mint = NSColor(calibratedRed: 0.74, green: 0.93, blue: 0.65, alpha: 1)
    sparkle(NSPoint(x: 475, y: 490), 280, mint)
    sparkle(NSPoint(x: 735, y: 735), 85, mint.withAlphaComponent(0.8))
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let file = URL(fileURLWithPath: output).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try drawIcon(pixels: size * scale).write(to: file)
    }
}
