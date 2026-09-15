import AppKit
import Combine
import SwiftUI
import ThumbwheelRemapperCore

private extension NSToolbarItem.Identifier {
    static let addMapping = NSToolbarItem.Identifier(
        "com.jannespeters.thumbwheel-remapper.toolbar.add-mapping"
    )
    static let removeMapping = NSToolbarItem.Identifier(
        "com.jannespeters.thumbwheel-remapper.toolbar.remove-mapping"
    )
}

@MainActor
final class MappingPreferencesWindowController: NSWindowController, NSToolbarDelegate {
    private let model: ModernMappingPreferencesModel
    private let splitViewController: NSSplitViewController
    private var removeItem: NSToolbarItem?
    private var selectionCancellable: AnyCancellable?
    private var isHiddenForJoystick = false
    private var shouldRestoreAfterJoystick = false

    init(
        document: ConfigurationDocument,
        onChange: @escaping (ConfigurationDocument, [MappingValidationIssue]) -> Void
    ) {
        model = ModernMappingPreferencesModel(document: document, onChange: onChange)

        let sidebarController = NSHostingController(
            rootView: MappingSidebarView(model: model)
        )
        let detailController = NSHostingController(
            rootView: MappingDetailView(model: model)
        )

        let splitViewController = NSSplitViewController()
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: sidebarController
        )
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 600

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(detailItem)
        self.splitViewController = splitViewController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = model.selectedTitle
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 860, height: 620)
        window.isReleasedWhenClosed = false
        window.contentViewController = splitViewController

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "ThumbwheelRemapperToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar

        selectionCancellable = model.$selection.sink { [weak self] selection in
            self?.window?.title = self?.model.selectedTitle ?? "Mappings"
            self?.removeItem?.isEnabled = selection != nil && selection != .about
        }
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func hideForJoystick() {
        isHiddenForJoystick = true
        shouldRestoreAfterJoystick = window?.isVisible == true
        if shouldRestoreAfterJoystick {
            window?.orderOut(nil)
        }
    }

    func restoreAfterJoystick() {
        isHiddenForJoystick = false
        guard shouldRestoreAfterJoystick else { return }
        shouldRestoreAfterJoystick = false
        show()
    }

    func show() {
        guard !isHiddenForJoystick else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .addMapping,
            .removeMapping,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .addMapping,
            .removeMapping,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Show or Hide Sidebar"
            item.toolTip = "Show or hide the sidebar"
            item.image = NSImage(
                systemSymbolName: "sidebar.leading",
                accessibilityDescription: "Show or hide sidebar"
            )
            item.target = splitViewController
            item.action = #selector(NSSplitViewController.toggleSidebar(_:))
            return item

        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitViewController.splitView,
                dividerIndex: 0
            )

        case .addMapping:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Mapping"
            item.toolTip = "Add a mapping"
            item.image = NSImage(
                systemSymbolName: "plus",
                accessibilityDescription: "Add mapping"
            )
            item.menu = makeAddMenu()
            return item

        case .removeMapping:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Remove Mapping"
            item.toolTip = "Remove the selected mapping"
            item.image = NSImage(
                systemSymbolName: "trash",
                accessibilityDescription: "Remove mapping"
            )
            item.target = self
            item.action = #selector(removeMapping)
            item.isEnabled = model.selection != nil && model.selection != .about
            removeItem = item
            return item

        default:
            return nil
        }
    }

    private func makeAddMenu() -> NSMenu {
        let menu = NSMenu()
        for kind in ModernMappingKind.allCases {
            let item = NSMenuItem(
                title: kind.title,
                action: #selector(addMapping(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = kind.rawValue
            menu.addItem(item)
        }
        return menu
    }

    @objc private func addMapping(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = ModernMappingKind(rawValue: rawValue) else {
            return
        }
        model.newMappingKind = kind
        model.addMapping()
    }

    @objc private func removeMapping() {
        model.removeSelection()
    }
}
