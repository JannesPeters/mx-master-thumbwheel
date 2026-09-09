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
    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4
    static let initialDelay: TimeInterval = 0.3
    static let interval: TimeInterval = 0.05

    static let buttonNumberRange: ClosedRange<Int64> = 0...31
    static let initialDelayRange: ClosedRange<TimeInterval> = 0.05...2.0
    static let intervalRange: ClosedRange<TimeInterval> = 0.01...0.5
}

final class RemappingSettings {
    static let didChangeNotification = Notification.Name("RemappingSettings.didChange")

    private let defaults: UserDefaults
    private let thumbwheelRemappingEnabledKey = "ThumbwheelRemappingEnabled"
    private let verticalScrollDirectionKey = "ThumbwheelVerticalScrollDirection"
    private let requireLineBasedScrollEventsKey = "RequireLineBasedScrollEvents"
    private let thumbButtonRemappingEnabledKey = "ThumbButtonRemappingEnabled"
    private let backButtonNumberKey = "BackButtonNumber"
    private let forwardButtonNumberKey = "ForwardButtonNumber"
    private let initialDelayKey = "ThumbButtonScrollRepeatInitialDelay"
    private let intervalKey = "ThumbButtonScrollRepeatInterval"

    private(set) var thumbwheelRemappingEnabled: Bool
    private(set) var verticalScrollDirection: Int64
    private(set) var requireLineBasedScrollEvents: Bool
    private(set) var thumbButtonRemappingEnabled: Bool
    private(set) var backButtonNumber: Int64
    private(set) var forwardButtonNumber: Int64
    private(set) var initialDelay: TimeInterval
    private(set) var interval: TimeInterval

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

        let storedDelay = defaults.object(forKey: initialDelayKey) as? Double
        let storedInterval = defaults.object(forKey: intervalKey) as? Double
        initialDelay = Self.clamp(storedDelay ?? RemappingDefaults.initialDelay, to: RemappingDefaults.initialDelayRange)
        interval = Self.clamp(storedInterval ?? RemappingDefaults.interval, to: RemappingDefaults.intervalRange)
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

    func setInterval(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: RemappingDefaults.intervalRange)
        guard clamped != interval else { return }
        interval = clamped
        defaults.set(clamped, forKey: intervalKey)
        notifyChanged()
    }

    func restoreDefaults() {
        setThumbwheelRemappingEnabled(RemappingDefaults.thumbwheelRemappingEnabled)
        setVerticalScrollDirection(RemappingDefaults.verticalScrollDirection)
        setRequireLineBasedScrollEvents(RemappingDefaults.requireLineBasedScrollEvents)
        setThumbButtonRemappingEnabled(RemappingDefaults.thumbButtonRemappingEnabled)
        setButtonNumbers(
            back: RemappingDefaults.backButtonNumber,
            forward: RemappingDefaults.forwardButtonNumber
        )
        setInitialDelay(RemappingDefaults.initialDelay)
        setInterval(RemappingDefaults.interval)
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

private final class EventTapController {
    private(set) var eventTap: CFMachPort?
    private var activeScrollButtonNumber: Int64?
    private var activeScrollTimer: Timer?
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
            self.stopRepeatingScroll()
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
            postVerticalScroll(direction: scrollDirection)
            startRepeatingScroll(direction: scrollDirection, buttonNumber: buttonNumber)
            return nil

        case .otherMouseUp:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            if buttonNumber == activeScrollButtonNumber {
                stopRepeatingScroll()
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

    private func startRepeatingScroll(direction: Int32, buttonNumber: Int64) {
        stopRepeatingScroll()
        activeScrollButtonNumber = buttonNumber

        // Read the configured delay/interval fresh on every button press so
        // changes made in the preferences window take effect on the next
        // hold without requiring a restart.
        let timer = Timer(
            fire: Date().addingTimeInterval(settings.initialDelay),
            interval: settings.interval,
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
    private let delaySlider = NSSlider()
    private let delayValueLabel = NSTextField(labelWithString: "")
    private let intervalSlider = NSSlider()
    private let intervalValueLabel = NSTextField(labelWithString: "")
    private let buttonValidationLabel = NSTextField(labelWithString: "")

    init(settings: RemappingSettings) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
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

        let buttonTitles = RemappingDefaults.buttonNumberRange.map { "Button \($0)" }
        backButtonPopUp.addItems(withTitles: buttonTitles)
        backButtonPopUp.target = self
        backButtonPopUp.action = #selector(backButtonNumberChanged)
        backButtonPopUp.widthAnchor.constraint(equalToConstant: 120).isActive = true
        forwardButtonPopUp.addItems(withTitles: buttonTitles)
        forwardButtonPopUp.target = self
        forwardButtonPopUp.action = #selector(forwardButtonNumberChanged)
        forwardButtonPopUp.widthAnchor.constraint(equalToConstant: 120).isActive = true

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

        delayValueLabel.alignment = .right
        intervalValueLabel.alignment = .right
        delayValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        intervalValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

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
                makeFormRow(
                    label: "Repeat delay:",
                    control: makeSliderRow(slider: delaySlider, valueLabel: delayValueLabel)
                ),
                makeFormRow(
                    label: "Repeat interval:",
                    control: makeSliderRow(slider: intervalSlider, valueLabel: intervalValueLabel)
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
        delaySlider.doubleValue = settings.initialDelay
        intervalSlider.doubleValue = settings.interval
        delayValueLabel.stringValue = String(format: "%.2f s", settings.initialDelay)
        intervalValueLabel.stringValue = String(format: "%.2f s", settings.interval)

        directionPopUp.isEnabled = settings.thumbwheelRemappingEnabled
        lineBasedCheckbox.isEnabled = settings.thumbwheelRemappingEnabled
        backButtonPopUp.isEnabled = settings.thumbButtonRemappingEnabled
        forwardButtonPopUp.isEnabled = settings.thumbButtonRemappingEnabled
        delaySlider.isEnabled = settings.thumbButtonRemappingEnabled
        intervalSlider.isEnabled = settings.thumbButtonRemappingEnabled
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

    @objc private func delaySliderChanged() {
        settings.setInitialDelay(delaySlider.doubleValue)
        refreshControls()
    }

    @objc private func intervalSliderChanged() {
        settings.setInterval(intervalSlider.doubleValue)
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
