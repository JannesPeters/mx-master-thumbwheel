import AppKit
import CoreGraphics
import Foundation
import ThumbwheelRemapperCore

final class EventTapController {
    private(set) var eventTap: CFMachPort?

    private var document: ConfigurationDocument
    private var router: EventRouter
    private let reenableGate = EventTapReenableGate()
    private var gestureRecognizer: ButtonGestureRecognizer
    private var gestureTimer: Timer?
    private var clickTimer: Timer?
    private var holdTimer: Timer?
    private var clickRequestID = 0
    private var clickAnimation: DiscreteScrollAnimation?
    private var clickDirection: ScrollDirection = .up
    private var clickStartedAt: TimeInterval?
    private var clickLastElapsed: TimeInterval = 0
    private var fractionalPointCarry = 0.0

    private var activeButton: InputButton?
    private var activeHold: ButtonHoldMapping?
    private var holdStartedAt: TimeInterval?
    private var holdLastFrameAt: TimeInterval?
    private var holdVelocity = 0.0
    private var momentumEngine = DragScrollMomentumEngine()
    private var momentumDirection: ScrollDirection = .up
    private var joystickDisplacement = JoystickDisplacement1D()
    private var joystickPointer = 0.0
    private var joystickSpeed = 1.0
    private var isCursorLocked = false
    private var hiddenCursorDisplayID: CGDirectDisplayID?

    private let joystickProfile = JoystickSpeedProfile()
    private let joystickHUD = JoystickHUDController()

    init(document: ConfigurationDocument) {
        self.document = document
        self.router = EventRouter(document: document)
        self.gestureRecognizer = ButtonGestureRecognizer(
            timing: GestureTimingPolicy(
                doubleClickInterval: NSEvent.doubleClickInterval,
                holdDelay: 0.3
            )
        )
    }

    deinit {
        gestureTimer?.invalidate()
        clickTimer?.invalidate()
        holdTimer?.invalidate()
        unlockCursor()
    }

    func update(document: ConfigurationDocument) {
        self.document = document
        router.document = document

        if let activeButton,
           !document.buttonHolds.contains(where: { $0.button == activeButton }) {
            stopHold(released: false)
        }
    }

    func createEventTap() -> CFMachPort? {
        let eventMask =
            (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.leftMouseUp.rawValue) |
            (CGEventMask(1) << CGEventType.rightMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.rightMouseUp.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseUp.rawValue) |
            (CGEventMask(1) << CGEventType.mouseMoved.rawValue) |
            (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue) |
            (CGEventMask(1) << CGEventType.rightMouseDragged.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue) |
            (CGEventMask(1) << CGEventType.scrollWheel.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        return eventTap
    }

    func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func process(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let normalized = EventNormalizer.normalize(rawEvent(for: event, type: type))
            if reenableGate.shouldReenable(for: normalized) {
                reenableEventTap()
            }
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            return processWheel(event)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return processButtonDown(event, type: type)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return processButtonUp(event, type: type)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return processPointerMotion(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func processButtonDown(
        _ event: CGEvent,
        type: CGEventType
    ) -> Unmanaged<CGEvent>? {
        guard let button = normalizedButton(event: event, type: type) else {
            return Unmanaged.passUnretained(event)
        }
        let normalized = EventNormalizer.normalize(rawEvent(for: event, type: type))
        guard router.route(normalized) != .forward else {
            return Unmanaged.passUnretained(event)
        }

        activeButton = button
        let hasSingle = document.buttonClicks.contains {
            $0.button == button && $0.click == .single
        }
        let hasDouble = document.buttonClicks.contains {
            $0.button == button && $0.click == .double
        }
        let hasHold = document.buttonHolds.contains { $0.button == button }
        let outputs = gestureRecognizer.buttonDown(
            button,
            at: ProcessInfo.processInfo.systemUptime,
            hasSingleMapping: hasSingle,
            hasDoubleMapping: hasDouble,
            hasHoldMapping: hasHold
        )
        handleGestureOutputs(outputs)
        scheduleGestureTimerIfNeeded()
        return nil
    }

    private func processButtonUp(
        _ event: CGEvent,
        type: CGEventType
    ) -> Unmanaged<CGEvent>? {
        guard let button = normalizedButton(event: event, type: type) else {
            return Unmanaged.passUnretained(event)
        }
        let normalized = EventNormalizer.normalize(rawEvent(for: event, type: type))
        let isMapped = router.route(normalized) != .forward
        guard isMapped || activeButton == button else {
            return Unmanaged.passUnretained(event)
        }

        if activeHold != nil, activeButton == button {
            stopHold(released: true)
        }

        let outputs = gestureRecognizer.buttonUp(
            button,
            at: ProcessInfo.processInfo.systemUptime
        )
        handleGestureOutputs(outputs)
        if !gestureRecognizer.isWaiting {
            gestureTimer?.invalidate()
            gestureTimer = nil
        }
        if activeButton == button {
            activeButton = nil
        }
        return isMapped ? nil : Unmanaged.passUnretained(event)
    }

    private func processPointerMotion(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let activeHold,
              activeHold.action.joystickEnabled else {
            return Unmanaged.passUnretained(event)
        }

        joystickPointer -= event.getDoubleValueField(.mouseEventDeltaY)
        let displacement = joystickDisplacement.update(pointer: joystickPointer)
        joystickSpeed = joystickProfile.multiplier(
            for: displacement,
            direction: activeHold.action.direction == .up ? 1 : -1
        )
        joystickHUD.update(speedMultiplier: joystickSpeed)
        return nil
    }

    private func processWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let raw = rawEvent(for: event, type: .scrollWheel)
        guard case let .wheel(wheel) = EventNormalizer.normalize(raw),
              case let .mapped(.wheel(_, transformed)) = router.route(.wheel(wheel)) else {
            return Unmanaged.passUnretained(event)
        }

        event.setIntegerValueField(
            .scrollWheelEventDeltaAxis1,
            value: transformed.integerVertical != 0
                ? transformed.integerVertical
                : Int64(transformed.vertical.rounded())
        )
        event.setDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis1,
            value: transformed.vertical
        )
        event.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: transformed.pointVertical
        )
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
        return Unmanaged.passUnretained(event)
    }

    private func handleGestureOutputs(_ outputs: [GestureOutput]) {
        for output in outputs {
            switch output {
            case let .single(button):
                guard let mapping = document.buttonClicks.first(where: {
                    $0.button == button && $0.click == .single
                }) else { continue }
                startClick(mapping.action)

            case let .double(button):
                guard let mapping = document.buttonClicks.first(where: {
                    $0.button == button && $0.click == .double
                }) else { continue }
                startClick(mapping.action)

            case let .hold(button):
                guard let mapping = document.buttonHolds.first(where: { $0.button == button }) else {
                    continue
                }
                startHold(mapping)
            }
        }
    }

    private func scheduleGestureTimerIfNeeded() {
        guard gestureRecognizer.isWaiting else { return }
        gestureTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let outputs = self.gestureRecognizer.advance(
                to: ProcessInfo.processInfo.systemUptime
            )
            self.handleGestureOutputs(outputs)
            if !self.gestureRecognizer.isWaiting {
                self.gestureTimer?.invalidate()
                self.gestureTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        gestureTimer = timer
    }

    private func startClick(_ options: ScrollActionOptions) {
        clickTimer?.invalidate()
        clickTimer = nil
        clickRequestID &+= 1
        fractionalPointCarry = 0
        clickDirection = options.direction

        let requestID = clickRequestID
        switch options.amount {
        case let .fixed(points):
            beginClick(
                distance: points,
                options: options,
                requestID: requestID
            )

        case .page:
            let location = NSEvent.mouseLocation
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let distance = PageDistanceResolver.distance(at: location)
                DispatchQueue.main.async {
                    self?.beginClick(
                        distance: distance,
                        options: options,
                        requestID: requestID
                    )
                }
            }
        }
    }

    private func beginClick(
        distance: Double,
        options: ScrollActionOptions,
        requestID: Int
    ) {
        guard requestID == clickRequestID else { return }
        let signedDistance = distance * Double(options.direction.rawValue)
        let animation = DiscreteScrollAnimation(
            distance: signedDistance,
            duration: options.duration,
            easing: options.easing
        )
        clickAnimation = animation
        clickStartedAt = ProcessInfo.processInfo.systemUptime
        clickLastElapsed = 0

        guard options.duration > 0 else {
            postAccumulatedScroll(points: signedDistance)
            flushAccumulatedScroll()
            clickAnimation = nil
            clickStartedAt = nil
            return
        }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tickClick()
        }
        RunLoop.main.add(timer, forMode: .common)
        clickTimer = timer
    }

    private func tickClick() {
        guard let animation = clickAnimation,
              let startedAt = clickStartedAt else {
            clickTimer?.invalidate()
            clickTimer = nil
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        postAccumulatedScroll(points: animation.delta(from: clickLastElapsed, to: elapsed))
        clickLastElapsed = elapsed
        if elapsed >= animation.duration {
            flushAccumulatedScroll()
            clickTimer?.invalidate()
            clickTimer = nil
            clickAnimation = nil
            clickStartedAt = nil
        }
    }

    private func startHold(_ mapping: ButtonHoldMapping) {
        clickTimer?.invalidate()
        clickTimer = nil
        activeHold = mapping
        holdStartedAt = ProcessInfo.processInfo.systemUptime
        holdLastFrameAt = holdStartedAt
        holdVelocity = 0
        joystickDisplacement.reset()
        joystickPointer = 0
        joystickSpeed = 1
        momentumEngine = DragScrollMomentumEngine(
            friction: 1 / max(mapping.action.releaseDuration, 0.01)
        )

        if mapping.action.joystickEnabled {
            lockCursor()
            joystickHUD.show(
                at: NSEvent.mouseLocation,
                direction: mapping.action.direction
            )
        }

        holdTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tickHold()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func stopHold(released: Bool) {
        guard let mapping = activeHold else { return }
        activeHold = nil
        unlockCursor()
        joystickHUD.hide()
        if released, abs(holdVelocity) > 0.01, mapping.action.releaseDuration > 0 {
            momentumEngine.setVelocity(holdVelocity)
            momentumEngine.release()
            momentumDirection = mapping.action.direction
        } else {
            holdTimer?.invalidate()
            holdTimer = nil
        }
        holdStartedAt = nil
        holdLastFrameAt = nil
    }

    private func tickHold() {
        if activeHold != nil {
            tickActiveHold()
        } else {
            tickMomentum()
        }
    }

    private func tickActiveHold() {
        guard let mapping = activeHold,
              let last = holdLastFrameAt else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(max(now - last, 0), 1.0 / 30.0)
        holdLastFrameAt = now

        let accelerationDuration = mapping.action.accelerationDuration
        let progress = accelerationDuration > 0
            ? min(max((now - (holdStartedAt ?? now)) / accelerationDuration, 0), 1)
            : 1
        let acceleration = EasingCurve.smoothStep.value(at: progress)
        let multiplier = mapping.action.joystickEnabled ? joystickSpeed : 1
        holdVelocity = mapping.action.pointsPerSecond * acceleration * multiplier
        postAccumulatedScroll(
            points: holdVelocity * deltaTime * Double(mapping.action.direction.rawValue)
        )
    }

    private func tickMomentum() {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(max(now - (holdLastFrameAt ?? now), 0), 1.0 / 30.0)
        holdLastFrameAt = now
        let distance = momentumEngine.advance(deltaTime: deltaTime)
        postAccumulatedScroll(
            points: distance * Double(momentumDirection.rawValue)
        )
        if momentumEngine.velocity == 0 {
            holdTimer?.invalidate()
            holdTimer = nil
            holdLastFrameAt = nil
        }
    }

    private func postAccumulatedScroll(points: Double) {
        fractionalPointCarry += points
        let wholePoints = Int32(fractionalPointCarry.rounded(.towardZero))
        guard wholePoints != 0 else { return }
        fractionalPointCarry -= Double(wholePoints)
        postVerticalScroll(points: wholePoints)
    }

    private func flushAccumulatedScroll() {
        let remaining = Int32(fractionalPointCarry.rounded())
        guard remaining != 0 else { return }
        fractionalPointCarry = 0
        postVerticalScroll(points: remaining)
    }

    private func postVerticalScroll(points: Int32) {
        guard points != 0,
              let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: points,
                wheel2: 0,
                wheel3: 0
              ) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cgSessionEventTap)
    }

    private func lockCursor() {
        guard !isCursorLocked else { return }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if CGDisplayHideCursor(displayID) == .success {
                hiddenCursorDisplayID = displayID
            }
        }
        isCursorLocked = true
    }

    private func unlockCursor() {
        guard isCursorLocked else { return }
        if let displayID = hiddenCursorDisplayID {
            CGDisplayShowCursor(displayID)
            hiddenCursorDisplayID = nil
        }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        isCursorLocked = false
    }

    private func normalizedButton(
        event: CGEvent,
        type: CGEventType
    ) -> InputButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp:
            return .left
        case .rightMouseDown, .rightMouseUp:
            return .right
        case .otherMouseDown, .otherMouseUp:
            return .other(event.getIntegerValueField(.mouseEventButtonNumber))
        default:
            return nil
        }
    }

    private func rawEvent(for event: CGEvent, type: CGEventType) -> RawInputEvent {
        let eventType: RawInputEventType
        switch type {
        case .leftMouseDown: eventType = .leftMouseDown
        case .leftMouseUp: eventType = .leftMouseUp
        case .rightMouseDown: eventType = .rightMouseDown
        case .rightMouseUp: eventType = .rightMouseUp
        case .otherMouseDown: eventType = .otherMouseDown
        case .otherMouseUp: eventType = .otherMouseUp
        case .mouseMoved: eventType = .mouseMoved
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: eventType = .mouseMoved
        case .scrollWheel: eventType = .scrollWheel
        case .tapDisabledByTimeout: eventType = .tapDisabledByTimeout
        case .tapDisabledByUserInput: eventType = .tapDisabledByUserInput
        default: eventType = .mouseMoved
        }
        return RawInputEvent(
            type: eventType,
            buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
            integerAxis1: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            integerAxis2: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            axis1: event.type == .scrollWheel
                ? event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                : event.getDoubleValueField(.mouseEventDeltaY),
            axis2: event.type == .scrollWheel
                ? event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                : event.getDoubleValueField(.mouseEventDeltaX),
            pointAxis1: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            pointAxis2: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            shiftPressed: event.flags.contains(.maskShift)
        )
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<EventTapController>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    return controller.process(event: event, type: type)
}
