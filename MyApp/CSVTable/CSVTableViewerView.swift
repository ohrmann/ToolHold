import SwiftUI

struct CSVTableViewerView: View {
    @Bindable var workspace: CSVTableWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var jumpTask: Task<Void, Never>?
    @State private var jumpSelection: CSVTableSelection?
    @State private var dragStart: Double?
    @State private var details = false
    @State private var showGo = false
    @State private var rowNumber = "1"
    @State private var columnNumber = "1"
    @State private var goError = ""
    @State private var copyMessage = ""
    @FocusState private var searchFocused: Bool
    private var reduced: Bool { systemReduced || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var diagnostic: JSONDiagnostic? { workspace.result?.status == .resourceLimit ? nil : workspace.result?.diagnostics.first }
    private var editorOptions: JSONEditorOptions { .init(syntax: workspace.format == .csv ? .csv : .tsv, syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: workspace.preferences.wordWrap) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { profile; Spacer(); actions }
                    VStack(alignment: .leading, spacing: 8) { profile; HStack { actions; Spacer() } }
                }
                status
                CSVTablePanelLayout(horizontal: wide, fraction: workspace.fraction, collapsed: workspace.inputCollapsed) {
                    inputPanel
                    divider(wide: wide, length: wide ? geometry.size.width : geometry.size.height)
                    tablePanel
                }
                .animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.inputCollapsed)
            }
            .padding()
            .animation(reduced ? nil : .easeInOut(duration: 0.2), value: diagnostic?.code)
        }
        .navigationTitle("CSV / TSV Table Viewer")
        .onAppear { workspace.refreshPreferences() }
        .onChange(of: workspace.input) { _, _ in cancelJump(); copyMessage = ""; details = false }
        .onChange(of: workspace.format) { _, _ in cancelJump(); details = false }
        .onChange(of: workspace.selection) { _, selection in if jumpSelection != selection { cancelJump() } }
        .onChange(of: workspace.hasHeader) { _, _ in cancelJump(); details = false }
        .onDisappear { cancelJump() }
        .sheet(isPresented: $details) { cellDetails }
        .background { Button("Find in table") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden() }
    }
    private var profile: some View {
        HStack(spacing: 12) {
            Picker("Table format", selection: $workspace.format) {
                ForEach(DelimitedFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 125).accessibilityIdentifier("table-format")
            Toggle("Header row", isOn: $workspace.hasHeader).fixedSize().accessibilityIdentifier("table-header")
        }
    }
    private var actions: some View {
        HStack {
            Button("Build Table") { workspace.build() }.keyboardShortcut(.return, modifiers: .command)
                .disabled(workspace.busy).accessibilityIdentifier("table-build")
            Button(workspace.inputCollapsed ? "Edit Input" : "Hide Input") { commands.resignFocus?(); workspace.inputCollapsed.toggle() }
                .accessibilityIdentifier("table-toggle-input")
            Menu {
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
                Picker("Column width", selection: $workspace.columnWidth) {
                    Text("Compact").tag(110.0); Text("Normal").tag(180.0); Text("Wide").tag(280.0)
                }
            } label: { Label("Table Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
            .accessibilityLabel("Table Options")
        }
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input · \(workspace.format.rawValue)").font(.headline)
                Spacer()
                Button("Clear Input", systemImage: "trash") { commands.clear?(); workspace.clear() }
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("table-clear")
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: diagnostic, jumpTarget: jumpTarget,
                jumpRequest: jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                onPaste: { workspace.didPaste() }, commands: commands, options: editorOptions,
                placeholder: "Paste or type \(workspace.format.rawValue). Your data stays on this device.")
                // A collapsed panel must not give TextKit a zero-width container.
                .frame(minWidth: 240, minHeight: 100)
                .accessibilityIdentifier("table-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipped().opacity(workspace.inputCollapsed ? 0 : 1)
            .allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
    }
    private var tablePanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter rows…", text: $workspace.query).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityIdentifier("table-search").disabled(workspace.document == nil)
                if !workspace.query.isEmpty { Button { workspace.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear filter") }
                Text(workspace.filtering ? "Filtering…" : rowCountCaption)
                    .font(.caption).foregroundStyle(.secondary).fixedSize().accessibilityIdentifier("table-row-count")
            }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            ViewThatFits(in: .horizontal) {
                HStack { tableControls; Spacer(); selectionActions }
                VStack(alignment: .leading, spacing: 6) { tableControls; selectionActions }
            }
            CSVTableGrid(document: workspace.document, projection: workspace.projection, selection: workspace.selection,
                columnWidth: workspace.columnWidth, scrollRequest: workspace.scrollRequest, reduced: reduced,
                onSelect: { workspace.selection = $0; copyMessage = "" },
                onActivate: { selection in if let cell = workspace.document?.cell(selection) { show(cell.range) } },
                onSort: { workspace.toggleSort($0) }, onKey: handleKey)
                .accessibilityIdentifier("table-grid")
                .help("Drag the table to pan. Double-click a cell to show its source.")
                .overlay {
                    if workspace.document == nil {
                        ContentUnavailableView(workspace.result?.status == .invalid ? "Check Input" : "Your table appears here", systemImage: "tablecells", description: Text("Choose CSV or TSV, then paste data or select Build Table."))
                            .allowsHitTesting(false)
                    } else if workspace.projection?.rows.isEmpty == true {
                        ContentUnavailableView(workspace.query.isEmpty ? "No data records" : "No matching rows", systemImage: "tablecells", description: Text(workspace.query.isEmpty ? "This document contains only a header or is empty." : "Clear or change the row filter."))
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            Text(selectionCaption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading).accessibilityIdentifier("table-selection")
        }
    }
    private var rowCountCaption: String {
        if let projection = workspace.projection, projection.query != workspace.query || projection.sort != workspace.sort { return "Previous rows" }
        let count = workspace.projection?.rows.count ?? 0
        return "\(count) \(count == 1 ? "row" : "rows")"
    }
    private var tableControls: some View {
        HStack {
            Text("Table").font(.headline)
            Button("Go to Cell") { goError = ""; showGo = true }.disabled(workspace.document == nil)
                .accessibilityIdentifier("table-go").popover(isPresented: $showGo) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Source data row and column (1-based)").font(.headline)
                        TextField("Data row", text: $rowNumber).accessibilityIdentifier("table-go-row")
                        TextField("Column", text: $columnNumber).accessibilityIdentifier("table-go-column")
                        Text(goError).font(.caption).foregroundStyle(.secondary)
                        Button("Go") {
                            if let row = Int(rowNumber), let column = Int(columnNumber), workspace.go(row: row - 1, column: column - 1) { showGo = false }
                            else { goError = "Cell not present or hidden by the filter." }
                        }.accessibilityIdentifier("table-go-confirm")
                    }.textFieldStyle(.roundedBorder).padding().frame(minWidth: 260)
                }
            Button("Reset Sort") { workspace.sort = nil }.disabled(workspace.sort == nil)
                .help("Column headers cycle through ascending text, descending text and source order.")
        }.controlSize(.small)
    }
    private var selectionActions: some View {
        HStack {
            Button("Details") { details = true }.accessibilityIdentifier("table-details")
            Menu("Copy") {
                Button("Copy Cell") { copy(record: false) }
                Button("Copy Record") { copy(record: true) }
            }.accessibilityIdentifier("table-copy")
            Button("Show Source") {
                if let selection = workspace.selection, let cell = workspace.document?.cell(selection) { show(cell.range) }
            }.accessibilityIdentifier("table-show-source")
        }.controlSize(.small).disabled(workspace.selection == nil)
    }
    private var selectionCaption: String {
        if !copyMessage.isEmpty { return copyMessage }
        guard let selection = workspace.selection, let document = workspace.document else { return "Select a cell · headers sort as text · ∅ empty · — missing" }
        return "Data row \(selection.row + 1) · column \(selection.column + 1) · \(document.header(selection.column)) · \(document.record(selection.row).cells.count) fields"
    }
    private var title: String {
        if workspace.busy { return "Processing" }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .success: return result.diagnostics.isEmpty ? "Loaded · \(workspace.document?.rowCount ?? 0) rows · \(workspace.document?.columnCount ?? 0) columns" : "Loaded with warnings"
        case .invalid: return "Invalid \(workspace.format.rawValue)"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        case .unsupported: return "Cannot display table"
        }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: diagnostic?.severity == .warning ? "exclamationmark.triangle" : "tablecells").font(.callout.weight(.medium)).accessibilityIdentifier("table-status")
                Spacer()
                HStack { ProgressView().controlSize(.mini); Button("Cancel") { workspace.cancel() }.controlSize(.small) }
                    .opacity(workspace.busy || workspace.filtering ? 1 : 0).disabled(!workspace.busy && !workspace.filtering).accessibilityHidden(!workspace.busy && !workspace.filtering)
            }.frame(minHeight: 26)
            if let issue = workspace.result?.diagnostics.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if workspace.result?.status != .resourceLimit {
                        Text("Source line \(issue.line), column \(issue.column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
                        if let context = workspace.context { Text(snippet(context)).font(.system(.caption, design: .monospaced)).lineLimit(3) }
                        HStack {
                            Button("Show Detection") { show(issue.range) }.accessibilityIdentifier("table-show-detection")
                            if !issue.related.isEmpty { Menu("Show Related") { ForEach(Array(issue.related.enumerated()), id: \.offset) { _, related in Button(related.role.rawValue) { show(related.range) } } } }
                        }.controlSize(.small)
                    }
                }.transition(.opacity)
            }
        }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func snippet(_ context: JSONDiagnosticContext) -> AttributedString {
        var text = AttributedString(context.text)
        if let original = Range(context.detectionRange, in: context.text), let range = Range(original, in: text) { text[range].underlineStyle = .single; text[range].foregroundColor = diagnostic?.severity == .warning ? .orange : .red }
        return text
    }
    private var cellDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Cell Details").font(.headline); Spacer(); Button("Done") { details = false } }
            Text(selectionCaption).font(.caption).foregroundStyle(.secondary)
            if let selection = workspace.selection, let document = workspace.document, let cell = document.cell(selection) {
                Text(cell.value.isEmpty ? "Empty value · \(cell.quoted ? "quoted" : "unquoted")" : "Decoded text · \(cell.value.utf16.count) UTF-16 code units").font(.caption)
                JSONTextEditor(text: .constant(cell.value), editable: false, options: editorOptions)
                    .accessibilityIdentifier("table-cell-value")
                HStack { Button("Copy Cell") { copy(record: false) }; Button("Copy Record") { copy(record: true) }; Button("Show Source") { details = false; show(cell.range) } }
            }
        }.padding().frame(minWidth: 280, idealWidth: 600, minHeight: 300, idealHeight: 450)
    }
    private func handleKey(_ key: String) {
        switch key {
        case "up": workspace.move(row: -1, column: 0)
        case "down": workspace.move(row: 1, column: 0)
        case "left": workspace.move(row: 0, column: -1)
        case "right": workspace.move(row: 0, column: 1)
        case "copy": copy(record: false)
        default: break
        }
    }
    private func copy(record: Bool) {
        guard let selection = workspace.selection, let document = workspace.document, let cell = document.cell(selection) else { return }
        let text = record ? document.fragment(selection.row) : cell.value
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copyMessage = record ? "Record copied · exact source text" : "Cell copied · decoded text"
    }
    private func cancelJump() { jumpTask?.cancel(); commands.cancelNavigation?(); jumpSelection = nil; jumpTarget = nil; jumpRequest += 1 }
    private func show(_ range: NSRange) {
        cancelJump()
        jumpSelection = workspace.selection
        let wait = workspace.inputCollapsed
        workspace.inputCollapsed = false
        let source = workspace.input
        jumpTask = Task { @MainActor in
            if wait { try? await Task.sleep(for: .milliseconds(reduced ? 30 : 240)) }
            guard !Task.isCancelled, workspace.input.utf16.elementsEqual(source.utf16) else { return }
            jumpTarget = range; jumpRequest += 1
        }
    }
    private func divider(wide: Bool, length: CGFloat) -> some View {
        ZStack { Color.clear; Capsule().fill(.secondary.opacity(0.5)).frame(width: wide ? 3 : 36, height: wide ? 36 : 3) }
            .contentShape(Rectangle()).clipped().allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                if dragStart == nil { dragStart = workspace.fraction }
                workspace.fraction = min(0.75, max(0.25, (dragStart ?? 0.42) + (wide ? value.translation.width : value.translation.height) / max(1, length)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityElement().accessibilityLabel("Input panel size")
            .accessibilityAdjustableAction { value in workspace.fraction = min(0.75, max(0.25, workspace.fraction + (value == .increment ? 0.05 : -0.05))) }
    }
}

private struct CSVTablePanelLayout: Layout {
    let horizontal: Bool
    var fraction: Double
    var collapseProgress: Double
    init(horizontal: Bool, fraction: Double, collapsed: Bool) { self.horizontal = horizontal; self.fraction = fraction; collapseProgress = collapsed ? 1 : 0 }
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(fraction, collapseProgress) }
        set { fraction = newValue.first; collapseProgress = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions(by: .init(width: 600, height: 500)) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let length = horizontal ? bounds.width : bounds.height
        let divider: CGFloat = 12 * (1 - collapseProgress)
        let input = max(0, length - divider) * fraction * (1 - collapseProgress)
        for (index, pair) in [(0, (CGFloat.zero, input)), (1, (input, divider)), (2, (input + divider, max(0, length - input - divider)))] {
            let origin = CGPoint(x: bounds.minX + (horizontal ? pair.0 : 0), y: bounds.minY + (horizontal ? 0 : pair.0))
            subviews[index].place(at: origin, anchor: .topLeading, proposal: .init(width: horizontal ? pair.1 : bounds.width, height: horizontal ? bounds.height : pair.1))
        }
    }
}
