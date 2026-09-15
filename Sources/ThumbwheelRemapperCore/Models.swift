import Foundation

public enum InputButton: Codable, Equatable, Hashable, Identifiable {
    case left
    case right
    case other(Int64)

    public var id: String {
        switch self {
        case .left:
            return "left"
        case .right:
            return "right"
        case let .other(number):
            return "other-\(number)"
        }
    }

    public var displayName: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case let .other(number):
            switch number {
            case 2:
                return "Middle button (2)"
            case 3:
                return "Back button (3)"
            case 4:
                return "Forward button (4)"
            default:
                return "Extra button \(number)"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case number
    }

    private enum Kind: String, Codable {
        case left
        case right
        case other
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .left:
            self = .left
        case .right:
            self = .right
        case .other:
            self = .other(try container.decode(Int64.self, forKey: .number))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .left:
            try container.encode(Kind.left, forKey: .kind)
        case .right:
            try container.encode(Kind.right, forKey: .kind)
        case let .other(number):
            try container.encode(Kind.other, forKey: .kind)
            try container.encode(number, forKey: .number)
        }
    }
}

public enum ButtonClickKind: String, Codable, CaseIterable, Equatable, Identifiable {
    case single
    case double

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum ScrollDirection: Int, Codable, CaseIterable, Equatable {
    case down = -1
    case up = 1

    public var displayName: String {
        switch self {
        case .down:
            return "Scroll down"
        case .up:
            return "Scroll up"
        }
    }
}

public enum HoldScrollMode: String, Codable, CaseIterable, Equatable, Identifiable {
    case scrollUp
    case scrollDown
    case joystick
    case dragScroll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scrollUp:
            return "Scroll up"
        case .scrollDown:
            return "Scroll down"
        case .joystick:
            return "Joystick"
        case .dragScroll:
            return "Drag scroll"
        }
    }

    public var direction: ScrollDirection? {
        switch self {
        case .scrollUp:
            return .up
        case .scrollDown:
            return .down
        case .joystick:
            return nil
        case .dragScroll:
            return nil
        }
    }
}

public enum ScrollAmount: Codable, Equatable {
    case fixed(Double)
    case page

    private enum CodingKeys: String, CodingKey {
        case kind
        case points
    }

    private enum Kind: String, Codable {
        case fixed
        case page
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .fixed:
            self = .fixed(try container.decode(Double.self, forKey: .points))
        case .page:
            self = .page
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .fixed(points):
            try container.encode(Kind.fixed, forKey: .kind)
            try container.encode(points, forKey: .points)
        case .page:
            try container.encode(Kind.page, forKey: .kind)
        }
    }
}

public enum EasingCurve: String, Codable, CaseIterable, Equatable, Identifiable {
    case linear
    case smoothStep
    case quickInLongOut

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linear:
            return "Linear"
        case .smoothStep:
            return "Smooth"
        case .quickInLongOut:
            return "Quick in, long out"
        }
    }

    public func value(at progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        switch self {
        case .linear:
            return progress
        case .smoothStep:
            return progress * progress * (3 - (2 * progress))
        case .quickInLongOut:
            let accelerationShare = 0.2
            if progress < accelerationShare {
                let normalized = progress / accelerationShare
                return accelerationShare * (1 - cos(normalized * .pi / 2))
            }

            let decelerationShare = 1 - accelerationShare
            let normalized = (progress - accelerationShare) / decelerationShare
            return accelerationShare + decelerationShare * sin(normalized * .pi / 2)
        }
    }
}

public struct ScrollActionOptions: Codable, Equatable {
    public var direction: ScrollDirection
    public var amount: ScrollAmount
    public var duration: TimeInterval
    public var easing: EasingCurve
    public var easingEnabled: Bool

    public init(
        direction: ScrollDirection,
        amount: ScrollAmount = .fixed(40),
        duration: TimeInterval = 0.18,
        easing: EasingCurve = .quickInLongOut,
        easingEnabled: Bool = true
    ) {
        self.direction = direction
        self.amount = amount
        self.duration = duration
        self.easing = easing
        self.easingEnabled = easingEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case amount
        case duration
        case easing
        case easingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decode(ScrollDirection.self, forKey: .direction)
        amount = try container.decode(ScrollAmount.self, forKey: .amount)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        easing = try container.decodeIfPresent(EasingCurve.self, forKey: .easing) ?? .quickInLongOut
        easingEnabled = try container.decodeIfPresent(Bool.self, forKey: .easingEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(direction, forKey: .direction)
        try container.encode(amount, forKey: .amount)
        try container.encode(duration, forKey: .duration)
        try container.encode(easing, forKey: .easing)
        try container.encode(easingEnabled, forKey: .easingEnabled)
    }
}

public struct HoldActionOptions: Codable, Equatable {
    public var mode: HoldScrollMode
    public var pointsPerSecond: Double
    public var accelerationDuration: TimeInterval
    public var releaseDuration: TimeInterval
    public var joystickVerticalEnabled: Bool
    public var joystickHorizontalEnabled: Bool
    public var joystickCapturesCursor: Bool
    public var dragScrollVerticalEnabled: Bool
    public var dragScrollHorizontalEnabled: Bool
    public var dragScrollMultiplier: Double
    public var dragScrollCapturesCursor: Bool
    public var dragScrollDistanceAccelerationEnabled: Bool
    public var dragScrollDistanceGain: Double
    public var dragScrollInertiaEnabled: Bool
    public var dragScrollInertiaAmount: Double
    public var easingEnabled: Bool

    public init(
        mode: HoldScrollMode = .scrollUp,
        pointsPerSecond: Double = 800,
        accelerationDuration: TimeInterval = 0.18,
        releaseDuration: TimeInterval = 0.14,
        joystickVerticalEnabled: Bool = true,
        joystickHorizontalEnabled: Bool = false,
        joystickCapturesCursor: Bool = true,
        dragScrollVerticalEnabled: Bool = true,
        dragScrollHorizontalEnabled: Bool = true,
        dragScrollMultiplier: Double = 1,
        dragScrollCapturesCursor: Bool = false,
        dragScrollDistanceAccelerationEnabled: Bool = false,
        dragScrollDistanceGain: Double = 1,
        dragScrollInertiaEnabled: Bool = true,
        dragScrollInertiaAmount: Double = 1,
        easingEnabled: Bool = true
    ) {
        self.mode = mode
        self.pointsPerSecond = pointsPerSecond
        self.accelerationDuration = accelerationDuration
        self.releaseDuration = releaseDuration
        self.joystickVerticalEnabled = joystickVerticalEnabled
        self.joystickHorizontalEnabled = joystickHorizontalEnabled
        self.joystickCapturesCursor = joystickCapturesCursor
        self.dragScrollVerticalEnabled = dragScrollVerticalEnabled
        self.dragScrollHorizontalEnabled = dragScrollHorizontalEnabled
        self.dragScrollMultiplier = dragScrollMultiplier
        self.dragScrollCapturesCursor = dragScrollCapturesCursor
        self.dragScrollDistanceAccelerationEnabled = dragScrollDistanceAccelerationEnabled
        self.dragScrollDistanceGain = dragScrollDistanceGain
        self.dragScrollInertiaEnabled = dragScrollInertiaEnabled
        self.dragScrollInertiaAmount = dragScrollInertiaAmount
        self.easingEnabled = easingEnabled
    }

    @available(*, deprecated, message: "Use init(mode:pointsPerSecond:accelerationDuration:releaseDuration:easingEnabled:) instead.")
    public init(
        direction: ScrollDirection,
        pointsPerSecond: Double = 800,
        accelerationDuration: TimeInterval = 0.18,
        releaseDuration: TimeInterval = 0.14,
        joystickEnabled: Bool = false,
        easingEnabled: Bool = true
    ) {
        self.init(
            mode: joystickEnabled
                ? .joystick
                : direction == .up ? .scrollUp : .scrollDown,
            pointsPerSecond: pointsPerSecond,
            accelerationDuration: accelerationDuration,
            releaseDuration: releaseDuration,
            joystickVerticalEnabled: true,
            joystickHorizontalEnabled: false,
            joystickCapturesCursor: true,
            easingEnabled: easingEnabled
        )
    }

    @available(*, deprecated, message: "Use mode instead.")
    public var direction: ScrollDirection {
        get { mode.direction ?? .up }
        set { mode = newValue == .up ? .scrollUp : .scrollDown }
    }

    @available(*, deprecated, message: "Use mode instead.")
    public var joystickEnabled: Bool {
        get { mode == .joystick }
        set {
            if newValue {
                mode = .joystick
            } else if mode == .joystick {
                mode = .scrollUp
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case direction
        case pointsPerSecond
        case accelerationDuration
        case releaseDuration
        case joystickVerticalEnabled
        case joystickHorizontalEnabled
        case joystickCapturesCursor
        case dragScrollVerticalEnabled
        case dragScrollHorizontalEnabled
        case dragScrollMultiplier
        case dragScrollCapturesCursor
        case dragScrollDistanceAccelerationEnabled
        case dragScrollDistanceGain
        case dragScrollInertiaEnabled
        case dragScrollInertiaAmount
        case joystickEnabled
        case easingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyDirection = try container.decodeIfPresent(ScrollDirection.self, forKey: .direction) ?? .up
        let legacyJoystickEnabled = try container.decodeIfPresent(Bool.self, forKey: .joystickEnabled) ?? false
        mode = try container.decodeIfPresent(HoldScrollMode.self, forKey: .mode)
            ?? (legacyJoystickEnabled
                ? .joystick
                : legacyDirection == .up ? .scrollUp : .scrollDown)
        pointsPerSecond = try container.decode(Double.self, forKey: .pointsPerSecond)
        accelerationDuration = try container.decode(TimeInterval.self, forKey: .accelerationDuration)
        releaseDuration = try container.decode(TimeInterval.self, forKey: .releaseDuration)
        joystickVerticalEnabled = try container.decodeIfPresent(Bool.self, forKey: .joystickVerticalEnabled) ?? true
        joystickHorizontalEnabled = try container.decodeIfPresent(Bool.self, forKey: .joystickHorizontalEnabled) ?? false
        joystickCapturesCursor = try container.decodeIfPresent(Bool.self, forKey: .joystickCapturesCursor) ?? true
        dragScrollVerticalEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragScrollVerticalEnabled) ?? true
        dragScrollHorizontalEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragScrollHorizontalEnabled) ?? true
        dragScrollMultiplier = try container.decodeIfPresent(Double.self, forKey: .dragScrollMultiplier) ?? 1
        dragScrollCapturesCursor = try container.decodeIfPresent(Bool.self, forKey: .dragScrollCapturesCursor) ?? false
        dragScrollDistanceAccelerationEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragScrollDistanceAccelerationEnabled) ?? false
        dragScrollDistanceGain = try container.decodeIfPresent(Double.self, forKey: .dragScrollDistanceGain) ?? 1
        dragScrollInertiaEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragScrollInertiaEnabled) ?? true
        dragScrollInertiaAmount = try container.decodeIfPresent(Double.self, forKey: .dragScrollInertiaAmount) ?? 1
        easingEnabled = try container.decodeIfPresent(Bool.self, forKey: .easingEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(mode.direction ?? .up, forKey: .direction)
        try container.encode(pointsPerSecond, forKey: .pointsPerSecond)
        try container.encode(accelerationDuration, forKey: .accelerationDuration)
        try container.encode(releaseDuration, forKey: .releaseDuration)
        try container.encode(joystickVerticalEnabled, forKey: .joystickVerticalEnabled)
        try container.encode(joystickHorizontalEnabled, forKey: .joystickHorizontalEnabled)
        try container.encode(joystickCapturesCursor, forKey: .joystickCapturesCursor)
        try container.encode(dragScrollVerticalEnabled, forKey: .dragScrollVerticalEnabled)
        try container.encode(dragScrollHorizontalEnabled, forKey: .dragScrollHorizontalEnabled)
        try container.encode(dragScrollMultiplier, forKey: .dragScrollMultiplier)
        try container.encode(dragScrollCapturesCursor, forKey: .dragScrollCapturesCursor)
        try container.encode(dragScrollDistanceAccelerationEnabled, forKey: .dragScrollDistanceAccelerationEnabled)
        try container.encode(dragScrollDistanceGain, forKey: .dragScrollDistanceGain)
        try container.encode(dragScrollInertiaEnabled, forKey: .dragScrollInertiaEnabled)
        try container.encode(dragScrollInertiaAmount, forKey: .dragScrollInertiaAmount)
        try container.encode(mode == .joystick, forKey: .joystickEnabled)
        try container.encode(easingEnabled, forKey: .easingEnabled)
    }
}

public enum WheelInputShape: String, Codable, CaseIterable, Equatable, Identifiable {
    case horizontalOnly
    case anyHorizontal

    public var id: String { rawValue }
}

public struct WheelActionOptions: Codable, Equatable {
    public var direction: ScrollDirection
    public var inputShape: WheelInputShape
    public var ignoreContinuousEvents: Bool
    public var preserveShiftGestures: Bool

    public init(
        direction: ScrollDirection = .up,
        inputShape: WheelInputShape = .horizontalOnly,
        ignoreContinuousEvents: Bool = true,
        preserveShiftGestures: Bool = true
    ) {
        self.direction = direction
        self.inputShape = inputShape
        self.ignoreContinuousEvents = ignoreContinuousEvents
        self.preserveShiftGestures = preserveShiftGestures
    }
}

public enum WheelMappingSource: String, Codable, CaseIterable, Equatable, Identifiable {
    case horizontalThumbwheel

    public var id: String { rawValue }
    public var displayName: String { "Horizontal thumbwheel" }
}

public struct ButtonClickMapping: Codable, Equatable, Identifiable {
    public var id: UUID
    public var isEnabled: Bool
    public var button: InputButton
    public var click: ButtonClickKind
    public var action: ScrollActionOptions
    public var label: String

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        button: InputButton,
        click: ButtonClickKind = .single,
        action: ScrollActionOptions,
        label: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.button = button
        self.click = click
        self.action = action
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case button
        case click
        case action
        case label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        button = try container.decode(InputButton.self, forKey: .button)
        click = try container.decode(ButtonClickKind.self, forKey: .click)
        action = try container.decode(ScrollActionOptions.self, forKey: .action)
        label = try container.decode(String.self, forKey: .label)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(button, forKey: .button)
        try container.encode(click, forKey: .click)
        try container.encode(action, forKey: .action)
        try container.encode(label, forKey: .label)
    }
}

public struct ButtonHoldMapping: Codable, Equatable, Identifiable {
    public var id: UUID
    public var isEnabled: Bool
    public var button: InputButton
    public var action: HoldActionOptions
    public var label: String

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        button: InputButton,
        action: HoldActionOptions,
        label: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.button = button
        self.action = action
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case button
        case action
        case label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        button = try container.decode(InputButton.self, forKey: .button)
        action = try container.decode(HoldActionOptions.self, forKey: .action)
        label = try container.decode(String.self, forKey: .label)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(button, forKey: .button)
        try container.encode(action, forKey: .action)
        try container.encode(label, forKey: .label)
    }
}

public struct WheelMapping: Codable, Equatable, Identifiable {
    public var id: UUID
    public var isEnabled: Bool
    public var source: WheelMappingSource
    public var action: WheelActionOptions
    public var label: String

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        source: WheelMappingSource = .horizontalThumbwheel,
        action: WheelActionOptions = WheelActionOptions(),
        label: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.source = source
        self.action = action
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case source
        case action
        case label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        source = try container.decode(WheelMappingSource.self, forKey: .source)
        action = try container.decode(WheelActionOptions.self, forKey: .action)
        label = try container.decode(String.self, forKey: .label)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(source, forKey: .source)
        try container.encode(action, forKey: .action)
        try container.encode(label, forKey: .label)
    }
}

public struct ConfigurationDocument: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var buttonClicks: [ButtonClickMapping]
    public var buttonHolds: [ButtonHoldMapping]
    public var wheelMappings: [WheelMapping]

    public init(
        version: Int = ConfigurationDocument.currentVersion,
        buttonClicks: [ButtonClickMapping],
        buttonHolds: [ButtonHoldMapping],
        wheelMappings: [WheelMapping]
    ) {
        self.version = version
        self.buttonClicks = buttonClicks
        self.buttonHolds = buttonHolds
        self.wheelMappings = wheelMappings
    }

    public static let defaults = ConfigurationDocument(
        buttonClicks: [
            ButtonClickMapping(
                button: .other(3),
                click: .single,
                action: ScrollActionOptions(direction: .down),
                label: "Back"
            ),
            ButtonClickMapping(
                button: .other(4),
                click: .single,
                action: ScrollActionOptions(direction: .up),
                label: "Forward"
            ),
        ],
        buttonHolds: [],
        wheelMappings: [
            WheelMapping(
                source: .horizontalThumbwheel,
                action: WheelActionOptions(direction: .up),
                label: "Thumbwheel"
            ),
        ]
    )
}

public struct Point2D: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D()

    public static func - (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}
