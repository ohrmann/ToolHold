import SwiftUI

struct JSONTreeViewerView: View {
    @Bindable var workspace: JSONTreeWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return systemReduceMotion || (arguments.contains("--navigation-ui-tests") && arguments.contains("--reduce-motion"))
    }
    @State private var commands = JSONEditorCommands()
    @State private var jumpRequest = 0
    @State private var jumpTarget: NSRange?
    @State private var dragStart: Double?
    @State private var details = false
    @State private var copyConfirmation = ""
    @FocusState private var focus: Focus?
    private enum Focus: Hashable { case search, tree }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            VStack(spacing: 8) {
                HStack {
                    Button("Build Tree") { workspace.build() }.keyboardShortcut(.return, modifiers: .command)
                        .disabled(workspace.busy || workspace.input.isEmpty)
                        .accessibilityIdentifier("tree-build")
                    Button(workspace.inputCollapsed ? "Edit Input" : "Hide Input", systemImage: "rectangle.leadinghalf.inset.filled") {
                        if !workspace.inputCollapsed { commands.resignFocus?() }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { workspace.inputCollapsed.toggle() }
                    }.accessibilityIdentifier("tree-input-toggle")
                    Spacer(minLength: 0)
                    options
                }
                if workspace.document == nil || workspace.result?.diagnostics.isEmpty == false {
                    JSONDiagnosticsPanel(workspace: workspace, show: showSource)
                        .transition(.opacity)
                }
                GeometryReader { panels in
                    TreePanelLayout(horizontal: wide, fraction: workspace.panelFraction, collapsed: workspace.inputCollapsed) {
                        inputPanel
                        divider(wide: wide, length: wide ? panels.size.width : panels.size.height)
                        treePanel(compact: !wide)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: workspace.result?.diagnostics.isEmpty == false)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: workspace.document == nil || workspace.result?.diagnostics.isEmpty == false)
            .padding(12)
        }
        .navigationTitle("JSON Tree Viewer")
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { workspace.cancel() }
        .sheet(isPresented: $details) { selectedDetails }
        .onChange(of: workspace.document?.snapshotID) { _, _ in details = false }
        .background {
            Button("Find in Tree") { focus = .search }.keyboardShortcut("f", modifiers: .command)
                .hidden().accessibilityHidden(true)
        }
    }
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
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input").font(.headline)
                Spacer()
                Button("Clear Input") { commands.clear?(); workspace.clear() }.disabled(workspace.input.isEmpty)
            }
            JSONTextEditor(text: $workspace.input,
                diagnostic: workspace.resourceLimited ? nil : workspace.result?.diagnostics.first(where: { $0.severity == .error }) ?? workspace.result?.diagnostics.first,
                jumpTarget: jumpTarget, jumpRequest: jumpRequest, onPaste: { workspace.didPaste() }, commands: commands,
                options: JSONEditorOptions(syntaxHighlighting: workspace.preferences.syntaxHighlighting,
                    rainbowBrackets: workspace.preferences.rainbowBrackets, matchingBrackets: workspace.preferences.matchingBrackets,
                    wordWrap: workspace.preferences.wordWrap),
                placeholder: "Paste or type JSON, then Build Tree.")
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
        .opacity(workspace.inputCollapsed ? 0 : 1)
        .allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
        .clipped()
    }
    private func divider(wide: Bool, length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            .frame(width: wide ? 5 : nil, height: wide ? nil : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                if dragStart == nil { dragStart = workspace.panelFraction }
                let delta = wide ? value.translation.width : value.translation.height
                workspace.panelFraction = min(0.7, max(0.25, (dragStart ?? 0.4) + delta / max(1, length)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Input panel size")
            .accessibilityAdjustableAction { direction in
                workspace.panelFraction = min(0.7, max(0.25, workspace.panelFraction + (direction == .increment ? 0.05 : -0.05)))
            }.opacity(workspace.inputCollapsed ? 0 : 1).allowsHitTesting(!workspace.inputCollapsed)
            .accessibilityHidden(workspace.inputCollapsed)
    }
    private func treePanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            search
            HStack {
                Button("Expand All") { workspace.expandAll() }.accessibilityIdentifier("tree-expand-all")
                Button("Collapse All") { workspace.collapseAll() }.accessibilityIdentifier("tree-collapse-all")
                Spacer(minLength: 0)
                if workspace.projecting || workspace.searching {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { workspace.cancel() }.controlSize(.small)
                }
            }.disabled(workspace.document == nil)
            JSONTreeTable(rows: workspace.visible, rowNumbers: workspace.rowNumbers, version: workspace.renderVersion,
                rowsVersion: workspace.rowsVersion, changes: workspace.rowChanges, animate: !reduceMotion,
                selection: workspace.selection, scrollRequest: workspace.scrollRequest, scrollTarget: workspace.scrollTarget,
                row: { id in AnyView(treeRow(id, compact: compact)) },
                select: { workspace.selection = $0 }, key: treeKey)
                .overlay {
                    if workspace.document == nil {
                        ContentUnavailableView {
                            Label(workspace.result?.status == .invalid ? "Check Input" : "Explore JSON structure", systemImage: "list.bullet.indent")
                        } description: { Text("Build a valid JSON document to browse its keys and values.") }
                        .allowsHitTesting(false)
                    }
                }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            if let document = workspace.document, let id = workspace.selection {
                selectedFooter(id, document: document)
            }
        }
    }
    @ViewBuilder private func treeRow(_ id: Int, compact: Bool) -> some View {
        if let document = workspace.document, document.nodes.indices.contains(id) {
            JSONTreeRow(node: document.nodes[id], number: workspace.rowNumbers[id] ?? 0,
                expanded: workspace.expanded(id), selected: workspace.selection == id, compact: compact,
                matches: workspace.matches, nodeMatches: workspace.matchesByNode[id] ?? JSONTreeNodeMatches(), active: workspace.activeMatch,
                toggle: { workspace.toggle(id) }, select: { workspace.selection = id })
            .contextMenu { copyActions(id, document: document); Button("Show Source") { showSource(document.nodes[id].range) } }
        }
    }
    private func treeKey(_ key: JSONTreeTable.TreeKey) {
        switch key {
        case .up: workspace.moveSelection(-1)
        case .down: workspace.moveSelection(1)
        case .left: workspace.moveHorizontal(right: false)
        case .right: workspace.moveHorizontal(right: true)
        case .copy:
            if let document = workspace.document, let id = workspace.selection { copy(document.fragment(id), label: "JSON fragment copied") }
        }
    }
    private var search: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search keys and values...", text: $workspace.query).textFieldStyle(.plain)
                    .focused($focus, equals: .search).accessibilityIdentifier("tree-search")
                    .submitLabel(.next).onSubmit { workspace.nextMatch() }
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        workspace.nextMatch(backwards: press.modifiers.contains(.shift)); return .handled
                    }
                if !workspace.query.isEmpty {
                    Button { workspace.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear tree search")
                }
            }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text(searchStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("tree-search-count")
                Spacer(minLength: 0)
                Button { workspace.nextMatch(backwards: true) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Previous match").keyboardShortcut("g", modifiers: [.command, .shift])
                Button { workspace.nextMatch() } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Next match").keyboardShortcut("g", modifiers: .command)
            }.disabled(workspace.matches.isEmpty)
        }.disabled(workspace.document == nil)
    }
    private var searchStatus: String {
        if workspace.searching { return "Searching…" }
        if workspace.query.isEmpty { return "Search all keys and values" }
        if workspace.matches.isEmpty { return "No matches" }
        return "\((workspace.activeMatch ?? 0) + 1) / \(workspace.matches.count)" + (workspace.activeHidden ? " · Hidden" : "")
    }
    private func selectedFooter(_ id: Int, document: JSONStructureDocument) -> some View {
        let node = document.nodes[id], path = document.path(id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(node.kind.rawValue).font(.caption.weight(.semibold))
                Text(JSONTreePreview.make(path.jsonPath).text).font(.system(.caption, design: .monospaced)).lineLimit(1)
                Spacer(minLength: 0)
                Menu("Copy") { copyActions(id, document: document) }.accessibilityIdentifier("tree-copy")
                Menu("Actions") {
                    Button("Details") { details = true }
                    Button("Show Source") { showSource(node.range) }
                }
            }
            if path.ambiguous { Label("Ambiguous path · duplicate field name", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if !copyConfirmation.isEmpty { Text(copyConfirmation).font(.caption).foregroundStyle(.secondary) }
        }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    @ViewBuilder private func copyActions(_ id: Int, document: JSONStructureDocument) -> some View {
        let node = document.nodes[id], path = document.path(id)
        Button("Copy Value") { if let scalar = node.scalar { copy(scalar, label: "Value copied") } }.disabled(node.scalar == nil)
        Button("Copy JSON Fragment") { copy(document.fragment(id), label: "JSON fragment copied") }
        Button("Copy JSON Pointer" + (path.ambiguous ? " (ambiguous)" : "")) { copy(path.pointer, label: id == 0 ? "Root pointer copied (empty string)" : "JSON Pointer copied") }
        Button("Copy JSONPath" + (path.ambiguous ? " (ambiguous)" : "")) { copy(path.jsonPath, label: "JSONPath copied") }
    }
    @ViewBuilder private var selectedDetails: some View {
        if let document = workspace.document, let id = workspace.selection {
            JSONTreeNodeDetails(document: document, nodeID: id)
        }
    }
    private func showSource(_ range: NSRange) {
        workspace.inputCollapsed = false
        jumpTarget = range
        // The editor retains its identity; request the jump after the reveal transaction.
        let source = workspace.input
        DispatchQueue.main.async {
            guard workspace.input.utf16.elementsEqual(source.utf16) else { return }
            jumpRequest += 1
        }
    }
    private func copy(_ text: String, label: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copyConfirmation = label
    }
}

/// Keeps the native editor alive across collapse, axis changes and resizing.
private struct TreePanelLayout: Layout {
    let horizontal: Bool
    var fraction: Double
    var collapseProgress: Double
    init(horizontal: Bool, fraction: Double, collapsed: Bool) {
        self.horizontal = horizontal; self.fraction = fraction; collapseProgress = collapsed ? 1 : 0
    }
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fraction, collapseProgress) }
        set { fraction = newValue.first; collapseProgress = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 600, height: 500))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let length = horizontal ? bounds.width : bounds.height
        let divider: CGFloat = 12 * (1 - collapseProgress)
        let input = max(0, length - divider) * fraction * (1 - collapseProgress)
        for (index, pair) in [(0, (CGFloat.zero, input)), (1, (input, divider)), (2, (input + divider, max(0, length - input - divider)))] {
            let origin = CGPoint(x: bounds.minX + (horizontal ? pair.0 : 0), y: bounds.minY + (horizontal ? 0 : pair.0))
            let size = CGSize(width: horizontal ? pair.1 : bounds.width, height: horizontal ? bounds.height : pair.1)
            subviews[index].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}
