import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct JSONSchemaValidatorView: View {
    @Bindable var workspace: JSONSchemaWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var jsonCommands = JSONEditorCommands()
    @State private var schemaCommands = JSONEditorCommands()
    @State private var referencedCommands = JSONEditorCommands()
    @State private var referencedTarget: NSRange?
    @State private var referencedJump = 0
    @State private var jsonTarget: NSRange?
    @State private var schemaTarget: NSRange?
    @State private var jsonJump = 0
    @State private var schemaJump = 0
    @State private var navigationID = UUID()
    @State private var navigationSelection: Int?
    @State private var details = false
    @State private var resourcesVisible = false
    @State private var importing = false
    @State private var replacing: UUID?
    @State private var confirmation = ""
    @State private var dragging: Double?
    @State private var splitDragging: Double?
    private var reduced: Bool {
        systemReduceMotion || (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") && ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
    }
    private var animation: Animation? { reduced ? nil : .easeInOut(duration: 0.2) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            VStack(spacing: 7) {
                controls
                Text(workspace.profile)
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                GeometryReader { area in
                    SchemaWorkspaceLayout(fraction: workspace.inputFraction,
                        minimum: workspace.instanceCollapsed && workspace.schemaCollapsed ? (wide ? 36 : 80) : (wide ? 150 : 220),
                        collapsed: workspace.instanceCollapsed && workspace.schemaCollapsed) {
                        SchemaInputsLayout(horizontal: wide, fraction: workspace.splitFraction,
                            firstCollapsed: workspace.instanceCollapsed, secondCollapsed: workspace.schemaCollapsed) {
                            input(schemaSide: false)
                            input(schemaSide: true)
                            splitDivider(horizontal: wide, length: wide ? area.size.width : area.size.height)
                        }
                        divider(height: area.size.height)
                        results(wide: wide)
                    }
                }
            }.padding(12)
                .animation(animation, value: workspace.instanceCollapsed)
                .animation(animation, value: workspace.schemaCollapsed)
                .animation(animation, value: workspace.instance.result?.diagnostics.isEmpty == false)
                .animation(animation, value: workspace.displayedSchema.result?.diagnostics.isEmpty == false)
        }
        .navigationTitle("JSON Schema Validator")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { cancelNavigation(); workspace.cancel() }
        .onChange(of: workspace.version) { _, _ in cancelNavigation(); details = false; confirmation = "" }
        .onChange(of: workspace.selection) { _, selected in
            if navigationSelection != nil && selected != navigationSelection { cancelNavigation() }
        }
        .sheet(isPresented: $details) { selectedDetails }
        .sheet(isPresented: $resourcesVisible) { referencedSchemas }
        #if os(macOS)
        .onExitCommand { if workspace.busy { workspace.cancel() } }
        #else
        .onKeyPress(.escape) {
            guard workspace.busy else { return .ignored }
            workspace.cancel(); return .handled
        }
        #endif
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button("Validate", systemImage: "checkmark.circle") { workspace.validate() }
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("schema-validate")
                .disabled(workspace.busy || workspace.instance.source.isEmpty || workspace.schema.source.isEmpty)
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Button("Cancel") { workspace.cancel() }.accessibilityIdentifier("schema-cancel")
            }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy)
                .accessibilityHidden(!workspace.busy)
            Spacer(minLength: 0)
            Menu {
                Toggle("Validate formats", isOn: $workspace.validateFormats)
                Picker("Default draft when $schema is absent", selection: $workspace.assumedDialect) {
                    Text("Draft 2020-12").tag(Dialect.draft2020_12)
                    Text("Draft-07").tag(Dialect.draft7)
                    Text("Draft 2019-09").tag(Dialect.draft2019_09)
                }
                Text("Declared $schema takes precedence.")
            } label: { Label("Validation Options", systemImage: "checkmark.shield").labelStyle(.iconOnly) }
                .accessibilityIdentifier("schema-validation-options")
            Button { resourcesVisible = true } label: { Label("Referenced Schemas", systemImage: "doc.on.doc").labelStyle(.iconOnly) }
                .accessibilityLabel("Referenced Schemas").accessibilityIdentifier("schema-references")
            Menu {
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Divider()
                Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
                Toggle("Rainbow Brackets", isOn: $workspace.preferences.rainbowBrackets)
                Toggle("Matching Brackets", isOn: $workspace.preferences.matchingBrackets)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
            } label: { Label("Editor Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
                .accessibilityLabel("Editor Options")
        }.controlSize(.small)
    }
    private func input(schemaSide: Bool) -> some View {
        let source = schemaSide ? workspace.displayedSchema : workspace.instance
        let commands = schemaSide ? (workspace.activeResource == nil ? schemaCommands : referencedCommands) : jsonCommands
        let collapsed = schemaSide ? workspace.schemaCollapsed : workspace.instanceCollapsed
        let title = schemaSide ? workspace.displayedSchemaName : "JSON"
        let diagnostic = source.result?.diagnostics.first { $0.severity == .error } ?? source.result?.diagnostics.first
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(JSONTreePreview.make(title, budget: 100).text).font(.headline).lineLimit(1)
                if schemaSide && workspace.activeResource != nil {
                    Button("Main Schema") { cancelNavigation(); workspace.activeResource = nil }
                        .accessibilityIdentifier("schema-main-schema")
                }
                Spacer(minLength: 0)
                Button("Clear", systemImage: "xmark") {
                    if let clear = commands.clear { clear() } else { source.source = "" }
                }.disabled(source.source.isEmpty || (schemaSide && workspace.activeResource != nil)).labelStyle(.iconOnly).accessibilityLabel("Clear \(title)")
                Button(collapsed ? "Edit \(title)" : "Hide \(title)", systemImage: collapsed ? "chevron.down" : "chevron.up") {
                    cancelNavigation()
                    if !collapsed { commands.resignFocus?() }
                    withAnimation(animation) {
                        if schemaSide { workspace.schemaCollapsed.toggle() } else { workspace.instanceCollapsed.toggle() }
                    }
                }.accessibilityIdentifier(schemaSide ? "schema-toggle-schema" : "schema-toggle-json")
            }.controlSize(.small).frame(height: 30)
            if diagnostic != nil && !collapsed {
                JSONDiagnosticsPanel(input: source.source, result: source.result, context: source.context,
                    busy: source.busy, wasCancelled: source.wasCancelled, compact: true,
                    cancel: { source.cancel() }, show: { show(schemaSide: schemaSide, range: $0) })
                    .transition(.opacity)
            }
            ZStack {
                // The primary editor remains mounted with its own Undo/caret even when
                // a referenced document is shown. Imported previews are read-only.
                nativeEditor(source: schemaSide ? workspace.schema : workspace.instance, schemaSide: schemaSide,
                    commands: commands, diagnostic: schemaSide ? workspace.schema.result?.diagnostics.first : diagnostic,
                    editable: true, collapsed: collapsed)
                    .opacity(schemaSide && workspace.activeResource != nil ? 0 : 1)
                    .allowsHitTesting(!schemaSide || workspace.activeResource == nil)
                    .accessibilityHidden(schemaSide && workspace.activeResource != nil)
                if schemaSide, workspace.activeResource != nil {
                    nativeEditor(source: source, schemaSide: true, commands: referencedCommands, diagnostic: diagnostic, editable: false, collapsed: collapsed)
                        .id(workspace.activeResource)
                }
            }
        }.clipped()
    }
    private func nativeEditor(source: JSONDiffInput, schemaSide: Bool, commands: JSONEditorCommands?, diagnostic: JSONDiagnostic?, editable: Bool, collapsed: Bool) -> some View {
        JSONTextEditor(text: Binding(get: { source.source }, set: { if editable { source.source = $0 } }),
            editable: editable, diagnostic: diagnostic, jumpTarget: schemaSide ? (editable ? schemaTarget : referencedTarget) : jsonTarget,
            jumpRequest: schemaSide ? (editable ? schemaJump : referencedJump) : jsonJump,
            animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
            onPaste: { workspace.didPaste(schema: schemaSide) }, commands: commands,
            options: JSONEditorOptions(syntaxHighlighting: workspace.preferences.syntaxHighlighting,
                rainbowBrackets: workspace.preferences.rainbowBrackets, matchingBrackets: workspace.preferences.matchingBrackets,
                wordWrap: workspace.preferences.wordWrap),
            placeholder: schemaSide ? "Paste or type a JSON Schema." : "Paste or type JSON to validate.")
            .accessibilityLabel(schemaSide ? "JSON Schema input" : "JSON instance input")
            .accessibilityIdentifier(schemaSide ? (editable ? "schema-schema-input" : "schema-referenced-input") : "schema-json-input")
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .opacity(collapsed ? 0 : 1).allowsHitTesting(!collapsed).accessibilityHidden(collapsed).clipped()
    }
    private var referencedSchemas: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Only explicitly added schemas are available. Contents stay in memory until the app closes.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Files are registered beside the main schema by filename; an explicit $id supplies their canonical identifier. Imported source is read-only; use Replace to update it.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = workspace.importMessage { Text(message).foregroundStyle(.secondary).font(.callout) }
                List(workspace.referenced) { resource in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(JSONTreePreview.make(resource.name, budget: 100).text).font(.headline).lineLimit(1)
                        Text(workspace.retrievalURI(for: resource).absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let document = resource.input.document,
                           let key = document.nodes[0].children.first(where: { document.nodes[$0].key == "$id" }), let id = document.nodes[key].scalar {
                            Text("$id: " + JSONTreePreview.make(id, budget: 180).text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(resource.input.document == nil ? resource.input.result?.status == .invalid ? "Invalid JSON syntax" : "Not checked / resource limit" : "Loaded · Validate to check schema")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Show") { cancelNavigation(); workspace.activeResource = resource.id; workspace.schemaCollapsed = false; resourcesVisible = false }
                            Button("Replace") { replacing = resource.id; importing = true }
                            Button("Remove", role: .destructive) { workspace.removeResource(resource.id) }
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                if workspace.importing { HStack { ProgressView("Reading schemas…"); Button("Cancel") { workspace.cancelImport() } } }
                Button("Add Schemas", systemImage: "plus") { replacing = nil; importing = true }
                    .disabled(workspace.importing).accessibilityIdentifier("schema-add-references")
            }.padding().navigationTitle("Referenced Schemas")
                .toolbar { Button("Done") { resourcesVisible = false } }
                .frame(minWidth: 300, idealWidth: 560, minHeight: 320, idealHeight: 450)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: replacing == nil) { result in
            switch result {
            case .success(let urls):
                let replacement = replacing
                Task { await workspace.importResources(urls, replacing: replacement).value }
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { workspace.importFailed() }
            }
            replacing = nil
        }
    }
    private func splitDivider(horizontal: Bool, length: CGFloat) -> some View {
        Rectangle().fill(.quaternary).frame(width: horizontal ? 3 : nil, height: horizontal ? nil : 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                if splitDragging == nil { splitDragging = workspace.splitFraction }
                let distance = horizontal ? value.translation.width : value.translation.height
                workspace.splitFraction = min(0.75, max(0.25, (splitDragging ?? 0.5) + distance / max(1, length)))
            }.onEnded { _ in splitDragging = nil })
            .accessibilityLabel("JSON and Schema panel balance")
            .accessibilityAdjustableAction { direction in
                workspace.splitFraction = min(0.75, max(0.25, workspace.splitFraction + (direction == .increment ? 0.05 : -0.05)))
            }
    }
    private func divider(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                if dragging == nil { dragging = workspace.inputFraction }
                workspace.inputFraction = min(0.8, max(0.3, (dragging ?? 0.62) + value.translation.height / max(1, height)))
            }.onEnded { _ in dragging = nil })
            .accessibilityLabel("Input area height")
            .accessibilityAdjustableAction { direction in
                workspace.inputFraction = min(0.8, max(0.3, workspace.inputFraction + (direction == .increment ? 0.05 : -0.05)))
            }
    }
    private func results(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(workspace.status, systemImage: workspace.report?.status == .valid ? "checkmark.circle" : workspace.report == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium)).lineLimit(2).accessibilityIdentifier("schema-status")
                Spacer(minLength: 0)
                Button { workspace.move(-1) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Previous issue")
                Button { workspace.move(1) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Next issue")
                Button("Copy Report") { if let report = workspace.report { copy(report.copyText) } }
                    .disabled(workspace.report == nil).accessibilityIdentifier("schema-copy-report")
            }.controlSize(.small)
            JSONTreeTable(rows: workspace.rows, rowNumbers: workspace.rowNumbers, version: workspace.version,
                rowsVersion: workspace.version, changes: nil, animate: false,
                selection: workspace.selection, scrollRequest: workspace.scrollRequest, scrollTarget: workspace.selection,
                row: { id in AnyView(issueRow(id)) }, select: { workspace.selection = $0 }, key: key,
                preferredRowHeight: wide ? 70 : 86, tableIdentifier: "schema-issues", suppressSoftwareKeyboard: true)
                .overlay {
                    if workspace.rows.isEmpty {
                        VStack(spacing: 5) {
                            Text(workspace.report?.status == .valid ? "JSON matches the schema" : workspace.report?.notes.first ?? "Enter JSON and a Schema, then Validate.")
                                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            if workspace.report == nil { Text("Both documents stay on this device.").font(.caption).foregroundStyle(.secondary) }
                        }.padding(8).allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            if let notes = workspace.report?.notes, !notes.isEmpty, !workspace.rows.isEmpty || workspace.report?.status == .valid {
                Text(notes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(contextText(workspace.jsonContext)).font(.system(.caption, design: .monospaced)).lineLimit(1)
                .frame(height: workspace.selectedIssue?.instanceNode == nil ? 0 : 20).clipped()
                .accessibilityIdentifier("schema-source-context")
                .accessibilityHidden(workspace.selectedIssue?.instanceNode == nil)
            ViewThatFits(in: .horizontal) {
                HStack { actions; Spacer(minLength: 0); Text(confirmation).font(.caption).foregroundStyle(.secondary) }
                HStack { actions; Spacer(minLength: 0) }
            }.controlSize(.small)
        }
    }
    @ViewBuilder private func issueRow(_ id: Int) -> some View {
        if let issues = workspace.report?.issues, issues.indices.contains(id) {
            let issue = issues[id]
            let content = VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(JSONTreePreview.make(issue.instanceNode == nil && issue.schemaNode != nil ? "Schema " + (issue.schemaPointer.isEmpty ? "root" : issue.schemaPointer) : issue.instancePointer.isEmpty ? "root" : issue.instancePointer, budget: 90).text)
                        .font(.system(.caption, design: .monospaced)).lineLimit(1)
                    Spacer(minLength: 3)
                    Text(issue.keyword).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(issue.message).font(.callout).lineLimit(2)
            }.padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(workspace.selection == id ? Color.green.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .accessibilityIdentifier("schema-issue-\(id)")
            #if os(macOS)
            content.onTapGesture(count: 2) { workspace.selection = id; showBoth(issue) }
                .onTapGesture { workspace.selection = id }
                .contextMenu { issueActions(issue) }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Show JSON and Schema") { showBoth(issue) }
            #else
            Button { workspace.selection = id } label: { content }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded { workspace.selection = id; showBoth(issue) })
                .contextMenu { issueActions(issue) }
                .accessibilityAction(named: "Show JSON and Schema") { showBoth(issue) }
            #endif
        }
    }
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { detailControls; sourceButtons }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { detailControls }
                sourceButtons
            }
        }
    }
    @ViewBuilder private var detailControls: some View {
        Button("Details") { details = true }.disabled(workspace.report == nil)
            .accessibilityIdentifier("schema-details")
        Menu("Actions") { if let issue = workspace.selectedIssue { issueActions(issue) } }
            .disabled(workspace.selectedIssue == nil)
    }
    private var sourceButtons: some View {
        HStack(spacing: 8) {
            Button("Show JSON") { if let issue = workspace.selectedIssue, let range = workspace.sourceRange(issue, schemaSide: false) { show(schemaSide: false, range: range) } }
                .disabled(workspace.selectedIssue.flatMap { workspace.sourceRange($0, schemaSide: false) } == nil)
                .accessibilityIdentifier("schema-show-json")
            Button("Show Schema") { if let issue = workspace.selectedIssue, let range = workspace.sourceRange(issue, schemaSide: true) { workspace.revealSchema(for: issue); show(schemaSide: true, range: range) } }
                .disabled(workspace.selectedIssue.flatMap { workspace.sourceRange($0, schemaSide: true) } == nil)
                .accessibilityIdentifier("schema-show-schema")
        }
    }
    @ViewBuilder private func issueActions(_ issue: JSONSchemaIssue) -> some View {
        Button("Show Both") { showBoth(issue) }
        Button("Copy JSON Pointer") { copy(issue.instancePointer) }
        Button("Copy Schema Pointer") { copy(issue.schemaPointer) }
        Button("Copy Message") { copy(issue.message) }
    }
    private var selectedDetails: some View {
        NavigationStack {
            ScrollView {
                if let selected = workspace.selectedIssue, let issues = workspace.report?.issues {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text(selected.message).font(.headline)
                        if selected.instancePrecision == .containingValue {
                            Text("The constraint applies to this value or container; no exact offending character is implied.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("JSON: " + JSONTreePreview.make(selected.instancePointer.isEmpty ? "root" : selected.instancePointer, budget: 300).text)
                        Text(selected.schemaDocumentName + ": " + JSONTreePreview.make(selected.schemaPointer.isEmpty ? "root" : selected.schemaPointer, budget: 300).text)
                        if let resource = selected.schemaResource { Text("Rule resource: " + JSONTreePreview.make(resource, budget: 200).text) }
                        if let context = workspace.jsonContext {
                            Text("JSON context").font(.caption.weight(.semibold))
                            Text(contextText(context)).font(.system(.body, design: .monospaced))
                        }
                        if let context = workspace.schemaContext {
                            Text("Schema context").font(.caption.weight(.semibold))
                            Text(contextText(context)).font(.system(.body, design: .monospaced))
                        }
                        Button("Show Both") { details = false; showBoth(selected) }
                        ForEach(branch(issues, selected: selected)) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.keyword).font(.caption.weight(.semibold))
                                Text(issue.message).font(.callout)
                                HStack {
                                    Button("Show JSON") { if let range = workspace.sourceRange(issue, schemaSide: false) { details = false; show(schemaSide: false, range: range) } }
                                    Button("Show Schema") { if let range = workspace.sourceRange(issue, schemaSide: true) { details = false; workspace.revealSchema(for: issue); show(schemaSide: true, range: range) } }
                                }.controlSize(.small)
                            }.padding(.leading, CGFloat(min(4, issue.depth)) * 8)
                        }
                        if workspace.report?.truncated == true { Text("Showing the first 1,000 diagnostic entries. The report was truncated.") }
                        ForEach(Array((workspace.report?.notes ?? []).enumerated()), id: \.offset) { _, note in Text(note).font(.caption).foregroundStyle(.secondary) }
                    }.padding().textSelection(.enabled)
                } else if let report = workspace.report {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(report.status.rawValue).font(.headline)
                        Text(workspace.profile)
                        ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in Text(note) }
                    }.padding().textSelection(.enabled)
                }
            }.navigationTitle("Validation Details")
                .toolbar { Button("Done") { details = false } }
                .frame(idealWidth: 600, idealHeight: 420)
        }
    }
    private func branch(_ issues: [JSONSchemaIssue], selected: JSONSchemaIssue) -> [JSONSchemaIssue] {
        Array(issues.dropFirst(selected.id + 1).prefix { $0.depth > selected.depth })
    }
    private func key(_ key: JSONTreeTable.TreeKey) {
        switch key {
        case .up: workspace.move(-1)
        case .down: workspace.move(1)
        case .copy: if let issue = workspace.selectedIssue { copy(issue.message) }
        default: break
        }
    }
    private func contextText(_ context: JSONDiagnosticContext?) -> AttributedString {
        guard let context else { return AttributedString(" ") }
        var text = AttributedString(context.text)
        if let range = Range(context.detectionRange, in: context.text), let converted = Range(range, in: text) {
            text[converted].underlineStyle = .single
            text[converted].font = .system(.caption, design: .monospaced).bold()
        }
        return text
    }
    private func copy(_ text: String) { 
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        confirmation = "Copied" }
    private func cancelNavigation() {
        navigationID = UUID(); navigationSelection = nil; jsonCommands.cancelNavigation?(); schemaCommands.cancelNavigation?(); referencedCommands.cancelNavigation?()
    }
    private func showBoth(_ issue: JSONSchemaIssue) {
        workspace.revealSchema(for: issue)
        show(json: workspace.sourceRange(issue, schemaSide: false), schema: workspace.sourceRange(issue, schemaSide: true))
    }
    private func show(schemaSide: Bool, range: NSRange) { show(json: schemaSide ? nil : range, schema: schemaSide ? range : nil) }
    private func show(json: NSRange?, schema: NSRange?) {
        cancelNavigation(); let request = navigationID; navigationSelection = workspace.selection
        withAnimation(animation) {
            if json != nil { workspace.instanceCollapsed = false }
            if schema != nil { workspace.schemaCollapsed = false }
        }
        Task { @MainActor in
            // Wait for editor geometry without stealing focus or recreating either editor.
            try? await Task.sleep(for: .milliseconds(reduced ? 1 : 220))
            guard request == navigationID else { return }
            if let json { jsonTarget = json; jsonJump += 1 }
            if let schema {
                if workspace.activeResource == nil { schemaTarget = schema; schemaJump += 1 }
                else { referencedTarget = schema; referencedJump += 1 }
            }
        }
    }
}

private struct SchemaInputsLayout: Layout {
    var horizontal: Bool
    var fraction: Double
    var first: Double
    var second: Double
    init(horizontal: Bool, fraction: Double, firstCollapsed: Bool, secondCollapsed: Bool) {
        self.horizontal = horizontal; self.fraction = fraction
        first = firstCollapsed ? 0 : 1; second = secondCollapsed ? 0 : 1
    }
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(first, second) }
        set { first = newValue.first; second = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gap: CGFloat = 8
        let total = max(0, (horizontal ? bounds.width : bounds.height) - gap)
        // Even a collapsed editor retains a usable header; its native view stays mounted.
        let minimum: CGFloat = horizontal ? 140 : 36
        let extra = max(0, total - 2 * minimum)
        let weight = first + second
        let firstSize = min(total, minimum + extra * (weight == 0 ? 0.5 : (first > 0 && second > 0 ? fraction : first / weight)))
        for (i, view) in subviews.prefix(2).enumerated() {
            let length = i == 0 ? firstSize : max(0, total - firstSize)
            let size = CGSize(width: horizontal ? length : bounds.width, height: horizontal ? bounds.height : length)
            view.place(at: CGPoint(x: bounds.minX + (horizontal && i == 1 ? firstSize + gap : 0),
                y: bounds.minY + (!horizontal && i == 1 ? firstSize + gap : 0)), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
        if subviews.count > 2 {
            subviews[2].place(at: CGPoint(x: bounds.minX + (horizontal ? firstSize : 0), y: bounds.minY + (horizontal ? 0 : firstSize)),
                anchor: .topLeading, proposal: .init(width: horizontal ? gap : bounds.width, height: horizontal ? bounds.height : gap))
        }
    }
}
private struct SchemaWorkspaceLayout: Layout {
    var fraction: Double
    var minimum: Double
    var collapse: Double
    init(fraction: Double, minimum: Double, collapsed: Bool) { self.fraction = fraction; self.minimum = minimum; collapse = collapsed ? 1 : 0 }
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(minimum, collapse) }
        set { minimum = newValue.first; collapse = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let openHeight = min(max(0, bounds.height - 108), max(minimum, bounds.height * fraction))
        let height = min(bounds.height, openHeight * (1 - collapse) + minimum * collapse)
        let gap: CGFloat = 12
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: height))
        subviews[1].place(at: .init(x: bounds.minX, y: bounds.minY + height), anchor: .topLeading, proposal: .init(width: bounds.width, height: gap))
        subviews[2].place(at: .init(x: bounds.minX, y: bounds.minY + height + gap), anchor: .topLeading,
            proposal: .init(width: bounds.width, height: max(0, bounds.height - height - gap)))
    }
}
