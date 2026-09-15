import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import ThumbwheelRemapperCore

@MainActor
final class RemapperRuntime {
    private let store = ConfigurationStore()
    private(set) var document: ConfigurationDocument
    private var eventTapController: EventTapController?
    private var eventTapRunLoopSource: CFRunLoopSource?
    var onCursorCaptureActivityChanged: ((Bool) -> Void)?

    init() {
        document = store.load()
    }

    func start() {
        let controller = EventTapController(document: document) { [weak self] isActive in
            DispatchQueue.main.async { [weak self] in
                self?.onCursorCaptureActivityChanged?(isActive)
            }
        }
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

    func update(
        document: ConfigurationDocument,
        issues: [MappingValidationIssue]
    ) {
        guard issues.isEmpty else { return }
        guard store.save(document) else { return }
        self.document = document
        eventTapController?.update(document: document)
    }

    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = "Thumbwheel Remapper needs Accessibility access to observe and remap mouse events. Enable it for this app, then launch again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(
               string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
           ) {
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runtime = RemapperRuntime()
    private var mappingsWindow: MappingPreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runtime.onCursorCaptureActivityChanged = { [weak self] isActive in
            if isActive {
                self?.mappingsWindow?.hideForCursorCapture()
            } else {
                self?.mappingsWindow?.restoreAfterCursorCapture()
            }
        }
        runtime.start()
    }

    func showMappings() {
        if mappingsWindow == nil {
            mappingsWindow = MappingPreferencesWindowController(
                document: runtime.document,
                onChange: runtime.update
            )
        }
        mappingsWindow?.show()
    }
}

private struct StatusMenu: View {
    let showMappings: () -> Void

    var body: some View {
        Button("Mappings…") {
            showMappings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Thumbwheel Remapper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@main
struct ThumbwheelRemapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(showMappings: appDelegate.showMappings)
        } label: {
            Image(nsImage: makeStatusItemImage())
        }
        .menuBarExtraStyle(.menu)
    }
}
