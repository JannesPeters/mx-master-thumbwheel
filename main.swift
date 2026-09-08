import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

// Set to -1 if the remapped scroll direction feels inverted.
private let verticalScrollDirection: Int64 = 1

// Keep this true to ignore pixel-based trackpad gestures. If the MX thumbwheel
// is reported as continuous on your macOS/device combination, set it to false.
private let requireLineBasedScrollEvents = true

// Quartz reports mouse buttons with zero-based numbers: left is 0, right is
// 1, and middle is 2. MX Master side buttons normally arrive as button 3
// (Back) and button 4 (Forward). Change these values if the connected mode or
// device reports different button numbers.
private let backButtonNumber: Int64 = 3
private let forwardButtonNumber: Int64 = 4

// While a thumb button is held down, keep posting scroll events at this
// cadence so scrolling continues instead of firing a single line. The
// initial delay mirrors typical key-repeat behavior before the fast repeat
// kicks in.
private let thumbButtonScrollRepeatInitialDelay: TimeInterval = 0.3
private let thumbButtonScrollRepeatInterval: TimeInterval = 0.05

private struct ScrollDeltas {
    let integer: Int64
    let fixedPoint: Double
    let point: Int64

    var isZero: Bool {
        integer == 0 && fixedPoint == 0 && point == 0
    }
}

private func readDeltas(from event: CGEvent, axis: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField)) -> ScrollDeltas {
    ScrollDeltas(
        integer: event.getIntegerValueField(axis.integer),
        fixedPoint: event.getDoubleValueField(axis.fixedPoint),
        point: event.getIntegerValueField(axis.point)
    )
}

private func writeDeltas(_ deltas: ScrollDeltas, to event: CGEvent, axis: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField)) {
    event.setIntegerValueField(axis.integer, value: deltas.integer * verticalScrollDirection)
    event.setDoubleValueField(axis.fixedPoint, value: deltas.fixedPoint * Double(verticalScrollDirection))
    event.setIntegerValueField(axis.point, value: deltas.point * verticalScrollDirection)
}

private func clearDeltas(in event: CGEvent, axis: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField)) {
    event.setIntegerValueField(axis.integer, value: 0)
    event.setDoubleValueField(axis.fixedPoint, value: 0)
    event.setIntegerValueField(axis.point, value: 0)
}

private final class EventTapController {
    private(set) var eventTap: CFMachPort?
    private var activeScrollButtonNumber: Int64?
    private var activeScrollTimer: Timer?

    func createEventTap() -> CFMachPort? {
        let eventsOfInterest =
            (CGEventMask(1) << CGEventType.scrollWheel.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventTapCallback,
            userInfo: userInfo
        )

        self.eventTap = eventTap
        return eventTap
    }

    func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func process(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch event.type {
        case .otherMouseDown:
            guard let scrollDirection = scrollDirection(for: event) else {
                return Unmanaged.passUnretained(event)
            }

            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            postVerticalScroll(direction: scrollDirection)
            startRepeatingScroll(direction: scrollDirection, buttonNumber: buttonNumber)
            return nil

        case .otherMouseUp:
            // Suppress the matching navigation release without generating a
            // second scroll event.
            guard isMappedThumbButton(event) else {
                return Unmanaged.passUnretained(event)
            }

            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            if buttonNumber == activeScrollButtonNumber {
                stopRepeatingScroll()
            }
            return nil

        case .scrollWheel:
            return processScrollWheel(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func processScrollWheel(_ event: CGEvent) -> Unmanaged<CGEvent> {

        // Shift+scroll remains the native horizontal-scroll gesture.
        guard !event.flags.contains(.maskShift) else {
            return Unmanaged.passUnretained(event)
        }

        if requireLineBasedScrollEvents {
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            guard !isContinuous else {
                return Unmanaged.passUnretained(event)
            }
        }

        let verticalAxis = readDeltas(
            from: event,
            axis: (
                integer: .scrollWheelEventDeltaAxis1,
                fixedPoint: .scrollWheelEventFixedPtDeltaAxis1,
                point: .scrollWheelEventPointDeltaAxis1
            )
        )
        let horizontalAxis = readDeltas(
            from: event,
            axis: (
                integer: .scrollWheelEventDeltaAxis2,
                fixedPoint: .scrollWheelEventFixedPtDeltaAxis2,
                point: .scrollWheelEventPointDeltaAxis2
            )
        )

        // Only remap events that contain horizontal movement and no vertical
        // movement. This leaves diagonal and ordinary wheel events untouched.
        guard verticalAxis.isZero, !horizontalAxis.isZero else {
            return Unmanaged.passUnretained(event)
        }

        writeDeltas(horizontalAxis, to: event, axis: verticalAxisFields)
        clearDeltas(in: event, axis: horizontalAxisFields)
        return Unmanaged.passUnretained(event)
    }

    private func isMappedThumbButton(_ event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        return buttonNumber == backButtonNumber || buttonNumber == forwardButtonNumber
    }

    private func scrollDirection(for event: CGEvent) -> Int32? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        switch buttonNumber {
        case forwardButtonNumber:
            return 1
        case backButtonNumber:
            return -1
        default:
            return nil
        }
    }

    private func startRepeatingScroll(direction: Int32, buttonNumber: Int64) {
        stopRepeatingScroll()
        activeScrollButtonNumber = buttonNumber

        let timer = Timer(
            fire: Date().addingTimeInterval(thumbButtonScrollRepeatInitialDelay),
            interval: thumbButtonScrollRepeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.postVerticalScroll(direction: direction)
        }
        RunLoop.current.add(timer, forMode: .common)
        activeScrollTimer = timer
    }

    private func stopRepeatingScroll() {
        activeScrollTimer?.invalidate()
        activeScrollTimer = nil
        activeScrollButtonNumber = nil
    }

    private func postVerticalScroll(direction: Int32) {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: direction,
            wheel2: 0,
            wheel3: 0
        ) else {
            fail("Could not create a synthesized vertical scroll event.")
        }

        scrollEvent.post(tap: .cgSessionEventTap)
    }
}

private let verticalAxisFields: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField) = (
    integer: .scrollWheelEventDeltaAxis1,
    fixedPoint: .scrollWheelEventFixedPtDeltaAxis1,
    point: .scrollWheelEventPointDeltaAxis1
)

private let horizontalAxisFields: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField) = (
    integer: .scrollWheelEventDeltaAxis2,
    fixedPoint: .scrollWheelEventFixedPtDeltaAxis2,
    point: .scrollWheelEventPointDeltaAxis2
)

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        controller.reenableEventTap()
    default:
        break
    }

    return controller.process(event: event)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(EXIT_FAILURE)
}

private let controller = EventTapController()
guard let eventTap = controller.createEventTap() else {
    fail(
        """
        Could not create the event tap. Grant this executable Accessibility \
        permission in System Settings > Privacy & Security > Accessibility, \
        then run it again.
        """
    )
}

guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
    fail("Could not create the event-tap run-loop source.")
}

CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

print("Thumbwheel remapping active. Press Control-C to stop.")
CFRunLoopRun()
