import SwiftUI

struct JSONCSVConverterView: View {
    @Bindable var workspace: JSONCSVWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var dragStart: Double?
    @State private var keyboardVisible = false
    @State private var showOutputWithKeyboard = false
    @State private var copied = false
    private var reduced: Bool { systemReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var diagnostic: JSONDiagnostic? { workspace.result?.status == .resourceLimit || workspace.result?.diagnostics.first?.code == "TABLE-OPTIONS" ? nil : workspace.result?.diagnostics.first }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && keyboardVisible
        #else
        false
        #endif
    }
    private func options(json: Bool) -> JSONEditorOptions {
        JSONEditorOptions(syntax: json ? .json : (workspace.options.format == .csv ? .csv : .tsv),
            syntaxHighlighting: workspace.preferences.syntaxHighlighting,
            rainbowBrackets: json && workspace.preferences.rainbowBrackets,
            matchingBrackets: json && workspace.preferences.matchingBrackets,
            wordWrap: workspace.preferences.wordWrap)
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            let collapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { direction; format; Spacer(); actions }
                    VStack(alignment: .leading, spacing: 8) { direction; HStack { format; Spacer(minLength: 4); actions } }
                }
                Text(workspace.options.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(workspace.options.summary).accessibilityIdentifier("csv-profile")
                status
                JSONPanelLayout(horizontal: wide, fraction: workspace.fraction, collapsed: collapsed) {
                    inputPanel
                    divider(wide: wide, length: wide ? geometry.size.width : geometry.size.height, collapsed: collapsed)
                    outputPanel(wide: wide, collapsed: collapsed)
                }
                .coordinateSpace(name: "csv-panels")
                .animation(reduced ? nil : .easeInOut(duration: 0.2), value: collapsed)
            }
            .animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.result?.status)
            .padding()
        }
        .navigationTitle("JSON ↔ CSV / TSV")
        .onAppear { workspace.refreshPreferences() }
        .onChange(of: workspace.input) { _, _ in cancelJump(); copied = false }
        .onChange(of: workspace.options) { _, _ in cancelJump(); copied = false }
        .onChange(of: workspace.output == nil) { _, empty in if empty { copied = false } }
        .onChange(of: workspace.direction) { _, _ in cancelJump(); copied = false }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false; showOutputWithKeyboard = false }
        #endif
    }
    private var direction: some View {
        Picker("Direction", selection: $workspace.direction) {
            Text("JSON → " + workspace.options.format.rawValue).tag(JSONCSVDirection.toDelimited)
            Text(workspace.options.format.rawValue + " → JSON").tag(JSONCSVDirection.toJSON)
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("csv-direction")
    }
    private var format: some View {
        Picker("Table format", selection: $workspace.options.format) {
            ForEach(DelimitedFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(width: 125)
            .accessibilityLabel("Table format").accessibilityIdentifier("csv-format")
    }
    private var actions: some View {
        HStack {
            Button("Convert") { workspace.run() }.keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("csv-convert")
            Button("Check") { workspace.run(convert: false) }.accessibilityIdentifier("csv-check")
            Menu {
                Menu("Row shape") {
                    Picker("Row shape", selection: $workspace.options.shape) {
                        ForEach(JSONCSVRowShape.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.inline)
                }
                Toggle("Header row", isOn: $workspace.options.hasHeader)
                Menu("Cell representation") {
                    Picker("Cell representation", selection: $workspace.options.cells) {
                        ForEach(JSONCSVCellMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.inline)
                }
                Menu("Empty text cells") {
                    Picker("Empty text cells", selection: $workspace.options.empty) {
                        ForEach(JSONCSVEmptyCell.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.inline)
                }.disabled(workspace.options.cells != .text || workspace.direction == .toDelimited)
                Toggle("Infer JSON scalars", isOn: $workspace.options.inferScalars).disabled(workspace.options.cells != .text || workspace.direction == .toDelimited)
                Toggle("Spreadsheet protection", isOn: $workspace.options.protectFormulas).disabled(workspace.direction == .toJSON)
                Menu("Output line endings") {
                    Picker("Output line endings", selection: $workspace.options.lineEnding) {
                        ForEach(DelimitedLineEnding.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.inline)
                }
                Divider()
                Menu("Indent") {
                    Picker("Indent", selection: $workspace.preferences.indentation) {
                        Text("2 spaces").tag(JSONIndentation.two); Text("4 spaces").tag(JSONIndentation.four)
                    }.pickerStyle(.inline)
                }
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
            } label: { Label("Conversion Settings", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
            .accessibilityLabel("Conversion Settings").accessibilityIdentifier("csv-settings")
        }.disabled(workspace.busy)
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input · \(workspace.inputName)").font(.headline)
                Spacer()
                Button("Clear Input", systemImage: "trash") { commands.clear?(); workspace.clear() }
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("csv-clear")
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: diagnostic, jumpTarget: jumpTarget,
                jumpRequest: jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                onPaste: { workspace.didPaste() }, commands: commands,
                options: options(json: workspace.direction == .toDelimited),
                placeholder: "Paste or type \(workspace.inputName). Processing stays on this device.")
                .accessibilityIdentifier("csv-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output · \(workspace.outputName)").font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy Output", systemImage: copied ? "checkmark" : "doc.on.doc") { copy() }
                    .disabled(workspace.output == nil).accessibilityIdentifier("csv-copy")
                if !wide {
                    Button {
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                    .accessibilityLabel(collapsed ? "Expand Output" : "Collapse Output")
                }
            }.frame(minHeight: 30)
            JSONTextEditor(text: .constant(workspace.output ?? ""), editable: false,
                options: options(json: workspace.direction == .toJSON), placeholder: workspace.output == "" ? "Empty table · 0 rows" : "Convert to create \(workspace.outputName) output.")
                .accessibilityIdentifier("csv-output")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .opacity(collapsed ? 0 : 1).accessibilityHidden(collapsed).allowsHitTesting(!collapsed)
        }.clipped()
    }
    private var title: String {
        if workspace.busy { return "Processing" }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .success: return result.diagnostics.isEmpty ? (workspace.output == nil ? "Ready to convert" : "Converted") : (workspace.output == nil ? "Ready with warnings" : "Converted with warnings")
        case .invalid: return "Invalid \(workspace.inputName)"
        case .unsupported: return "Cannot convert this construct"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: workspace.result?.status == .success ? "checkmark.circle" : "info.circle")
                    .font(.callout.weight(.medium)).accessibilityIdentifier("csv-status")
                Spacer()
                HStack { ProgressView().controlSize(.mini); Button("Cancel") { workspace.cancel() }.controlSize(.small) }
                    .opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 26)
            if let result = workspace.result {
                if let issue = result.diagnostics.first {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(issue.message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if result.status != .resourceLimit && issue.code != "TABLE-OPTIONS" {
                            Text("\(issue.precision == .exact ? "Detected at" : "Reported region starts at") line \(issue.line), column \(issue.column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
                            if let context = workspace.context { Text(snippet(context)).font(.system(.caption, design: .monospaced)).lineLimit(3) }
                            HStack {
                                Button("Show Detection") { show(issue.range) }.accessibilityIdentifier("csv-show-detection")
                                if !issue.related.isEmpty {
                                    Menu("Show Related") { ForEach(Array(issue.related.enumerated()), id: \.offset) { _, item in Button(item.role.rawValue) { show(item.range) } } }
                                }
                            }.controlSize(.small)
                        }
                    }.transition(.opacity)
                } else if result.status == .success {
                    Text("\(result.rowCount) rows · \(result.columnCount) columns").font(.caption).foregroundStyle(.secondary)
                    if let note = result.notes.first {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if result.notes.count > 1 {
                        Menu("Conversion notes") { ForEach(result.notes, id: \.self) { Text($0) } }.controlSize(.small)
                    }
                }
                if let format = result.suggestedFormat {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This may be tab-separated text. Use TSV if tabs should separate columns.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Use \(format.rawValue)") { workspace.options.format = format }
                            .controlSize(.small).accessibilityIdentifier("csv-use-suggested-format")
                    }
                }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func snippet(_ context: JSONDiagnosticContext) -> AttributedString {
        var text = AttributedString(context.text)
        if let sourceRange = Range(context.detectionRange, in: context.text), let range = Range(sourceRange, in: text) { text[range].underlineStyle = .single; text[range].foregroundColor = diagnostic?.severity == .warning ? .orange : .red }
        return text
    }
    private func cancelJump() { commands.cancelNavigation?(); jumpTarget = nil; jumpRequest += 1 }
    private func show(_ range: NSRange) { commands.cancelNavigation?(); jumpTarget = range; jumpRequest += 1 }
    private func divider(wide: Bool, length: CGFloat, collapsed: Bool) -> some View {
        ZStack { Color.clear; Capsule().fill(.secondary.opacity(0.5)).frame(width: wide ? 3 : 36, height: wide ? 36 : 3) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                guard !collapsed else { return }
                if dragStart == nil { dragStart = workspace.fraction }
                let delta = wide ? value.translation.width : value.translation.height
                workspace.fraction = min(0.75, max(0.25, (dragStart ?? 0.5) + delta / max(1, length - JSONPanelLayout.divider)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityElement().accessibilityLabel("Input panel size")
            .accessibilityValue("\(Int(workspace.fraction * 100)) percent")
            .accessibilityAdjustableAction { direction in workspace.fraction = min(0.75, max(0.25, workspace.fraction + (direction == .increment ? 0.05 : -0.05))) }
            .contextMenu { Button("Equal panels") { workspace.fraction = 0.5 } }
    }
    private func copy() {
        guard let output = workspace.output else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string)
        #else
        UIPasteboard.general.string = output
        #endif
        copied = true
    }
}
