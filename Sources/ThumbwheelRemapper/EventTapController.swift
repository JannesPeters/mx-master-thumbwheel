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
    private var fractionalHorizontalPointCarry = 0.0

    private var activeButton: InputButton?
    private var activeHold: ButtonHoldMapping?
    private var holdStartedAt: TimeInterval?
    private var holdLastFrameAt: TimeInterval?
    private var holdVerticalVelocity = 0.0
    private var holdHorizontalVelocity = 0.0
    private var verticalMomentumEngine = DragScrollMomentumEngine()
    private var horizontalMomentumEngine = DragScrollMomentumEngine()
    private var joystickDisplacement = JoystickDisplacement2D()
    private var joystickPointer = Point2D.zero
    private var joystickVerticalSpeed = 0.0
    private var joystickHorizontalSpeed = 0.0
    private var joystickVerticalIntent = JoystickIntentAxis()
    private var joystickHorizontalIntent = JoystickIntentAxis()
    private var isCursorCaptureActive = false
    private var isCursorHidden = false
    private var isCursorAssociated = true
    private var previousFrontmostApplication: NSRunningApplication?

    private let joystickProfile = JoystickSpeedProfile()
    private let joystickHUD = JoystickHUDController()
    private let onJoystickActivityChanged: (Bool) -> Void

    init(
        document: ConfigurationDocument,
        onJoystickActivityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.document = document
        self.router = EventRouter(document: document)
        self.onJoystickActivityChanged = onJoystickActivityChanged
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
        releaseCursor()
    }

    func update(document: ConfigurationDocument) {
        self.document = document
        router.document = document

        if let activeButton,
           !document.buttonHolds.contains(where: {
               $0.isEnabled && $0.button == activeButton
           }) {
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
            $0.isEnabled && $0.button == button && $0.click == .single
        }
        let hasDouble = document.buttonClicks.contains {
            $0.isEnabled && $0.button == button && $0.click == .double
        }
        let hasHold = document.buttonHolds.contains {
            $0.isEnabled && $0.button == button
        }
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
              activeHold.action.mode == .joystick else {
            return Unmanaged.passUnretained(event)
        }

        joystickPointer.x += event.getDoubleValueField(.mouseEventDeltaX)
        joystickPointer.y -= event.getDoubleValueField(.mouseEventDeltaY)
        let displacement = joystickDisplacement.update(pointer: joystickPointer)
        joystickVerticalSpeed = activeHold.action.joystickVerticalEnabled
            ? joystickVerticalIntent.multiplier(
                for: displacement.y,
                profile: joystickProfile
            )
            : 0
        joystickHorizontalSpeed = activeHold.action.joystickHorizontalEnabled
            ? joystickHorizontalIntent.multiplier(
                for: displacement.x,
                profile: joystickProfile
            )
            : 0
        joystickHUD.update(
            verticalSpeedMultiplier: joystickVerticalSpeed,
            horizontalSpeedMultiplier: joystickHorizontalSpeed
        )
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
                    $0.isEnabled && $0.button == button && $0.click == .single
                }) else { continue }
                startClick(mapping.action)

            case let .double(button):
                guard let mapping = document.buttonClicks.first(where: {
                    $0.isEnabled && $0.button == button && $0.click == .double
                }) else { continue }
                startClick(mapping.action)

            case let .hold(button):
                guard let mapping = document.buttonHolds.first(where: {
                    $0.isEnabled && $0.button == button
                }) else {
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
        fractionalHorizontalPointCarry = 0
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

        guard options.easingEnabled, options.duration > 0 else {
            postAccumulatedScroll(vertical: signedDistance)
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
        postAccumulatedScroll(vertical: animation.delta(from: clickLastElapsed, to: elapsed))
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
        holdVerticalVelocity = 0
        holdHorizontalVelocity = 0
        joystickDisplacement.reset()
        joystickPointer = .zero
        _ = joystickDisplacement.update(pointer: joystickPointer)
        joystickVerticalSpeed = 0
        joystickHorizontalSpeed = 0
        joystickVerticalIntent.reset()
        joystickHorizontalIntent.reset()
        verticalMomentumEngine = DragScrollMomentumEngine(
            friction: 1 / max(mapping.action.releaseDuration, 0.01)
        )
        horizontalMomentumEngine = DragScrollMomentumEngine(
            friction: 1 / max(mapping.action.releaseDuration, 0.01)
        )

        if mapping.action.mode == .joystick {
            let cursorLocation = NSEvent.mouseLocation
            if mapping.action.joystickCapturesCursor {
                captureCursor()
                onJoystickActivityChanged(true)
            }
            joystickHUD.show(at: cursorLocation)
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
        let wasCursorCaptureEnabled = mapping.action.mode == .joystick
            && mapping.action.joystickCapturesCursor
        activeHold = nil
        joystickHUD.hide()
        releaseCursor()
        if wasCursorCaptureEnabled {
            onJoystickActivityChanged(false)
        }
        if released,
           mapping.action.easingEnabled,
           max(abs(holdVerticalVelocity), abs(holdHorizontalVelocity)) > 0.01,
           mapping.action.releaseDuration > 0 {
            verticalMomentumEngine.setVelocity(holdVerticalVelocity)
            horizontalMomentumEngine.setVelocity(holdHorizontalVelocity)
            verticalMomentumEngine.release()
            horizontalMomentumEngine.release()
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
        let acceleration = mapping.action.easingEnabled
            ? EasingCurve.smoothStep.value(at: progress)
            : 1
        let verticalMultiplier: Double
        let horizontalMultiplier: Double
        switch mapping.action.mode {
        case .scrollUp:
            verticalMultiplier = 1
            horizontalMultiplier = 0
        case .scrollDown:
            verticalMultiplier = -1
            horizontalMultiplier = 0
        case .joystick:
            verticalMultiplier = mapping.action.joystickVerticalEnabled
                ? joystickVerticalSpeed
                : 0
            horizontalMultiplier = mapping.action.joystickHorizontalEnabled
                ? joystickHorizontalSpeed
                : 0
        }
        holdVerticalVelocity = mapping.action.pointsPerSecond * acceleration * verticalMultiplier
        holdHorizontalVelocity = mapping.action.pointsPerSecond * acceleration * horizontalMultiplier
        postAccumulatedScroll(
            vertical: holdVerticalVelocity * deltaTime,
            horizontal: holdHorizontalVelocity * deltaTime
        )
    }

    private func tickMomentum() {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(max(now - (holdLastFrameAt ?? now), 0), 1.0 / 30.0)
        holdLastFrameAt = now
        let verticalDistance = verticalMomentumEngine.advance(deltaTime: deltaTime)
        let horizontalDistance = horizontalMomentumEngine.advance(deltaTime: deltaTime)
        postAccumulatedScroll(
            vertical: verticalDistance,
            horizontal: horizontalDistance
        )
        if verticalMomentumEngine.velocity == 0,
           horizontalMomentumEngine.velocity == 0 {
            holdTimer?.invalidate()
            holdTimer = nil
            holdLastFrameAt = nil
        }
    }

    private func postAccumulatedScroll(
        vertical: Double = 0,
        horizontal: Double = 0
    ) {
        fractionalPointCarry += vertical
        fractionalHorizontalPointCarry += horizontal
        let verticalPoints = Int32(fractionalPointCarry.rounded(.towardZero))
        let horizontalPoints = Int32(fractionalHorizontalPointCarry.rounded(.towardZero))
        guard verticalPoints != 0 || horizontalPoints != 0 else { return }
        fractionalPointCarry -= Double(verticalPoints)
        fractionalHorizontalPointCarry -= Double(horizontalPoints)
        postScroll(vertical: verticalPoints, horizontal: horizontalPoints)
    }

    private func flushAccumulatedScroll() {
        let verticalRemaining = Int32(fractionalPointCarry.rounded())
        let horizontalRemaining = Int32(fractionalHorizontalPointCarry.rounded())
        guard verticalRemaining != 0 || horizontalRemaining != 0 else { return }
        fractionalPointCarry = 0
        fractionalHorizontalPointCarry = 0
        postScroll(vertical: verticalRemaining, horizontal: horizontalRemaining)
    }

    private func postScroll(vertical: Int32, horizontal: Int32) {
        guard vertical != 0 || horizontal != 0,
              let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: vertical,
                wheel2: horizontal,
                wheel3: 0
              ) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cgSessionEventTap)
    }

    private func captureCursor() {
        guard !isCursorCaptureActive else { return }
        let currentApplication = NSRunningApplication.current
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != currentApplication.processIdentifier {
            previousFrontmostApplication = frontmostApplication
        }
        NSApp.activate(ignoringOtherApps: true)

        let hideResult = CGDisplayHideCursor(CGMainDisplayID())
        isCursorHidden = hideResult == .success
        if hideResult != .success {
            NSLog("Thumbwheel Remapper could not hide the cursor: \(hideResult.rawValue)")
        }

        let associationResult = CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        isCursorAssociated = associationResult != .success
        if associationResult != .success {
            NSLog("Thumbwheel Remapper could not capture the cursor: \(associationResult.rawValue)")
        }
        isCursorCaptureActive = true
    }

    private func releaseCursor() {
        guard isCursorCaptureActive else { return }
        if !isCursorAssociated {
            let associationResult = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            if associationResult != .success {
                NSLog("Thumbwheel Remapper could not release the cursor: \(associationResult.rawValue)")
            }
            isCursorAssociated = true
        }
        if isCursorHidden {
            let showResult = CGDisplayShowCursor(CGMainDisplayID())
            if showResult != .success {
                NSLog("Thumbwheel Remapper could not show the cursor: \(showResult.rawValue)")
            }
            isCursorHidden = false
        }
        isCursorCaptureActive = false

        let application = previousFrontmostApplication
        previousFrontmostApplication = nil
        if let application, !application.isTerminated {
            application.activate(options: [])
        }
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
