import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-app-icon.swift <output.iconset>\n".utf8))
    exit(EXIT_FAILURE)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func drawIcon() {
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.saveGraphicsState()

    let background = NSBezierPath(
        roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928),
        xRadius: 215,
        yRadius: 215
    )
    NSGradient(
        starting: NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.22, alpha: 1),
        ending: NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.52, alpha: 1)
    )?.draw(in: background, angle: -35)

    let glow = NSBezierPath(ovalIn: NSRect(x: 180, y: 420, width: 680, height: 520))
    NSColor(calibratedWhite: 1, alpha: 0.07).setFill()
    glow.fill()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.32)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()

    let mouseBody = NSBezierPath()
    mouseBody.move(to: NSPoint(x: 512, y: 142))
    mouseBody.curve(
        to: NSPoint(x: 286, y: 500),
        controlPoint1: NSPoint(x: 362, y: 156),
        controlPoint2: NSPoint(x: 274, y: 286)
    )
    mouseBody.curve(
        to: NSPoint(x: 512, y: 886),
        controlPoint1: NSPoint(x: 296, y: 720),
        controlPoint2: NSPoint(x: 378, y: 862)
    )
    mouseBody.curve(
        to: NSPoint(x: 738, y: 500),
        controlPoint1: NSPoint(x: 646, y: 862),
        controlPoint2: NSPoint(x: 728, y: 720)
    )
    mouseBody.curve(
        to: NSPoint(x: 512, y: 142),
        controlPoint1: NSPoint(x: 750, y: 286),
        controlPoint2: NSPoint(x: 662, y: 156)
    )
    mouseBody.close()

    NSGradient(
        starting: NSColor(calibratedWhite: 0.98, alpha: 1),
        ending: NSColor(calibratedWhite: 0.72, alpha: 1)
    )?.draw(in: mouseBody, angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()

    mouseBody.lineWidth = 9
    NSColor(calibratedWhite: 0.08, alpha: 0.24).setStroke()
    mouseBody.stroke()

    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 512, y: 876))
    divider.line(to: NSPoint(x: 512, y: 618))
    divider.lineWidth = 8
    divider.lineCapStyle = .round
    NSColor(calibratedWhite: 0.10, alpha: 0.22).setStroke()
    divider.stroke()

    let centerWheel = NSBezierPath(
        roundedRect: NSRect(x: 477, y: 662, width: 70, height: 126),
        xRadius: 34,
        yRadius: 34
    )
    NSColor(calibratedWhite: 0.16, alpha: 0.72).setFill()
    centerWheel.fill()

    let thumbwheelShadow = NSShadow()
    thumbwheelShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.3)
    thumbwheelShadow.shadowBlurRadius = 16
    thumbwheelShadow.shadowOffset = NSSize(width: -4, height: -7)
    thumbwheelShadow.set()

    let thumbwheel = NSBezierPath(
        roundedRect: NSRect(x: 246, y: 450, width: 112, height: 214),
        xRadius: 54,
        yRadius: 54
    )
    NSGradient(
        starting: NSColor(calibratedRed: 1.00, green: 0.73, blue: 0.22, alpha: 1),
        ending: NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.10, alpha: 1)
    )?.draw(in: thumbwheel, angle: -20)

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()

    let grooveColor = NSColor(calibratedWhite: 0.22, alpha: 0.42)
    grooveColor.setStroke()
    for y in stride(from: 484.0, through: 630.0, by: 29.0) {
        let groove = NSBezierPath()
        groove.move(to: NSPoint(x: 270, y: y))
        groove.line(to: NSPoint(x: 334, y: y))
        groove.lineWidth = 7
        groove.lineCapStyle = .round
        groove.stroke()
    }

    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: 390, y: 815))
    highlight.curve(
        to: NSPoint(x: 354, y: 602),
        controlPoint1: NSPoint(x: 342, y: 760),
        controlPoint2: NSPoint(x: 328, y: 676)
    )
    highlight.lineWidth = 12
    highlight.lineCapStyle = .round
    NSColor(calibratedWhite: 1, alpha: 0.32).setStroke()
    highlight.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

func makePNG(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "ThumbwheelRemapperIcon", code: 1)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ThumbwheelRemapperIcon", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ThumbwheelRemapperIcon", code: 3)
    }
    return data
}

let outputs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for output in outputs {
    let data = try makePNG(pixelSize: output.size)
    try data.write(to: outputURL.appendingPathComponent(output.name))
}
