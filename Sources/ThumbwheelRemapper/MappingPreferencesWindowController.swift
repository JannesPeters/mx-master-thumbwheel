import AppKit
import Foundation
import ThumbwheelRemapperCore

final class MappingPreferencesWindowController: NSWindowController,
    NSWindowDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSMenuDelegate
{
    private enum MappingKind: String, CaseIterable {
        case click
        case hold
        case wheel

        var displayName: String {
            switch self {
            case .click: return "Button click"
            case .hold: return "Button hold"
            case .wheel: return "Wheel"
            }
        }
    }

    private struct MappingListItem {
        var kind: MappingKind
        var id: UUID
        var title: String
        var detail: String
    }

    private final class MappingTableCellView: NSTableCellView {
        let titleLabel = NSTextField(labelWithString: "")
        let detailLabel = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            titleLabel.lineBreakMode = .byTruncatingTail
            detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail

            let stack = NSStackView(views: [titleLabel, detailLabel])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            ])
            textField = titleLabel
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }

    private var configuration: ConfigurationDocument
    private var items: [MappingListItem] = []
    private var selectedKind: MappingKind?
    private var selectedID: UUID?
    private var captureMonitor: Any?
    private var validationIssues: [MappingValidationIssue] = []
    private let onChange: (ConfigurationDocument, [MappingValidationIssue]) -> Void

    private let tableView = NSTableView()
    private let kindPopup = NSPopUpButton()
    private let buttonPopup = NSPopUpButton()
    private let clickPopup = NSPopUpButton()
    private let directionPopup = NSPopUpButton()
    private let amountPopup = NSPopUpButton()
    private let wheelShapePopup = NSPopUpButton()
    private let continuousCheckbox = NSButton(
        checkboxWithTitle: "Ignore continuous trackpad-style events",
        target: nil,
        action: nil
    )
    private let shiftCheckbox = NSButton(
        checkboxWithTitle: "Preserve Shift horizontal scrolling",
        target: nil,
        action: nil
    )
    private let distanceField = NSTextField(string: "40")
    private let durationField = NSTextField(string: "0.18")
    private let speedField = NSTextField(string: "800")
    private let accelerationField = NSTextField(string: "0.18")
    private let releaseField = NSTextField(string: "0.14")
    private let joystickCheckbox = NSButton(checkboxWithTitle: "Use pointer movement as a joystick", target: nil, action: nil)
    private let captureButton = NSButton(title: "Capture Button", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private let editorTitle = NSTextField(labelWithString: "")
    private let editorDescription = NSTextField(wrappingLabelWithString: "")
    private let editorStack = NSStackView()

    init(
        document: ConfigurationDocument,
        onChange: @escaping (ConfigurationDocument, [MappingValidationIssue]) -> Void
    ) {
        self.configuration = document
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 780),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Thumbwheel Remapper Mappings"
        window.minSize = NSSize(width: 680, height: 640)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        reloadList()
        selectFirstMapping()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        stopCapture()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent(in window: NSWindow) {
        let listColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mapping"))
        listColumn.title = "Mappings"
        listColumn.width = 680
        tableView.addTableColumn(listColumn)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(mappingTableClicked)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 58
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.menu = makeContextMenu()

        let listScrollView = NSScrollView()
        listScrollView.hasVerticalScroller = true
        listScrollView.hasHorizontalScroller = false
        listScrollView.borderType = .bezelBorder
        listScrollView.documentView = tableView
        listScrollView.translatesAutoresizingMaskIntoConstraints = false

        let listTitle = NSTextField(labelWithString: "Mappings")
        listTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        let listDescription = NSTextField(
            wrappingLabelWithString: "Select a mapping to edit its trigger and action."
        )
        listDescription.textColor = .secondaryLabelColor
        listDescription.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        kindPopup.addItems(withTitles: MappingKind.allCases.map(\.displayName))
        kindPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let addButton = NSButton(title: "Add", target: self, action: #selector(addMappingPressed))
        addButton.controlSize = .regular
        removeButton.target = self
        removeButton.action = #selector(removeMappingPressed)
        removeButton.controlSize = .regular
        removeButton.keyEquivalent = ""

        let listButtons = NSStackView(
            views: [
                NSTextField(labelWithString: "Add mapping"),
                kindPopup,
                addButton,
                NSView(),
                removeButton,
            ]
        )
        listButtons.orientation = .horizontal
        listButtons.alignment = .centerY
        listButtons.spacing = 8

        let listSection = NSStackView(
            views: [listTitle, listDescription, listScrollView, listButtons]
        )
        listSection.orientation = .vertical
        listSection.alignment = .width
        listSection.spacing = 8
        listSection.setCustomSpacing(4, after: listTitle)
        listSection.setCustomSpacing(12, after: listDescription)
        listScrollView.heightAnchor.constraint(equalToConstant: 188).isActive = true

        configureEditorControls()
        editorStack.orientation = .vertical
        editorStack.alignment = .width
        editorStack.spacing = 10

        editorTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        editorDescription.textColor = .secondaryLabelColor
        editorDescription.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        editorDescription.preferredMaxLayoutWidth = 680
        editorDescription.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let editorHeader = NSStackView(views: [editorTitle, editorDescription])
        editorHeader.orientation = .vertical
        editorHeader.alignment = .width
        editorHeader.spacing = 4

        let editorPanel = NSView()
        editorPanel.wantsLayer = true
        editorPanel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        editorPanel.layer?.borderColor = NSColor.separatorColor.cgColor
        editorPanel.layer?.borderWidth = 1
        editorPanel.layer?.cornerRadius = 8
        editorPanel.layer?.masksToBounds = true
        editorStack.translatesAutoresizingMaskIntoConstraints = false
        editorPanel.addSubview(editorStack)
        NSLayoutConstraint.activate([
            editorStack.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor, constant: 22),
            editorStack.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor, constant: -22),
            editorStack.topAnchor.constraint(equalTo: editorPanel.topAnchor, constant: 18),
            editorStack.bottomAnchor.constraint(equalTo: editorPanel.bottomAnchor, constant: -18),
        ])

        editorPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 270).isActive = true
        editorPanel.setContentHuggingPriority(.defaultLow, for: .vertical)
        editorPanel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let editorSection = NSStackView(views: [editorHeader, editorPanel])
        editorSection.orientation = .vertical
        editorSection.alignment = .width
        editorSection.spacing = 10

        let restoreButton = NSButton(
            title: "Restore Defaults",
            target: self,
            action: #selector(restoreDefaultsPressed)
        )
        restoreButton.controlSize = .regular
        let help = NSTextField(
            wrappingLabelWithString: "Button mappings can have independent single, double, and hold gestures. Used choices are disabled to prevent duplicates. Changes save immediately."
        )
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        help.preferredMaxLayoutWidth = 600

        let versionLabel = NSTextField(labelWithString: appVersionDescription())
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        versionLabel.alignment = .right
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let footer = NSStackView(views: [restoreButton, help, NSView(), versionLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        let root = NSStackView(views: [listSection, editorSection, footer])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        window.contentView = content
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.initialFirstResponder = tableView
    }

    private func appVersionDescription() -> String {
        let shortVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        return "Version \(shortVersion) (\(build))"
    }

    private func configureEditorControls() {
        configurePopup(buttonPopup, action: #selector(editorChanged))
        configurePopup(clickPopup, action: #selector(editorChanged))
        configurePopup(directionPopup, action: #selector(editorChanged))
        configurePopup(amountPopup, action: #selector(editorChanged))
        configurePopup(wheelShapePopup, action: #selector(editorChanged))
        clickPopup.addItems(withTitles: ButtonClickKind.allCases.map(\.displayName))
        directionPopup.addItems(withTitles: [ScrollDirection.down.displayName, ScrollDirection.up.displayName])
        amountPopup.addItems(withTitles: ["Fixed points", "One page"])
        wheelShapePopup.addItems(withTitles: ["Horizontal only", "Any horizontal movement"])
        continuousCheckbox.state = .on
        shiftCheckbox.state = .on

        for field in [distanceField, durationField, speedField, accelerationField, releaseField] {
            field.target = self
            field.action = #selector(editorChanged)
            field.controlSize = .small
            field.alignment = .right
        }
        joystickCheckbox.target = self
        joystickCheckbox.action = #selector(editorChanged)
        continuousCheckbox.target = self
        continuousCheckbox.action = #selector(editorChanged)
        shiftCheckbox.target = self
        shiftCheckbox.action = #selector(editorChanged)
        captureButton.target = self
        captureButton.action = #selector(captureButtonPressed)
        captureButton.controlSize = .small
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        validationLabel.preferredMaxLayoutWidth = 520
        validationLabel.isHidden = true
    }

    private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
        popup.target = self
        popup.action = action
        popup.controlSize = .small
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Edit", action: #selector(editContextMapping), keyEquivalent: "")
        menu.addItem(withTitle: "Remove", action: #selector(removeMappingPressed), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    private func reloadList(refreshEditorAfterReload: Bool = true) {
        items = configuration.buttonClicks.map {
            MappingListItem(
                kind: .click,
                id: $0.id,
                title: "\($0.button.displayName) \($0.click.displayName)",
                detail: "\($0.action.direction.displayName) · \($0.label.isEmpty ? "Scroll" : $0.label)"
            )
        }
        items += configuration.buttonHolds.map {
            MappingListItem(
                kind: .hold,
                id: $0.id,
                title: "\($0.button.displayName) Hold",
                detail: "\($0.action.direction.displayName) · \($0.label.isEmpty ? "Continuous scroll" : $0.label)"
            )
        }
        items += configuration.wheelMappings.map {
            MappingListItem(
                kind: .wheel,
                id: $0.id,
                title: $0.label.isEmpty ? $0.source.displayName : $0.label,
                detail: "Wheel · \($0.action.direction.displayName)"
            )
        }
        tableView.reloadData()
        if let selectedID,
           let row = items.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        if refreshEditorAfterReload {
            refreshEditor()
        }
    }

    private func selectFirstMapping() {
        guard !items.isEmpty else {
            refreshEditor()
            return
        }
        selectedKind = items[0].kind
        selectedID = items[0].id
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        refreshEditor()
    }

    private func refreshEditor() {
        editorStack.arrangedSubviews.forEach { editorStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let kind = selectedKind,
              let id = selectedID else {
            editorTitle.stringValue = "No mapping selected"
            editorDescription.stringValue = "Select a mapping on the left, or add one below the list to configure a new gesture."
            let empty = NSTextField(wrappingLabelWithString: "Select a mapping or add one to begin.")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 14)
            editorStack.addArrangedSubview(empty)
            validationLabel.isHidden = true
            editorStack.addArrangedSubview(validationLabel)
            removeButton.isEnabled = false
            return
        }
        removeButton.isEnabled = true
        switch kind {
        case .click:
            editorTitle.stringValue = "Button click mapping"
            editorDescription.stringValue = "Choose a button and click gesture, then set the scroll action. Single and double clicks can coexist on the same button."
        case .hold:
            editorTitle.stringValue = "Button hold mapping"
            editorDescription.stringValue = "Hold a button to scroll continuously. Enable joystick mode when pointer displacement should control the speed."
        case .wheel:
            editorTitle.stringValue = "Thumbwheel mapping"
            editorDescription.stringValue = "Configure the horizontal thumbwheel input and how it becomes vertical scrolling."
        }
        updateButtonChoices(kind: kind, id: id)

        if kind == .click {
            editorStack.addArrangedSubview(makeFormRow("Button:", buttonPopup))
            editorStack.addArrangedSubview(makeFormRow("Click:", clickPopup))
            editorStack.addArrangedSubview(makeFormRow("Direction:", directionPopup))
            editorStack.addArrangedSubview(makeFormRow("Amount:", amountPopup))
            editorStack.addArrangedSubview(makeFormRow("Points:", distanceField))
            editorStack.addArrangedSubview(makeFormRow("Duration (s):", durationField))
            editorStack.addArrangedSubview(makeFormRow("", captureButton))
        } else if kind == .hold {
            editorStack.addArrangedSubview(makeFormRow("Button:", buttonPopup))
            editorStack.addArrangedSubview(makeFormRow("Direction:", directionPopup))
            editorStack.addArrangedSubview(makeFormRow("Speed (pt/s):", speedField))
            editorStack.addArrangedSubview(makeFormRow("Acceleration (s):", accelerationField))
            editorStack.addArrangedSubview(makeFormRow("Release (s):", releaseField))
            editorStack.addArrangedSubview(makeFormRow("", joystickCheckbox))
            editorStack.addArrangedSubview(makeFormRow("", captureButton))
        } else {
            editorStack.addArrangedSubview(makeFormRow("Direction:", directionPopup))
            editorStack.addArrangedSubview(makeFormRow("Source:", NSTextField(labelWithString: "Horizontal thumbwheel")))
            editorStack.addArrangedSubview(makeFormRow("Shape:", wheelShapePopup))
            editorStack.addArrangedSubview(makeFormRow("", continuousCheckbox))
            editorStack.addArrangedSubview(makeFormRow("", shiftCheckbox))
        }
        editorStack.addArrangedSubview(validationLabel)
        loadSelectedValues(kind: kind, id: id)
    }

    private func makeFormRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let row = NSStackView(views: [label, control, NSView()])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    private func updateButtonChoices(kind: MappingKind, id: UUID) {
        buttonPopup.removeAllItems()
        buttonPopup.addItem(withTitle: "Left")
        buttonPopup.item(at: 0)?.tag = -1
        buttonPopup.addItem(withTitle: "Right")
        buttonPopup.item(at: 1)?.tag = -2
        for number in 0...15 {
            buttonPopup.addItem(withTitle: "Other \(number)")
            buttonPopup.item(at: buttonPopup.numberOfItems - 1)?.tag = number
        }

        let selectedClick = configuration.buttonClicks.first(where: { $0.id == id })
        let selectedClickKind = selectedClick?.click
        let selectedButton = selectedClick?.button
            ?? configuration.buttonHolds.first(where: { $0.id == id })?.button
            ?? .other(0)

        for item in buttonPopup.itemArray {
            guard let candidate = inputButton(tag: item.tag) else { continue }
            let used: Bool
            switch kind {
            case .click:
                used = configuration.buttonClicks.contains {
                    $0.id != id && $0.button == candidate && $0.click == (selectedClickKind ?? .single)
                }
            case .hold:
                used = configuration.buttonHolds.contains { $0.id != id && $0.button == candidate }
            case .wheel:
                used = false
            }
            item.isEnabled = !used
        }
        buttonPopup.selectItem(withTag: buttonTag(selectedButton))
    }

    private func loadSelectedValues(kind: MappingKind, id: UUID) {
        switch kind {
        case .click:
            guard let mapping = configuration.buttonClicks.first(where: { $0.id == id }) else { return }
            clickPopup.selectItem(withTitle: mapping.click.displayName)
            directionPopup.selectItem(at: mapping.action.direction == .down ? 0 : 1)
            switch mapping.action.amount {
            case let .fixed(points):
                amountPopup.selectItem(at: 0)
                distanceField.doubleValue = points
            case .page:
                amountPopup.selectItem(at: 1)
            }
            distanceField.isEnabled = amountPopup.indexOfSelectedItem == 0
            durationField.doubleValue = mapping.action.duration
            joystickCheckbox.state = .off

        case .hold:
            guard let mapping = configuration.buttonHolds.first(where: { $0.id == id }) else { return }
            directionPopup.selectItem(at: mapping.action.direction == .down ? 0 : 1)
            speedField.doubleValue = mapping.action.pointsPerSecond
            accelerationField.doubleValue = mapping.action.accelerationDuration
            releaseField.doubleValue = mapping.action.releaseDuration
            joystickCheckbox.state = mapping.action.joystickEnabled ? .on : .off

        case .wheel:
            guard let mapping = configuration.wheelMappings.first(where: { $0.id == id }) else { return }
            directionPopup.selectItem(at: mapping.action.direction == .down ? 0 : 1)
            wheelShapePopup.selectItem(at: mapping.action.inputShape == .horizontalOnly ? 0 : 1)
            continuousCheckbox.state = mapping.action.ignoreContinuousEvents ? .on : .off
            shiftCheckbox.state = mapping.action.preserveShiftGestures ? .on : .off
            joystickCheckbox.state = .off
        }
        displayValidationForSelection()
    }

    @objc private func addMappingPressed() {
        let kind = MappingKind.allCases[max(0, kindPopup.indexOfSelectedItem)]
        switch kind {
        case .click:
            guard let button = firstAvailableButton(for: .single) else {
                showValidation("All available buttons already have a single-click mapping.")
                return
            }
            let mapping = ButtonClickMapping(
                button: button,
                click: .single,
                action: ScrollActionOptions(direction: .up)
            )
            configuration.buttonClicks.append(mapping)
            selectedKind = .click
            selectedID = mapping.id
        case .hold:
            guard let button = firstAvailableHoldButton() else {
                showValidation("All available buttons already have a hold mapping.")
                return
            }
            let mapping = ButtonHoldMapping(
                button: button,
                action: HoldActionOptions(direction: .up)
            )
            configuration.buttonHolds.append(mapping)
            selectedKind = .hold
            selectedID = mapping.id
        case .wheel:
            guard !configuration.wheelMappings.contains(where: { $0.source == .horizontalThumbwheel }) else {
                showValidation("A horizontal thumbwheel mapping already exists.")
                return
            }
            let mapping = WheelMapping()
            configuration.wheelMappings.append(mapping)
            selectedKind = .wheel
            selectedID = mapping.id
        }
        commitDocument()
        reloadList()
    }

    @objc private func removeMappingPressed() {
        guard let selectedKind, let selectedID else { return }
        switch selectedKind {
        case .click:
            configuration.buttonClicks.removeAll { $0.id == selectedID }
        case .hold:
            configuration.buttonHolds.removeAll { $0.id == selectedID }
        case .wheel:
            configuration.wheelMappings.removeAll { $0.id == selectedID }
        }
        self.selectedID = nil
        self.selectedKind = nil
        commitDocument()
        reloadList()
        selectFirstMapping()
    }

    @objc private func editContextMapping() {
        guard tableView.selectedRow >= 0 else { return }
        window?.makeFirstResponder(nil)
        refreshEditor()
    }

    @objc private func editorChanged() {
        guard let kind = selectedKind, let id = selectedID else { return }
        let direction: ScrollDirection = directionPopup.indexOfSelectedItem == 0 ? .down : .up

        switch kind {
        case .click:
            guard let button = inputButton(tag: buttonPopup.selectedItem?.tag ?? -3) else { return }
            guard let index = configuration.buttonClicks.firstIndex(where: { $0.id == id }),
                  let click = ButtonClickKind.allCases[safe: clickPopup.indexOfSelectedItem] else { return }
            let amount: ScrollAmount
            if amountPopup.indexOfSelectedItem == 1 {
                amount = .page
            } else {
                guard let points = positiveValue(from: distanceField, label: "Scroll distance") else { return }
                amount = .fixed(points)
            }
            guard let duration = nonNegativeValue(from: durationField, label: "Scroll duration") else {
                return
            }
            configuration.buttonClicks[index].button = button
            configuration.buttonClicks[index].click = click
            configuration.buttonClicks[index].action = ScrollActionOptions(
                direction: direction,
                amount: amount,
                duration: duration,
                easing: .quickInLongOut
            )

        case .hold:
            guard let button = inputButton(tag: buttonPopup.selectedItem?.tag ?? -3) else { return }
            guard let index = configuration.buttonHolds.firstIndex(where: { $0.id == id }) else { return }
            guard let speed = positiveValue(from: speedField, label: "Hold speed"),
                  let acceleration = nonNegativeValue(
                      from: accelerationField,
                      label: "Acceleration duration"
                  ),
                  let release = nonNegativeValue(from: releaseField, label: "Release duration") else {
                return
            }
            configuration.buttonHolds[index].button = button
            configuration.buttonHolds[index].action = HoldActionOptions(
                direction: direction,
                pointsPerSecond: speed,
                accelerationDuration: acceleration,
                releaseDuration: release,
                joystickEnabled: joystickCheckbox.state == .on
            )

        case .wheel:
            guard let index = configuration.wheelMappings.firstIndex(where: { $0.id == id }) else { return }
            configuration.wheelMappings[index].action = WheelActionOptions(
                direction: direction,
                inputShape: wheelShapePopup.indexOfSelectedItem == 0 ? .horizontalOnly : .anyHorizontal,
                ignoreContinuousEvents: continuousCheckbox.state == .on,
                preserveShiftGestures: shiftCheckbox.state == .on
            )
        }
        commitDocument()
        reloadList(refreshEditorAfterReload: false)
        updateButtonChoices(kind: kind, id: id)
        if kind == .click {
            distanceField.isEnabled = amountPopup.indexOfSelectedItem == 0
        }
    }

    @objc private func captureButtonPressed() {
        if captureMonitor != nil {
            stopCapture()
            return
        }
        captureButton.title = "Listening…"
        captureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.applyCapturedButton(event)
            }
        }
    }

    private func applyCapturedButton(_ event: NSEvent) {
        stopCapture()
        guard selectedKind != .wheel else { return }
        let button: InputButton
        switch event.type {
        case .leftMouseDown: button = .left
        case .rightMouseDown: button = .right
        case .otherMouseDown: button = .other(Int64(event.buttonNumber))
        default: return
        }
        buttonPopup.selectItem(withTag: buttonTag(button))
        editorChanged()
    }

    private func stopCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
        captureButton.title = "Capture Button"
    }

    @objc private func restoreDefaultsPressed() {
        configuration = .defaults
        selectedKind = nil
        selectedID = nil
        commitDocument()
        reloadList()
        selectFirstMapping()
    }

    private func commitDocument() {
        validationIssues = MappingValidator.validate(configuration)
        displayValidationForSelection()
        onChange(configuration, validationIssues)
    }

    private func showValidation(_ message: String) {
        validationLabel.stringValue = message
        validationLabel.isHidden = false
    }

    private func displayValidationForSelection() {
        guard selectedID != nil else {
            validationLabel.isHidden = true
            return
        }
        if let issue = validationIssues.first(where: { $0.mappingID == selectedID }) {
            showValidation(issue.description)
        } else {
            validationLabel.isHidden = true
        }
    }

    private func positiveValue(from field: NSTextField, label: String) -> Double? {
        guard let value = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite,
              value > 0 else {
            showValidation("\(label) must be greater than zero.")
            return nil
        }
        return value
    }

    private func nonNegativeValue(from field: NSTextField, label: String) -> Double? {
        guard let value = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite,
              value >= 0 else {
            showValidation("\(label) cannot be negative.")
            return nil
        }
        return value
    }

    private func firstAvailableButton(for click: ButtonClickKind) -> InputButton? {
        let candidates: [InputButton] = [.left, .right] + (0...15).map { .other(Int64($0)) }
        return candidates.first(where: { candidate in
            !configuration.buttonClicks.contains { mapping in
                mapping.button == candidate && mapping.click == click
            }
        })
    }

    private func firstAvailableHoldButton() -> InputButton? {
        let candidates: [InputButton] = [.left, .right] + (0...15).map { .other(Int64($0)) }
        return candidates.first(where: { candidate in
            !configuration.buttonHolds.contains { $0.button == candidate }
        })
    }

    private func inputButton(tag: Int) -> InputButton? {
        switch tag {
        case -1: return .left
        case -2: return .right
        case 0...15: return .other(Int64(tag))
        default: return nil
        }
    }

    private func buttonTag(_ button: InputButton) -> Int {
        switch button {
        case .left: return -1
        case .right: return -2
        case let .other(number): return Int(number)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("mapping-cell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? MappingTableCellView)
            ?? MappingTableCellView(frame: .zero)
        cell.identifier = identifier
        cell.titleLabel.stringValue = items[row].title
        cell.detailLabel.stringValue = items[row].detail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectMapping(at: tableView.selectedRow)
    }

    @objc private func mappingTableClicked() {
        selectMapping(at: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
    }

    private func selectMapping(at row: Int) {
        guard row >= 0, row < items.count else { return }
        selectedKind = items[row].kind
        selectedID = items[row].id
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshEditor()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        selectedKind = items[row].kind
        selectedID = items[row].id
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func windowWillClose(_ notification: Notification) {
        stopCapture()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
