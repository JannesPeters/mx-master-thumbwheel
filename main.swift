import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

// Set to -1 if the remapped scroll direction feels inverted.
private let verticalScrollDirection: Int64 = 1

// Keep this true to ignore pixel-based trackpad gestures. If the MX thumbwheel
// is reported as continuous on your macOS/device combination, set it to false.
private let requireLineBasedScrollEvents = true

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

    func createEventTap() -> CFMachPort? {
        let eventsOfInterest = CGEventMask(1) << CGEventType.scrollWheel.rawValue
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

    func process(event: CGEvent) -> Unmanaged<CGEvent> {
        guard event.type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

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
