import SwiftUI

struct HexBytesView: View {
    @Bindable var workspace: HexBytesWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var outputCommands = JSONEditorCommands()
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
    private var sourceName: String { workspace.options.direction == .decode ? "Hex" : "Text" }
    private var outputName: String { workspace.options.direction == .encode ? "Hex" : "Text" }
    private var primaryIssue: HexBytesIssue? { workspace.result?.issues.first { $0.severity == .error } ?? workspace.result?.issues.first }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            let collapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { choices; Spacer(minLength: 8); actions }
                    VStack(alignment: .leading, spacing: 8) { choices; actions }
                }
                Text(summary).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HexBytesStatusView(workspace: workspace, expanded: expandedNotes,
                    toggleDetails: { expandedNotes.toggle() }, show: show, cancel: { cancelJump(); workspace.cancel() })
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
        .navigationTitle("Hex ↔ UTF-8 / Bytes")
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { cancelJump() }
        .onChange(of: workspace.sourceRevision) { _, _ in cancelJump(); copied = false; expandedNotes = false }
        .onChange(of: workspace.options) { _, _ in cancelJump(); copied = false; expandedNotes = false }
        .onChange(of: workspace.publicationID) { _, _ in copied = false }
        .onChange(of: workspace.showingBytes) { _, showing in if showing { outputCommands.resignFocus?() } }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false; showOutputWithKeyboard = false }
        #endif
    }
    private var choices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { direction; inputFormat }
            VStack(alignment: .leading, spacing: 6) { direction; inputFormat }
        }.pickerStyle(.menu)
    }
    private var direction: some View {
        Picker("Direction", selection: $workspace.preferences.direction) {
            ForEach(HexBytesDirection.allCases, id: \.self) { Text($0.title).tag($0) }
        }.fixedSize().accessibilityIdentifier("hex-bytes-direction")
    }
    @ViewBuilder private var inputFormat: some View {
        if workspace.preferences.direction == .decode {
            Picker("Input format", selection: $workspace.preferences.inputFormat) {
                ForEach(HexBytesInputFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }.fixedSize().accessibilityIdentifier("hex-bytes-input-format")
        }
    }
    private var summary: String {
        workspace.options.direction == .decode ? "Exact bytes · Strict UTF-8 · No replacement decoding" : "UTF-8 bytes · No normalization"
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button("Convert") { cancelJump(); workspace.run() }
                .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("hex-bytes-convert")
            Button("Check") { cancelJump(); workspace.run(.check) }.accessibilityIdentifier("hex-bytes-check")
            Menu {
                Picker("Hex output / Copy Hex", selection: $workspace.preferences.outputFormat) {
                    ForEach(HexBytesOutputFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("hex-bytes-output-format")
                Picker("Hex digits", selection: $workspace.preferences.hexCase) {
                    ForEach(HexBytesCase.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Check automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
                Divider()
                Text("Hex pairs accept even digit runs, ASCII whitespace, ':' and '-'. Other profiles require explicit byte prefixes.")
                Text("Processing stays on this device.")
            } label: { Label("Options", systemImage: "slider.horizontal.3") }
            .accessibilityLabel("Options").accessibilityIdentifier("hex-bytes-settings")
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
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("hex-bytes-clear")
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: HexBytesEditorDiagnosticAdapter.make(primaryIssue),
                jumpTarget: jumpTarget, jumpRequest: jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                onPaste: { workspace.didPaste() }, commands: commands, options: editorOptions,
                placeholder: "Paste or type text. Processing stays on this device.", contentName: sourceName)
                .accessibilityIdentifier("hex-bytes-input")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output").font(.headline).lineLimit(1)
                Picker("Output view", selection: Binding(get: { workspace.showingBytes ? HexBytesOutputView.bytes : .text }, set: {
                    outputCommands.resignFocus?(); workspace.preferences.preferredOutputView = $0
                })) {
                    Text(outputName).tag(HexBytesOutputView.text).disabled(workspace.artifact?.text == nil)
                    Text("Bytes").tag(HexBytesOutputView.bytes)
                }.pickerStyle(.menu).fixedSize().disabled(workspace.artifact == nil).accessibilityIdentifier("hex-bytes-output-view")
                Spacer(minLength: 2)
                Menu {
                    Button("Copy Text") { copy(.text) }.disabled(!workspace.canCopyText).accessibilityIdentifier("hex-bytes-copy-text")
                    Button("Copy Hex") { copy(.hex) }.disabled(!workspace.canCopyHex).accessibilityIdentifier("hex-bytes-copy-hex")
                    if workspace.artifact != nil && !workspace.copyHexFits { Text("Copy format exceeds limit; choose Compact in Options.") }
                } label: { Label(copied ? "Copied" : workspace.copyBusy ? "Preparing…" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .disabled(!workspace.canCopyText && !workspace.canCopyHex && !workspace.copyBusy)
                .accessibilityLabel("Copy Output").accessibilityIdentifier("hex-bytes-copy")
                if !wide {
                    Button {
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                    .accessibilityLabel(collapsed ? "Expand Output" : "Collapse Output").accessibilityIdentifier("hex-bytes-collapse")
                }
            }.frame(minHeight: 30)
            ZStack {
                JSONTextEditor(text: .constant(workspace.output ?? ""), editable: false, commands: outputCommands, options: editorOptions,
                    placeholder: workspace.artifact?.bytes.isEmpty == true ? "Empty result · 0 bytes" : "Choose Convert to see the result here.", contentName: outputName)
                    .accessibilityIdentifier("hex-bytes-output")
                    .opacity(workspace.showingBytes ? 0 : 1).accessibilityHidden(workspace.showingBytes).allowsHitTesting(!workspace.showingBytes)
                if workspace.showingBytes, let artifact = workspace.artifact {
                    HexBytesInspector(artifact: artifact, hexCase: workspace.preferences.hexCase)
                }
            }
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
    private func copy(_ kind: HexBytesWorkspaceSession.CopyKind) {
        let work = workspace.prepareCopy(kind)
        Task { @MainActor in
            guard let payload = await work.value, workspace.isCurrent(payload) else { return }
            #if os(macOS)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(payload.text, forType: .string)
            #else
            UIPasteboard.general.string = payload.text
            #endif
            copied = true
        }
    }
}
