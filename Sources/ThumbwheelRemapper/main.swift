import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ThumbwheelRemapperCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: ConfigurationStore
    private var document: ConfigurationDocument
    private var statusItem: NSStatusItem?
    private var mappingWindow: ModernMappingPreferencesWindowController?
    private var eventTapController: EventTapController?
    private var eventTapRunLoopSource: CFRunLoopSource?

    override init() {
        store = ConfigurationStore()
        document = store.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        startEventTap()
    }

    @objc private func showPreferences() {
        if mappingWindow == nil {
            mappingWindow = ModernMappingPreferencesWindowController(
                document: document
            ) { [weak self] document, issues in
                guard let self else { return }
                guard issues.isEmpty else { return }
                guard self.store.save(document) else { return }
                self.document = document
                self.eventTapController?.update(document: document)
            }
        }
        mappingWindow?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = makeStatusItemImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Thumbwheel Remapper"

        let menu = NSMenu()
        let preferences = menu.addItem(
            withTitle: "Mappings…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferences.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        item.menu = menu
        statusItem = item
    }

    private func startEventTap() {
        let controller = EventTapController(document: document)
        guard let eventTap = controller.createEventTap() else {
            if AXIsProcessTrusted() {
                showError(
                    message: "Could not create the event tap.",
                    detail: "Accessibility access is enabled, but Thumbwheel Remapper could not start listening for mouse events."
                )
            } else {
                showAccessibilityPrompt()
            }
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(
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
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        eventTapController = controller
        eventTapRunLoopSource = source
    }

    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = "Thumbwheel Remapper needs Accessibility access to observe and remap mouse events. Enable it for this app, then launch again."
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

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
