import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ThumbwheelRemapperCore

final class PageDistanceResolver {
    private static let accessibilityTimeout: Float = 0.05
    private static let maximumPageDistance = 10_000.0
    private static let pageEdgeViewportCount = 12.0
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

    static func edgeAnimationDistance(at point: CGPoint) -> Double {
        distance(at: point) * pageEdgeViewportCount
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
    var verticalDisplacement = 0.0
    var horizontalDisplacement = 0.0
    var verticalPauseDirection: Double?
    var horizontalPauseDirection: Double?
    var pauseZoneDistance = 80.0
    var verticalAxisEnabled = true
    var horizontalAxisEnabled = true

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let vertical = verticalAxisEnabled ? verticalSpeedMultiplier : 0
        let horizontal = horizontalAxisEnabled ? horizontalSpeedMultiplier : 0
        let magnitude = hypot(horizontal, vertical)
        let movementStart = 0.05
        let morph = min(max((magnitude - movementStart) / 0.45, 0), 1)
        let angle = magnitude > movementStart ? atan2(vertical, horizontal) : 0
        let displacementScale = max(pauseZoneDistance, 1)
        let normalizedVerticalDisplacement = verticalAxisEnabled
            ? min(max(verticalDisplacement / displacementScale, -1), 1)
            : 0
        let normalizedHorizontalDisplacement = horizontalAxisEnabled
            ? min(max(horizontalDisplacement / displacementScale, -1), 1)
            : 0
        let markerCenter = NSPoint(
            x: center.x + (normalizedHorizontalDisplacement * 17),
            y: center.y + (normalizedVerticalDisplacement * 17)
        )
        let color = NSColor.controlAccentColor.withAlphaComponent(0.78)

        let track = NSBezierPath()
        if verticalAxisEnabled {
            track.move(to: NSPoint(x: center.x, y: center.y - 17))
            track.line(to: NSPoint(x: center.x, y: center.y + 17))
        }
        if horizontalAxisEnabled {
            track.move(to: NSPoint(x: center.x - 17, y: center.y))
            track.line(to: NSPoint(x: center.x + 17, y: center.y))
        }
        track.lineWidth = 2
        NSColor.tertiaryLabelColor.withAlphaComponent(0.34).setStroke()
        track.stroke()

        let pauseZoneLength = 17.0
        let pauseZone = NSBezierPath()
        if verticalAxisEnabled,
           let verticalPauseDirection {
            pauseZone.move(to: center)
            pauseZone.line(to: NSPoint(
                x: center.x,
                y: center.y - CGFloat(verticalPauseDirection * pauseZoneLength)
            ))
        }
        if horizontalAxisEnabled,
           let horizontalPauseDirection {
            pauseZone.move(to: center)
            pauseZone.line(to: NSPoint(
                x: center.x - CGFloat(horizontalPauseDirection * pauseZoneLength),
                y: center.y
            ))
        }
        pauseZone.lineWidth = 6
        pauseZone.lineCapStyle = .round
        color.withAlphaComponent(0.16).setStroke()
        pauseZone.stroke()

        func drawArrow(
            tip: NSPoint,
            first: NSPoint,
            second: NSPoint
        ) {
            let path = NSBezierPath()
            path.move(to: first)
            path.line(to: tip)
            path.line(to: second)
            path.lineWidth = 1.5
            path.stroke()
        }
        color.withAlphaComponent(0.62).setStroke()
        if verticalAxisEnabled {
            drawArrow(
                tip: NSPoint(x: center.x, y: center.y + 24),
                first: NSPoint(x: center.x - 4, y: center.y + 20),
                second: NSPoint(x: center.x + 4, y: center.y + 20)
            )
            drawArrow(
                tip: NSPoint(x: center.x, y: center.y - 24),
                first: NSPoint(x: center.x - 4, y: center.y - 20),
                second: NSPoint(x: center.x + 4, y: center.y - 20)
            )
        }
        if horizontalAxisEnabled {
            drawArrow(
                tip: NSPoint(x: center.x + 24, y: center.y),
                first: NSPoint(x: center.x + 20, y: center.y - 4),
                second: NSPoint(x: center.x + 20, y: center.y + 4)
            )
            drawArrow(
                tip: NSPoint(x: center.x - 24, y: center.y),
                first: NSPoint(x: center.x - 20, y: center.y - 4),
                second: NSPoint(x: center.x - 20, y: center.y + 4)
            )
        }

        color.withAlphaComponent(0.78 * (1 - morph)).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: markerCenter.x - 5.5,
                y: markerCenter.y - 5.5,
                width: 11,
                height: 11
            )
        ).fill()

        let triangleRadius = 8.0
        let triangle = NSBezierPath()
        let tip = NSPoint(
            x: markerCenter.x + (cos(angle) * triangleRadius),
            y: markerCenter.y + (sin(angle) * triangleRadius)
        )
        let left = NSPoint(
            x: markerCenter.x + (cos(angle + (2 * .pi / 3)) * triangleRadius),
            y: markerCenter.y + (sin(angle + (2 * .pi / 3)) * triangleRadius)
        )
        let right = NSPoint(
            x: markerCenter.x + (cos(angle - (2 * .pi / 3)) * triangleRadius),
            y: markerCenter.y + (sin(angle - (2 * .pi / 3)) * triangleRadius)
        )
        triangle.move(to: tip)
        triangle.line(to: left)
        triangle.line(to: right)
        triangle.close()
        color.withAlphaComponent(0.78 * morph).setFill()
        triangle.fill()
    }
}

final class JoystickHUDController {
    private let panel: NSPanel
    private let view: JoystickHUDView
    private let size = NSSize(width: 78, height: 78)

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
        panel.alphaValue = 0.84
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
    }

    func show(
        at point: NSPoint,
        verticalAxisEnabled: Bool,
        horizontalAxisEnabled: Bool,
        pauseZoneDistance: Double
    ) {
        view.verticalAxisEnabled = verticalAxisEnabled
        view.horizontalAxisEnabled = horizontalAxisEnabled
        view.verticalSpeedMultiplier = 0
        view.horizontalSpeedMultiplier = 0
        view.verticalDisplacement = 0
        view.horizontalDisplacement = 0
        view.verticalPauseDirection = nil
        view.horizontalPauseDirection = nil
        view.pauseZoneDistance = pauseZoneDistance
        updatePosition(around: point)
        panel.orderFrontRegardless()
    }

    func update(
        verticalSpeedMultiplier: Double,
        horizontalSpeedMultiplier: Double,
        verticalDisplacement: Double,
        horizontalDisplacement: Double,
        verticalPauseDirection: Double?,
        horizontalPauseDirection: Double?
    ) {
        view.verticalSpeedMultiplier = verticalSpeedMultiplier
        view.horizontalSpeedMultiplier = horizontalSpeedMultiplier
        view.verticalDisplacement = verticalDisplacement
        view.horizontalDisplacement = horizontalDisplacement
        view.verticalPauseDirection = verticalPauseDirection
        view.horizontalPauseDirection = horizontalPauseDirection
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

struct FloatingScrollBarAxisState {
    var position: Double
    var visibleProportion: Double
}

struct FloatingScrollBarState {
    var vertical: FloatingScrollBarAxisState?
    var horizontal: FloatingScrollBarAxisState?
}

final class FloatingScrollTarget {
    private static let accessibilityTimeout: Float = 0.05
    private let hitElement: AXUIElement

    private init(hitElement: AXUIElement) {
        self.hitElement = hitElement
    }

    static func capture(at point: CGPoint) -> FloatingScrollTarget? {
        let systemWideElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWideElement, accessibilityTimeout)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        ) == .success, let hitElement else {
            return nil
        }
        return FloatingScrollTarget(hitElement: hitElement)
    }

    func state(verticalEnabled: Bool, horizontalEnabled: Bool) -> FloatingScrollBarState {
        var currentElement = hitElement
        var descendantSizes: [CGSize] = []

        for _ in 0..<16 {
            AXUIElementSetMessagingTimeout(currentElement, Self.accessibilityTimeout)
            let currentSize = Self.size(of: currentElement)
            if let currentSize {
                descendantSizes.append(currentSize)
            }

            let verticalBar = verticalEnabled
                ? Self.element(kAXVerticalScrollBarAttribute as CFString, of: currentElement)
                : nil
            let horizontalBar = horizontalEnabled
                ? Self.element(kAXHorizontalScrollBarAttribute as CFString, of: currentElement)
                : nil
            if verticalBar != nil || horizontalBar != nil {
                let viewportSize = currentSize ?? .zero
                let contentSize = Self.contentSize(
                    of: currentElement,
                    including: descendantSizes
                )
                return FloatingScrollBarState(
                    vertical: verticalBar.flatMap {
                        Self.axisState(
                            for: $0,
                            viewportLength: viewportSize.height,
                            contentLength: contentSize.height
                        )
                    },
                    horizontal: horizontalBar.flatMap {
                        Self.axisState(
                            for: $0,
                            viewportLength: viewportSize.width,
                            contentLength: contentSize.width
                        )
                    }
                )
            }

            guard let parent = Self.element(
                kAXParentAttribute as CFString,
                of: currentElement
            ) else {
                break
            }
            currentElement = parent
        }
        return FloatingScrollBarState()
    }

    private static func axisState(
        for scrollBar: AXUIElement,
        viewportLength: CGFloat,
        contentLength: CGFloat
    ) -> FloatingScrollBarAxisState? {
        let minimum = number(kAXMinValueAttribute as CFString, of: scrollBar) ?? 0
        let maximum = number(kAXMaxValueAttribute as CFString, of: scrollBar) ?? 1
        guard let value = number(kAXValueAttribute as CFString, of: scrollBar),
              maximum > minimum else {
            return nil
        }
        let position = min(max((value - minimum) / (maximum - minimum), 0), 1)
        let visibleProportion: Double
        if viewportLength > 0, contentLength > viewportLength {
            visibleProportion = Double(viewportLength / contentLength)
        } else if viewportLength > 0, maximum - minimum > 1 {
            visibleProportion = Double(viewportLength)
                / (Double(viewportLength) + maximum - minimum)
        } else {
            visibleProportion = 0.2
        }
        return FloatingScrollBarAxisState(
            position: position,
            visibleProportion: min(max(visibleProportion, 0.08), 1)
        )
    }

    private static func contentSize(
        of element: AXUIElement,
        including descendantSizes: [CGSize]
    ) -> CGSize {
        var candidates = descendantSizes
        for attributeName in [
            kAXContentsAttribute as CFString,
            kAXChildrenAttribute as CFString,
        ] {
            guard let values = attribute(attributeName, of: element) as? [AnyObject] else {
                continue
            }
            for value in values where CFGetTypeID(value) == AXUIElementGetTypeID() {
                let child = unsafeBitCast(value, to: AXUIElement.self)
                if let childSize = size(of: child) {
                    candidates.append(childSize)
                }
            }
        }
        return candidates.reduce(.zero) { result, size in
            CGSize(
                width: max(result.width, size.width),
                height: max(result.height, size.height)
            )
        }
    }

    private static func number(_ name: CFString, of element: AXUIElement) -> Double? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        return (value as? NSNumber)?.doubleValue
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        guard let value = attribute(kAXSizeAttribute as CFString, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        let axValue = unsafeBitCast(value, to: AXValue.self)
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private static func element(_ name: CFString, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }
}

private final class FloatingScrollBarHUDView: NSView {
    var verticalAxisEnabled = true
    var horizontalAxisEnabled = true
    var state = FloatingScrollBarState()

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let trackLength: CGFloat = 88
        let trackThickness: CGFloat = 6
        let trackColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.28)
        let thumbColor = NSColor.controlAccentColor.withAlphaComponent(0.88)

        if verticalAxisEnabled, let vertical = state.vertical {
            let x = horizontalAxisEnabled ? center.x + 12 : center.x
            let trackRect = NSRect(
                x: x - trackThickness / 2,
                y: center.y - trackLength / 2,
                width: trackThickness,
                height: trackLength
            )
            drawTrack(trackRect, color: trackColor)

            let thumbLength = min(
                max(trackLength * vertical.visibleProportion, 14),
                trackLength
            )
            let travel = trackLength - thumbLength
            let thumbY = trackRect.maxY - thumbLength
                - CGFloat(vertical.position) * travel
            drawThumb(
                NSRect(
                    x: x - trackThickness,
                    y: thumbY,
                    width: trackThickness * 2,
                    height: thumbLength
                ),
                color: thumbColor
            )
        }

        if horizontalAxisEnabled, let horizontal = state.horizontal {
            let y = verticalAxisEnabled ? center.y - 12 : center.y
            let trackRect = NSRect(
                x: center.x - trackLength / 2,
                y: y - trackThickness / 2,
                width: trackLength,
                height: trackThickness
            )
            drawTrack(trackRect, color: trackColor)

            let thumbLength = min(
                max(trackLength * horizontal.visibleProportion, 14),
                trackLength
            )
            let travel = trackLength - thumbLength
            let thumbX = trackRect.minX + CGFloat(horizontal.position) * travel
            drawThumb(
                NSRect(
                    x: thumbX,
                    y: y - trackThickness,
                    width: thumbLength,
                    height: trackThickness * 2
                ),
                color: thumbColor
            )
        }
    }

    private func drawTrack(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: min(rect.width, rect.height) / 2,
            yRadius: min(rect.width, rect.height) / 2
        ).fill()
    }

    private func drawThumb(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: min(rect.width, rect.height) / 2,
            yRadius: min(rect.width, rect.height) / 2
        ).fill()
    }
}

final class FloatingScrollBarHUDController {
    private let panel: NSPanel
    private let view: FloatingScrollBarHUDView
    private let size = NSSize(width: 112, height: 112)
    private let stateQueue = DispatchQueue(
        label: "com.jannespeters.thumbwheel-remapper.floating-scrollbar",
        qos: .userInteractive
    )
    private var target: FloatingScrollTarget?
    private var refreshPending = false
    private var generation = 0

    init() {
        view = FloatingScrollBarHUDView(frame: NSRect(origin: .zero, size: size))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = 0.9
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
    }

    func show(
        at point: NSPoint,
        target: FloatingScrollTarget?,
        verticalAxisEnabled: Bool,
        horizontalAxisEnabled: Bool
    ) {
        generation &+= 1
        self.target = target
        view.verticalAxisEnabled = verticalAxisEnabled
        view.horizontalAxisEnabled = horizontalAxisEnabled
        view.state = FloatingScrollBarState()
        view.needsDisplay = true
        updatePosition(around: point)
        panel.orderFrontRegardless()
        refresh()
    }

    func refresh() {
        guard !refreshPending, let target else { return }
        refreshPending = true
        let generation = generation
        let verticalEnabled = view.verticalAxisEnabled
        let horizontalEnabled = view.horizontalAxisEnabled
        stateQueue.async { [weak self] in
            let state = target.state(
                verticalEnabled: verticalEnabled,
                horizontalEnabled: horizontalEnabled
            )
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.refreshPending = false
                self.view.state = state
                self.view.needsDisplay = true
            }
        }
    }

    func hide() {
        generation &+= 1
        target = nil
        refreshPending = false
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
