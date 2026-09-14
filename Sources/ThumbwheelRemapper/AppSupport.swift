import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ThumbwheelRemapperCore

final class PageDistanceResolver {
    private static let accessibilityTimeout: Float = 0.05
    private static let maximumPageDistance = 10_000.0
    private static let scrollAreaRoles = [
        kAXScrollAreaRole as String,
        "AXWebArea",
    ]

    static func distance(at point: CGPoint) -> Double {
        if let height = scrollAreaOrWindowHeight(at: point) {
            return normalized(height)
        }
        return normalized(displayHeight(at: point))
    }

    private static func scrollAreaOrWindowHeight(at point: CGPoint) -> CGFloat? {
        let systemWideElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWideElement, accessibilityTimeout)

        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        ) == .success, var currentElement = hitElement else {
            return nil
        }
        AXUIElementSetMessagingTimeout(currentElement, accessibilityTimeout)

        var windowHeight: CGFloat?
        for _ in 0..<12 {
            if let role = attribute(kAXRoleAttribute as CFString, of: currentElement) as? String {
                if scrollAreaRoles.contains(role),
                   let size = size(of: currentElement),
                   size.height > 0 {
                    return size.height
                }
                if role == kAXWindowRole as String,
                   let size = size(of: currentElement),
                   size.height > 0 {
                    windowHeight = size.height
                }
            }

            guard let parent = attribute(kAXParentAttribute as CFString, of: currentElement),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }
            currentElement = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return windowHeight
    }

    private static func displayHeight(at point: CGPoint) -> CGFloat {
        var displayID = CGMainDisplayID()
        var displayCount: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &displayID, &displayCount) == .success,
           displayCount > 0 {
            return CGDisplayBounds(displayID).height
        }
        return CGDisplayBounds(CGMainDisplayID()).height
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        guard let value = attribute(kAXSizeAttribute as CFString, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    private static func normalized(_ height: CGFloat) -> Double {
        min(max(Double(height), 5), maximumPageDistance)
    }
}

private final class JoystickHUDView: NSView {
    var verticalSpeedMultiplier = 0.0
    var horizontalSpeedMultiplier = 0.0

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = NSPoint(x: bounds.midX, y: bounds.midY + 10)
        let dialRect = NSRect(x: center.x - 27, y: center.y - 27, width: 54, height: 54)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: dialRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.gridColor.setStroke()
        let border = NSBezierPath(ovalIn: dialRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let track = NSBezierPath()
        track.move(to: NSPoint(x: center.x, y: center.y - 17))
        track.line(to: NSPoint(x: center.x, y: center.y + 17))
        track.move(to: NSPoint(x: center.x - 17, y: center.y))
        track.line(to: NSPoint(x: center.x + 17, y: center.y))
        track.lineWidth = 2
        NSColor.tertiaryLabelColor.setStroke()
        track.stroke()

        let normalizedVertical = min(max(verticalSpeedMultiplier / 3, -1), 1)
        let normalizedHorizontal = min(max(horizontalSpeedMultiplier / 3, -1), 1)
        let knobPoint = NSPoint(
            x: center.x + (normalizedHorizontal * 17),
            y: center.y + (normalizedVertical * 17)
        )
        let color = verticalSpeedMultiplier < -0.05 || horizontalSpeedMultiplier < -0.05
            ? NSColor.systemOrange
            : NSColor.systemBlue
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: knobPoint.x - 5, y: knobPoint.y - 5, width: 10, height: 10)
        ).fill()

        let arrows = [
            (tip: NSPoint(x: center.x, y: center.y + 24), first: NSPoint(x: center.x - 4, y: center.y + 20), second: NSPoint(x: center.x + 4, y: center.y + 20)),
            (tip: NSPoint(x: center.x, y: center.y - 24), first: NSPoint(x: center.x - 4, y: center.y - 20), second: NSPoint(x: center.x + 4, y: center.y - 20)),
            (tip: NSPoint(x: center.x + 24, y: center.y), first: NSPoint(x: center.x + 20, y: center.y - 4), second: NSPoint(x: center.x + 20, y: center.y + 4)),
            (tip: NSPoint(x: center.x - 24, y: center.y), first: NSPoint(x: center.x - 20, y: center.y - 4), second: NSPoint(x: center.x - 20, y: center.y + 4)),
        ]
        color.setStroke()
        for arrow in arrows {
            let path = NSBezierPath()
            path.move(to: arrow.first)
            path.line(to: arrow.tip)
            path.line(to: arrow.second)
            path.lineWidth = 1.5
            path.stroke()
        }

        let text = max(abs(verticalSpeedMultiplier), abs(horizontalSpeedMultiplier)) < 0.05
            ? "Paused"
            : String(
                format: "V %.1f×  H %.1f×",
                verticalSpeedMultiplier,
                horizontalSpeedMultiplier
            )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: 9,
                weight: .semibold
            ),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - (textSize.width / 2), y: 7),
            withAttributes: attributes
        )
    }
}

final class JoystickHUDController {
    private let panel: NSPanel
    private let view: JoystickHUDView
    private let size = NSSize(width: 112, height: 106)

    init() {
        view = JoystickHUDView(frame: NSRect(origin: .zero, size: size))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
    }

    func show(at point: NSPoint) {
        view.verticalSpeedMultiplier = 0
        view.horizontalSpeedMultiplier = 0
        updatePosition(around: point)
        panel.orderFrontRegardless()
    }

    func update(
        verticalSpeedMultiplier: Double,
        horizontalSpeedMultiplier: Double
    ) {
        view.verticalSpeedMultiplier = verticalSpeedMultiplier
        view.horizontalSpeedMultiplier = horizontalSpeedMultiplier
        view.needsDisplay = true
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func updatePosition(around point: NSPoint) {
        var origin = NSPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let frame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }
}

func makeStatusItemImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.setStroke()
        let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 1, width: 10, height: 16), xRadius: 5, yRadius: 5)
        body.lineWidth = 1.25
        body.stroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 9, y: 16))
        divider.line(to: NSPoint(x: 9, y: 11.5))
        divider.lineWidth = 1.1
        divider.stroke()
        let wheel = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 6.5, width: 2.5, height: 5), xRadius: 1.2, yRadius: 1.2)
        wheel.lineWidth = 1.1
        wheel.stroke()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Thumbwheel Remapper"
    return image
}
