import SwiftUI

struct JSONXMLConverterView: View {
    @Bindable var workspace: JSONXMLWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var dragStart: Double?
    @State private var keyboardVisible = false
    @State private var showOutputWithKeyboard = false
    @State private var copied = false
    private var reduced: Bool { systemReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var diagnostic: JSONDiagnostic? { workspace.result?.status == .resourceLimit ? nil : workspace.result?.diagnostics.first }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && keyboardVisible
        #else
        false
        #endif
    }
    private func options(json: Bool) -> JSONEditorOptions {
        JSONEditorOptions(syntax: json ? .json : .xml,
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
                    HStack { direction; mapping; Spacer(); actions }
                    VStack(alignment: .leading, spacing: 8) { HStack { direction; Spacer(minLength: 4); mapping }; HStack { actions; Spacer() } }
                }
                Text(workspace.mapping.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .help(workspace.mapping.note).accessibilityIdentifier("xml-profile")
                status
                JSONPanelLayout(horizontal: wide, fraction: workspace.fraction, collapsed: collapsed) {
                    inputPanel
                    divider(wide: wide, length: wide ? geometry.size.width : geometry.size.height, collapsed: collapsed)
                    outputPanel(wide: wide, collapsed: collapsed)
                }
                .coordinateSpace(name: "xml-panels")
                .animation(reduced ? nil : .easeInOut(duration: 0.2), value: collapsed)
            }
            .animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.result?.status)
            .padding()
        }
        .navigationTitle("JSON ↔ XML")
        .onAppear { workspace.refreshPreferences() }
        .onChange(of: workspace.input) { _, _ in cancelJump(); copied = false }
        .onChange(of: workspace.output == nil) { _, empty in if empty { copied = false } }
        .onChange(of: workspace.mapping) { _, _ in cancelJump(); copied = false }
        .onChange(of: workspace.direction) { _, _ in cancelJump(); copied = false }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false; showOutputWithKeyboard = false }
        #endif
    }
    private var direction: some View {
        Picker("Direction", selection: $workspace.direction) {
            ForEach(JSONXMLDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("xml-direction")
    }
    private var actions: some View {
        HStack {
            Button("Convert") { workspace.run() }.keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("xml-convert")
            Button("Check") { workspace.run(convert: false) }.accessibilityIdentifier("xml-check")
            Menu {
                Text("XML 1.0 · DTD and external entities disabled")
                Divider()
                Picker("Indent", selection: $workspace.preferences.indentation) {
                    Text("2 spaces").tag(JSONIndentation.two); Text("4 spaces").tag(JSONIndentation.four)
                }
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
            } label: { Label("Editor Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
            .accessibilityLabel("Editor Options").accessibilityIdentifier("xml-settings")
        }.disabled(workspace.busy)
    }
    private var mapping: some View {
        Picker("Mapping", selection: $workspace.mapping) {
            ForEach(JSONXMLMapping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("xml-mapping")
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input · \(workspace.direction.inputName)").font(.headline)
                Spacer()
                Button("Clear Input", systemImage: "trash") { commands.clear?(); workspace.clear() }
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("xml-clear")
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: diagnostic, jumpTarget: jumpTarget,
                jumpRequest: jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                onPaste: { workspace.didPaste() }, commands: commands,
                options: options(json: workspace.direction == .jsonToXML),
                placeholder: "Paste or type \(workspace.direction.inputName). Processing stays on this device.")
                .accessibilityIdentifier("xml-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output · \(workspace.direction.outputName)").font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy Output", systemImage: copied ? "checkmark" : "doc.on.doc") { copy() }
                    .disabled(workspace.output == nil).accessibilityIdentifier("xml-copy")
                if !wide {
                    Button {
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                    .accessibilityLabel(collapsed ? "Expand Output" : "Collapse Output")
                }
            }.frame(minHeight: 30)
            JSONTextEditor(text: .constant(workspace.output ?? ""), editable: false,
                options: options(json: workspace.direction == .xmlToJSON), placeholder: "Convert to create \(workspace.direction.outputName) output.")
                .accessibilityIdentifier("xml-output")
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
        case .invalid: return "Invalid \(workspace.direction.inputName)"
        case .unsupported: return "Cannot convert this construct"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: workspace.result?.status == .success ? "checkmark.circle" : "info.circle")
                    .font(.callout.weight(.medium)).accessibilityIdentifier("xml-status")
                Spacer()
                HStack { ProgressView().controlSize(.mini); Button("Cancel") { workspace.cancel() }.controlSize(.small) }
                    .opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 26)
            if let result = workspace.result {
                if let issue = result.diagnostics.first {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(issue.message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if result.status != .resourceLimit {
                            Text("\(issue.precision == .exact ? "Detected at" : "Reported region starts at") line \(issue.line), column \(issue.column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
                            if let context = workspace.context { Text(snippet(context)).font(.system(.caption, design: .monospaced)).lineLimit(3) }
                            HStack {
                                Button("Show Detection") { show(issue.range) }.accessibilityIdentifier("xml-show-detection")
                                if !issue.related.isEmpty {
                                    Menu("Show Related") { ForEach(Array(issue.related.enumerated()), id: \.offset) { _, item in Button(item.role.rawValue) { show(item.range) } } }
                                }
                            }.controlSize(.small)
                        }
                    }.transition(.opacity)
                } else if result.status == .success {
                    if let note = result.notes.first { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if result.notes.count > 1 { Menu("Conversion notes") { ForEach(result.notes, id: \.self) { Text($0) } }.controlSize(.small) }
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
