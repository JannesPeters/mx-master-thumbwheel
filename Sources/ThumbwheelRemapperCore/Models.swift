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
            return "Other \(number)"
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

    public init(
        direction: ScrollDirection,
        amount: ScrollAmount = .fixed(40),
        duration: TimeInterval = 0.18,
        easing: EasingCurve = .quickInLongOut
    ) {
        self.direction = direction
        self.amount = amount
        self.duration = duration
        self.easing = easing
    }
}

public struct HoldActionOptions: Codable, Equatable {
    public var direction: ScrollDirection
    public var pointsPerSecond: Double
    public var accelerationDuration: TimeInterval
    public var releaseDuration: TimeInterval
    public var joystickEnabled: Bool

    public init(
        direction: ScrollDirection,
        pointsPerSecond: Double = 800,
        accelerationDuration: TimeInterval = 0.18,
        releaseDuration: TimeInterval = 0.14,
        joystickEnabled: Bool = true
    ) {
        self.direction = direction
        self.pointsPerSecond = pointsPerSecond
        self.accelerationDuration = accelerationDuration
        self.releaseDuration = releaseDuration
        self.joystickEnabled = joystickEnabled
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
    public var button: InputButton
    public var click: ButtonClickKind
    public var action: ScrollActionOptions
    public var label: String

    public init(
        id: UUID = UUID(),
        button: InputButton,
        click: ButtonClickKind = .single,
        action: ScrollActionOptions,
        label: String = ""
    ) {
        self.id = id
        self.button = button
        self.click = click
        self.action = action
        self.label = label
    }
}

public struct ButtonHoldMapping: Codable, Equatable, Identifiable {
    public var id: UUID
    public var button: InputButton
    public var action: HoldActionOptions
    public var label: String

    public init(
        id: UUID = UUID(),
        button: InputButton,
        action: HoldActionOptions,
        label: String = ""
    ) {
        self.id = id
        self.button = button
        self.action = action
        self.label = label
    }
}

public struct WheelMapping: Codable, Equatable, Identifiable {
    public var id: UUID
    public var source: WheelMappingSource
    public var action: WheelActionOptions
    public var label: String

    public init(
        id: UUID = UUID(),
        source: WheelMappingSource = .horizontalThumbwheel,
        action: WheelActionOptions = WheelActionOptions(),
        label: String = ""
    ) {
        self.id = id
        self.source = source
        self.action = action
        self.label = label
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
