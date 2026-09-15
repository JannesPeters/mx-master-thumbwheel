import Combine
import SwiftUI
import ThumbwheelRemapperCore

enum ModernMappingInputKind: String, CaseIterable, Identifiable {
    case button
    case wheel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .button:
            return "Button"
        case .wheel:
            return "Wheel"
        }
    }
}

enum ModernButtonGesture: String, CaseIterable, Identifiable {
    case single
    case double
    case hold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single:
            return "Single click"
        case .double:
            return "Double click"
        case .hold:
            return "Press and hold"
        }
    }
}

enum ModernMappingSelection: Hashable {
    case mapping(UUID)
    case about
}

enum ModernMappingRecord {
    case click(ButtonClickMapping)
    case hold(ButtonHoldMapping)
    case wheel(WheelMapping)

    var id: UUID {
        switch self {
        case let .click(mapping):
            return mapping.id
        case let .hold(mapping):
            return mapping.id
        case let .wheel(mapping):
            return mapping.id
        }
    }

    var isEnabled: Bool {
        switch self {
        case let .click(mapping):
            return mapping.isEnabled
        case let .hold(mapping):
            return mapping.isEnabled
        case let .wheel(mapping):
            return mapping.isEnabled
        }
    }
}

struct ModernMappingItem: Identifiable {
    let id: String
    let selection: ModernMappingSelection
    let title: String
    let detail: String
    let symbolName: String
    let isEnabled: Bool
}

@MainActor
final class ModernMappingPreferencesModel: ObservableObject {
    @Published var document: ConfigurationDocument
    @Published var selection: ModernMappingSelection?
    @Published var validationMessage: String?

    private let onChange: (ConfigurationDocument, [MappingValidationIssue]) -> Void

    init(
        document: ConfigurationDocument,
        onChange: @escaping (ConfigurationDocument, [MappingValidationIssue]) -> Void
    ) {
        self.document = document
        self.onChange = onChange
        if let mapping = document.buttonClicks.first {
            selection = .mapping(mapping.id)
        } else if let mapping = document.buttonHolds.first {
            selection = .mapping(mapping.id)
        } else if let mapping = document.wheelMappings.first {
            selection = .mapping(mapping.id)
        }
    }

    var items: [ModernMappingItem] {
        document.buttonClicks.map {
            ModernMappingItem(
                id: "click-\($0.id.uuidString)",
                selection: .mapping($0.id),
                title: "\($0.button.displayName) · \($0.click.displayName) click",
                detail: "\($0.action.direction.displayName) · \($0.label.isEmpty ? "Scroll" : $0.label)",
                symbolName: "computermouse",
                isEnabled: $0.isEnabled
            )
        } + document.buttonHolds.map {
            ModernMappingItem(
                id: "hold-\($0.id.uuidString)",
                selection: .mapping($0.id),
                title: "\($0.button.displayName) · Press and hold",
                detail: "\($0.action.mode.displayName) · \($0.label.isEmpty ? "Hold scroll" : $0.label)",
                symbolName: "hand.point.up.left",
                isEnabled: $0.isEnabled
            )
        } + document.wheelMappings.map {
            ModernMappingItem(
                id: "wheel-\($0.id.uuidString)",
                selection: .mapping($0.id),
                title: $0.label.isEmpty ? $0.source.displayName : $0.label,
                detail: "Wheel · \($0.action.direction.displayName)",
                symbolName: "scroll",
                isEnabled: $0.isEnabled
            )
        }
    }

    var selectedTitle: String {
        switch selection {
        case .mapping:
            return "Mapping"
        case .about:
            return "About"
        case nil:
            return "Mappings"
        }
    }

    var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    func addMapping() {
        if let button = availableButtons(for: ModernButtonGesture.single).first {
            let mapping = ButtonClickMapping(
                isEnabled: false,
                button: button,
                click: .single,
                action: ScrollActionOptions(direction: .up)
            )
            document.buttonClicks.append(mapping)
            selection = .mapping(mapping.id)
        } else if let button = availableButtons(for: ModernButtonGesture.double).first {
            let mapping = ButtonClickMapping(
                isEnabled: false,
                button: button,
                click: .double,
                action: ScrollActionOptions(direction: .up)
            )
            document.buttonClicks.append(mapping)
            selection = .mapping(mapping.id)
        } else if let button = availableHoldButtons.first {
            let mapping = ButtonHoldMapping(
                isEnabled: false,
                button: button,
                action: HoldActionOptions(mode: .scrollUp)
            )
            document.buttonHolds.append(mapping)
            selection = .mapping(mapping.id)
        } else if !document.wheelMappings.contains(where: { $0.source == .horizontalThumbwheel }) {
            let mapping = WheelMapping(isEnabled: false)
            document.wheelMappings.append(mapping)
            selection = .mapping(mapping.id)
        } else {
            validationMessage = "All supported input triggers already have mappings."
            return
        }
        commit()
    }

    func removeSelection() {
        guard let selection else { return }
        switch selection {
        case let .mapping(id):
            removeMapping(id)
        case .about:
            return
        }
        self.selection = items.first?.selection
        commit()
    }

    func restoreDefaults() {
        document = .defaults
        selection = items.first?.selection
        commit()
    }

    func updateClick(_ id: UUID, _ update: (inout ButtonClickMapping) -> Void) {
        guard let index = document.buttonClicks.firstIndex(where: { $0.id == id }) else { return }
        update(&document.buttonClicks[index])
        commit()
    }

    func updateHold(_ id: UUID, _ update: (inout ButtonHoldMapping) -> Void) {
        guard let index = document.buttonHolds.firstIndex(where: { $0.id == id }) else { return }
        update(&document.buttonHolds[index])
        commit()
    }

    func updateWheel(_ id: UUID, _ update: (inout WheelMapping) -> Void) {
        guard let index = document.wheelMappings.firstIndex(where: { $0.id == id }) else { return }
        update(&document.wheelMappings[index])
        commit()
    }

    func click(_ id: UUID) -> ButtonClickMapping? {
        document.buttonClicks.first { $0.id == id }
    }

    func hold(_ id: UUID) -> ButtonHoldMapping? {
        document.buttonHolds.first { $0.id == id }
    }

    func wheel(_ id: UUID) -> WheelMapping? {
        document.wheelMappings.first { $0.id == id }
    }

    func mapping(_ id: UUID) -> ModernMappingRecord? {
        if let mapping = click(id) {
            return .click(mapping)
        }
        if let mapping = hold(id) {
            return .hold(mapping)
        }
        if let mapping = wheel(id) {
            return .wheel(mapping)
        }
        return nil
    }

    func isEnabled(_ id: UUID) -> Bool? {
        mapping(id)?.isEnabled
    }

    func updateEnabled(_ id: UUID, _ isEnabled: Bool) {
        if let index = document.buttonClicks.firstIndex(where: { $0.id == id }) {
            document.buttonClicks[index].isEnabled = isEnabled
            commit()
        } else if let index = document.buttonHolds.firstIndex(where: { $0.id == id }) {
            document.buttonHolds[index].isEnabled = isEnabled
            commit()
        } else if let index = document.wheelMappings.firstIndex(where: { $0.id == id }) {
            document.wheelMappings[index].isEnabled = isEnabled
            commit()
        }
    }

    func inputKind(_ id: UUID) -> ModernMappingInputKind? {
        guard let mapping = mapping(id) else { return nil }
        switch mapping {
        case .click, .hold:
            return .button
        case .wheel:
            return .wheel
        }
    }

    func buttonGesture(_ id: UUID) -> ModernButtonGesture? {
        guard let mapping = mapping(id) else { return nil }
        switch mapping {
        case let .click(mapping):
            return mapping.click == .single ? .single : .double
        case .hold:
            return .hold
        case .wheel:
            return nil
        }
    }

    func button(for id: UUID) -> InputButton? {
        guard let mapping = mapping(id) else { return nil }
        switch mapping {
        case let .click(mapping):
            return mapping.button
        case let .hold(mapping):
            return mapping.button
        case .wheel:
            return nil
        }
    }

    func wheelSource(_ id: UUID) -> WheelMappingSource? {
        guard let mapping = wheel(id) else { return nil }
        return mapping.source
    }

    func updateInputKind(_ id: UUID, _ inputKind: ModernMappingInputKind) {
        guard let mapping = mapping(id) else { return }
        switch (mapping, inputKind) {
        case (.click, .button), (.hold, .button), (.wheel, .wheel):
            return
        case let (.wheel(wheel), .button):
            guard let button = availableButtons(
                for: ModernButtonGesture.single,
                excluding: id
            ).first else {
                validationMessage = "All available buttons already have a single-click mapping."
                return
            }
            replace(
                .click(
                    ButtonClickMapping(
                        id: wheel.id,
                        isEnabled: wheel.isEnabled,
                        button: button,
                        click: .single,
                        action: ScrollActionOptions(direction: wheel.action.direction),
                        label: wheel.label
                    )
                )
            )
        case (.click, .wheel), (.hold, .wheel):
            guard !document.wheelMappings.contains(where: { $0.id != id }) else {
                validationMessage = "A horizontal thumbwheel mapping already exists."
                return
            }
            let direction: ScrollDirection
            let label: String
            switch mapping {
            case let .click(click):
                direction = click.action.direction
                label = click.label
            case let .hold(hold):
                direction = hold.action.mode.direction ?? .up
                label = hold.label
            case .wheel:
                return
            }
            replace(
                .wheel(
                    WheelMapping(
                        id: id,
                        isEnabled: mapping.isEnabled,
                        action: WheelActionOptions(direction: direction),
                        label: label
                    )
                )
            )
        }
        commit()
    }

    func updateButton(_ id: UUID, _ button: InputButton) {
        if let index = document.buttonClicks.firstIndex(where: { $0.id == id }) {
            document.buttonClicks[index].button = button
            commit()
        } else if let index = document.buttonHolds.firstIndex(where: { $0.id == id }) {
            document.buttonHolds[index].button = button
            commit()
        }
    }

    func updateButtonGesture(_ id: UUID, _ gesture: ModernButtonGesture) {
        guard let mapping = mapping(id) else { return }
        switch mapping {
        case let .click(click):
            switch gesture {
            case .single, .double:
                guard let index = document.buttonClicks.firstIndex(where: { $0.id == id }) else {
                    return
                }
                document.buttonClicks[index].click = gesture == .single ? .single : .double
            case .hold:
                replace(
                    .hold(
                        ButtonHoldMapping(
                            id: id,
                            isEnabled: click.isEnabled,
                            button: click.button,
                            action: HoldActionOptions(
                                mode: click.action.direction == .up ? .scrollUp : .scrollDown
                            ),
                            label: click.label
                        )
                    )
                )
            }
        case let .hold(hold):
            switch gesture {
            case .hold:
                return
            case .single, .double:
                replace(
                    .click(
                        ButtonClickMapping(
                            id: id,
                            isEnabled: hold.isEnabled,
                            button: hold.button,
                            click: gesture == .single ? .single : .double,
                            action: ScrollActionOptions(
                                direction: hold.action.mode.direction ?? .up
                            ),
                            label: hold.label
                        )
                    )
                )
            }
        case let .wheel(wheel):
            guard let button = availableButtons(for: gesture, excluding: id).first else {
                validationMessage = "All available buttons already have that button gesture."
                return
            }
            switch gesture {
            case .single, .double:
                replace(
                    .click(
                        ButtonClickMapping(
                            id: id,
                            isEnabled: wheel.isEnabled,
                            button: button,
                            click: gesture == .single ? .single : .double,
                            action: ScrollActionOptions(direction: wheel.action.direction),
                            label: wheel.label
                        )
                    )
                )
            case .hold:
                replace(
                    .hold(
                        ButtonHoldMapping(
                            id: id,
                            isEnabled: wheel.isEnabled,
                            button: button,
                            action: HoldActionOptions(
                                mode: wheel.action.direction == .up ? .scrollUp : .scrollDown
                            ),
                            label: wheel.label
                        )
                    )
                )
            }
        }
        commit()
    }

    func updateWheelSource(_ id: UUID, _ source: WheelMappingSource) {
        guard let index = document.wheelMappings.firstIndex(where: { $0.id == id }) else {
            return
        }
        document.wheelMappings[index].source = source
        commit()
    }

    func availableButtons(
        for gesture: ModernButtonGesture,
        excluding id: UUID? = nil
    ) -> [InputButton] {
        allButtons.filter { candidate in
            switch gesture {
            case .single:
                return !document.buttonClicks.contains {
                    $0.id != id && $0.button == candidate && $0.click == .single
                }
            case .double:
                return !document.buttonClicks.contains {
                    $0.id != id && $0.button == candidate && $0.click == .double
                }
            case .hold:
                return !document.buttonHolds.contains {
                    $0.id != id && $0.button == candidate
                }
            }
        }
    }

    func availableButtons(
        for gesture: ModernButtonGesture,
        excluding id: UUID? = nil,
        including button: InputButton
    ) -> [InputButton] {
        var available = availableButtons(for: gesture, excluding: id)
        if !available.contains(button) {
            available.append(button)
        }
        return available
    }

    var availableHoldButtons: [InputButton] {
        allButtons.filter { candidate in
            !document.buttonHolds.contains { $0.button == candidate }
        }
    }

    private func replace(_ mapping: ModernMappingRecord) {
        let id = mapping.id
        removeMapping(id)
        switch mapping {
        case let .click(mapping):
            document.buttonClicks.append(mapping)
        case let .hold(mapping):
            document.buttonHolds.append(mapping)
        case let .wheel(mapping):
            document.wheelMappings.append(mapping)
        }
    }

    private func removeMapping(_ id: UUID) {
        document.buttonClicks.removeAll { $0.id == id }
        document.buttonHolds.removeAll { $0.id == id }
        document.wheelMappings.removeAll { $0.id == id }
    }

    private func commit() {
        let issues = MappingValidator.validate(document)
        validationMessage = issues.first?.description
        onChange(document, issues)
    }

    private var allButtons: [InputButton] {
        (0...15).map { .other(Int64($0)) }
    }
}

struct MappingSidebarView: View {
    @ObservedObject var model: ModernMappingPreferencesModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(model.items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(item.isEnabled ? 1 : 0.55)
                    .tag(item.selection)
                }
            }
            Section {
                Label("About", systemImage: "info.circle")
                    .tag(ModernMappingSelection.about)
            }
        }
        .listStyle(.sidebar)
    }
}

struct MappingDetailView: View {
    @ObservedObject var model: ModernMappingPreferencesModel

    var body: some View {
        VStack(spacing: 0) {
            detailView
        }
        .frame(minWidth: 600, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detailView: some View {
        if let selection = model.selection {
            if case .about = selection {
                aboutView
            } else {
                ScrollView {
                    Form {
                        switch selection {
                        case let .mapping(id):
                            mappingEditor(id)
                        case .about:
                            EmptyView()
                        }
                        if let validationMessage = model.validationMessage {
                            Section {
                                Label(validationMessage, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            }
                        }

                    }
                    .formStyle(.grouped)
                    .padding(24)
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } else {
            ContentUnavailableView(
                "No mapping selected",
                systemImage: "slider.horizontal.3",
                description: Text("Add a mapping or select one from the list.")
            )
        }
    }

    private var aboutView: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Thumbwheel Remapper", systemImage: "computermouse")
                    .font(.title2.weight(.semibold))
                Text("A native Tahoe utility for remapping thumbwheel and secondary mouse-button gestures.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Configuration") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Changes save automatically. The primary left and right mouse buttons are intentionally not remappable.")
                        .foregroundStyle(.secondary)
                    Button("Restore Defaults") {
                        model.restoreDefaults()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Version") {
                Text(model.versionDescription)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func mappingEditor(_ id: UUID) -> some View {
        if let mapping = model.mapping(id),
           let inputKind = model.inputKind(id) {
            inputTriggerEditor(id, inputKind: inputKind)
            switch mapping {
            case .click:
                clickActionEditor(id)
            case .hold:
                holdActionEditor(id)
            case .wheel:
                wheelActionEditor(id)
            }
        }
    }

    @ViewBuilder
    private func inputTriggerEditor(
        _ id: UUID,
        inputKind: ModernMappingInputKind
    ) -> some View {
        Section("Input trigger") {
            Picker(
                "Input",
                selection: mappingInputKindBinding(id, value: inputKind)
            ) {
                ForEach(ModernMappingInputKind.allCases) {
                    Text($0.displayName).tag($0)
                }
            }
            if let isEnabled = model.isEnabled(id) {
                Toggle(
                    "Enabled",
                    isOn: mappingEnabledBinding(id, value: isEnabled)
                )
            }

            switch inputKind {
            case .button:
                if let button = model.button(for: id),
                   let gesture = model.buttonGesture(id) {
                    Picker("Button", selection: mappingButtonBinding(id, value: button)) {
                        ForEach(
                            model.availableButtons(
                                for: gesture,
                                excluding: id,
                                including: button
                            ),
                            id: \.self
                        ) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    Picker(
                        "Gesture",
                        selection: mappingGestureBinding(id, value: gesture)
                    ) {
                        ForEach(ModernButtonGesture.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
            case .wheel:
                if let source = model.wheelSource(id) {
                    Picker(
                        "Source",
                        selection: mappingWheelSourceBinding(id, value: source)
                    ) {
                        ForEach(WheelMappingSource.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func clickActionEditor(_ id: UUID) -> some View {
        if let mapping = model.click(id) {
            Section("Action") {
                Picker("Direction", selection: clickDirectionBinding(id, value: mapping.action.direction)) {
                    ForEach(ScrollDirection.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0)
                    }
                }
                Toggle(
                    "Ease each click",
                    isOn: clickEasingEnabledBinding(id, value: mapping.action.easingEnabled)
                )
                Picker("Easing curve", selection: clickEasingBinding(id, value: mapping.action.easing)) {
                    ForEach(EasingCurve.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .disabled(!mapping.action.easingEnabled)
                Picker("Amount", selection: clickAmountBinding(id, value: mapping.action.amount)) {
                    Text("Fixed points").tag(ModernScrollAmount.fixed)
                    Text("One page").tag(ModernScrollAmount.page)
                }
                if case .fixed = mapping.action.amount {
                    valueSlider(
                        label: "Points",
                        value: clickPointsBinding(id, value: mapping.action.amount),
                        range: SliderRanges.scrollDistance,
                        step: 5,
                        format: { String(format: "%.0f pt", $0) }
                    )
                }
                valueSlider(
                    label: "Duration",
                    value: clickDurationBinding(id, value: mapping.action.duration),
                    range: SliderRanges.duration,
                    step: 0.01,
                    format: { String(format: "%.2f s", $0) }
                )
                .disabled(!mapping.action.easingEnabled)
            }
        }
    }

    @ViewBuilder
    private func holdActionEditor(_ id: UUID) -> some View {
        if let mapping = model.hold(id) {
            Section("Action") {
                Picker("Mode", selection: holdModeBinding(id, value: mapping.action.mode)) {
                    ForEach(HoldScrollMode.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                if mapping.action.mode == .joystick {
                    Text("Move the pointer up or down while holding to scroll in either direction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(
                        "Vertical scrolling",
                        isOn: holdJoystickVerticalBinding(
                            id,
                            value: mapping.action.joystickVerticalEnabled
                        )
                    )
                    Toggle(
                        "Horizontal scrolling",
                        isOn: holdJoystickHorizontalBinding(
                            id,
                            value: mapping.action.joystickHorizontalEnabled
                        )
                    )
                    Toggle(
                        "Capture and hide cursor",
                        isOn: holdJoystickCursorBinding(
                            id,
                            value: mapping.action.joystickCapturesCursor
                        )
                    )
                    Text("Temporarily activates Thumbwheel Remapper while the joystick is held, then returns to the previous app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(
                    "Ease acceleration and deceleration",
                    isOn: holdEasingEnabledBinding(id, value: mapping.action.easingEnabled)
                )
                valueSlider(
                    label: "Speed",
                    value: holdSpeedBinding(id, value: mapping.action.pointsPerSecond),
                    range: SliderRanges.holdSpeed,
                    step: 10,
                    format: { String(format: "%.0f pt/s", $0) }
                )
                valueSlider(
                    label: "Acceleration",
                    value: holdAccelerationBinding(id, value: mapping.action.accelerationDuration),
                    range: SliderRanges.duration,
                    step: 0.01,
                    format: { String(format: "%.2f s", $0) }
                )
                .disabled(!mapping.action.easingEnabled)
                valueSlider(
                    label: "Deceleration",
                    value: holdReleaseBinding(id, value: mapping.action.releaseDuration),
                    range: SliderRanges.duration,
                    step: 0.01,
                    format: { String(format: "%.2f s", $0) }
                )
                .disabled(!mapping.action.easingEnabled)
            }
        }
    }

    @ViewBuilder
    private func wheelActionEditor(_ id: UUID) -> some View {
        if let mapping = model.wheel(id) {
            Section("Action") {
                Picker("Input shape", selection: wheelShapeBinding(id, value: mapping.action.inputShape)) {
                    Text("Horizontal only").tag(WheelInputShape.horizontalOnly)
                    Text("Any horizontal movement").tag(WheelInputShape.anyHorizontal)
                }
            }
            Section("Action") {
                Picker("Direction", selection: wheelDirectionBinding(id, value: mapping.action.direction)) {
                    ForEach(ScrollDirection.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0)
                    }
                }
                Toggle("Ignore continuous trackpad-style events", isOn: wheelContinuousBinding(id, value: mapping.action.ignoreContinuousEvents))
                Toggle("Preserve Shift horizontal scrolling", isOn: wheelShiftBinding(id, value: mapping.action.preserveShiftGestures))
            }
        }
    }

    private enum ModernScrollAmount: Hashable {
        case fixed
        case page
    }

    private enum SliderRanges {
        static let scrollDistance = 5.0...1_000.0
        static let duration = 0.0...1.0
        static let holdSpeed = 80.0...4_000.0
    }

    private func valueSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 12) {
                Slider(value: value, in: range, step: step)
                    .accessibilityLabel(Text(label))
                Text(format(value.wrappedValue))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 68, alignment: .trailing)
            }
        }
    }

    private func mappingInputKindBinding(
        _ id: UUID,
        value: ModernMappingInputKind
    ) -> Binding<ModernMappingInputKind> {
        Binding(
            get: { model.inputKind(id) ?? value },
            set: { newValue in model.updateInputKind(id, newValue) }
        )
    }

    private func mappingButtonBinding(
        _ id: UUID,
        value: InputButton
    ) -> Binding<InputButton> {
        Binding(
            get: { model.button(for: id) ?? value },
            set: { newValue in model.updateButton(id, newValue) }
        )
    }

    private func mappingEnabledBinding(
        _ id: UUID,
        value: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { model.isEnabled(id) ?? value },
            set: { newValue in model.updateEnabled(id, newValue) }
        )
    }

    private func mappingGestureBinding(
        _ id: UUID,
        value: ModernButtonGesture
    ) -> Binding<ModernButtonGesture> {
        Binding(
            get: { model.buttonGesture(id) ?? value },
            set: { newValue in model.updateButtonGesture(id, newValue) }
        )
    }

    private func mappingWheelSourceBinding(
        _ id: UUID,
        value: WheelMappingSource
    ) -> Binding<WheelMappingSource> {
        Binding(
            get: { model.wheelSource(id) ?? value },
            set: { newValue in model.updateWheelSource(id, newValue) }
        )
    }

    private func clickDirectionBinding(_ id: UUID, value: ScrollDirection) -> Binding<ScrollDirection> {
        Binding(
            get: { model.click(id)?.action.direction ?? value },
            set: { newValue in model.updateClick(id) { $0.action.direction = newValue } }
        )
    }

    private func clickEasingBinding(_ id: UUID, value: EasingCurve) -> Binding<EasingCurve> {
        Binding(
            get: { model.click(id)?.action.easing ?? value },
            set: { newValue in model.updateClick(id) { $0.action.easing = newValue } }
        )
    }

    private func clickEasingEnabledBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.click(id)?.action.easingEnabled ?? value },
            set: { newValue in model.updateClick(id) { $0.action.easingEnabled = newValue } }
        )
    }

    private func clickAmountBinding(_ id: UUID, value: ScrollAmount) -> Binding<ModernScrollAmount> {
        Binding(
            get: {
                let amount = model.click(id)?.action.amount ?? value
                if case .page = amount { return .page }
                return .fixed
            },
            set: { newValue in
                model.updateClick(id) {
                    if newValue == .page {
                        $0.action.amount = .page
                    } else if case let .fixed(points) = $0.action.amount {
                        $0.action.amount = .fixed(points)
                    } else {
                        $0.action.amount = .fixed(40)
                    }
                }
            }
        )
    }

    private func clickPointsBinding(_ id: UUID, value: ScrollAmount) -> Binding<Double> {
        Binding(
            get: {
                guard case let .fixed(points) = model.click(id)?.action.amount ?? value else { return 40 }
                return points
            },
            set: { newValue in
                guard newValue > 0 else { return }
                model.updateClick(id) { $0.action.amount = .fixed(newValue) }
            }
        )
    }

    private func clickDurationBinding(_ id: UUID, value: TimeInterval) -> Binding<Double> {
        Binding(
            get: { model.click(id)?.action.duration ?? value },
            set: { newValue in
                guard newValue >= 0 else { return }
                model.updateClick(id) { $0.action.duration = newValue }
            }
        )
    }

    private func holdModeBinding(_ id: UUID, value: HoldScrollMode) -> Binding<HoldScrollMode> {
        Binding(
            get: { model.hold(id)?.action.mode ?? value },
            set: { newValue in model.updateHold(id) { $0.action.mode = newValue } }
        )
    }

    private func holdSpeedBinding(_ id: UUID, value: Double) -> Binding<Double> {
        Binding(
            get: { model.hold(id)?.action.pointsPerSecond ?? value },
            set: { newValue in
                guard newValue > 0 else { return }
                model.updateHold(id) { $0.action.pointsPerSecond = newValue }
            }
        )
    }

    private func holdAccelerationBinding(_ id: UUID, value: Double) -> Binding<Double> {
        Binding(
            get: { model.hold(id)?.action.accelerationDuration ?? value },
            set: { newValue in
                guard newValue >= 0 else { return }
                model.updateHold(id) { $0.action.accelerationDuration = newValue }
            }
        )
    }

    private func holdReleaseBinding(_ id: UUID, value: Double) -> Binding<Double> {
        Binding(
            get: { model.hold(id)?.action.releaseDuration ?? value },
            set: { newValue in
                guard newValue >= 0 else { return }
                model.updateHold(id) { $0.action.releaseDuration = newValue }
            }
        )
    }

    private func holdEasingEnabledBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.hold(id)?.action.easingEnabled ?? value },
            set: { newValue in model.updateHold(id) { $0.action.easingEnabled = newValue } }
        )
    }

    private func holdJoystickVerticalBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.hold(id)?.action.joystickVerticalEnabled ?? value },
            set: { newValue in model.updateHold(id) { $0.action.joystickVerticalEnabled = newValue } }
        )
    }

    private func holdJoystickHorizontalBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.hold(id)?.action.joystickHorizontalEnabled ?? value },
            set: { newValue in model.updateHold(id) { $0.action.joystickHorizontalEnabled = newValue } }
        )
    }

    private func holdJoystickCursorBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.hold(id)?.action.joystickCapturesCursor ?? value },
            set: { newValue in model.updateHold(id) { $0.action.joystickCapturesCursor = newValue } }
        )
    }

    private func wheelDirectionBinding(_ id: UUID, value: ScrollDirection) -> Binding<ScrollDirection> {
        Binding(
            get: { model.wheel(id)?.action.direction ?? value },
            set: { newValue in model.updateWheel(id) { $0.action.direction = newValue } }
        )
    }

    private func wheelShapeBinding(_ id: UUID, value: WheelInputShape) -> Binding<WheelInputShape> {
        Binding(
            get: { model.wheel(id)?.action.inputShape ?? value },
            set: { newValue in model.updateWheel(id) { $0.action.inputShape = newValue } }
        )
    }

    private func wheelContinuousBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.wheel(id)?.action.ignoreContinuousEvents ?? value },
            set: { newValue in model.updateWheel(id) { $0.action.ignoreContinuousEvents = newValue } }
        )
    }

    private func wheelShiftBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.wheel(id)?.action.preserveShiftGestures ?? value },
            set: { newValue in model.updateWheel(id) { $0.action.preserveShiftGestures = newValue } }
        )
    }

}
