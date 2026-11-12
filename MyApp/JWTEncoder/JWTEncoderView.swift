import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct JWTEncoderView: View {
    @Bindable var workspace: JWTEncoderWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var headerCommands = JSONEditorCommands()
    @State private var payloadCommands = JSONEditorCommands()
    @State private var outputCommands = JSONEditorCommands()
    @State private var keyCommands = JWTSigningKeyCommands()
    @State private var details = false
    @State private var copied = false
    @State private var dragStart: Double?
    @State private var applyingAlgorithm = false
    @State private var algorithmEditError: String?
    private var reduced: Bool { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    #if os(macOS)
    private var keyControlHeight: CGFloat { 24 }
    #else
    private var keyControlHeight: CGFloat { 44 }
    #endif
    private var motion: Animation? { reduced ? nil : .easeInOut(duration: 0.2) }
    private var jsonOptions: JSONEditorOptions { .init(wordWrap: workspace.preferences.wordWrap) }
    private var plainOptions: JSONEditorOptions { .init(syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: workspace.preferences.wordWrap) }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack { operations; Spacer(); options }
                    VStack(alignment: .leading, spacing: 6) { operations; options }
                }
                status
                GeometryReader { area in
                    let wide = area.size.width >= 760
                    ScrollViewReader { proxy in
                        ScrollView {
                            JWTEncoderWorkspaceLayout(wide: wide, fraction: workspace.fraction) {
                                jsonPanel(.header).id("jwt-encoder-header-panel")
                                jsonPanel(.payload).id("jwt-encoder-payload-panel")
                                signingKey.id("jwt-encoder-sign-panel")
                                divider(wide: wide, length: area.size.width)
                                output.id("jwt-encoder-output-panel")
                            }
                            .frame(height: max(area.size.height, wide ? 600 : 920))
                            .id(workspace.editorEpoch)
                        }
                        .accessibilityIdentifier("jwt-encoder-form")
                        .onChange(of: workspace.jumpRequest) { _, _ in
                            let target = workspace.headerTarget != nil ? "jwt-encoder-header-panel" : workspace.payloadTarget != nil ? "jwt-encoder-payload-panel" : nil
                            if let target { withAnimation(motion) { proxy.scrollTo(target, anchor: .top) } }
                        }
                    }
                }
            }.padding(12).animation(motion, value: details)
                .animation(motion, value: workspace.result?.issues.contains { $0.severity == .error } == true)
        }
        .navigationTitle("JWT Encoder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { resign() } } }
        #endif
        .onChange(of: workspace.header) { _, _ in algorithmEditError = nil }
        .onChange(of: workspace.revision) { _, _ in copied = false; details = false; cancelJumps() }
        .onChange(of: phase) { _, value in
            if value == .background { resign(); workspace.concealSecrets() }
        }
        .onDisappear { resign(); workspace.disappear() }
    }
    private var operations: some View {
        HStack {
            Button("Check JSON", systemImage: "checkmark.circle") { cancelJumps(); workspace.run(.jsonOnly) }
                .disabled(workspace.masked || workspace.busy).accessibilityIdentifier("jwt-encoder-check")
            if workspace.busy { Button("Cancel") { workspace.cancel() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("jwt-encoder-cancel") }
        }.fixedSize()
    }
    private var options: some View {
        HStack {
            Button(workspace.masked ? "Reveal data" : "Hide data", systemImage: workspace.masked ? "eye" : "eye.slash") {
                resign(); cancelJumps()
                if workspace.masked { workspace.reveal() } else { workspace.hide() }
            }.accessibilityIdentifier("jwt-encoder-mask")
            Menu {
                Picker("JSON serialization", selection: $workspace.preferences.serialization) {
                    ForEach(JWTEncoderSerialization.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
                Toggle("Check JSON on paste", isOn: $workspace.preferences.checkJSONOnPaste)
                Divider()
                Toggle("Enable Unsigned test token", isOn: Binding(get: { workspace.unsignedConsent }, set: { value in
                    resign(); workspace.unsignedConsent = value
                }))
                Text("Unsigned tokens have no integrity protection. Consent is not saved.")
                Divider()
                Button("Clear All", role: .destructive) { resign(); keyCommands.clear?(); headerCommands.purgeUndo?(); payloadCommands.purgeUndo?(); workspace.clear() }.accessibilityIdentifier("jwt-encoder-clear")
            } label: { Label("Options", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("jwt-encoder-options")
        }.fixedSize()
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: workspace.algorithm == JWTSigningAlgorithm.none ? "exclamationmark.shield" : "signature").foregroundStyle(.secondary)
                Text(workspace.masked ? "Sensitive content hidden" : workspace.busy ? "Processing…" : workspace.result?.status.rawValue ?? "Ready · not checked")
                    .font(.callout).accessibilityIdentifier("jwt-encoder-status")
                if workspace.busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                if !workspace.masked, let result = workspace.result, result.issueCount > 0 {
                    Button { withAnimation(motion) { details.toggle() } } label: { Label("\(result.issueCount) issues", systemImage: details ? "chevron.up" : "chevron.down") }
                        .font(.callout).accessibilityIdentifier("jwt-encoder-details")
                }
            }.frame(minHeight: 28)
            if !workspace.masked, let issue = workspace.result?.issues.first(where: { $0.severity == .error }) { issueSummary(issue) }
            if !workspace.masked, workspace.algorithm == JWTSigningAlgorithm.none { Label("Unsigned test token · no integrity protection", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if details && !workspace.masked, let result = workspace.result {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(result.issues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                issueSummary(issue)
                                if let diagnostic = issue.diagnostic { Text("\(issue.component.rawValue) · line \(diagnostic.line), column \(diagnostic.column) (UTF-16)").font(.caption).foregroundStyle(.secondary) }
                                if let context = issue.context { contextText(context).font(.system(.caption, design: .monospaced)).lineLimit(3) }
                                if issue.diagnostic?.related.isEmpty == false { Button("Show Related") { show(issue, related: true) }.font(.caption) }
                            }
                        }
                        if result.issueCount > result.issues.count { Text("Showing \(result.issues.count) of \(result.issueCount) issues. All fields were checked.").font(.caption) }
                    }
                }.frame(maxHeight: 155)
            }
        }
    }
    private func issueSummary(_ issue: JWTEncoderIssue) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle").foregroundStyle(issue.severity == .error ? .red : .orange)
            Text(issue.message).font(.callout).lineLimit(3)
            Spacer(minLength: 0)
            if issue.diagnostic != nil { Button("Show Detection") { show(issue) }.font(.caption).accessibilityIdentifier("jwt-encoder-show-detection") }
        }
    }
    private func jsonPanel(_ component: JWTEncoderIssue.Component) -> some View {
        let isHeader = component == .header
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(component.rawValue).font(.headline)
                Text(isHeader ? "Token metadata" : "JSON claims").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.frame(minHeight: 28)
            ZStack {
                JSONTextEditor(text: isHeader ? $workspace.header : $workspace.payload,
                    diagnostic: workspace.diagnostic(component), jumpTarget: isHeader ? workspace.headerTarget : workspace.payloadTarget,
                    jumpRequest: workspace.jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                    onPaste: { workspace.didPaste() }, commands: isHeader ? headerCommands : payloadCommands, options: jsonOptions,
                    presentationHidden: workspace.masked, usesPrivacyContainer: true, privateUndo: true,
                    placeholder: isHeader ? "Enter a JWT header object." : "Enter a JSON claims object.", contentName: "JWT Encoder \(component.rawValue)")
                    .accessibilityHidden(workspace.masked).allowsHitTesting(!workspace.masked)
                if workspace.masked { cover("Sensitive content hidden") }
            }.clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private var signingKey: some View {
        let visible = !workspace.masked && workspace.keyRevealed && workspace.algorithm != JWTSigningAlgorithm.none
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sign JWT").font(.headline)
                Spacer(minLength: 0)
                Picker("Algorithm", selection: Binding<JWTSigningAlgorithm?>(get: { workspace.algorithm }, set: { value in
                    if let value { applyAlgorithm(value) }
                })) {
                    Text("Check Header").tag(Optional<JWTSigningAlgorithm>.none).disabled(true)
                    ForEach(JWTSigningAlgorithm.allCases.filter { $0 != .none || workspace.unsignedConsent || workspace.algorithm == JWTSigningAlgorithm.none }, id: \.self) { value in
                        Text(value.title).tag(Optional.some(value)).disabled(value == .none && !workspace.unsignedConsent)
                    }
                }.pickerStyle(.menu).disabled(workspace.masked || applyingAlgorithm).accessibilityIdentifier("jwt-encoder-algorithm")
            }.frame(minHeight: 28)
            if let algorithmEditError { Text(algorithmEditError).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("jwt-encoder-algorithm-edit-error") }
            keyControls
            ZStack {
                JWTSigningKeyEditor(text: $workspace.key, commands: keyCommands, visible: visible)
                    .accessibilityHidden(!visible).allowsHitTesting(visible)
                if !visible { cover(workspace.algorithm == JWTSigningAlgorithm.none ? "No signing key used" : "Signing key hidden") }
            }.clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            Text(keyHint)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button("Generate JWT", systemImage: "signature") { cancelJumps(); workspace.run() }
                .keyboardShortcut(.return, modifiers: .command).disabled(workspace.masked || workspace.busy)
                .accessibilityIdentifier("jwt-encoder-generate")
        }.clipped()
    }
    private var keyHint: String {
        guard let algorithm = workspace.algorithm else { return "Choose an algorithm or check Header 'alg' · processed locally" }
        if algorithm == .none { return "Unsigned test token · no signing key used" }
        return algorithm.family == .hmac ? "Enter a secret · \(algorithm.signatureBytes) bytes minimum · processed locally" : "Enter a private key · processed locally"
    }
    private var keyControls: some View {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Signing key").font(.subheadline.weight(.medium)).fixedSize()
            Picker("Key encoding", selection: $workspace.preferences.keyEncoding) {
                ForEach(JWTSigningKeyEncoding.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("jwt-encoder-key-encoding")
            Spacer(minLength: 0)
          }
          HStack(spacing: 12) {
            Button { pasteKey() } label: { Text("Paste").frame(minHeight: keyControlHeight).contentShape(Rectangle()) }.disabled(workspace.masked || workspace.algorithm == JWTSigningAlgorithm.none).accessibilityIdentifier("jwt-encoder-paste-key")
            Button {
                keyCommands.resignFocus?(); workspace.keyRevealed.toggle()
            } label: { Image(systemName: workspace.keyRevealed ? "eye.slash" : "eye").frame(width: keyControlHeight, height: keyControlHeight).contentShape(Rectangle()) }
                .help(workspace.keyRevealed ? "Hide signing key" : "Show signing key")
                .accessibilityLabel(workspace.keyRevealed ? "Hide signing key" : "Show signing key")
                .disabled(workspace.masked || workspace.algorithm == JWTSigningAlgorithm.none).accessibilityIdentifier("jwt-encoder-reveal-key")
            Button { keyCommands.resignFocus?(); keyCommands.clear?() } label: { Image(systemName: "trash").frame(minWidth: keyControlHeight, minHeight: keyControlHeight).contentShape(Rectangle()) }
                .accessibilityLabel("Clear signing key").accessibilityIdentifier("jwt-encoder-clear-key").disabled(workspace.masked || workspace.key.isEmpty)
          }
        }.font(.callout)
    }
    private var output: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack { outputControls; Spacer(minLength: 0) }
                VStack(alignment: .leading) { outputControls }
            }.frame(minHeight: 30)
            if let artifact = workspace.artifact {
                Text("\(artifact.algorithm.rawValue) · \(artifact.byteCount) bytes · \(artifact.algorithm == .none ? "unsigned" : "signed locally, issuer not authenticated")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ZStack {
                JSONTextEditor(text: .constant(workspace.artifact?.token ?? ""), editable: false, commands: outputCommands, options: plainOptions,
                    presentationHidden: workspace.masked || !workspace.tokenRevealed || workspace.artifact == nil, usesPrivacyContainer: true, contentName: "Generated JWT")
                    .accessibilityHidden(workspace.masked || !workspace.tokenRevealed || workspace.artifact == nil)
                if workspace.masked || (workspace.artifact != nil && !workspace.tokenRevealed) { cover("Token hidden · use Reveal or Copy") }
                else if workspace.artifact == nil { ContentUnavailableView("Build a JWT", systemImage: "signature", description: Text("Enter Header, Payload and a signing key, then choose Generate JWT.")) }
            }.clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private var outputControls: some View {
        HStack(spacing: 10) {
            Text("Token").font(.headline)
            Button(workspace.tokenRevealed ? "Hide" : "Reveal") { outputCommands.resignFocus?(); workspace.tokenRevealed.toggle() }
                .disabled(workspace.artifact == nil || workspace.masked).accessibilityIdentifier("jwt-encoder-reveal-token")
            Button(copied ? "Copied" : "Copy JWT", systemImage: "doc.on.doc") { copy() }
                .disabled(workspace.copy() == nil).accessibilityIdentifier("jwt-encoder-copy")
            Menu { Button("Copy Bearer Token") { copy(bearer: true) } } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Copy options").disabled(workspace.copy() == nil).accessibilityIdentifier("jwt-encoder-copy-options")
        }.font(.callout)
    }
    private func cover(_ text: String) -> some View {
        VStack(spacing: 6) { Image(systemName: "eye.slash"); Text(text).font(.callout).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background).accessibilityElement(children: .combine)
    }
    private func divider(wide: Bool, length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.3)).frame(width: wide ? 4 : 30, height: wide ? 30 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                guard wide else { return }
                if dragStart == nil { dragStart = workspace.fraction }
                workspace.fraction = min(0.75, max(0.35, (dragStart ?? 0.57) + value.translation.width / max(1, length - 16)))
            }.onEnded { _ in dragStart = nil })
            .opacity(wide ? 1 : 0).allowsHitTesting(wide).accessibilityHidden(!wide)
            .accessibilityLabel("Panel proportions").accessibilityAdjustableAction { value in workspace.fraction = min(0.75, max(0.35, workspace.fraction + (value == .increment ? 0.05 : -0.05))) }
    }
    private func contextText(_ context: JSONDiagnosticContext) -> Text {
        let text = context.text as NSString, range = context.detectionRange
        let before = Text(text.substring(to: range.location))
        let marker = Text(text.substring(with: range)).bold().underline()
        let after = Text(text.substring(from: NSMaxRange(range)))
        return Text("\(before)\(marker)\(after)")
    }
    private func applyAlgorithm(_ algorithm: JWTSigningAlgorithm) {
        applyingAlgorithm = true
        algorithmEditError = nil
        let source = workspace.header, revision = workspace.revision
        Task {
            let edit = await Task.detached { JWTEncoderProcessor.algorithmEdit(header: source, algorithm: algorithm) }.value
            applyingAlgorithm = false
            guard workspace.revision == revision, !workspace.masked else { return }
            guard let edit else {
                algorithmEditError = "Fix Header JSON and duplicate fields before choosing an algorithm."
                return
            }
            headerCommands.replace?(edit.0, edit.1)
        }
    }
    private func show(_ issue: JWTEncoderIssue, related: Bool = false) {
        cancelJumps(); resign()
        withAnimation(motion) { workspace.show(issue, related: related) }
    }
    private func pasteKey() {
        #if os(macOS)
        let value = NSPasteboard.general.string(forType: .string)
        #else
        let value = UIPasteboard.general.string
        #endif
        if let value { keyCommands.paste?(value) }
    }
    private func copy(bearer: Bool = false) {
        guard let text = workspace.copy(bearer: bearer) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true])
        #endif
        copied = true
    }
    private func cancelJumps() { headerCommands.cancelNavigation?(); payloadCommands.cancelNavigation?(); outputCommands.cancelNavigation?() }
    private func resign() { headerCommands.resignFocus?(); payloadCommands.resignFocus?(); keyCommands.resignFocus?(); outputCommands.resignFocus?() }
}

/// All four panels retain their native editors across width and height changes.
/// A single form scroll view keeps sections reachable on a short window/keyboard.
private struct JWTEncoderWorkspaceLayout: Layout {
    var wide: Bool
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 5 else { return }
        func place(_ index: Int, _ rect: CGRect) { subviews[index].place(at: rect.origin, anchor: .topLeading, proposal: .init(rect.size)) }
        if wide {
            let left = (bounds.width - 16) * fraction
            let header: CGFloat = 144, signing: CGFloat = 310
            let payload = max(100, bounds.height - header - signing - 24)
            place(0, .init(x: bounds.minX, y: bounds.minY, width: left, height: header))
            place(1, .init(x: bounds.minX, y: bounds.minY + header + 12, width: left, height: payload))
            place(2, .init(x: bounds.minX, y: bounds.maxY - signing, width: left, height: signing))
            place(3, .init(x: bounds.minX + left, y: bounds.minY, width: 16, height: bounds.height))
            place(4, .init(x: bounds.minX + left + 16, y: bounds.minY, width: bounds.width - left - 16, height: bounds.height))
        } else {
            let heights: [CGFloat] = [150, 220, 310, 0, max(200, bounds.height - 716)]
            var y = bounds.minY
            for index in [0, 1, 2, 4] {
                place(index, .init(x: bounds.minX, y: y, width: bounds.width, height: heights[index]))
                y += heights[index] + 12
            }
            place(3, .init(x: bounds.minX, y: bounds.minY, width: 0, height: 0))
        }
    }
}
