import SwiftUI

struct JSONPathExplorerView: View {
    @Bindable var workspace: JSONPathWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        systemReduceMotion || (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") && ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
    }
    @State private var commands = JSONEditorCommands()
    @State private var dragStart: Double?
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var navigationRequest = UUID()
    @State private var querySelection: TextSelection?
    @State private var help = false
    @State private var details = false
    @State private var confirmation = ""
    @State private var copying = false
    @State private var copyTask: Task<Void, Never>?
    @FocusState private var queryFocused: Bool

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            VStack(spacing: 8) {
                controls
                queryBar
                if workspace.validation?.diagnostics.isEmpty == false || workspace.validation?.status == .invalid || workspace.resourceLimited {
                    JSONDiagnosticsPanel(input: workspace.input, result: workspace.validation, context: workspace.context,
                        busy: workspace.busy, wasCancelled: workspace.status == .cancelled,
                        compact: geometry.size.height < 620,
                        cancel: workspace.cancel, show: showSource)
                        .transition(.opacity)
                }
                if let failure = workspace.failure {
                    queryDiagnostic(failure).transition(.opacity.combined(with: .move(edge: .top)))
                }
                GeometryReader { panels in
                    JSONPathPanelLayout(horizontal: wide, fraction: workspace.panelFraction, collapsed: workspace.inputCollapsed) {
                        inputPanel
                        divider(horizontal: wide, length: wide ? panels.size.width : panels.size.height)
                        results
                    }
                }
            }
            .padding(12)
            .animation(animation, value: workspace.failure != nil)
            .animation(animation, value: workspace.validation?.diagnostics.isEmpty == false || workspace.resourceLimited)
        }
        .navigationTitle("JSONPath Explorer")
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { workspace.cancel(); copyTask?.cancel(); commands.cancelNavigation?(); navigationRequest = UUID() }
        .onChange(of: workspace.version) { _, _ in details = false; copyTask?.cancel(); copying = false; commands.cancelNavigation?(); navigationRequest = UUID(); confirmation = "" }
        .sheet(isPresented: $details) {
            if let document = workspace.document, let id = workspace.selectedNodeID { JSONTreeNodeDetails(document: document, nodeID: id) }
        }
        .background {
            Button("Focus JSONPath Query") { queryFocused = true }.keyboardShortcut("f", modifiers: .command)
                .hidden().accessibilityHidden(true)
        }
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button(workspace.inputCollapsed ? "Edit Input" : "Hide Input", systemImage: "rectangle.leadinghalf.inset.filled") {
                navigationRequest = UUID()
                commands.cancelNavigation?()
                if !workspace.inputCollapsed { commands.resignFocus?() }
                withAnimation(animation) { workspace.inputCollapsed.toggle() }
            }.accessibilityIdentifier("path-input-toggle")
            Spacer(minLength: 0)
            Button { help = true } label: { Image(systemName: "questionmark.circle") }
                .accessibilityLabel("JSONPath syntax help")
                .popover(isPresented: $help) { syntaxHelp }
            Menu {
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Divider()
                Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
                Toggle("Rainbow Brackets", isOn: $workspace.preferences.rainbowBrackets)
                Toggle("Matching Brackets", isOn: $workspace.preferences.matchingBrackets)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
            } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Editor Options")
        }.controlSize(.small)
    }
    private var queryBar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                TextField("JSONPath, e.g. $.users[*].name", text: $workspace.query, selection: $querySelection)
                    .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder)
                    .focused($queryFocused).onSubmit { run() }
                    .accessibilityLabel("JSONPath query").accessibilityIdentifier("path-query")
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                Button("Run", action: run).keyboardShortcut(.return, modifiers: .command)
                    .disabled(workspace.input.isEmpty || workspace.query.isEmpty || workspace.busy)
                    .accessibilityIdentifier("path-run")
            }
            HStack(spacing: 6) {
                if workspace.busy { ProgressView().controlSize(.mini) }
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("path-status")
                Spacer(minLength: 0)
                if workspace.busy { Button("Cancel") { workspace.cancel() }.controlSize(.small) }
            }.frame(height: 22)
        }
    }
    private func run() { confirmation = ""; workspace.run() }
    private var status: String {
        switch workspace.status {
        case .ready: return workspace.document == nil ? "Enter JSON and a query, then Run" : "JSON checked · Ready to run"
        case .checking: return "Checking JSON and preparing query…"
        case .running: return "Running query…"
        case .complete: return "\(workspace.rows.count) " + (workspace.rows.count == 1 ? "match" : "matches")
        case .invalidJSON: return "Invalid JSON · Check Input"
        case .invalidQuery: return "Invalid JSONPath"
        case .blocked: return "Query unavailable · Duplicate member names"
        case .limited: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        }
    }
    private func queryDiagnostic(_ failure: JSONPathFailure) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(JSONTreePreview.make(failure.message, budget: 240).text).font(.callout).fixedSize(horizontal: false, vertical: true)
                if case .syntax(_, let range) = failure {
                    HStack {
                        Text("Query UTF-16 position \(range.location + 1)" + (range.length == 0 ? " · End of query" : ""))
                        Button("Show in Query") {
                            queryFocused = true
                            let text = workspace.query as NSString
                            let safe = range.location < text.length ? text.rangeOfComposedCharacterSequence(at: range.location) : NSRange(location: text.length, length: 0)
                            if let selection = Range(safe, in: workspace.query) { querySelection = TextSelection(range: selection) }
                        }
                    }.font(.caption)
                }
            }
            Spacer(minLength: 0)
        }.padding(8).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("path-diagnostic")
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input").font(.headline)
                Spacer(minLength: 0)
                Button("Clear Input") { commands.clear?(); workspace.clear() }.disabled(workspace.input.isEmpty)
            }
            JSONTextEditor(text: $workspace.input,
                diagnostic: workspace.resourceLimited ? nil : workspace.validation?.diagnostics.first(where: { $0.severity == .error }) ?? workspace.validation?.diagnostics.first,
                jumpTarget: jumpTarget, jumpRequest: jumpRequest, animateJumps: !reduceMotion, highlightJumps: true,
                focusOnJump: false, onPaste: { workspace.didPaste() }, commands: commands,
                options: JSONEditorOptions(syntaxHighlighting: workspace.preferences.syntaxHighlighting,
                    rainbowBrackets: workspace.preferences.rainbowBrackets, matchingBrackets: workspace.preferences.matchingBrackets,
                    wordWrap: workspace.preferences.wordWrap), placeholder: "Paste or type JSON to query.")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }.opacity(workspace.inputCollapsed ? 0 : 1).allowsHitTesting(!workspace.inputCollapsed)
            .accessibilityHidden(workspace.inputCollapsed).clipped()
    }
    private func divider(horizontal: Bool, length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            .frame(width: horizontal ? 5 : nil, height: horizontal ? nil : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                if dragStart == nil { dragStart = workspace.panelFraction }
                let delta = horizontal ? value.translation.width : value.translation.height
                workspace.panelFraction = min(0.75, max(0.25, (dragStart ?? 0.42) + delta / max(1, length)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Input panel size")
            .accessibilityAdjustableAction { direction in workspace.panelFraction = min(0.75, max(0.25, workspace.panelFraction + (direction == .increment ? 0.05 : -0.05))) }
            .opacity(workspace.inputCollapsed ? 0 : 1).allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Results").font(.headline)
                Spacer(minLength: 0)
                Button(copying ? "Preparing…" : "Copy Results as JSON Array", action: copyAll)
                    .controlSize(.small).disabled(workspace.result == nil || copying)
                    .accessibilityIdentifier("path-copy-results")
            }
            JSONTreeTable(rows: workspace.rows, rowNumbers: workspace.rowNumbers, version: workspace.version,
                rowsVersion: workspace.version, changes: nil, animate: false, selection: workspace.selection,
                scrollRequest: workspace.scrollRequest, scrollTarget: workspace.scrollTarget,
                row: { id in AnyView(row(id)) }, select: { workspace.selection = $0 }, key: key,
                preferredRowHeight: 62, tableIdentifier: "json-path-results", suppressSoftwareKeyboard: true)
                .overlay {
                    if workspace.rows.isEmpty {
                        ContentUnavailableView {
                            Label(workspace.result == nil ? "Query JSON values" : "No matches", systemImage: "magnifyingglass")
                        } description: {
                            Text(workspace.result == nil ? "Run a JSONPath query to find values and inspect their source." : "The query completed successfully. Try a different path or filter.")
                        }.allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Button("Show Source") { showSelected() }.disabled(workspace.selectedNodeID == nil)
                    .accessibilityIdentifier("path-show-source")
                Menu("Actions") {
                    if let id = workspace.selectedNodeID, let document = workspace.document {
                        copyActions(id, document: document)
                        Divider()
                        Button("Selected Node Details") { details = true }
                    }
                }.disabled(workspace.selectedNodeID == nil)
                Spacer(minLength: 0)
                Text(confirmation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.controlSize(.small).frame(height: 30)
        }
    }
    @ViewBuilder private func row(_ occurrence: Int) -> some View {
        if let result = workspace.result, result.nodeIDs.indices.contains(occurrence),
           let presentation = workspace.presentations[result.nodeIDs[occurrence]], let document = workspace.document {
            JSONPathResultRow(occurrence: occurrence, data: presentation, selected: workspace.selection == occurrence,
                select: { workspace.selection = occurrence }, reveal: {
                    workspace.selection = occurrence; showSource(document.nodes[presentation.nodeID].range)
                })
                .contextMenu {
                    copyActions(presentation.nodeID, document: document)
                    Button("Show Source") { showSource(document.nodes[presentation.nodeID].range) }
                    Button("Selected Node Details") { workspace.selection = occurrence; details = true }
                }
        }
    }
    @ViewBuilder private func copyActions(_ id: Int, document: JSONStructureDocument) -> some View {
        let node = document.nodes[id]
        Button("Copy Value") { if let value = node.scalar { copy(value) } }.disabled(node.scalar == nil)
        Button("Copy JSON Fragment") { copy(document.fragment(id)) }
        Button("Copy JSONPath") { copy(document.path(id).jsonPath) }
        Button("Copy JSON Pointer") { copy(document.path(id).pointer, root: id == 0) }
    }
    private func showSelected() {
        if let id = workspace.selectedNodeID, let document = workspace.document { showSource(document.nodes[id].range) }
    }
    private func showSource(_ range: NSRange) {
        let request = UUID(), source = workspace.input, collapsed = workspace.inputCollapsed
        commands.cancelNavigation?()
        navigationRequest = request; details = false
        withAnimation(animation) { workspace.inputCollapsed = false }
        Task { @MainActor in
            if collapsed && !reduceMotion { try? await Task.sleep(for: .milliseconds(220)) } else { await Task.yield() }
            guard navigationRequest == request, !workspace.inputCollapsed, source.utf16.elementsEqual(workspace.input.utf16) else { return }
            jumpTarget = range.length <= 80 ? range : NSRange(location: range.location, length: 0); jumpRequest += 1
        }
    }
    private func key(_ key: JSONTreeTable.TreeKey) {
        switch key {
        case .up: workspace.moveSelection(-1)
        case .down: workspace.moveSelection(1)
        case .copy: if let id = workspace.selectedNodeID, let document = workspace.document { copy(document.fragment(id)) }
        default: break
        }
    }
    private func copyAll() {
        guard let result = workspace.result, let document = workspace.document else { return }
        copyTask?.cancel(); copying = true; confirmation = ""
        let version = workspace.version
        copyTask = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) { try JSONPathOperations.copyArray(result, document: document) }
            do {
                let text = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, workspace.version == version else { return }
                copying = false; copy(text)
            } catch {
                guard !Task.isCancelled, workspace.version == version else { return }
                copying = false; confirmation = (error as? JSONPathFailure)?.message ?? "Copy cancelled"
            }
        }
    }
    private func copy(_ text: String, root: Bool = false) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        confirmation = root ? "Root pointer copied (empty string)" : "Copied"
    }
    private var syntaxHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JSONPath · RFC 9535").font(.headline)
            ForEach([("$", "Root value"), ("$.users[*].name", "Names of every user"),
                     ("$..price", "Prices at any depth"), ("$.users[0:10]", "First ten users"),
                     ("$.users[?@.active == true]", "Users with active set to true")], id: \.0) { query, description in
                VStack(alignment: .leading, spacing: 2) {
                    Text(query).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Functions: length, count, value, match, search. Names and strings use exact Unicode scalars. Numbers compare by value; original numeric text is preserved. Duplicate member names block execution.")
                .font(.caption)
            Text("Queries run only when requested. All data stays in memory. Expensive queries stop with a resource status; no partial results are published.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Done") { help = false }
        }.padding().frame(idealWidth: 360).presentationCompactAdaptation(.sheet)
    }
}

private struct JSONPathResultRow: View {
    let occurrence: Int
    let data: JSONPathRowData
    let selected: Bool
    let select: () -> Void
    let reveal: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Group {
            #if os(macOS)
            content.onTapGesture(count: 2, perform: reveal).onTapGesture(perform: select)
            #else
            Button(action: select) { content }.buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded(reveal))
            #endif
        }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Result \(occurrence + 1). \(data.path). \(data.kind.rawValue). \(data.preview)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityActions { Button("Show Source", action: reveal) }
            .accessibilityIdentifier("path-result-\(occurrence)")
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                Text(data.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                Text(data.preview.isEmpty ? "\"\"" : data.preview).font(.system(.callout, design: .monospaced))
                    .foregroundStyle(color).lineLimit(1)
            }
        }.padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(selected ? Color.green.opacity(scheme == .dark ? 0.22 : 0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
    }
    private var color: Color {
        if contrast == .increased { return .primary }
        switch data.kind {
        case .string: return scheme == .dark ? Color(red: 0.6, green: 0.84, blue: 0.65) : Color(red: 0.17, green: 0.43, blue: 0.25)
        case .number: return scheme == .dark ? .orange : .brown
        case .boolean, .null: return .purple
        default: return .primary
        }
    }
}

/// Identity-stable panels: collapsing/resizing never removes the native editor.
private struct JSONPathPanelLayout: Layout {
    let horizontal: Bool
    var fraction: Double
    var collapse: Double
    init(horizontal: Bool, fraction: Double, collapsed: Bool) {
        self.horizontal = horizontal; self.fraction = fraction; collapse = collapsed ? 1 : 0
    }
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fraction, collapse) }
        set { fraction = newValue.first; collapse = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions(by: CGSize(width: 600, height: 500)) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let length = horizontal ? bounds.width : bounds.height
        let divider: CGFloat = 12 * (1 - collapse)
        let input = max(0, length - divider) * fraction * (1 - collapse)
        let ranges = [(CGFloat.zero, input), (input, divider), (input + divider, max(0, length - input - divider))]
        for (index, range) in ranges.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + (horizontal ? range.0 : 0), y: bounds.minY + (horizontal ? 0 : range.0)), anchor: .topLeading,
                proposal: ProposedViewSize(width: horizontal ? range.1 : bounds.width, height: horizontal ? bounds.height : range.1))
        }
    }
}
