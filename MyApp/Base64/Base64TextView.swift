import SwiftUI

struct Base64TextView: View {
    @Bindable var workspace: Base64WorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var dragStart: Double?
    @State private var copied = false
    @State private var expandedNotes = false
    @State private var keyboardVisible = false
    @State private var showOutputWithKeyboard = false
    private var reduced: Bool { systemReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var animation: Animation? { reduced ? nil : .easeInOut(duration: 0.2) }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && keyboardVisible
        #else
        false
        #endif
    }
    private var sourceName: String { workspace.options.direction == .decode ? workspace.options.alphabet.title : "Text" }
    private var outputName: String { workspace.options.direction == .encode ? workspace.options.alphabet.title : workspace.result?.status == .bytesOnly ? "Bytes preview" : "Text" }
    private var primaryIssue: Base64Issue? { workspace.result?.issues.first { $0.severity == .error } ?? workspace.result?.issues.first }
    private var previewText: String {
        guard workspace.result?.status == .bytesOnly, let result = workspace.result else { return "" }
        return "Preview · first \(min(result.byteCount, Base64Limits.previewBytes)) of \(result.byteCount) bytes\n\n" + result.preview
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            let collapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { choices; Spacer(minLength: 8); actions }
                    VStack(alignment: .leading, spacing: 8) { choices; actions }
                }
                Base64StatusView(workspace: workspace, expanded: expandedNotes,
                    toggleDetails: { expandedNotes.toggle() }, show: show)
                JSONPanelLayout(horizontal: wide, fraction: workspace.fraction, collapsed: collapsed) {
                    inputPanel
                    divider(wide: wide, length: wide ? geometry.size.width : geometry.size.height, collapsed: collapsed)
                    outputPanel(wide: wide, collapsed: collapsed)
                }.animation(animation, value: collapsed)
            }
            .padding()
            .animation(animation, value: primaryIssue?.code)
            .animation(animation, value: expandedNotes)
        }
        .navigationTitle("Base64 Text / Base64URL")
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { cancelJump() }
        .onChange(of: workspace.sourceRevision) { _, _ in cancelJump(); copied = false; expandedNotes = false }
        .onChange(of: workspace.options) { _, _ in cancelJump(); copied = false; expandedNotes = false }
        .onChange(of: workspace.publicationID) { _, _ in copied = false }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false; showOutputWithKeyboard = false }
        #endif
    }
    private var choices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { direction; alphabet; encoding }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { direction; alphabet }
                encoding
            }
        }.pickerStyle(.menu)
    }
    private var direction: some View {
        Picker("Direction", selection: $workspace.preferences.direction) {
            ForEach(Base64Direction.allCases, id: \.self) { Text($0.title).tag($0) }
        }.fixedSize().accessibilityIdentifier("base64-direction")
    }
    private var alphabet: some View {
        Picker("Alphabet", selection: $workspace.preferences.alphabet) {
            ForEach(Base64Alphabet.allCases, id: \.self) { Text($0.title).tag($0) }
        }.fixedSize().accessibilityIdentifier("base64-alphabet")
    }
    private var encoding: some View {
        Picker("Text encoding", selection: $workspace.preferences.textEncoding) {
            ForEach(Base64TextEncoding.allCases, id: \.self) { Text($0.title).tag($0) }
        }.fixedSize().accessibilityIdentifier("base64-encoding")
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button(workspace.options.direction.title) { workspace.run() }
                .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("base64-convert")
            Button("Check") { workspace.run(.check) }.accessibilityIdentifier("base64-check")
            Menu {
                if workspace.preferences.direction == .decode {
                    Picker("Decode mode", selection: $workspace.preferences.decodeMode) {
                        ForEach(Base64DecodeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Forgiving accepts ASCII whitespace and omitted padding; other invalid symbols are rejected.")
                }
                if workspace.preferences.direction == .encode && workspace.preferences.alphabet == .urlSafe {
                    Toggle("Include '=' padding", isOn: $workspace.preferences.urlPadding)
                }
                Toggle("Check automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
                Divider()
                Text("Base64 is an encoding, not encryption. Processing stays on this device.")
            } label: {
                Label(workspace.preferences.direction == .decode ? workspace.preferences.decodeMode.title : "Options", systemImage: "slider.horizontal.3")
            }.accessibilityLabel("Options").accessibilityIdentifier("base64-settings")
        }.controlSize(.regular).fixedSize(horizontal: true, vertical: false)
    }
    private var editorOptions: JSONEditorOptions {
        .init(syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: workspace.preferences.wordWrap)
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input · \(sourceName)").font(.headline).lineLimit(1); Spacer()
                Button("Clear Input", systemImage: "trash") { commands.clear?(); workspace.clear() }
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("base64-clear")
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: Base64EditorDiagnosticAdapter.make(primaryIssue),
                jumpTarget: jumpTarget, jumpRequest: jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                onPaste: { workspace.didPaste() }, commands: commands, options: editorOptions,
                placeholder: "Paste or type \(sourceName == "Text" ? "text" : sourceName). Processing stays on this device.", contentName: sourceName)
                .accessibilityIdentifier("base64-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output · \(outputName)").font(.headline).lineLimit(1); Spacer(minLength: 2)
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") { copy() }
                    .disabled(!workspace.canCopy).accessibilityLabel("Copy Output").accessibilityIdentifier("base64-copy")
                if !wide {
                    Button {
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                    .accessibilityLabel(collapsed ? "Expand Output" : "Collapse Output").accessibilityIdentifier("base64-collapse")
                }
            }.frame(minHeight: 30)
            JSONTextEditor(text: .constant(workspace.output ?? previewText), editable: false, options: editorOptions,
                placeholder: "Choose \(workspace.options.direction.title) to see the result here.", contentName: outputName)
                .accessibilityIdentifier("base64-output")
                .frame(minWidth: 120, minHeight: 60).frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .opacity(collapsed ? 0 : 1).accessibilityHidden(collapsed).allowsHitTesting(!collapsed)
        }.clipped()
    }
    private func divider(wide: Bool, length: CGFloat, collapsed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.35))
            .frame(width: wide ? 4 : 34, height: wide ? 34 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                guard !collapsed else { return }
                if dragStart == nil { dragStart = workspace.fraction }
                let movement = wide ? value.translation.width : value.translation.height
                workspace.fraction = min(0.75, max(0.25, (dragStart ?? 0.5) + movement / max(1, length - 16)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Panel proportions").accessibilityValue("\(Int(workspace.fraction * 100)) percent input")
            .accessibilityAdjustableAction { direction in
                workspace.fraction = min(0.75, max(0.25, workspace.fraction + (direction == .increment ? 0.05 : -0.05)))
            }
            .contextMenu { Button("Reset split") { withAnimation(animation) { workspace.fraction = 0.5 } } }
    }
    private func cancelJump() { commands.cancelNavigation?(); jumpTarget = nil; jumpRequest += 1 }
    private func show(_ range: NSRange) {
        commands.cancelNavigation?(); jumpTarget = range; jumpRequest += 1
    }
    private func copy() {
        guard workspace.canCopy, let text = workspace.output else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copied = true
    }
}
