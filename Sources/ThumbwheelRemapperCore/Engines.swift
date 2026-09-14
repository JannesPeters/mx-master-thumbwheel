import Foundation

public struct DiscreteScrollAnimation: Equatable {
    public var distance: Double
    public var duration: TimeInterval
    public var easing: EasingCurve

    public init(
        distance: Double,
        duration: TimeInterval,
        easing: EasingCurve = .quickInLongOut
    ) {
        self.distance = distance
        self.duration = max(duration, 0)
        self.easing = easing
    }

    public func position(at elapsed: TimeInterval) -> Double {
        guard duration > 0 else {
            return elapsed >= 0 ? distance : 0
        }
        let progress = min(max(elapsed / duration, 0), 1)
        return distance * easing.value(at: progress)
    }

    public func delta(from previousElapsed: TimeInterval, to elapsed: TimeInterval) -> Double {
        position(at: elapsed) - position(at: previousElapsed)
    }
}

public struct ContinuousScrollEngine: Equatable {
    public private(set) var position: Double
    public private(set) var velocity: Double
    public var response: Double

    public init(response: Double = 1, position: Double = 0, velocity: Double = 0) {
        self.response = max(response, 0)
        self.position = position
        self.velocity = velocity
    }

    @discardableResult
    public mutating func advance(
        targetVelocity: Double,
        deltaTime: TimeInterval
    ) -> Double {
        let dt = max(deltaTime, 0)
        let blend = response == 0 ? 1 : min(max(dt * response, 0), 1)
        velocity += (targetVelocity - velocity) * blend
        let delta = velocity * dt
        position += delta
        return delta
    }

    public mutating func reset() {
        position = 0
        velocity = 0
    }
}

public struct DragScrollMomentumEngine: Equatable {
    public private(set) var velocity: Double
    public private(set) var isReleased: Bool
    public var friction: Double

    public init(friction: Double = 8) {
        self.velocity = 0
        self.isReleased = false
        self.friction = max(friction, 0)
    }

    public mutating func drag(delta: Double, deltaTime: TimeInterval) -> Double {
        isReleased = false
        let dt = max(deltaTime, 0)
        if dt > 0 {
            velocity = delta / dt
        }
        return delta
    }

    public mutating func release() {
        isReleased = true
    }

    public mutating func setVelocity(_ velocity: Double) {
        self.velocity = velocity
    }

    @discardableResult
    public mutating func advance(deltaTime: TimeInterval) -> Double {
        guard isReleased else { return 0 }
        let dt = max(deltaTime, 0)
        let delta = velocity * dt
        let decay = exp(-friction * dt)
        velocity *= decay
        if abs(velocity) < 0.01 {
            velocity = 0
        }
        return delta
    }
}

public struct JoystickDisplacement1D: Equatable {
    private var anchor: Double?

    public init() {
        anchor = nil
    }

    public var isStarted: Bool {
        anchor != nil
    }

    public mutating func update(pointer: Double) -> Double {
        guard let anchor else {
            self.anchor = pointer
            return 0
        }
        return pointer - anchor
    }

    public mutating func reset() {
        anchor = nil
    }
}

public struct JoystickDisplacement2D: Equatable {
    private var anchor: Point2D?

    public init() {
        anchor = nil
    }

    public var isStarted: Bool {
        anchor != nil
    }

    public mutating func update(pointer: Point2D) -> Point2D {
        guard let anchor else {
            self.anchor = pointer
            return .zero
        }
        return pointer - anchor
    }

    public mutating func reset() {
        anchor = nil
    }
}

public enum JoystickMath {
    public static func zeroStartDisplacement(
        pointer: Double,
        anchor: inout Double?
    ) -> Double {
        guard let anchor else {
            anchor = pointer
            return 0
        }
        return pointer - anchor
    }

    public static func zeroStartDisplacement(
        pointer: Point2D,
        anchor: inout Point2D?
    ) -> Point2D {
        guard let anchor else {
            anchor = pointer
            return .zero
        }
        return pointer - anchor
    }
}

public struct JoystickSpeedProfile: Equatable {
    public var activationDeadZone: Double
    public var forwardPointsPerSpeedStep: Double
    public var pauseZoneNearEdge: Double
    public var pauseZoneFarEdge: Double
    public var reversePointsPerSpeedStep: Double
    public var minimumSpeedMultiplier: Double
    public var maximumSpeedMultiplier: Double

    public init(
        activationDeadZone: Double = 8,
        forwardPointsPerSpeedStep: Double = 100,
        pauseZoneNearEdge: Double = -60,
        pauseZoneFarEdge: Double = -140,
        reversePointsPerSpeedStep: Double = 80,
        minimumSpeedMultiplier: Double = -2,
        maximumSpeedMultiplier: Double = 3
    ) {
        self.activationDeadZone = activationDeadZone
        self.forwardPointsPerSpeedStep = forwardPointsPerSpeedStep
        self.pauseZoneNearEdge = pauseZoneNearEdge
        self.pauseZoneFarEdge = pauseZoneFarEdge
        self.reversePointsPerSpeedStep = reversePointsPerSpeedStep
        self.minimumSpeedMultiplier = minimumSpeedMultiplier
        self.maximumSpeedMultiplier = maximumSpeedMultiplier
    }

    public func multiplier(
        for displacement: Double,
        direction: Double = 1,
        centeredMode: Bool = false
    ) -> Double {
        let signedDistance = displacement * direction
        if centeredMode {
            let centeredPauseRadius = abs(pauseZoneFarEdge - pauseZoneNearEdge) / 2
            if abs(signedDistance) <= centeredPauseRadius {
                return 0
            }
            if signedDistance > 0 {
                return min(
                    (signedDistance - centeredPauseRadius) / forwardPointsPerSpeedStep,
                    maximumSpeedMultiplier
                )
            }
            return max(
                (signedDistance + centeredPauseRadius) / reversePointsPerSpeedStep,
                minimumSpeedMultiplier
            )
        }

        let adjustedDistance: Double
        if abs(signedDistance) <= activationDeadZone {
            adjustedDistance = 0
        } else if signedDistance > 0 {
            adjustedDistance = signedDistance - activationDeadZone
        } else {
            adjustedDistance = signedDistance + activationDeadZone
        }

        switch adjustedDistance {
        case 0...:
            return min(
                1 + (adjustedDistance / forwardPointsPerSpeedStep),
                maximumSpeedMultiplier
            )
        case pauseZoneNearEdge..<0:
            return 1 - (adjustedDistance / pauseZoneNearEdge)
        case pauseZoneFarEdge...pauseZoneNearEdge:
            return 0
        default:
            return max(
                -((pauseZoneFarEdge - adjustedDistance) / reversePointsPerSpeedStep),
                minimumSpeedMultiplier
            )
        }
    }
}
