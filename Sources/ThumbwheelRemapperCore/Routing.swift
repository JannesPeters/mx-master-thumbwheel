import Foundation

public enum RawInputEventType: String, Codable, Equatable {
    case leftMouseDown
    case leftMouseUp
    case rightMouseDown
    case rightMouseUp
    case otherMouseDown
    case otherMouseUp
    case mouseMoved
    case scrollWheel
    case tapDisabledByTimeout
    case tapDisabledByUserInput
}

public struct RawInputEvent: Equatable {
    public var type: RawInputEventType
    public var buttonNumber: Int64?
    public var integerAxis1: Int64
    public var integerAxis2: Int64
    public var axis1: Double
    public var axis2: Double
    public var pointAxis1: Int64
    public var pointAxis2: Int64
    public var isContinuous: Bool
    public var shiftPressed: Bool
    public var sourceID: UInt64?

    public init(
        type: RawInputEventType,
        buttonNumber: Int64? = nil,
        integerAxis1: Int64 = 0,
        integerAxis2: Int64 = 0,
        axis1: Double = 0,
        axis2: Double = 0,
        pointAxis1: Int64 = 0,
        pointAxis2: Int64 = 0,
        isContinuous: Bool = false,
        shiftPressed: Bool = false,
        sourceID: UInt64? = nil
    ) {
        self.type = type
        self.buttonNumber = buttonNumber
        self.integerAxis1 = integerAxis1
        self.integerAxis2 = integerAxis2
        self.axis1 = axis1
        self.axis2 = axis2
        self.pointAxis1 = pointAxis1
        self.pointAxis2 = pointAxis2
        self.isContinuous = isContinuous
        self.shiftPressed = shiftPressed
        self.sourceID = sourceID
    }
}

public enum NormalizedButton: Equatable, Hashable {
    case left
    case right
    case other(Int64)

    public init(_ inputButton: InputButton) {
        switch inputButton {
        case .left:
            self = .left
        case .right:
            self = .right
        case let .other(number):
            self = .other(number)
        }
    }

    public var inputButton: InputButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case let .other(number):
            return .other(number)
        }
    }
}

public enum NormalizedInputEvent: Equatable {
    case buttonDown(NormalizedButton)
    case buttonUp(NormalizedButton)
    case pointerMoved(deltaX: Double, deltaY: Double)
    case wheel(WheelEvent)
    case tapDisabled(EventTapDisableReason)
    case other
}

public enum EventTapDisableReason: Equatable {
    case timeout
    case userInput
}

public struct WheelEvent: Equatable {
    public var integerVertical: Int64
    public var integerHorizontal: Int64
    public var vertical: Double
    public var horizontal: Double
    public var pointVertical: Int64
    public var pointHorizontal: Int64
    public var isContinuous: Bool
    public var shiftPressed: Bool
    public var sourceID: UInt64?

    public init(
        integerVertical: Int64 = 0,
        integerHorizontal: Int64 = 0,
        vertical: Double = 0,
        horizontal: Double = 0,
        pointVertical: Int64 = 0,
        pointHorizontal: Int64 = 0,
        isContinuous: Bool = false,
        shiftPressed: Bool = false,
        sourceID: UInt64? = nil
    ) {
        self.integerVertical = integerVertical
        self.integerHorizontal = integerHorizontal
        self.vertical = vertical
        self.horizontal = horizontal
        self.pointVertical = pointVertical
        self.pointHorizontal = pointHorizontal
        self.isContinuous = isContinuous
        self.shiftPressed = shiftPressed
        self.sourceID = sourceID
    }
}

public enum EventNormalizer {
    public static func normalize(_ event: RawInputEvent) -> NormalizedInputEvent {
        switch event.type {
        case .leftMouseDown:
            return .buttonDown(.left)
        case .leftMouseUp:
            return .buttonUp(.left)
        case .rightMouseDown:
            return .buttonDown(.right)
        case .rightMouseUp:
            return .buttonUp(.right)
        case .otherMouseDown:
            guard let number = event.buttonNumber else { return .other }
            return .buttonDown(.other(number))
        case .otherMouseUp:
            guard let number = event.buttonNumber else { return .other }
            return .buttonUp(.other(number))
        case .mouseMoved:
            return .pointerMoved(deltaX: event.axis2, deltaY: event.axis1)
        case .scrollWheel:
            return .wheel(
                WheelEvent(
                    integerVertical: event.integerAxis1,
                    integerHorizontal: event.integerAxis2,
                    vertical: event.axis1,
                    horizontal: event.axis2,
                    pointVertical: event.pointAxis1,
                    pointHorizontal: event.pointAxis2,
                    isContinuous: event.isContinuous,
                    shiftPressed: event.shiftPressed,
                    sourceID: event.sourceID
                )
            )
        case .tapDisabledByTimeout:
            return .tapDisabled(.timeout)
        case .tapDisabledByUserInput:
            return .tapDisabled(.userInput)
        }
    }
}

public enum WheelSourceDetector {
    public static func matches(
        _ event: WheelEvent,
        inputShape: WheelInputShape,
        ignoreContinuousEvents: Bool
    ) -> Bool {
        guard event.horizontal != 0
                || event.pointHorizontal != 0
                || event.integerHorizontal != 0 else {
            return false
        }
        if ignoreContinuousEvents && event.isContinuous {
            return false
        }
        switch inputShape {
        case .horizontalOnly:
            return event.vertical == 0
                && event.pointVertical == 0
                && event.integerVertical == 0
        case .anyHorizontal:
            return true
        }
    }

    public static func isHorizontalThumbwheel(
        _ event: WheelEvent,
        ignoreContinuousEvents: Bool = true
    ) -> Bool {
        matches(
            event,
            inputShape: .horizontalOnly,
            ignoreContinuousEvents: ignoreContinuousEvents
        )
    }
}

public enum WheelTransform {
    public static func horizontalToVertical(
        _ event: WheelEvent,
        direction: ScrollDirection = .up
    ) -> WheelEvent? {
        guard event.horizontal != 0
                || event.pointHorizontal != 0
                || event.integerHorizontal != 0 else {
            return nil
        }

        let multiplier = Double(direction == .up ? 1 : -1)
        return WheelEvent(
            integerVertical: Int64(
                (Double(event.integerHorizontal) * multiplier).rounded()
            ),
            integerHorizontal: 0,
            vertical: event.horizontal * multiplier,
            horizontal: 0,
            pointVertical: Int64((Double(event.pointHorizontal) * multiplier).rounded()),
            pointHorizontal: 0,
            isContinuous: event.isContinuous,
            shiftPressed: event.shiftPressed,
            sourceID: event.sourceID
        )
    }

    public static func apply(
        _ event: WheelEvent,
        options: WheelActionOptions
    ) -> WheelEvent? {
        if options.preserveShiftGestures && event.shiftPressed {
            return nil
        }
        guard WheelSourceDetector.matches(
            event,
            inputShape: options.inputShape,
            ignoreContinuousEvents: options.ignoreContinuousEvents
        ) else {
            return nil
        }
        return horizontalToVertical(event, direction: options.direction)
    }
}

public enum RoutedGesture: Equatable {
    case buttonDown(InputButton)
    case buttonUp(InputButton)
    case click(ButtonClickMapping)
    case hold(ButtonHoldMapping)
    case wheel(WheelMapping, WheelEvent)
}

public enum RouteDecision: Equatable {
    case forward
    case consume
    case mapped(RoutedGesture)
    case reenableEventTap
}

public struct EventRouter {
    public var document: ConfigurationDocument

    public init(document: ConfigurationDocument = .defaults) {
        self.document = document
    }

    public func route(_ event: NormalizedInputEvent) -> RouteDecision {
        switch event {
        case .tapDisabled:
            return .reenableEventTap
        case let .buttonDown(button):
            let inputButton = button.inputButton
            let hasMapping = document.buttonClicks.contains {
                $0.isEnabled && $0.button == inputButton
            } || document.buttonHolds.contains {
                $0.isEnabled && $0.button == inputButton
            }
            return hasMapping ? .consume : .forward
        case let .buttonUp(button):
            let inputButton = button.inputButton
            let hasMapping = document.buttonClicks.contains {
                $0.isEnabled && $0.button == inputButton
            } || document.buttonHolds.contains {
                $0.isEnabled && $0.button == inputButton
            }
            return hasMapping ? .consume : .forward
        case let .wheel(event):
            guard let mapping = document.wheelMappings.first(where: {
                guard $0.isEnabled else { return false }
                switch $0.source {
                case .horizontalThumbwheel:
                    return WheelSourceDetector.matches(
                        event,
                        inputShape: $0.action.inputShape,
                        ignoreContinuousEvents: $0.action.ignoreContinuousEvents
                    )
                }
            }) else {
                return .forward
            }
            guard let transformed = WheelTransform.apply(event, options: mapping.action) else {
                return .forward
            }
            return .mapped(.wheel(mapping, transformed))
        case .pointerMoved, .other:
            return .forward
        }
    }

    public func route(click: ButtonClickKind, for button: InputButton) -> RouteDecision {
        guard let mapping = document.buttonClicks.first(where: {
            $0.isEnabled && $0.button == button && $0.click == click
        }) else {
            return .forward
        }
        return .mapped(.click(mapping))
    }

    public func routeHold(for button: InputButton) -> RouteDecision {
        guard let mapping = document.buttonHolds.first(where: {
            $0.isEnabled && $0.button == button
        }) else {
            return .forward
        }
        return .mapped(.hold(mapping))
    }
}

public struct EventTapReenableGate {
    public init() {}

    public func shouldReenable(for event: NormalizedInputEvent) -> Bool {
        if case .tapDisabled = event {
            return true
        }
        return false
    }
}
