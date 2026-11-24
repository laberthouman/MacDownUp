import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func makePNG(side: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    let scale = CGFloat(side) / 512
    graphics.cgContext.scaleBy(x: scale, y: scale)
    func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }
    func gradient(_ path: NSBezierPath, _ hexes: [UInt32], angle: CGFloat) {
        NSGradient(colors: hexes.map { color($0) })!.draw(in: path, angle: angle)
    }
    func stroke(_ path: NSBezierPath, _ shade: NSColor, _ width: CGFloat) {
        shade.setStroke(); path.lineWidth = width; path.stroke()
    }

    let plate = round(44, 44, 424, 424, 98)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x18365F, 0.24)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    color(0xE4EBF3).setFill(); plate.fill()
    NSGraphicsContext.restoreGraphicsState()
    gradient(plate, [0xDCE5F0, 0xF7FAFF, 0xFFFFFF], angle: 90)
    stroke(round(46, 46, 420, 420, 96), .white.withAlphaComponent(0.85), 2)

    let tile = round(114, 173, 284, 244, 52)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x1B59B9, 0.30)
    tileShadow.shadowBlurRadius = 16
    tileShadow.shadowOffset = NSSize(width: 0, height: -8)
    tileShadow.set()
    color(0x1465EA).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    gradient(tile, [0x0751DC, 0x118EFA, 0x86EDEB], angle: 55)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    for i in 0..<5 {
        let shift = CGFloat(i) * 23
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 88, y: 210 + shift))
        ribbon.curve(to: NSPoint(x: 450, y: 306 + shift), controlPoint1: NSPoint(x: 282, y: 500 + shift), controlPoint2: NSPoint(x: 224, y: 148 + shift))
        ribbon.line(to: NSPoint(x: 450, y: 465)); ribbon.line(to: NSPoint(x: 88, y: 465)); ribbon.close()
        NSGradient(colors: [color(0xFFFFFF, 0.12), color(0xA7FDFF, 0.24)])!.draw(in: ribbon, angle: 55)
        stroke(ribbon, .white.withAlphaComponent(0.14), 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    stroke(tile, .white.withAlphaComponent(0.55), 1.5)

    // A luminous download arrow floats above an aluminium installer tray.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 256, y: 352))
    arrow.line(to: NSPoint(x: 256, y: 258))
    arrow.move(to: NSPoint(x: 217, y: 294))
    arrow.line(to: NSPoint(x: 256, y: 255))
    arrow.line(to: NSPoint(x: 295, y: 294))
    arrow.lineWidth = 21
    arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let arrowShadow = NSShadow()
    arrowShadow.shadowColor = color(0x003B93, 0.30)
    arrowShadow.shadowBlurRadius = 5
    arrowShadow.shadowOffset = NSSize(width: 0, height: -3)
    arrowShadow.set()
    NSColor.white.setStroke(); arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let tray = round(117, 112, 278, 98, 29)
    NSGraphicsContext.saveGraphicsState()
    let trayShadow = NSShadow()
    trayShadow.shadowColor = color(0x274875, 0.26)
    trayShadow.shadowBlurRadius = 13
    trayShadow.shadowOffset = NSSize(width: 0, height: -9)
    trayShadow.set()
    color(0xB9C8DB).setFill(); tray.fill()
    NSGraphicsContext.restoreGraphicsState()
    gradient(tray, [0xA8B8CD, 0xDEE7F0, 0xFFFFFF], angle: 90)
    stroke(round(118, 113, 276, 96, 28), .white.withAlphaComponent(0.85), 1.5)
    let slot = round(170, 176, 172, 9, 4.5)
    gradient(slot, [0x829AB8, 0xC3D1E0], angle: 90)
    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 137, y: 153)); seam.line(to: NSPoint(x: 375, y: 153))
    stroke(seam, color(0x91A6C0, 0.35), 1)
    let light = NSBezierPath(ovalIn: NSRect(x: 354, y: 130, width: 6, height: 6))
    color(0x008CF9).setFill(); light.fill()
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, pixels) in sizes {
    try makePNG(side: pixels).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
}
