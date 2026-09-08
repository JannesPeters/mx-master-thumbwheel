import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

// Set to -1 if the remapped scroll direction feels inverted.
private let verticalScrollDirection: Int64 = 1

// Keep this true to ignore pixel-based trackpad gestures. If the MX thumbwheel
// is reported as continuous on your macOS/device combination, set it to false.
private let requireLineBasedScrollEvents = true

// Quartz reports mouse buttons with zero-based numbers: left is 0, right is
// 1, and middle is 2. MX Master side buttons normally arrive as button 3
// (Back) and button 4 (Forward). Change these values if the connected mode or
// device reports different button numbers.
private let backButtonNumber: Int64 = 3
private let forwardButtonNumber: Int64 = 4

// While a thumb button is held down, keep posting scroll events at this
// cadence so scrolling continues instead of firing a single line. The
// initial delay mirrors typical key-repeat behavior before the fast repeat
// kicks in. These are the fallback values used the first time the app runs;
// after that the user's saved values (from the menu-bar preferences window)
// take over. See `ScrollRepeatSettings` below.
enum ScrollRepeatDefaults {
    static let initialDelay: TimeInterval = 0.3
    static let interval: TimeInterval = 0.05

    // Keeps the repeat responsive without hammering the event tap.
    static let initialDelayRange: ClosedRange<TimeInterval> = 0.05...2.0
    static let intervalRange: ClosedRange<TimeInterval> = 0.01...0.5
}

/// Persists the thumb-button scroll-repeat delay/interval in `UserDefaults` so
/// they survive relaunches, and clamps any value (stored or user-supplied) to
/// a safe range before it can reach the scroll-repeat timer.
final class ScrollRepeatSettings {
    static let initialDelayDidChangeNotification = Notification.Name("ScrollRepeatSettings.initialDelayDidChange")
    static let intervalDidChangeNotification = Notification.Name("ScrollRepeatSettings.intervalDidChange")

    private let defaults: UserDefaults
    private let initialDelayKey = "ThumbButtonScrollRepeatInitialDelay"
    private let intervalKey = "ThumbButtonScrollRepeatInterval"

    private(set) var initialDelay: TimeInterval
    private(set) var interval: TimeInterval

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedDelay = defaults.object(forKey: initialDelayKey) as? Double
        let storedInterval = defaults.object(forKey: intervalKey) as? Double
        initialDelay = Self.clamp(storedDelay ?? ScrollRepeatDefaults.initialDelay, to: ScrollRepeatDefaults.initialDelayRange)
        interval = Self.clamp(storedInterval ?? ScrollRepeatDefaults.interval, to: ScrollRepeatDefaults.intervalRange)
    }

    func setInitialDelay(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: ScrollRepeatDefaults.initialDelayRange)
        guard clamped != initialDelay else { return }
        initialDelay = clamped
        defaults.set(clamped, forKey: initialDelayKey)
        NotificationCenter.default.post(name: Self.initialDelayDidChangeNotification, object: self)
    }

    func setInterval(_ value: TimeInterval) {
        let clamped = Self.clamp(value, to: ScrollRepeatDefaults.intervalRange)
        guard clamped != interval else { return }
        interval = clamped
        defaults.set(clamped, forKey: intervalKey)
        NotificationCenter.default.post(name: Self.intervalDidChangeNotification, object: self)
    }

    func restoreDefaults() {
        setInitialDelay(ScrollRepeatDefaults.initialDelay)
        setInterval(ScrollRepeatDefaults.interval)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
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
    private var activeScrollButtonNumber: Int64?
    private var activeScrollTimer: Timer?
    private let settings: ScrollRepeatSettings

    init(settings: ScrollRepeatSettings) {
        self.settings = settings
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
            guard let scrollDirection = scrollDirection(for: event) else {
                return Unmanaged.passUnretained(event)
            }

            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            postVerticalScroll(direction: scrollDirection)
            startRepeatingScroll(direction: scrollDirection, buttonNumber: buttonNumber)
            return nil

        case .otherMouseUp:
            // Suppress the matching navigation release without generating a
            // second scroll event.
            guard isMappedThumbButton(event) else {
                return Unmanaged.passUnretained(event)
            }

            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            if buttonNumber == activeScrollButtonNumber {
                stopRepeatingScroll()
            }
            return nil

        case .scrollWheel:
            return processScrollWheel(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func processScrollWheel(_ event: CGEvent) -> Unmanaged<CGEvent> {

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

    private func isMappedThumbButton(_ event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        return buttonNumber == backButtonNumber || buttonNumber == forwardButtonNumber
    }

    private func scrollDirection(for event: CGEvent) -> Int32? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        switch buttonNumber {
        case forwardButtonNumber:
            return 1
        case backButtonNumber:
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

/// A small native window exposing the two tunable scroll-repeat settings as
/// sliders, with live numeric labels and a "Restore Defaults" action. Kept as
/// plain AppKit (no nib/storyboard) so the whole app stays a single file.
private final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let settings: ScrollRepeatSettings

    private let delaySlider = NSSlider()
    private let delayValueLabel = NSTextField(labelWithString: "")
    private let intervalSlider = NSSlider()
    private let intervalValueLabel = NSTextField(labelWithString: "")

    init(settings: ScrollRepeatSettings) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Thumbwheel Scroll Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        refreshLabels()
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
        let delayTitle = NSTextField(labelWithString: "Repeat delay before scrolling starts")
        let intervalTitle = NSTextField(labelWithString: "Repeat interval (scroll speed)")

        delaySlider.minValue = ScrollRepeatDefaults.initialDelayRange.lowerBound
        delaySlider.maxValue = ScrollRepeatDefaults.initialDelayRange.upperBound
        delaySlider.target = self
        delaySlider.action = #selector(delaySliderChanged)

        intervalSlider.minValue = ScrollRepeatDefaults.intervalRange.lowerBound
        intervalSlider.maxValue = ScrollRepeatDefaults.intervalRange.upperBound
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalSliderChanged)

        delayValueLabel.alignment = .right
        intervalValueLabel.alignment = .right

        let restoreButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaultsPressed))
        let doneButton = NSButton(title: "Done", target: self, action: #selector(donePressed))
        doneButton.keyEquivalent = "\r"

        let delayRow = NSStackView(views: [delaySlider, delayValueLabel])
        delayRow.orientation = .horizontal
        delayRow.spacing = 8
        delayValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let intervalRow = NSStackView(views: [intervalSlider, intervalValueLabel])
        intervalRow.orientation = .horizontal
        intervalRow.spacing = 8
        intervalValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let buttonRow = NSStackView(views: [restoreButton, NSView(), doneButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [delayTitle, delayRow, intervalTitle, intervalRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        delayRow.translatesAutoresizingMaskIntoConstraints = false
        intervalRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            delayRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            intervalRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func refreshLabels() {
        delaySlider.doubleValue = settings.initialDelay
        intervalSlider.doubleValue = settings.interval
        delayValueLabel.stringValue = String(format: "%.2f s", settings.initialDelay)
        intervalValueLabel.stringValue = String(format: "%.2f s", settings.interval)
    }

    @objc private func delaySliderChanged() {
        settings.setInitialDelay(delaySlider.doubleValue)
        refreshLabels()
    }

    @objc private func intervalSliderChanged() {
        settings.setInterval(intervalSlider.doubleValue)
        refreshLabels()
    }

    @objc private func restoreDefaultsPressed() {
        settings.restoreDefaults()
        refreshLabels()
    }

    @objc private func donePressed() {
        window?.close()
    }
}

/// Hosts the persistent menu-bar (status item) UI: a menu with "Preferences…"
/// and "Quit", backed by the same `ScrollRepeatSettings` the event tap reads
/// from. This is the smallest UI surface that fits an always-running
/// background remapper — no dock icon or main window.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: ScrollRepeatSettings
    private var statusItem: NSStatusItem?
    private var preferencesWindowController: PreferencesWindowController?

    init(settings: ScrollRepeatSettings) {
        self.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "⇕"
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
}

let settings = ScrollRepeatSettings()
private let controller = EventTapController(settings: settings)
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

print("Thumbwheel remapping active. Use the ⇕ menu-bar icon for settings, or press Control-C to stop.")

let app = NSApplication.shared
private let appDelegate = AppDelegate(settings: settings)
app.delegate = appDelegate
app.run()
