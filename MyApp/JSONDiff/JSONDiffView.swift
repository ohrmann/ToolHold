import SwiftUI

struct JSONDiffView: View {
    @Bindable var workspace: JSONDiffWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        systemReduceMotion || (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") && ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
    }
    @State private var beforeCommands = JSONEditorCommands()
    @State private var afterCommands = JSONEditorCommands()
    @State private var beforeTarget: NSRange?
    @State private var afterTarget: NSRange?
    @State private var beforeJump = 0
    @State private var afterJump = 0
    @State private var beforeJumpFocus = true
    @State private var afterJumpFocus = true
    @State private var dragStart: Double?
    @State private var details = false
    @State private var confirmation = ""
    @State private var navigationRevision = UUID()

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            VStack(spacing: 8) {
                controls
                GeometryReader { content in
                    DiffWorkspaceLayout(fraction: !wide && content.size.height < 430 ? max(0.65, workspace.inputFraction) : workspace.inputFraction, collapsed: workspace.inputsCollapsed, minimumHeight: wide ? max(minimum(.before), minimum(.after)) : minimum(.before) + minimum(.after) + 8) {
                        DiffInputLayout(horizontal: wide, firstMinimum: minimum(.before), secondMinimum: minimum(.after)) {
                            input(.before)
                            input(.after)
                        }
                        divider(length: content.size.height)
                        results(wide: wide)
                    }
                }
            }.padding(12)
                .animation(animation, value: workspace.before.result?.diagnostics.isEmpty == false)
                .animation(animation, value: workspace.after.result?.diagnostics.isEmpty == false)
        }
        .navigationTitle("Structural JSON Diff")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { navigationRevision = UUID(); workspace.cancel() }
        .onChange(of: workspace.version) { _, _ in navigationRevision = UUID(); details = false; confirmation = "" }
        .sheet(isPresented: $details) { selectedDetails }
    }
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { mainActions; Spacer(minLength: 4); options }
            VStack(alignment: .leading, spacing: 6) {
                HStack { compareButton; progress; Spacer(); options }
                toggleInputs
            }
        }
    }
    @ViewBuilder private var mainActions: some View {
        compareButton
        toggleInputs
        progress
    }
    private var compareButton: some View {
        Button("Compare") { workspace.compare() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(workspace.busy || workspace.before.source.isEmpty || workspace.after.source.isEmpty)
            .accessibilityIdentifier("diff-compare")
    }
    private var toggleInputs: some View {
        Button(workspace.inputsCollapsed ? "Edit Inputs" : "Hide Inputs", systemImage: "rectangle.tophalf.inset.filled") {
            if !workspace.inputsCollapsed { beforeCommands.resignFocus?(); afterCommands.resignFocus?() }
            withAnimation(animation) { workspace.inputsCollapsed.toggle() }
        }.accessibilityIdentifier("diff-input-toggle")
    }
    private var progress: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Button("Cancel") { workspace.cancel() }
        }
        .opacity(workspace.busy || workspace.before.busy || workspace.after.busy ? 1 : 0)
        .disabled(!workspace.busy && !workspace.before.busy && !workspace.after.busy)
        .accessibilityHidden(!workspace.busy && !workspace.before.busy && !workspace.after.busy)
    }
    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    private var options: some View {
        Menu {
            Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
            Divider()
            Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
            Toggle("Rainbow Brackets", isOn: $workspace.preferences.rainbowBrackets)
            Toggle("Matching Brackets", isOn: $workspace.preferences.matchingBrackets)
            Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
        } label: { Label("Editor Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
        .accessibilityLabel("Editor Options")
    }
    private func input(_ side: JSONDiffSide) -> some View {
        let source = workspace.input(side)
        return JSONDiffInputPanel(input: source, side: side, options: workspace.preferences,
            commands: side == .before ? beforeCommands : afterCommands,
            jumpTarget: side == .before ? beforeTarget : afterTarget,
            jumpRequest: side == .before ? beforeJump : afterJump,
            focusOnJump: side == .before ? beforeJumpFocus : afterJumpFocus, animateJumps: !reduceMotion,
            paste: { workspace.didPaste(side) }, show: { show(side, range: $0) })
        .opacity(workspace.inputsCollapsed ? 0 : 1)
        .allowsHitTesting(!workspace.inputsCollapsed).accessibilityHidden(workspace.inputsCollapsed)
        .clipped()
    }
    private func divider(length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 5)
            .frame(maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                if dragStart == nil { dragStart = workspace.inputFraction }
                workspace.inputFraction = min(0.72, max(0.25, (dragStart ?? 0.44) + value.translation.height / max(1, length)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Input area height")
            .accessibilityAdjustableAction { direction in
                workspace.inputFraction = min(0.72, max(0.25, workspace.inputFraction + (direction == .increment ? 0.05 : -0.05)))
            }
            .opacity(workspace.inputsCollapsed ? 0 : 1)
            .allowsHitTesting(!workspace.inputsCollapsed).accessibilityHidden(workspace.inputsCollapsed)
    }
    private func results(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack { summary; Spacer(); navigation }
                VStack(alignment: .leading, spacing: 4) { summary; HStack { navigation; Spacer() } }
            }
            Text("Arrays compared by index · Number spelling compared")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if workspace.result?.hasDuplicates == true {
                Label("Duplicate keys — compared by occurrence", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            JSONTreeTable(rows: workspace.rows, rowNumbers: workspace.rowNumbers,
                version: workspace.version * 2 + (wide ? 1 : 0), rowsVersion: workspace.version,
                changes: nil, animate: false, selection: workspace.selection,
                scrollRequest: workspace.scrollRequest, scrollTarget: workspace.selection,
                row: { id in AnyView(changeRow(id, wide: wide)) },
                select: { workspace.selection = $0 }, key: key,
                preferredRowHeight: wide ? 82 : 116, tableIdentifier: "json-diff-results", suppressSoftwareKeyboard: true)
                .overlay {
                    if workspace.result?.changes.isEmpty != false {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: workspace.result != nil ? "checkmark.circle" : "arrow.left.arrow.right")
                        } description: {
                            Text(workspace.result != nil ? "Formatting and object key order are ignored. Number spelling is compared." : "Enter valid JSON on both sides, then Compare.")
                        }.allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            selectedActions
        }
    }
    private func minimum(_ side: JSONDiffSide) -> Double {
        workspace.input(side).result?.diagnostics.isEmpty == false ? 240 : 120
    }
    private var hasInvalidInput: Bool { workspace.before.result?.status == .invalid || workspace.after.result?.status == .invalid }
    private var hasResourceLimit: Bool {
        for input in [workspace.before, workspace.after] { if case .resourceLimit = input.result?.status { return true } }
        return false
    }
    private var emptyTitle: String {
        if workspace.busy { return "Comparing JSON…" }
        if workspace.wasCancelled { return "Cancelled" }
        if hasResourceLimit { return "Processing limit reached" }
        if hasInvalidInput { return "Check Inputs" }
        return workspace.result == nil ? "Compare JSON structures" : "No structural differences"
    }
    private var summary: some View {
        Text(workspace.busy || workspace.before.busy || workspace.after.busy ? "Processing…" : workspace.wasCancelled ? "Cancelled" : workspace.result.map {
            "\($0.changes.count) changes · +\($0.added) added · −\($0.removed) removed · \($0.changed) changed"
        } ?? (hasResourceLimit ? "Resource limit reached" : hasInvalidInput ? "Check Inputs" : "Ready to compare"))
        .font(.callout).lineLimit(2).accessibilityIdentifier("diff-summary")
    }
    private var navigation: some View {
        HStack(spacing: 8) {
            Button { workspace.move(-1) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Previous change")
            Text("\(workspace.selection.map { $0 + 1 } ?? 0) / \(workspace.rows.count)").monospacedDigit().font(.caption)
            Button { workspace.move(1) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Next change")
        }.disabled(workspace.rows.isEmpty)
    }
    @ViewBuilder private func changeRow(_ id: Int, wide: Bool) -> some View {
        if let result = workspace.result, result.changes.indices.contains(id) {
            let change = result.changes[id]
            JSONDiffRow(result: result, change: change, selected: workspace.selection == id, wide: wide,
                select: { workspace.selection = id }, reveal: { showBoth(result, change) })
            .contextMenu { actions(result, change) }
        }
    }
    private var selectedChange: JSONDiffChange? {
        guard let result = workspace.result, let id = workspace.selection, result.changes.indices.contains(id) else { return nil }
        return result.changes[id]
    }
    private var selectedActions: some View {
        HStack {
            Button("Details") { details = true }.disabled(selectedChange == nil)
            Menu("Actions") {
                if let result = workspace.result, let change = selectedChange { actions(result, change) }
            }.disabled(selectedChange == nil)
            Spacer(minLength: 0)
            Text(confirmation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(minHeight: 28)
    }
    @ViewBuilder private func actions(_ result: JSONDiffResult, _ change: JSONDiffChange) -> some View {
        if result.path(for: change).ambiguous { Text("Ambiguous path — duplicate key") }
        Button("Copy JSON Pointer") { copy(result.path(for: change).pointer, rootPointer: result.path(for: change).pointer.isEmpty) }
        Button("Show Before and After") { showBoth(result, change) }
        Divider()
        ForEach(JSONDiffSide.allCases, id: \.self) { side in
            Button("Show \(side.rawValue)") {
                let id = side == .before ? change.before : change.after
                let document = side == .before ? result.before : result.after
                if let id { show(side, range: document.nodes[id].range) }
            }.disabled((side == .before ? change.before : change.after) == nil)
            Button("Copy \(side.rawValue) Value") { if let value = result.value(change, side: side) { copy(value) } }
                .disabled(result.value(change, side: side) == nil)
            Button("Copy \(side.rawValue) JSON Fragment") { if let text = result.fragment(change, side: side) { copy(text) } }
                .disabled((side == .before ? change.before : change.after) == nil)
        }
    }
    private var selectedDetails: some View {
        NavigationStack {
            ScrollView {
                if let result = workspace.result, let change = selectedChange {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(change.kind.rawValue).font(.headline)
                        Text(JSONDiffRow.safeFullText(result.path(for: change).pointer.isEmpty ? "Root" : result.path(for: change).pointer))
                            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        if result.path(for: change).ambiguous { Label("Ambiguous path", systemImage: "exclamationmark.triangle") }
                        ForEach(JSONDiffSide.allCases, id: \.self) { side in
                            let document = side == .before ? result.before : result.after
                            let id = side == .before ? change.before : change.after
                            Text(side.rawValue).font(.headline)
                            if let id {
                                Text(document.nodes[id].kind.rawValue).foregroundStyle(.secondary)
                                // JSON fragments escape ordinary controls. Also render bidi/control scalars safely.
                                Text(JSONDiffRow.safeFullText(document.fragment(id)))
                                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                if let scalar = document.nodes[id].scalar, document.nodes[id].kind == .string {
                                    Text("Decoded Unicode scalars (up to 256)").font(.caption).foregroundStyle(.secondary)
                                    Text(scalar.unicodeScalars.prefix(256).map { String(format: "U+%04X", $0.value) }.joined(separator: " ") + (scalar.unicodeScalars.count > 256 ? " …" : ""))
                                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                }
                            } else { Text("Missing").foregroundStyle(.secondary) }
                        }
                        Menu("Actions") { actions(result, change) }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Change Details")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { details = false } } }
        }.frame(minWidth: 280, idealWidth: 640, minHeight: 300, idealHeight: 520)
    }
    private func showBoth(_ result: JSONDiffResult, _ change: JSONDiffChange) {
        guard workspace.result?.before.snapshotID == result.before.snapshotID,
              workspace.result?.after.snapshotID == result.after.snapshotID else { return }
        workspace.selection = change.id
        var targets: [(JSONDiffSide, NSRange)] = []
        if let id = change.before { targets.append((.before, result.before.nodes[id].range)) }
        if let id = change.after { targets.append((.after, result.after.nodes[id].range)) }
        show(targets, focus: false)
    }
    private func show(_ side: JSONDiffSide, range: NSRange) { show([(side, range)], focus: true) }
    private func show(_ targets: [(JSONDiffSide, NSRange)], focus: Bool) {
        let wasCollapsed = workspace.inputsCollapsed
        let snapshots = targets.map { workspace.input($0.0).source }
        let request = UUID(); navigationRevision = request; details = false
        withAnimation(animation) { workspace.inputsCollapsed = false }
        // One guarded request publishes both jumps after reveal geometry settles.
        Task { @MainActor in
            if wasCollapsed && !reduceMotion { try? await Task.sleep(for: .milliseconds(220)) }
            else { await Task.yield() }
            guard navigationRevision == request, !workspace.inputsCollapsed,
                  zip(targets, snapshots).allSatisfy({ target, source in
                      source.utf16.elementsEqual(workspace.input(target.0).source.utf16)
                  }) else { return }
            for (side, range) in targets {
                if side == .before { beforeTarget = range; beforeJumpFocus = focus; beforeJump += 1 }
                else { afterTarget = range; afterJumpFocus = focus; afterJump += 1 }
            }
        }
    }

    private func key(_ key: JSONTreeTable.TreeKey) {
        switch key {
        case .up: workspace.move(-1)
        case .down: workspace.move(1)
        case .copy: if let result = workspace.result, let change = selectedChange {
            if let text = result.fragment(change, side: .after) ?? result.fragment(change, side: .before) { copy(text) }
        }
        default: break
        }
    }
    private func copy(_ text: String, rootPointer: Bool = false) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        confirmation = rootPointer ? "Copied root pointer" : "Copied"
    }
}

private struct JSONDiffInputPanel: View {
    @Bindable var input: JSONDiffInput
    let side: JSONDiffSide
    let options: JSONToolPreferences
    let commands: JSONEditorCommands
    let jumpTarget: NSRange?
    let jumpRequest: Int
    let focusOnJump: Bool
    let animateJumps: Bool
    let paste: () -> Void
    let show: (NSRange) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactDetails = false
    private var diagnostic: JSONDiagnostic? { input.result?.diagnostics.first { $0.severity == .error } ?? input.result?.diagnostics.first }
    var body: some View {
        GeometryReader { geometry in
        let short = geometry.size.height < 190
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(side.rawValue).font(.headline)
                Spacer()
                if short, let diagnostic {
                    Button {
                        compactDetails = true
                    } label: {
                        Label(diagnostic.severity == .warning ? "Warning" : "Check Input", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                    }
                    .help(diagnostic.message)
                    .accessibilityLabel("\(side.rawValue) diagnostics. \(diagnostic.message)")
                    .accessibilityIdentifier("diff-\(side.rawValue.lowercased())-diagnostics")
                    .popover(isPresented: $compactDetails) {
                        JSONDiagnosticsPanel(input: input.source, result: input.result, context: input.context,
                            busy: input.busy, wasCancelled: input.wasCancelled, cancel: input.cancel,
                            show: { range in compactDetails = false; show(range) })
                            .padding().frame(idealWidth: 360).presentationCompactAdaptation(.sheet)
                    }
                }
                Button("Clear") { commands.clear?() }.disabled(input.source.isEmpty)
                    .accessibilityLabel("Clear \(side.rawValue)")
            }
            if diagnostic != nil && !short {
                JSONDiagnosticsPanel(input: input.source, result: input.result, context: input.context,
                    busy: input.busy, wasCancelled: input.wasCancelled, compact: true, cancel: input.cancel, show: show)
                    .transition(.opacity)
            }
            JSONTextEditor(text: $input.source, diagnostic: resourceLimited ? nil : diagnostic,
                jumpTarget: jumpTarget, jumpRequest: jumpRequest, animateJumps: animateJumps, focusOnJump: focusOnJump, onPaste: paste, commands: commands,
                options: JSONEditorOptions(syntaxHighlighting: options.syntaxHighlighting,
                    rainbowBrackets: options.rainbowBrackets, matchingBrackets: options.matchingBrackets, wordWrap: options.wordWrap),
                placeholder: "Paste or type \(side.rawValue.lowercased()) JSON.")
                .accessibilityLabel("\(side.rawValue) JSON input")
                .accessibilityIdentifier("diff-\(side.rawValue.lowercased())-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: diagnostic != nil)
        }
    }
    private var resourceLimited: Bool { if case .resourceLimit = input.result?.status { return true }; return false }
}

/// Same child identities at every width and when collapsed: native editors never move between conditional branches.
private struct DiffInputLayout: Layout {
    var horizontal: Bool
    var firstMinimum: Double
    var secondMinimum: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(firstMinimum, secondMinimum) }
        set { firstMinimum = newValue.first; secondMinimum = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gap: CGFloat = 8
        let available = max(0, bounds.height - gap)
        let first = min(available, max(0, available < firstMinimum + secondMinimum
            ? available * firstMinimum / max(1, firstMinimum + secondMinimum)
            : firstMinimum + (available - firstMinimum - secondMinimum) / 2))
        for (index, view) in subviews.enumerated() {
            let size = CGSize(width: horizontal ? max(0, (bounds.width - gap) / 2) : bounds.width,
                              height: horizontal ? bounds.height : index == 0 ? first : available - first)
            view.place(at: CGPoint(x: bounds.minX + (horizontal ? CGFloat(index) * (size.width + gap) : 0),
                                   y: bounds.minY + (horizontal || index == 0 ? 0 : first + gap)), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}
private struct DiffWorkspaceLayout: Layout {
    var fraction: Double
    var collapseProgress: Double
    var minimumHeight: Double
    init(fraction: Double, collapsed: Bool, minimumHeight: Double) {
        self.fraction = fraction; collapseProgress = collapsed ? 1 : 0; self.minimumHeight = minimumHeight
    }
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(fraction, collapseProgress), minimumHeight) }
        set { fraction = newValue.first.first; collapseProgress = newValue.first.second; minimumHeight = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let height = max(0, min(max(0, bounds.height - (bounds.height < 430 ? 44 : 90)), max(minimumHeight, bounds.height * fraction)) * (1 - collapseProgress)), gap: CGFloat = 12 * (1 - collapseProgress)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + height), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: gap))
        subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + height + gap), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: max(0, bounds.height - height - gap)))
    }
}
