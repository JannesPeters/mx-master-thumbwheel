import AppKit
import Combine
import SwiftUI
import ThumbwheelRemapperCore

private enum ModernMappingKind: String, CaseIterable, Identifiable {
    case click
    case hold
    case wheel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return "Button click"
        case .hold: return "Button hold"
        case .wheel: return "Wheel"
        }
    }
}

private enum ModernMappingSelection: Hashable {
    case click(UUID)
    case hold(UUID)
    case wheel(UUID)
}

private struct ModernMappingItem: Identifiable {
    let id: String
    let selection: ModernMappingSelection
    let title: String
    let detail: String
    let symbolName: String
}

@MainActor
private final class ModernMappingPreferencesModel: ObservableObject {
    @Published var document: ConfigurationDocument
    @Published var selection: ModernMappingSelection?
    @Published var newMappingKind: ModernMappingKind = .click
    @Published var validationMessage: String?
    @Published private(set) var capturingButton = false

    private let onChange: (ConfigurationDocument, [MappingValidationIssue]) -> Void
    private var captureMonitor: Any?

    init(
        document: ConfigurationDocument,
        onChange: @escaping (ConfigurationDocument, [MappingValidationIssue]) -> Void
    ) {
        self.document = document
        self.onChange = onChange
        if let mapping = document.buttonClicks.first {
            selection = .click(mapping.id)
        } else if let mapping = document.buttonHolds.first {
            selection = .hold(mapping.id)
        } else if let mapping = document.wheelMappings.first {
            selection = .wheel(mapping.id)
        }
    }

    deinit {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
        }
    }

    var items: [ModernMappingItem] {
        document.buttonClicks.map {
            ModernMappingItem(
                id: "click-\($0.id.uuidString)",
                selection: .click($0.id),
                title: "\($0.button.displayName) \($0.click.displayName)",
                detail: "\($0.action.direction.displayName) · \($0.label.isEmpty ? "Scroll" : $0.label)",
                symbolName: "computermouse"
            )
        } + document.buttonHolds.map {
            ModernMappingItem(
                id: "hold-\($0.id.uuidString)",
                selection: .hold($0.id),
                title: "\($0.button.displayName) Hold",
                detail: "\($0.action.direction.displayName) · \($0.label.isEmpty ? "Continuous scroll" : $0.label)",
                symbolName: "hand.point.up.left"
            )
        } + document.wheelMappings.map {
            ModernMappingItem(
                id: "wheel-\($0.id.uuidString)",
                selection: .wheel($0.id),
                title: $0.label.isEmpty ? $0.source.displayName : $0.label,
                detail: "Wheel · \($0.action.direction.displayName)",
                symbolName: "scroll"
            )
        }
    }

    var selectedTitle: String {
        guard let selection else { return "Mappings" }
        switch selection {
        case .click: return "Button click"
        case .hold: return "Button hold"
        case .wheel: return "Thumbwheel"
        }
    }

    var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    func addMapping() {
        switch newMappingKind {
        case .click:
            guard let button = availableButtons(for: .single).first else {
                validationMessage = "All available buttons already have a single-click mapping."
                return
            }
            let mapping = ButtonClickMapping(
                button: button,
                click: .single,
                action: ScrollActionOptions(direction: .up)
            )
            document.buttonClicks.append(mapping)
            selection = .click(mapping.id)
        case .hold:
            guard let button = availableHoldButtons.first else {
                validationMessage = "All available buttons already have a hold mapping."
                return
            }
            let mapping = ButtonHoldMapping(
                button: button,
                action: HoldActionOptions(direction: .up)
            )
            document.buttonHolds.append(mapping)
            selection = .hold(mapping.id)
        case .wheel:
            guard !document.wheelMappings.contains(where: { $0.source == .horizontalThumbwheel }) else {
                validationMessage = "A horizontal thumbwheel mapping already exists."
                return
            }
            let mapping = WheelMapping()
            document.wheelMappings.append(mapping)
            selection = .wheel(mapping.id)
        }
        commit()
    }

    func removeSelection() {
        guard let selection else { return }
        switch selection {
        case let .click(id):
            document.buttonClicks.removeAll { $0.id == id }
        case let .hold(id):
            document.buttonHolds.removeAll { $0.id == id }
        case let .wheel(id):
            document.wheelMappings.removeAll { $0.id == id }
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

    func availableButtons(for click: ButtonClickKind, excluding id: UUID? = nil) -> [InputButton] {
        allButtons.filter { candidate in
            !document.buttonClicks.contains {
                $0.id != id && $0.button == candidate && $0.click == click
            }
        }
    }

    var availableHoldButtons: [InputButton] {
        allButtons.filter { candidate in
            !document.buttonHolds.contains { $0.button == candidate }
        }
    }

    func toggleCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
            capturingButton = false
            return
        }
        capturingButton = true
        captureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.otherMouseDown]
        ) { [weak self] event in
            let button: InputButton
            switch event.type {
            case .otherMouseDown: button = .other(Int64(event.buttonNumber))
            default: return
            }
            DispatchQueue.main.async {
                guard let self, let selection = self.selection, case let .click(id) = selection else {
                    guard let self, let selection = self.selection else { return }
                    self.stopCapture()
                    if case let .hold(id) = selection {
                        self.updateHold(id) { $0.button = button }
                    }
                    return
                }
                self.stopCapture()
                self.updateClick(id) { $0.button = button }
            }
        }
    }

    private func stopCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
        capturingButton = false
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

private struct ModernMappingPreferencesView: View {
    @StateObject private var model: ModernMappingPreferencesModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(
        document: ConfigurationDocument,
        onChange: @escaping (ConfigurationDocument, [MappingValidationIssue]) -> Void
    ) {
        _model = StateObject(
            wrappedValue: ModernMappingPreferencesModel(document: document, onChange: onChange)
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                        .tag(item.selection)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mappings")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detailView
                .navigationTitle(model.selectedTitle)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(ModernMappingKind.allCases) { kind in
                                Button(kind.title) {
                                    model.newMappingKind = kind
                                    model.addMapping()
                                }
                            }
                        } label: {
                            Label("Add Mapping", systemImage: "plus")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            model.removeSelection()
                        }
                        .disabled(model.selection == nil)
                    }
                }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .frame(minWidth: 900, minHeight: 650)
    }

    @ViewBuilder
    private var detailView: some View {
        if let selection = model.selection {
            ScrollView {
                Form {
                    switch selection {
                    case let .click(id):
                        clickEditor(id)
                    case let .hold(id):
                        holdEditor(id)
                    case let .wheel(id):
                        wheelEditor(id)
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
        } else {
            ContentUnavailableView(
                "No mapping selected",
                systemImage: "slider.horizontal.3",
                description: Text("Add a mapping or select one from the list.")
            )
        }
    }

    @ViewBuilder
    private func clickEditor(_ id: UUID) -> some View {
        if let mapping = model.click(id) {
            Section("Trigger") {
                Picker("Button", selection: clickButtonBinding(id, value: mapping.button)) {
                    ForEach(model.availableButtons(for: mapping.click, excluding: id), id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                Picker("Gesture", selection: clickKindBinding(id, value: mapping.click)) {
                    ForEach(ButtonClickKind.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                Button(model.capturingButton ? "Listening…" : "Capture button") {
                    model.toggleCapture()
                }
            }
            Section("Action") {
                Picker("Direction", selection: clickDirectionBinding(id, value: mapping.action.direction)) {
                    ForEach(ScrollDirection.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0)
                    }
                }
                Picker("Amount", selection: clickAmountBinding(id, value: mapping.action.amount)) {
                    Text("Fixed points").tag(ModernScrollAmount.fixed)
                    Text("One page").tag(ModernScrollAmount.page)
                }
                if case .fixed = mapping.action.amount {
                    TextField("Points", text: clickPointsBinding(id, value: mapping.action.amount))
                }
                TextField("Duration (seconds)", text: clickDurationBinding(id, value: mapping.action.duration))
            }
        }
    }

    @ViewBuilder
    private func holdEditor(_ id: UUID) -> some View {
        if let mapping = model.hold(id) {
            Section("Trigger") {
                Picker("Button", selection: holdButtonBinding(id, value: mapping.button)) {
                    ForEach(model.availableHoldButtons + [mapping.button], id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                Button(model.capturingButton ? "Listening…" : "Capture button") {
                    model.toggleCapture()
                }
            }
            Section("Action") {
                Picker("Direction", selection: holdDirectionBinding(id, value: mapping.action.direction)) {
                    ForEach(ScrollDirection.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0)
                    }
                }
                TextField("Speed (points/second)", text: holdSpeedBinding(id, value: mapping.action.pointsPerSecond))
                TextField("Acceleration (seconds)", text: holdAccelerationBinding(id, value: mapping.action.accelerationDuration))
                TextField("Release (seconds)", text: holdReleaseBinding(id, value: mapping.action.releaseDuration))
                Toggle("Use pointer movement as a joystick", isOn: holdJoystickBinding(id, value: mapping.action.joystickEnabled))
            }
        }
    }

    @ViewBuilder
    private func wheelEditor(_ id: UUID) -> some View {
        if let mapping = model.wheel(id) {
            Section("Input") {
                LabeledContent("Source", value: mapping.source.displayName)
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

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Restore Defaults") {
                model.restoreDefaults()
            }
            Text("Changes save automatically.")
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.versionDescription)
                .foregroundStyle(.tertiary)
                .font(.footnote)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private enum ModernScrollAmount: Hashable {
        case fixed
        case page
    }

    private func clickButtonBinding(_ id: UUID, value: InputButton) -> Binding<InputButton> {
        Binding(
            get: { model.click(id)?.button ?? value },
            set: { newValue in model.updateClick(id) { $0.button = newValue } }
        )
    }

    private func clickKindBinding(_ id: UUID, value: ButtonClickKind) -> Binding<ButtonClickKind> {
        Binding(
            get: { model.click(id)?.click ?? value },
            set: { newValue in model.updateClick(id) { $0.click = newValue } }
        )
    }

    private func clickDirectionBinding(_ id: UUID, value: ScrollDirection) -> Binding<ScrollDirection> {
        Binding(
            get: { model.click(id)?.action.direction ?? value },
            set: { newValue in model.updateClick(id) { $0.action.direction = newValue } }
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

    private func clickPointsBinding(_ id: UUID, value: ScrollAmount) -> Binding<String> {
        Binding(
            get: {
                guard case let .fixed(points) = model.click(id)?.action.amount ?? value else { return "" }
                return String(format: "%.2f", points)
            },
            set: { newValue in
                guard let points = Double(newValue), points > 0 else { return }
                model.updateClick(id) { $0.action.amount = .fixed(points) }
            }
        )
    }

    private func clickDurationBinding(_ id: UUID, value: TimeInterval) -> Binding<String> {
        numericBinding(get: { model.click(id)?.action.duration ?? value }) { newValue in
            guard let duration = Double(newValue), duration >= 0 else { return }
            model.updateClick(id) { $0.action.duration = duration }
        }
    }

    private func holdButtonBinding(_ id: UUID, value: InputButton) -> Binding<InputButton> {
        Binding(
            get: { model.hold(id)?.button ?? value },
            set: { newValue in model.updateHold(id) { $0.button = newValue } }
        )
    }

    private func holdDirectionBinding(_ id: UUID, value: ScrollDirection) -> Binding<ScrollDirection> {
        Binding(
            get: { model.hold(id)?.action.direction ?? value },
            set: { newValue in model.updateHold(id) { $0.action.direction = newValue } }
        )
    }

    private func holdSpeedBinding(_ id: UUID, value: Double) -> Binding<String> {
        numericBinding(get: { model.hold(id)?.action.pointsPerSecond ?? value }) { newValue in
            guard let speed = Double(newValue), speed > 0 else { return }
            model.updateHold(id) { $0.action.pointsPerSecond = speed }
        }
    }

    private func holdAccelerationBinding(_ id: UUID, value: Double) -> Binding<String> {
        numericBinding(get: { model.hold(id)?.action.accelerationDuration ?? value }) { newValue in
            guard let duration = Double(newValue), duration >= 0 else { return }
            model.updateHold(id) { $0.action.accelerationDuration = duration }
        }
    }

    private func holdReleaseBinding(_ id: UUID, value: Double) -> Binding<String> {
        numericBinding(get: { model.hold(id)?.action.releaseDuration ?? value }) { newValue in
            guard let duration = Double(newValue), duration >= 0 else { return }
            model.updateHold(id) { $0.action.releaseDuration = duration }
        }
    }

    private func holdJoystickBinding(_ id: UUID, value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.hold(id)?.action.joystickEnabled ?? value },
            set: { newValue in model.updateHold(id) { $0.action.joystickEnabled = newValue } }
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

    private func numericBinding(
        get: @escaping () -> Double,
        set: @escaping (String) -> Void
    ) -> Binding<String> {
        Binding(
            get: { String(format: "%.2f", get()) },
            set: set
        )
    }
}

final class ModernMappingPreferencesWindowController: NSWindowController {
    init(
        document: ConfigurationDocument,
        onChange: @escaping (ConfigurationDocument, [MappingValidationIssue]) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Thumbwheel Remapper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 860, height: 620)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(
            rootView: ModernMappingPreferencesView(document: document, onChange: onChange)
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
