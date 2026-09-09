import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum RemappingDefaults {
    static let thumbwheelRemappingEnabled = true
    static let verticalScrollDirection: Int64 = 1
    static let requireLineBasedScrollEvents = true
    static let thumbButtonRemappingEnabled = true
    static let singleClickEasingEnabled = true
    static let buttonScrollEasingEnabled = true
    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4
    static let singlePressDistance = 40.0
    static let singleClickDuration: TimeInterval = 0.18
    static let initialDelay: TimeInterval = 0.3
    static let interval: TimeInterval = 0.05
    static let easeInDuration: TimeInterval = 0.18
    static let easeOutDuration: TimeInterval = 0.14

    static let buttonNumberRange: ClosedRange<Int64> = 0...31
    static let singlePressDistanceRange = 5.0...1_000.0
    static let initialDelayRange: ClosedRange<TimeInterval> = 0.05...2.0
    static let intervalRange: ClosedRange<TimeInterval> = 0.01...0.5
    static let easeDurationRange: ClosedRange<TimeInterval> = 0.05...1.0
}

private enum SmoothButtonScroll {
    // Keep the existing repeat-interval-to-speed relationship independent
    // from the configurable distance used for a single button press.
    static let holdSpeedReferenceDistance = 40.0
    static let frameInterval: TimeInterval = 1.0 / 120.0
    static let singleClickFrameInterval: TimeInterval = 1.0 / 240.0
    static let maximumSingleClickFrameDuration: TimeInterval = 1.0 / 120.0
    static let maximumFrameDuration: TimeInterval = 1.0 / 30.0
}

final class RemappingSettings {
    static let didChangeNotification = Notification.Name("RemappingSettings.didChange")

    private let defaults: UserDefaults
    private let thumbwheelRemappingEnabledKey = "ThumbwheelRemappingEnabled"
    private let verticalScrollDirectionKey = "ThumbwheelVerticalScrollDirection"
    private let requireLineBasedScrollEventsKey = "RequireLineBasedScrollEvents"
    private let thumbButtonRemappingEnabledKey = "ThumbButtonRemappingEnabled"
    private let singleClickEasingEnabledKey = "ThumbButtonSingleClickEasingEnabled"
    private let buttonScrollEasingEnabledKey = "ThumbButtonScrollEasingEnabled"
    private let backButtonNumberKey = "BackButtonNumber"
    private let forwardButtonNumberKey = "ForwardButtonNumber"
    private let singlePressDistanceKey = "ThumbButtonSinglePressDistance"
    private let singleClickDurationKey = "ThumbButtonSingleClickDuration"
    private let initialDelayKey = "ThumbButtonScrollRepeatInitialDelay"
    private let intervalKey = "ThumbButtonScrollRepeatInterval"
    private let easeInDurationKey = "ThumbButtonScrollEaseInDuration"
    private let easeOutDurationKey = "ThumbButtonScrollEaseOutDuration"

    private(set) var thumbwheelRemappingEnabled: Bool
    private(set) var verticalScrollDirection: Int64
    private(set) var requireLineBasedScrollEvents: Bool
    private(set) var thumbButtonRemappingEnabled: Bool
    private(set) var singleClickEasingEnabled: Bool
    private(set) var buttonScrollEasingEnabled: Bool
    private(set) var backButtonNumber: Int64
    private(set) var forwardButtonNumber: Int64
    private(set) var singlePressDistance: Double
    private(set) var singleClickDuration: TimeInterval
    private(set) var initialDelay: TimeInterval
    private(set) var interval: TimeInterval
    private(set) var easeInDuration: TimeInterval
    private(set) var easeOutDuration: TimeInterval

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        thumbwheelRemappingEnabled = Self.storedBool(
            in: defaults,
            forKey: thumbwheelRemappingEnabledKey,
            fallback: RemappingDefaults.thumbwheelRemappingEnabled
        )
        verticalScrollDirection = Self.normalizedDirection(
            Self.storedInt64(
                in: defaults,
                forKey: verticalScrollDirectionKey,
                fallback: RemappingDefaults.verticalScrollDirection
            )
        )
        requireLineBasedScrollEvents = Self.storedBool(
            in: defaults,
            forKey: requireLineBasedScrollEventsKey,
            fallback: RemappingDefaults.requireLineBasedScrollEvents
        )
        thumbButtonRemappingEnabled = Self.storedBool(
            in: defaults,
            forKey: thumbButtonRemappingEnabledKey,
            fallback: RemappingDefaults.thumbButtonRemappingEnabled
        )
        singleClickEasingEnabled = Self.storedBool(
            in: defaults,
            forKey: singleClickEasingEnabledKey,
            fallback: RemappingDefaults.singleClickEasingEnabled
        )
        buttonScrollEasingEnabled = Self.storedBool(
            in: defaults,
            forKey: buttonScrollEasingEnabledKey,
            fallback: RemappingDefaults.buttonScrollEasingEnabled
        )
        backButtonNumber = Self.clamp(
            Self.storedInt64(
                in: defaults,
                forKey: backButtonNumberKey,
                fallback: RemappingDefaults.backButtonNumber
            ),
            to: RemappingDefaults.buttonNumberRange
        )
        forwardButtonNumber = Self.clamp(
            Self.storedInt64(
                in: defaults,
                forKey: forwardButtonNumberKey,
                fallback: RemappingDefaults.forwardButtonNumber
            ),
            to: RemappingDefaults.buttonNumberRange
        )
        if backButtonNumber == forwardButtonNumber {
            backButtonNumber = RemappingDefaults.backButtonNumber
            forwardButtonNumber = RemappingDefaults.forwardButtonNumber
        }

        let storedSinglePressDistance = defaults.object(forKey: singlePressDistanceKey) as? Double
        let storedSingleClickDuration = defaults.object(forKey: singleClickDurationKey) as? Double
        let storedDelay = defaults.object(forKey: initialDelayKey) as? Double
        let storedInterval = defaults.object(forKey: intervalKey) as? Double
        let storedEaseInDuration = defaults.object(forKey: easeInDurationKey) as? Double
        let storedEaseOutDuration = defaults.object(forKey: easeOutDurationKey) as? Double
        singlePressDistance = Self.clamp(
            storedSinglePressDistance ?? RemappingDefaults.singlePressDistance,
            to: RemappingDefaults.singlePressDistanceRange
        )
        singleClickDuration = Self.clamp(
            storedSingleClickDuration ?? RemappingDefaults.singleClickDuration,
            to: RemappingDefaults.easeDurationRange
        )
        initialDelay = Self.clamp(storedDelay ?? RemappingDefaults.initialDelay, to: RemappingDefaults.initialDelayRange)
        interval = Self.clamp(storedInterval ?? RemappingDefaults.interval, to: RemappingDefaults.intervalRange)
        easeInDuration = Self.clamp(
            storedEaseInDuration ?? RemappingDefaults.easeInDuration,
            to: RemappingDefaults.easeDurationRange
        )
        easeOutDuration = Self.clamp(
            storedEaseOutDuration ?? RemappingDefaults.easeOutDuration,
            to: RemappingDefaults.easeDurationRange
        )
    }

    func setThumbwheelRemappingEnabled(_ enabled: Bool) {
        guard enabled != thumbwheelRemappingEnabled else { return }
        thumbwheelRemappingEnabled = enabled
        defaults.set(enabled, forKey: thumbwheelRemappingEnabledKey)
        notifyChanged()
    }

    func setVerticalScrollDirection(_ direction: Int64) {
        let normalized = Self.normalizedDirection(direction)
        guard normalized != verticalScrollDirection else { return }
        verticalScrollDirection = normalized
        defaults.set(normalized, forKey: verticalScrollDirectionKey)
        notifyChanged()
    }

    func setRequireLineBasedScrollEvents(_ required: Bool) {
        guard required != requireLineBasedScrollEvents else { return }
        requireLineBasedScrollEvents = required
        defaults.set(required, forKey: requireLineBasedScrollEventsKey)
        notifyChanged()
    }

    func setThumbButtonRemappingEnabled(_ enabled: Bool) {
        guard enabled != thumbButtonRemappingEnabled else { return }
        thumbButtonRemappingEnabled = enabled
        defaults.set(enabled, forKey: thumbButtonRemappingEnabledKey)
        notifyChanged()
    }

    func setButtonScrollEasingEnabled(_ enabled: Bool) {
        guard enabled != buttonScrollEasingEnabled else { return }
        buttonScrollEasingEnabled = enabled
        defaults.set(enabled, forKey: buttonScrollEasingEnabledKey)
        notifyChanged()
    }

    func setSingleClickEasingEnabled(_ enabled: Bool) {
        guard enabled != singleClickEasingEnabled else { return }
        singleClickEasingEnabled = enabled
        defaults.set(enabled, forKey: singleClickEasingEnabledKey)
        notifyChanged()
    }

    @discardableResult
    func setBackButtonNumber(_ buttonNumber: Int64) -> Bool {
        setButtonNumbers(back: buttonNumber, forward: forwardButtonNumber)
    }

    @discardableResult
    func setForwardButtonNumber(_ buttonNumber: Int64) -> Bool {
        setButtonNumbers(back: backButtonNumber, forward: buttonNumber)
    }

    @discardableResult
    func setButtonNumbers(back: Int64, forward: Int64) -> Bool {
        let clampedBack = Self.clamp(back, to: RemappingDefaults.buttonNumberRange)
        let clampedForward = Self.clamp(forward, to: RemappingDefaults.buttonNumberRange)
        guard clampedBack != clampedForward else { return false }
        guard clampedBack != backButtonNumber || clampedForward != forwardButtonNumber else {
            return true
        }

        backButtonNumber = clampedBack
        forwardButtonNumber = clampedForward
        defaults.set(clampedBack, forKey: backButtonNumberKey)
        defaults.set(clampedForward, forKey: forwardButtonNumberKey)
        notifyChanged()
        return true
    }

    func setInitialDelay(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: RemappingDefaults.initialDelayRange)
        guard clamped != initialDelay else { return }
        initialDelay = clamped
        defaults.set(clamped, forKey: initialDelayKey)
        notifyChanged()
    }

    func setSinglePressDistance(_ value: Double) {
        let clamped = Self.clamp(value, to: RemappingDefaults.singlePressDistanceRange)
        guard clamped != singlePressDistance else { return }
        singlePressDistance = clamped
        defaults.set(clamped, forKey: singlePressDistanceKey)
        notifyChanged()
    }

    func setSingleClickDuration(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: RemappingDefaults.easeDurationRange)
        guard clamped != singleClickDuration else { return }
        singleClickDuration = clamped
        defaults.set(clamped, forKey: singleClickDurationKey)
        notifyChanged()
    }

    func setInterval(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: RemappingDefaults.intervalRange)
        guard clamped != interval else { return }
        interval = clamped
        defaults.set(clamped, forKey: intervalKey)
        notifyChanged()
    }

    func setEaseInDuration(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: RemappingDefaults.easeDurationRange)
        guard clamped != easeInDuration else { return }
        easeInDuration = clamped
        defaults.set(clamped, forKey: easeInDurationKey)
        notifyChanged()
    }

    func setEaseOutDuration(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: RemappingDefaults.easeDurationRange)
        guard clamped != easeOutDuration else { return }
        easeOutDuration = clamped
        defaults.set(clamped, forKey: easeOutDurationKey)
        notifyChanged()
    }

    func restoreDefaults() {
        setThumbwheelRemappingEnabled(RemappingDefaults.thumbwheelRemappingEnabled)
        setVerticalScrollDirection(RemappingDefaults.verticalScrollDirection)
        setRequireLineBasedScrollEvents(RemappingDefaults.requireLineBasedScrollEvents)
        setThumbButtonRemappingEnabled(RemappingDefaults.thumbButtonRemappingEnabled)
        setSingleClickEasingEnabled(RemappingDefaults.singleClickEasingEnabled)
        setButtonScrollEasingEnabled(RemappingDefaults.buttonScrollEasingEnabled)
        setButtonNumbers(
            back: RemappingDefaults.backButtonNumber,
            forward: RemappingDefaults.forwardButtonNumber
        )
        setSinglePressDistance(RemappingDefaults.singlePressDistance)
        setSingleClickDuration(RemappingDefaults.singleClickDuration)
        setInitialDelay(RemappingDefaults.initialDelay)
        setInterval(RemappingDefaults.interval)
        setEaseInDuration(RemappingDefaults.easeInDuration)
        setEaseOutDuration(RemappingDefaults.easeOutDuration)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func storedBool(in defaults: UserDefaults, forKey key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private static func storedInt64(in defaults: UserDefaults, forKey key: String, fallback: Int64) -> Int64 {
        (defaults.object(forKey: key) as? NSNumber)?.int64Value ?? fallback
    }

    private static func normalizedDirection(_ direction: Int64) -> Int64 {
        direction < 0 ? -1 : 1
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Int64, to range: ClosedRange<Int64>) -> Int64 {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

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

private func writeDeltas(
    _ deltas: ScrollDeltas,
    to event: CGEvent,
    axis: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField),
    direction: Int64
) {
    event.setIntegerValueField(axis.integer, value: deltas.integer * direction)
    event.setDoubleValueField(axis.fixedPoint, value: deltas.fixedPoint * Double(direction))
    event.setIntegerValueField(axis.point, value: deltas.point * direction)
}

private func clearDeltas(in event: CGEvent, axis: (integer: CGEventField, fixedPoint: CGEventField, point: CGEventField)) {
    event.setIntegerValueField(axis.integer, value: 0)
    event.setDoubleValueField(axis.fixedPoint, value: 0)
    event.setIntegerValueField(axis.point, value: 0)
}

private enum ButtonScrollPhase: Equatable {
    case idle
    case waitingForHold
    case holding
    case releasingHold
    case animatingClick
}

private final class EventTapController {
    private(set) var eventTap: CFMachPort?
    private var activeScrollButtonNumber: Int64?
    private var activeScrollTimer: Timer?
    private var buttonScrollPhase = ButtonScrollPhase.idle
    private var activeScrollDirection: Int32 = 0
    private var activeSinglePressDistance = 0.0
    private var activeSingleClickUsesEasing = false
    private var activeSingleClickDuration: TimeInterval = 0
    private var activeScrollPointsPerSecond = 0.0
    private var activeEaseInDuration: TimeInterval = 0
    private var activeEaseOutDuration: TimeInterval = 0
    private var activeHoldUsesEasing = false
    private var phaseStartTimestamp: TimeInterval?
    private var holdReleaseVelocity = 0.0
    private var lastScrollFrameTimestamp: TimeInterval?
    private var clickAnimationElapsedDuration: TimeInterval = 0
    private var lastAnimatedDistance = 0.0
    private var fractionalPointCarry = 0.0
    private var settingsObserver: NSObjectProtocol?
    private let settings: RemappingSettings

    init(settings: RemappingSettings) {
        self.settings = settings
        settingsObserver = NotificationCenter.default.addObserver(
            forName: RemappingSettings.didChangeNotification,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.settings.thumbButtonRemappingEnabled else { return }
            self.stopButtonScroll()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

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
            guard settings.thumbButtonRemappingEnabled else {
                return Unmanaged.passUnretained(event)
            }

            guard let scrollDirection = scrollDirection(for: event) else {
                return Unmanaged.passUnretained(event)
            }

            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            startButtonScroll(direction: scrollDirection, buttonNumber: buttonNumber)
            return nil

        case .otherMouseUp:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            if buttonNumber == activeScrollButtonNumber {
                finishButtonScroll()
                return nil
            }

            guard settings.thumbButtonRemappingEnabled, isMappedThumbButton(event) else {
                return Unmanaged.passUnretained(event)
            }
            return nil

        case .scrollWheel:
            return processScrollWheel(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func processScrollWheel(_ event: CGEvent) -> Unmanaged<CGEvent> {
        guard settings.thumbwheelRemappingEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // Shift+scroll remains the native horizontal-scroll gesture.
        guard !event.flags.contains(.maskShift) else {
            return Unmanaged.passUnretained(event)
        }

        if settings.requireLineBasedScrollEvents {
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

        writeDeltas(
            horizontalAxis,
            to: event,
            axis: verticalAxisFields,
            direction: settings.verticalScrollDirection
        )
        clearDeltas(in: event, axis: horizontalAxisFields)
        return Unmanaged.passUnretained(event)
    }

    private func isMappedThumbButton(_ event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        return buttonNumber == settings.backButtonNumber || buttonNumber == settings.forwardButtonNumber
    }

    private func scrollDirection(for event: CGEvent) -> Int32? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        switch buttonNumber {
        case settings.forwardButtonNumber:
            return 1
        case settings.backButtonNumber:
            return -1
        default:
            return nil
        }
    }

    private func startButtonScroll(direction: Int32, buttonNumber: Int64) {
        stopButtonScroll()
        activeScrollButtonNumber = buttonNumber
        activeScrollDirection = direction
        activeSinglePressDistance = settings.singlePressDistance
        activeSingleClickUsesEasing = settings.singleClickEasingEnabled
        activeSingleClickDuration = settings.singleClickDuration
        activeScrollPointsPerSecond = SmoothButtonScroll.holdSpeedReferenceDistance / settings.interval
        activeEaseInDuration = settings.easeInDuration
        activeEaseOutDuration = settings.easeOutDuration
        activeHoldUsesEasing = settings.buttonScrollEasingEnabled
        fractionalPointCarry = 0

        buttonScrollPhase = .waitingForHold
        let timer = Timer(
            fire: Date().addingTimeInterval(settings.initialDelay),
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            self?.beginLongPressScroll()
        }
        timer.tolerance = min(settings.initialDelay / 10, 0.02)
        RunLoop.current.add(timer, forMode: .common)
        activeScrollTimer = timer
    }

    private func beginLongPressScroll() {
        guard buttonScrollPhase == .waitingForHold, activeScrollButtonNumber != nil else {
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        buttonScrollPhase = .holding
        phaseStartTimestamp = timestamp
        lastScrollFrameTimestamp = timestamp
        fractionalPointCarry = 0
        startScrollFrameTimer(interval: SmoothButtonScroll.frameInterval)
    }

    private func startScrollFrameTimer(interval: TimeInterval) {
        activeScrollTimer?.invalidate()
        let timer = Timer(
            timeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.postButtonScrollFrame()
        }
        timer.tolerance = interval / 8
        RunLoop.current.add(timer, forMode: .common)
        activeScrollTimer = timer
    }

    private func startSingleClickScroll() {
        activeScrollTimer?.invalidate()
        activeScrollTimer = nil
        activeScrollButtonNumber = nil

        guard activeSingleClickUsesEasing else {
            postVerticalScroll(
                direction: activeScrollDirection,
                points: Int32(activeSinglePressDistance.rounded())
            )
            stopButtonScroll()
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        buttonScrollPhase = .animatingClick
        phaseStartTimestamp = timestamp
        lastScrollFrameTimestamp = timestamp
        clickAnimationElapsedDuration = 0
        lastAnimatedDistance = 0
        fractionalPointCarry = 0
        startScrollFrameTimer(interval: SmoothButtonScroll.singleClickFrameInterval)
    }

    private func finishButtonScroll() {
        switch buttonScrollPhase {
        case .waitingForHold:
            startSingleClickScroll()

        case .holding:
            activeScrollButtonNumber = nil
            guard activeHoldUsesEasing else {
                stopButtonScroll()
                return
            }

            let timestamp = ProcessInfo.processInfo.systemUptime
            holdReleaseVelocity = holdVelocity(at: timestamp)
            buttonScrollPhase = .releasingHold
            phaseStartTimestamp = timestamp

        case .idle, .releasingHold, .animatingClick:
            stopButtonScroll()
        }
    }

    private func stopButtonScroll() {
        activeScrollTimer?.invalidate()
        activeScrollTimer = nil
        activeScrollButtonNumber = nil
        buttonScrollPhase = .idle
        activeScrollDirection = 0
        activeSinglePressDistance = 0
        activeSingleClickUsesEasing = false
        activeSingleClickDuration = 0
        activeScrollPointsPerSecond = 0
        activeEaseInDuration = 0
        activeEaseOutDuration = 0
        activeHoldUsesEasing = false
        phaseStartTimestamp = nil
        holdReleaseVelocity = 0
        lastScrollFrameTimestamp = nil
        clickAnimationElapsedDuration = 0
        lastAnimatedDistance = 0
        fractionalPointCarry = 0
    }

    private func postButtonScrollFrame() {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let frameDuration = elapsedFrameDuration(at: timestamp)

        switch buttonScrollPhase {
        case .holding:
            postAccumulatedScroll(points: holdVelocity(at: timestamp) * frameDuration)

        case .releasingHold:
            guard let phaseStartTimestamp else {
                stopButtonScroll()
                return
            }
            let progress = min(
                max(timestamp - phaseStartTimestamp, 0) / activeEaseOutDuration,
                1
            )
            postAccumulatedScroll(
                points: holdReleaseVelocity * (1 - smoothStep(progress)) * frameDuration
            )
            if progress >= 1 {
                flushAccumulatedScroll()
                stopButtonScroll()
            }

        case .animatingClick:
            clickAnimationElapsedDuration = min(
                clickAnimationElapsedDuration
                    + min(frameDuration, SmoothButtonScroll.maximumSingleClickFrameDuration),
                activeSingleClickDuration
            )
            let progress = clickAnimationElapsedDuration / activeSingleClickDuration
            let distance = activeSinglePressDistance * quickInLongOut(progress)
            postAccumulatedScroll(points: max(distance - lastAnimatedDistance, 0))
            lastAnimatedDistance = distance
            if progress >= 1 {
                flushAccumulatedScroll()
                stopButtonScroll()
            }

        case .idle, .waitingForHold:
            break
        }
    }

    private func holdVelocity(at timestamp: TimeInterval) -> Double {
        guard activeHoldUsesEasing, let phaseStartTimestamp else {
            return activeScrollPointsPerSecond
        }

        let easeInProgress = min(max(timestamp - phaseStartTimestamp, 0) / activeEaseInDuration, 1)
        return activeScrollPointsPerSecond * smoothStep(easeInProgress)
    }

    private func elapsedFrameDuration(at timestamp: TimeInterval) -> TimeInterval {
        guard let previousTimestamp = lastScrollFrameTimestamp else {
            lastScrollFrameTimestamp = timestamp
            return 0
        }

        lastScrollFrameTimestamp = timestamp
        return min(
            max(timestamp - previousTimestamp, 0),
            SmoothButtonScroll.maximumFrameDuration
        )
    }

    private func postAccumulatedScroll(points: Double) {
        fractionalPointCarry += points

        let wholePoints = Int32(fractionalPointCarry.rounded(.towardZero))
        guard wholePoints > 0 else { return }
        fractionalPointCarry -= Double(wholePoints)
        postVerticalScroll(direction: activeScrollDirection, points: wholePoints)
    }

    private func flushAccumulatedScroll() {
        let remainingPoints = Int32(fractionalPointCarry.rounded())
        guard remainingPoints > 0 else { return }
        fractionalPointCarry = 0
        postVerticalScroll(direction: activeScrollDirection, points: remainingPoints)
    }

    private func smoothStep(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }

    private func quickInLongOut(_ progress: Double) -> Double {
        let accelerationShare = 0.2

        if progress < accelerationShare {
            let normalized = progress / accelerationShare
            return accelerationShare * (1 - cos(normalized * .pi / 2))
        }

        let decelerationShare = 1 - accelerationShare
        let normalized = (progress - accelerationShare) / decelerationShare
        return accelerationShare + decelerationShare * sin(normalized * .pi / 2)
    }

    private func postVerticalScroll(direction: Int32, points: Int32) {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: direction * points,
            wheel2: 0,
            wheel3: 0
        ) else {
            fail("Could not create a synthesized vertical scroll event.")
        }

        scrollEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
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

private func makeStatusItemImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSGraphicsContext.current?.shouldAntialias = true
        NSColor.black.setStroke()

        let mouse = NSBezierPath()
        mouse.move(to: NSPoint(x: 9, y: 1.5))
        mouse.curve(
            to: NSPoint(x: 4.25, y: 9),
            controlPoint1: NSPoint(x: 5.75, y: 1.8),
            controlPoint2: NSPoint(x: 4.1, y: 4.8)
        )
        mouse.curve(
            to: NSPoint(x: 9, y: 16.5),
            controlPoint1: NSPoint(x: 4.4, y: 13.2),
            controlPoint2: NSPoint(x: 6.1, y: 16.2)
        )
        mouse.curve(
            to: NSPoint(x: 13.75, y: 9),
            controlPoint1: NSPoint(x: 11.9, y: 16.2),
            controlPoint2: NSPoint(x: 13.6, y: 13.2)
        )
        mouse.curve(
            to: NSPoint(x: 9, y: 1.5),
            controlPoint1: NSPoint(x: 13.9, y: 4.8),
            controlPoint2: NSPoint(x: 12.25, y: 1.8)
        )
        mouse.close()
        mouse.lineWidth = 1.35
        mouse.lineJoinStyle = .round
        mouse.stroke()

        let buttonDivider = NSBezierPath()
        buttonDivider.move(to: NSPoint(x: 9, y: 16.15))
        buttonDivider.line(to: NSPoint(x: 9, y: 11.9))
        buttonDivider.lineWidth = 1.15
        buttonDivider.lineCapStyle = .round
        buttonDivider.stroke()

        let thumbwheel = NSBezierPath(
            roundedRect: NSRect(x: 2.65, y: 7.1, width: 2.7, height: 5.2),
            xRadius: 1.3,
            yRadius: 1.3
        )
        thumbwheel.lineWidth = 1.2
        thumbwheel.stroke()

        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Thumbwheel Remapper"
    return image
}

private final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let settings: RemappingSettings

    private let thumbwheelEnabledCheckbox = NSButton()
    private let directionPopUp = NSPopUpButton()
    private let lineBasedCheckbox = NSButton()
    private let thumbButtonsEnabledCheckbox = NSButton()
    private let backButtonPopUp = NSPopUpButton()
    private let forwardButtonPopUp = NSPopUpButton()
    private let singlePressDistanceSlider = NSSlider()
    private let singlePressDistanceValueLabel = NSTextField(labelWithString: "")
    private let singleClickEasingCheckbox = NSButton()
    private let singleClickDurationSlider = NSSlider()
    private let singleClickDurationValueLabel = NSTextField(labelWithString: "")
    private let delaySlider = NSSlider()
    private let delayValueLabel = NSTextField(labelWithString: "")
    private let intervalSlider = NSSlider()
    private let intervalValueLabel = NSTextField(labelWithString: "")
    private let longPressEasingCheckbox = NSButton()
    private let easeInSlider = NSSlider()
    private let easeInValueLabel = NSTextField(labelWithString: "")
    private let easeOutSlider = NSSlider()
    private let easeOutValueLabel = NSTextField(labelWithString: "")
    private let buttonValidationLabel = NSTextField(labelWithString: "")

    init(settings: RemappingSettings) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Thumbwheel Remapper"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        refreshControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent(in window: NSWindow) {
        configureCheckbox(
            thumbwheelEnabledCheckbox,
            title: "Convert horizontal movement to vertical scrolling",
            action: #selector(thumbwheelEnabledChanged)
        )

        directionPopUp.addItems(withTitles: ["Keep scroll direction", "Reverse scroll direction"])
        directionPopUp.target = self
        directionPopUp.action = #selector(directionChanged)
        directionPopUp.widthAnchor.constraint(equalToConstant: 220).isActive = true

        configureCheckbox(
            lineBasedCheckbox,
            title: "Ignore continuous trackpad-style gestures",
            action: #selector(lineBasedRequirementChanged)
        )

        configureCheckbox(
            thumbButtonsEnabledCheckbox,
            title: "Use Back and Forward buttons for vertical scrolling",
            action: #selector(thumbButtonsEnabledChanged)
        )
        configureCheckbox(
            singleClickEasingCheckbox,
            title: "Ease each click",
            action: #selector(singleClickEasingChanged)
        )
        configureCheckbox(
            longPressEasingCheckbox,
            title: "Ease acceleration and release",
            action: #selector(longPressEasingChanged)
        )

        let buttonTitles = RemappingDefaults.buttonNumberRange.map { "Button \($0)" }
        backButtonPopUp.addItems(withTitles: buttonTitles)
        backButtonPopUp.target = self
        backButtonPopUp.action = #selector(backButtonNumberChanged)
        backButtonPopUp.widthAnchor.constraint(equalToConstant: 120).isActive = true
        forwardButtonPopUp.addItems(withTitles: buttonTitles)
        forwardButtonPopUp.target = self
        forwardButtonPopUp.action = #selector(forwardButtonNumberChanged)
        forwardButtonPopUp.widthAnchor.constraint(equalToConstant: 120).isActive = true

        singlePressDistanceSlider.minValue = RemappingDefaults.singlePressDistanceRange.lowerBound
        singlePressDistanceSlider.maxValue = RemappingDefaults.singlePressDistanceRange.upperBound
        singlePressDistanceSlider.target = self
        singlePressDistanceSlider.action = #selector(singlePressDistanceSliderChanged)
        singlePressDistanceSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        singleClickDurationSlider.minValue = RemappingDefaults.easeDurationRange.lowerBound
        singleClickDurationSlider.maxValue = RemappingDefaults.easeDurationRange.upperBound
        singleClickDurationSlider.target = self
        singleClickDurationSlider.action = #selector(singleClickDurationSliderChanged)
        singleClickDurationSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        delaySlider.minValue = RemappingDefaults.initialDelayRange.lowerBound
        delaySlider.maxValue = RemappingDefaults.initialDelayRange.upperBound
        delaySlider.target = self
        delaySlider.action = #selector(delaySliderChanged)
        delaySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        intervalSlider.minValue = RemappingDefaults.intervalRange.lowerBound
        intervalSlider.maxValue = RemappingDefaults.intervalRange.upperBound
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalSliderChanged)
        intervalSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        easeInSlider.minValue = RemappingDefaults.easeDurationRange.lowerBound
        easeInSlider.maxValue = RemappingDefaults.easeDurationRange.upperBound
        easeInSlider.target = self
        easeInSlider.action = #selector(easeInSliderChanged)
        easeInSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        easeOutSlider.minValue = RemappingDefaults.easeDurationRange.lowerBound
        easeOutSlider.maxValue = RemappingDefaults.easeDurationRange.upperBound
        easeOutSlider.target = self
        easeOutSlider.action = #selector(easeOutSliderChanged)
        easeOutSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        singlePressDistanceValueLabel.alignment = .right
        singleClickDurationValueLabel.alignment = .right
        delayValueLabel.alignment = .right
        intervalValueLabel.alignment = .right
        easeInValueLabel.alignment = .right
        easeOutValueLabel.alignment = .right
        singlePressDistanceValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        singleClickDurationValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        delayValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        intervalValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        easeInValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        easeOutValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        buttonValidationLabel.textColor = .systemRed
        buttonValidationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        buttonValidationLabel.isHidden = true

        let thumbwheelSection = makeSettingsSection(
            title: "Thumbwheel",
            rows: [
                makeFormRow(label: "Remapping:", control: thumbwheelEnabledCheckbox),
                makeFormRow(label: "Direction:", control: directionPopUp),
                makeFormRow(label: "Input filtering:", control: lineBasedCheckbox),
            ]
        )

        let buttonHelpLabel = NSTextField(
            wrappingLabelWithString: "Button numbers are zero-based. MX Master Back and Forward are usually 3 and 4."
        )
        buttonHelpLabel.textColor = .secondaryLabelColor
        buttonHelpLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        buttonHelpLabel.preferredMaxLayoutWidth = 300

        let buttonHelpStack = NSStackView(views: [buttonValidationLabel, buttonHelpLabel])
        buttonHelpStack.orientation = .vertical
        buttonHelpStack.alignment = .leading
        buttonHelpStack.spacing = 3

        let thumbButtonSection = makeSettingsSection(
            title: "Thumb buttons",
            rows: [
                makeFormRow(label: "Remapping:", control: thumbButtonsEnabledCheckbox),
                makeFormRow(label: "Back button:", control: backButtonPopUp),
                makeFormRow(label: "Forward button:", control: forwardButtonPopUp),
                makeFormRow(label: "", control: buttonHelpStack),
                makeFormRow(label: "", control: makeSubsectionHeading("Single click")),
                makeFormRow(
                    label: "Distance:",
                    control: makeSliderRow(
                        slider: singlePressDistanceSlider,
                        valueLabel: singlePressDistanceValueLabel
                    )
                ),
                makeFormRow(label: "Easing:", control: singleClickEasingCheckbox),
                makeFormRow(
                    label: "Duration:",
                    control: makeSliderRow(
                        slider: singleClickDurationSlider,
                        valueLabel: singleClickDurationValueLabel
                    )
                ),
                makeFormRow(label: "", control: makeSubsectionHeading("Press and hold")),
                makeFormRow(
                    label: "Start delay:",
                    control: makeSliderRow(slider: delaySlider, valueLabel: delayValueLabel)
                ),
                makeFormRow(
                    label: "Speed:",
                    control: makeSliderRow(slider: intervalSlider, valueLabel: intervalValueLabel)
                ),
                makeFormRow(label: "Easing:", control: longPressEasingCheckbox),
                makeFormRow(
                    label: "Time to full speed:",
                    control: makeSliderRow(slider: easeInSlider, valueLabel: easeInValueLabel)
                ),
                makeFormRow(
                    label: "Glide after release:",
                    control: makeSliderRow(slider: easeOutSlider, valueLabel: easeOutValueLabel)
                ),
            ]
        )

        let restoreButton = NSButton(
            title: "Restore Defaults",
            target: self,
            action: #selector(restoreDefaultsPressed)
        )
        restoreButton.controlSize = .small

        let separator = NSBox()
        separator.boxType = .separator

        let footer = NSStackView(views: [restoreButton, NSView()])
        footer.orientation = .horizontal
        footer.distribution = .fill

        let stack = NSStackView(views: [thumbwheelSection, separator, thumbButtonSection, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.setCustomSpacing(18, after: thumbwheelSection)
        stack.setCustomSpacing(18, after: separator)
        stack.setCustomSpacing(22, after: thumbButtonSection)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func configureCheckbox(_ checkbox: NSButton, title: String, action: Selector) {
        checkbox.setButtonType(.switch)
        checkbox.title = title
        checkbox.target = self
        checkbox.action = action
    }

    private func makeSettingsSection(title: String, rows: [NSView]) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 10

        let stack = NSStackView(views: [heading, rowsStack])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        return stack
    }

    private func makeSubsectionHeading(_ title: String) -> NSTextField {
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        heading.textColor = .secondaryLabelColor
        return heading
    }

    private func makeFormRow(label labelText: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: labelText)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 112).isActive = true

        let row = NSStackView(views: [label, control, NSView()])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.distribution = .fill
        return row
    }

    private func makeSliderRow(slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let sliderRow = NSStackView(views: [slider, valueLabel])
        sliderRow.orientation = .horizontal
        sliderRow.alignment = .centerY
        sliderRow.spacing = 8
        return sliderRow
    }

    private func refreshControls() {
        thumbwheelEnabledCheckbox.state = settings.thumbwheelRemappingEnabled ? .on : .off
        directionPopUp.selectItem(at: settings.verticalScrollDirection < 0 ? 1 : 0)
        lineBasedCheckbox.state = settings.requireLineBasedScrollEvents ? .on : .off
        thumbButtonsEnabledCheckbox.state = settings.thumbButtonRemappingEnabled ? .on : .off
        backButtonPopUp.selectItem(at: Int(settings.backButtonNumber))
        forwardButtonPopUp.selectItem(at: Int(settings.forwardButtonNumber))
        singlePressDistanceSlider.doubleValue = settings.singlePressDistance
        singleClickEasingCheckbox.state = settings.singleClickEasingEnabled ? .on : .off
        singleClickDurationSlider.doubleValue = settings.singleClickDuration
        delaySlider.doubleValue = settings.initialDelay
        intervalSlider.doubleValue = settings.interval
        longPressEasingCheckbox.state = settings.buttonScrollEasingEnabled ? .on : .off
        easeInSlider.doubleValue = settings.easeInDuration
        easeOutSlider.doubleValue = settings.easeOutDuration
        singlePressDistanceValueLabel.stringValue = String(
            format: "%.0f pt",
            settings.singlePressDistance
        )
        singleClickDurationValueLabel.stringValue = String(
            format: "%.2f s",
            settings.singleClickDuration
        )
        delayValueLabel.stringValue = String(format: "%.2f s", settings.initialDelay)
        intervalValueLabel.stringValue = String(format: "%.2f s", settings.interval)
        easeInValueLabel.stringValue = String(format: "%.2f s", settings.easeInDuration)
        easeOutValueLabel.stringValue = String(format: "%.2f s", settings.easeOutDuration)

        directionPopUp.isEnabled = settings.thumbwheelRemappingEnabled
        lineBasedCheckbox.isEnabled = settings.thumbwheelRemappingEnabled
        backButtonPopUp.isEnabled = settings.thumbButtonRemappingEnabled
        forwardButtonPopUp.isEnabled = settings.thumbButtonRemappingEnabled
        singlePressDistanceSlider.isEnabled = settings.thumbButtonRemappingEnabled
        singleClickEasingCheckbox.isEnabled = settings.thumbButtonRemappingEnabled
        singleClickDurationSlider.isEnabled =
            settings.thumbButtonRemappingEnabled && settings.singleClickEasingEnabled
        delaySlider.isEnabled = settings.thumbButtonRemappingEnabled
        intervalSlider.isEnabled = settings.thumbButtonRemappingEnabled
        longPressEasingCheckbox.isEnabled = settings.thumbButtonRemappingEnabled
        easeInSlider.isEnabled = settings.thumbButtonRemappingEnabled && settings.buttonScrollEasingEnabled
        easeOutSlider.isEnabled = settings.thumbButtonRemappingEnabled && settings.buttonScrollEasingEnabled
    }

    private func showButtonValidation() {
        buttonValidationLabel.stringValue = "Back and Forward must use different button numbers."
        buttonValidationLabel.isHidden = false
        NSSound.beep()
    }

    @objc private func thumbwheelEnabledChanged() {
        settings.setThumbwheelRemappingEnabled(thumbwheelEnabledCheckbox.state == .on)
        refreshControls()
    }

    @objc private func directionChanged() {
        settings.setVerticalScrollDirection(directionPopUp.indexOfSelectedItem == 1 ? -1 : 1)
        refreshControls()
    }

    @objc private func lineBasedRequirementChanged() {
        settings.setRequireLineBasedScrollEvents(lineBasedCheckbox.state == .on)
        refreshControls()
    }

    @objc private func thumbButtonsEnabledChanged() {
        settings.setThumbButtonRemappingEnabled(thumbButtonsEnabledCheckbox.state == .on)
        refreshControls()
    }

    @objc private func singleClickEasingChanged() {
        settings.setSingleClickEasingEnabled(singleClickEasingCheckbox.state == .on)
        refreshControls()
    }

    @objc private func longPressEasingChanged() {
        settings.setButtonScrollEasingEnabled(longPressEasingCheckbox.state == .on)
        refreshControls()
    }

    @objc private func backButtonNumberChanged() {
        guard settings.setBackButtonNumber(Int64(backButtonPopUp.indexOfSelectedItem)) else {
            showButtonValidation()
            refreshControls()
            return
        }
        buttonValidationLabel.isHidden = true
    }

    @objc private func forwardButtonNumberChanged() {
        guard settings.setForwardButtonNumber(Int64(forwardButtonPopUp.indexOfSelectedItem)) else {
            showButtonValidation()
            refreshControls()
            return
        }
        buttonValidationLabel.isHidden = true
    }

    @objc private func singlePressDistanceSliderChanged() {
        settings.setSinglePressDistance(singlePressDistanceSlider.doubleValue)
        refreshControls()
    }

    @objc private func singleClickDurationSliderChanged() {
        settings.setSingleClickDuration(singleClickDurationSlider.doubleValue)
        refreshControls()
    }

    @objc private func delaySliderChanged() {
        settings.setInitialDelay(delaySlider.doubleValue)
        refreshControls()
    }

    @objc private func intervalSliderChanged() {
        settings.setInterval(intervalSlider.doubleValue)
        refreshControls()
    }

    @objc private func easeInSliderChanged() {
        settings.setEaseInDuration(easeInSlider.doubleValue)
        refreshControls()
    }

    @objc private func easeOutSliderChanged() {
        settings.setEaseOutDuration(easeOutSlider.doubleValue)
        refreshControls()
    }

    @objc private func restoreDefaultsPressed() {
        settings.restoreDefaults()
        buttonValidationLabel.isHidden = true
        refreshControls()
    }

}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: RemappingSettings
    private var statusItem: NSStatusItem?
    private var preferencesWindowController: PreferencesWindowController?
    private var eventTapController: EventTapController?
    private var eventTapRunLoopSource: CFRunLoopSource?

    init(settings: RemappingSettings) {
        self.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startEventTap()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = makeStatusItemImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Thumbwheel Scroll Remapper"

        let menu = NSMenu()
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.last?.target = self
        item.menu = menu

        statusItem = item
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(settings: settings)
        }
        preferencesWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startEventTap() {
        let controller = EventTapController(settings: settings)
        guard let eventTap = controller.createEventTap() else {
            if AXIsProcessTrusted() {
                showError(
                    message: "Could not create the event tap.",
                    detail: "Accessibility access is enabled, but Thumbwheel Remapper could not start listening for mouse events. Quit other input-remapping utilities and try again."
                )
            } else {
                showAccessibilityPrompt()
            }
            return
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            showError(
                message: "Could not start the event tap.",
                detail: "Thumbwheel Remapper could not connect its event listener to the macOS run loop."
            )
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        eventTapController = controller
        eventTapRunLoopSource = runLoopSource
    }

    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = "Thumbwheel Remapper needs Accessibility access to observe and remap mouse events. Enable it for this app in System Settings, then launch the app again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        NSApp.terminate(nil)
    }

    private func showError(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let settings = RemappingSettings()
let app = NSApplication.shared
private let appDelegate = AppDelegate(settings: settings)
app.delegate = appDelegate
app.run()
