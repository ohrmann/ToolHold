import SwiftUI

struct JSONFormatterView: View {
    @Bindable var workspace: JSONWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return systemReduceMotion || (arguments.contains("--navigation-ui-tests") && arguments.contains("--reduce-motion"))
    }
    @State private var commands = JSONEditorCommands()
    @State private var jumpRequest = 0
    @State private var jumpTarget: NSRange?
    @State private var dragStart: Double?
    @State private var keyboardVisible = false
    @State private var showOutputWithKeyboard = false

    private var firstDiagnostic: JSONDiagnostic? {
        guard !workspace.resourceLimited else { return nil }
        return workspace.result?.diagnostics.first { $0.severity == .error } ?? workspace.result?.diagnostics.first
    }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && keyboardVisible
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            let collapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { actions; Spacer(); options }
                    VStack(alignment: .leading, spacing: 8) { HStack { actions }; HStack { options } }
                }
                JSONDiagnosticsPanel(workspace: workspace) { range in
                    jumpTarget = range
                    jumpRequest += 1
                }
                GeometryReader { panels in
                    JSONPanelLayout(horizontal: wide, fraction: workspace.panelFraction, collapsed: collapsed) {
                        inputPanel
                        divider(wide: wide, length: wide ? panels.size.width : panels.size.height, collapsed: collapsed)
                        outputPanel(wide: wide, collapsed: collapsed)
                    }
                }.coordinateSpace(name: "json-panels")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: collapsed)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                       value: workspace.result?.diagnostics.isEmpty == false)
            .padding(12)
        }
        .navigationTitle("JSON Formatter")
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { workspace.cancel() }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
            showOutputWithKeyboard = false
        }
        #endif
    }

    private var actions: some View {
        Group {
            Button("Format") { workspace.run(.format) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Minify") { workspace.run(.minify) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Validate") { workspace.run(.validate) }
                .keyboardShortcut(.return, modifiers: .command)
        }
        .disabled(workspace.busy || workspace.input.isEmpty)
    }

    private var options: some View {
        HStack {
            Picker("Indent", selection: $workspace.preferences.indentation) {
                Text("2 spaces").tag(JSONIndentation.two)
                Text("4 spaces").tag(JSONIndentation.four)
            }
            .pickerStyle(.menu).fixedSize()
            .accessibilityIdentifier("json-indent")
            Menu {
                Toggle("Validate automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Divider()
                Toggle("Syntax Highlighting", isOn: $workspace.preferences.syntaxHighlighting)
                Toggle("Rainbow Brackets", isOn: $workspace.preferences.rainbowBrackets)
                Toggle("Matching Brackets", isOn: $workspace.preferences.matchingBrackets)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
            } label: { Label("Editor Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
            .accessibilityLabel("Editor Options")
            .accessibilityIdentifier("JSON options")
        }
    }

    private var editorOptions: JSONEditorOptions {
        JSONEditorOptions(syntaxHighlighting: workspace.preferences.syntaxHighlighting,
                          rainbowBrackets: workspace.preferences.rainbowBrackets,
                          matchingBrackets: workspace.preferences.matchingBrackets,
                          wordWrap: workspace.preferences.wordWrap)
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input").font(.headline)
                Spacer()
                Button("Clear Input", systemImage: "trash") {
                    commands.clear?()
                    workspace.clear()
                }
                .disabled(workspace.input.isEmpty && workspace.result == nil)
            }.frame(minHeight: 30)
            JSONTextEditor(text: $workspace.input, diagnostic: firstDiagnostic, jumpTarget: jumpTarget,
                           jumpRequest: jumpRequest, onPaste: { workspace.didPaste() }, commands: commands,
                           options: editorOptions, highlightingLimit: JSONProcessor.maximumUTF16Length,
                           placeholder: "Paste or type JSON. Processing stays on this device.")
                .editorBorder()
        }
        .clipped()
    }

    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output").font(.headline)
                Spacer()
                Button("Copy Output", systemImage: "doc.on.doc") { copyResult() }
                    .disabled(workspace.output == nil)
                if !wide {
                    Button {
                        if phoneKeyboard {
                            workspace.outputCollapsed = false
                            showOutputWithKeyboard = collapsed
                        } else { workspace.outputCollapsed.toggle() }
                    } label: {
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    }
                    .accessibilityLabel(collapsed ? "Expand Output" : "Collapse Output")
                }
            }.frame(minHeight: 30)
            JSONTextEditor(text: .constant(workspace.output ?? ""), editable: false,
                           options: editorOptions, highlightingLimit: JSONProcessor.maximumUTF16Length,
                           placeholder: "Format or Minify to create output.")
                .editorBorder()
                .opacity(collapsed ? 0 : 1)
                .accessibilityHidden(collapsed)
                .allowsHitTesting(!collapsed)
        }.clipped()
    }

    private func divider(wide: Bool, length: CGFloat, collapsed: Bool) -> some View {
        ZStack {
            Color.clear
            Capsule().fill(.secondary.opacity(0.5))
                .frame(width: wide ? 3 : 36, height: wide ? 36 : 3)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("json-panels"))
            .onChanged { value in
                guard !collapsed else { return }
                if dragStart == nil { dragStart = workspace.panelFraction }
                let movement = wide ? value.translation.width : value.translation.height
                workspace.panelFraction = min(0.75, max(0.25, (dragStart ?? 0.5) + movement / max(1, length - JSONPanelLayout.divider)))
            }.onEnded { _ in dragStart = nil })
        .accessibilityElement()
        .accessibilityLabel("Input panel size")
        .accessibilityValue("\(Int(workspace.panelFraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard !collapsed else { return }
            workspace.panelFraction = min(0.75, max(0.25, workspace.panelFraction + (direction == .increment ? 0.05 : -0.05)))
        }
        .accessibilityAction(named: "Equal panels") { workspace.panelFraction = 0.5 }
        .contextMenu { Button("Equal panels") { workspace.panelFraction = 0.5 } }
    }

    private func copyResult() {
        guard let output = workspace.output else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #else
        UIPasteboard.general.string = output
        #endif
    }
}

private extension View {
    func editorBorder() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
    }
}
