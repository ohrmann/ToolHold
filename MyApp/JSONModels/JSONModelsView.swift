import SwiftUI

struct JSONModelsView: View {
    @Bindable var workspace: JSONModelsWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var dragStart: Double?
    @State private var keyboardVisible = false
    @State private var showOutputWithKeyboard = false
    @State private var copied = false
    @State private var usageVisible = false
    @State private var notesExpanded = false
    private var reduced: Bool { systemReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && keyboardVisible
        #else
        false
        #endif
    }
    private var diagnostic: JSONDiagnostic? {
        guard workspace.result?.parseResult.status == .invalid else { return nil }
        return workspace.result?.parseResult.diagnostics.first { $0.severity == .error }
    }
    private var inputOptions: JSONEditorOptions {
        .init(syntax: .json, syntaxHighlighting: workspace.preferences.syntaxHighlighting,
              rainbowBrackets: workspace.preferences.rainbowBrackets, matchingBrackets: workspace.preferences.matchingBrackets,
              wordWrap: workspace.preferences.wordWrap)
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            let collapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { language; rootName; Spacer(minLength: 4); actions }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { language; Spacer(minLength: 4); actions }
                        rootName
                    }
                }
                Text("Types inferred from this sample. Review before use.").font(.caption).foregroundStyle(.secondary)
                status
                JSONPanelLayout(horizontal: wide, fraction: workspace.fraction, collapsed: collapsed) {
                    inputPanel
                    divider(wide: wide, length: wide ? geometry.size.width : geometry.size.height, collapsed: collapsed)
                    outputPanel(wide: wide, collapsed: collapsed)
                }
                .animation(reduced ? nil : .easeInOut(duration: 0.2), value: collapsed)
            }
            .padding()
            .animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.result?.status)
            .animation(reduced ? nil : .easeInOut(duration: 0.2), value: notesExpanded)
        }
        .navigationTitle("JSON → Models")
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { cancelJump() }
        .onChange(of: workspace.input) { _, _ in cancelJump(); copied = false; notesExpanded = false }
        .onChange(of: workspace.options) { _, _ in cancelJump(); copied = false }
        .onChange(of: workspace.output) { _, _ in copied = false }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false; showOutputWithKeyboard = false }
        #endif
    }
    private var language: some View {
        Picker("Language", selection: $workspace.language) {
            ForEach(JSONModelLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("models-language")
    }
    private var rootName: some View {
        HStack(spacing: 6) {
            Text("Root name").font(.callout).fixedSize()
            TextField("RootModel", text: $workspace.rootName)
                .textFieldStyle(.roundedBorder).frame(minWidth: 120, idealWidth: 170, maxWidth: 230)
                .accessibilityLabel("Root model name").accessibilityIdentifier("models-root-name")
                .autocorrectionDisabled()
        }
    }
    private var actions: some View {
        HStack {
            Button("Generate Models") { workspace.run() }.keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("models-generate")
            Menu {
                Picker("Indent", selection: $workspace.preferences.indentation) {
                    Text("2 spaces").tag(JSONIndentation.two); Text("4 spaces").tag(JSONIndentation.four)
                }
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
                Toggle("Rainbow Brackets", isOn: $workspace.preferences.rainbowBrackets)
                Toggle("Matching Brackets", isOn: $workspace.preferences.matchingBrackets)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
            } label: { Label("Editor Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
            .accessibilityLabel("Editor Options").accessibilityIdentifier("models-settings")
        }
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input · JSON").font(.headline); Spacer()
                Button("Clear Input", systemImage: "trash") { commands.clear?(); workspace.clear() }
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("models-clear")
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: diagnostic, jumpTarget: jumpTarget, jumpRequest: jumpRequest,
                animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                onPaste: { workspace.didPaste() }, commands: commands, options: inputOptions,
                placeholder: "Paste or type a JSON sample. Processing stays on this device.")
                .accessibilityIdentifier("models-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Models").font(.headline)
                if wide, let name = workspace.artifact?.fileName {
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") { copyCode() }
                    .disabled(!workspace.canCopy).accessibilityLabel("Copy Models").accessibilityIdentifier("models-copy")
                Button("Usage") { usageVisible = true }.disabled(!workspace.canCopy)
                    .accessibilityIdentifier("models-usage")
                    .popover(isPresented: $usageVisible) {
                        VStack(alignment: .leading) {
                            HStack {
                                Button("Copy Usage") { if workspace.canCopy, let usage = workspace.artifact?.usage { copyText(usage) } }
                                Spacer()
                                Button("Done") { usageVisible = false }
                            }.padding([.horizontal, .top])
                            ScrollView {
                                Text(workspace.artifact?.usage ?? "").font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                            }
                        }.frame(idealWidth: 420, idealHeight: 300).presentationCompactAdaptation(.sheet)
                    }
                if !wide {
                    Button {
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                    .accessibilityLabel(collapsed ? "Expand Models" : "Collapse Models")
                }
            }.frame(minHeight: 30)
            JSONTextEditor(text: .constant(workspace.output ?? ""), editable: false,
                options: .init(syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false,
                               matchingBrackets: false, wordWrap: workspace.preferences.wordWrap),
                placeholder: "Generate models to see code here.")
                .accessibilityIdentifier("models-output")
                .frame(minWidth: 180, minHeight: 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .opacity(collapsed ? 0 : 1).accessibilityHidden(collapsed).allowsHitTesting(!collapsed)
        }.clipped()
    }
    private var title: String {
        if workspace.busy { return workspace.output == nil ? "Processing" : "Updating…" }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .success: return workspace.output == nil ? "Ready to generate" : (result.issueCount == 0 ? "Models generated" : "Models generated with notes")
        case .invalidJSON: return "Invalid JSON"
        case .unsupported: return "Valid JSON · Cannot generate this profile"
        case .invalidOptions: return "Check model options"
        case .resourceLimit: return "Processing limit reached"
        case .cancelled: return "Cancelled"
        }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let result = workspace.result, result.status == .invalidJSON || result.parseResult.status != .valid {
                JSONDiagnosticsPanel(input: workspace.input, result: result.parseResult, context: workspace.context,
                    busy: workspace.busy, wasCancelled: workspace.wasCancelled, cancel: workspace.cancel, show: show)
            } else {
                HStack {
                    Label(title, systemImage: workspace.result?.status == .success ? "checkmark.circle" : "info.circle")
                        .font(.callout.weight(.medium)).accessibilityIdentifier("models-status")
                    Spacer(minLength: 4)
                    HStack { ProgressView().controlSize(.mini); Button("Cancel") { workspace.cancel() }.controlSize(.small) }
                        .opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
                }.frame(minHeight: 26)
                if let result = workspace.result, let first = result.issues.first {
                    Text(first.message).font(.callout).lineLimit(2).textSelection(.enabled)
                    if let location = workspace.sourceLocation { Text(location).font(.caption).foregroundStyle(.secondary) }
                    if let context = workspace.context {
                        Text(contextSnippet(context)).font(.system(.caption, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                    }
                    HStack {
                        if let range = first.range { Button("Show Source") { show(range) }.accessibilityIdentifier("models-show-source") }
                        if let related = first.related { Button("Show Related") { show(related) } }
                        if result.issueCount > 1 {
                            Button(notesExpanded ? "Hide notes" : "Generation notes (\(result.issueCount))") { notesExpanded.toggle() }
                        }
                    }.controlSize(.small)
                    if notesExpanded {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(result.issues.dropFirst()) { issue in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(issue.message).font(.callout)
                                        if let range = issue.range { Button("Show Source") { show(range) }.controlSize(.small) }
                                    }
                                }
                                if result.issueCount > result.issues.count { Text("\(result.issueCount - result.issues.count) more notes").font(.caption) }
                            }
                        }.frame(maxHeight: 130).transition(.opacity)
                    }
                }
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func cancelJump() { commands.cancelNavigation?(); jumpTarget = nil; jumpRequest += 1 }
    private func contextSnippet(_ context: JSONDiagnosticContext) -> AttributedString {
        var value = AttributedString(context.text)
        if let sourceRange = Range(context.detectionRange, in: context.text), let range = Range(sourceRange, in: value) {
            value[range].underlineStyle = .single
        }
        return value
    }
    private func show(_ range: NSRange) {
        guard range.location != NSNotFound, range.location <= workspace.input.utf16.count,
              range.length <= workspace.input.utf16.count - range.location else { return }
        commands.cancelNavigation?(); jumpTarget = range; jumpRequest += 1
    }
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
    private func copyCode() {
        guard workspace.canCopy, let text = workspace.output else { return }
        copyText(text); copied = true
    }
    private func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
