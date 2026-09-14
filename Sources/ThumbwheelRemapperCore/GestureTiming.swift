import Foundation

public struct GestureTimingPolicy: Equatable {
    public var doubleClickInterval: TimeInterval
    public var holdDelay: TimeInterval

    public init(
        doubleClickInterval: TimeInterval = 0.25,
        holdDelay: TimeInterval = 0.3
    ) {
        self.doubleClickInterval = max(doubleClickInterval, 0)
        self.holdDelay = max(holdDelay, 0)
    }

    public func delayBeforeSingle(hasDoubleMapping: Bool) -> TimeInterval {
        hasDoubleMapping ? doubleClickInterval : 0
    }
}

public enum GestureOutput: Equatable {
    case single(InputButton)
    case double(InputButton)
    case hold(InputButton)
}

public struct ButtonGestureRecognizer {
    private struct PendingGesture {
        var button: InputButton
        var startedAt: TimeInterval
        var hasSingle: Bool
        var hasDouble: Bool
        var hasHold: Bool
        var holdEmitted: Bool
        var isDown: Bool
    }

    public let timing: GestureTimingPolicy
    private var pending: PendingGesture?

    public init(timing: GestureTimingPolicy = GestureTimingPolicy()) {
        self.timing = timing
    }

    public var isWaiting: Bool {
        pending != nil
    }

    public mutating func buttonDown(
        _ button: InputButton,
        at timestamp: TimeInterval,
        hasSingleMapping: Bool,
        hasDoubleMapping: Bool,
        hasHoldMapping: Bool
    ) -> [GestureOutput] {
        var outputs = advance(to: timestamp)

        if let pending, pending.button == button {
            if pending.hasDouble,
               timestamp - pending.startedAt <= timing.doubleClickInterval {
                self.pending = nil
                outputs.append(.double(button))
                return outputs
            }
            self.pending = nil
        } else if pending != nil {
            self.pending = nil
        }

        let shouldWaitForHold = hasHoldMapping && !hasDoubleMapping
        let shouldWaitForDouble = hasDoubleMapping
        if shouldWaitForHold || shouldWaitForDouble {
            self.pending = PendingGesture(
                button: button,
                startedAt: timestamp,
                hasSingle: hasSingleMapping,
                hasDouble: hasDoubleMapping,
                hasHold: hasHoldMapping,
                holdEmitted: false,
                isDown: true
            )
        } else if hasSingleMapping {
            outputs.append(.single(button))
        }
        return outputs
    }

    public mutating func buttonUp(
        _ button: InputButton,
        at timestamp: TimeInterval
    ) -> [GestureOutput] {
        guard let currentPending = pending, currentPending.button == button else {
            return advance(to: timestamp)
        }
        if currentPending.holdEmitted {
            self.pending = nil
            return []
        }
        self.pending?.isDown = false
        var outputs = advance(to: timestamp)
        guard let pending = self.pending, pending.button == button else {
            return outputs
        }
        if pending.holdEmitted {
            self.pending = nil
            return outputs
        }
        if pending.hasDouble {
            return outputs
        }
        if pending.hasSingle {
            outputs.append(.single(button))
        }
        self.pending = nil
        return outputs
    }

    public mutating func advance(to timestamp: TimeInterval) -> [GestureOutput] {
        guard let pending else {
            return []
        }

        if pending.hasHold,
           pending.isDown,
           !pending.holdEmitted,
           timestamp - pending.startedAt >= timing.holdDelay {
            self.pending?.holdEmitted = true
            return [.hold(pending.button)]
        }

        if pending.hasDouble,
           (!pending.hasHold || !pending.isDown),
           timestamp - pending.startedAt >= timing.doubleClickInterval {
            self.pending = nil
            if pending.hasSingle {
                return [.single(pending.button)]
            }
        }
        return []
    }
}
