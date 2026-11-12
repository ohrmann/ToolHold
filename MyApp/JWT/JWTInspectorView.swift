import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct JWTInspectorView: View {
    @Bindable var workspace: JWTWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var accessiblePanelHeight = 600.0
    private var accessibleLayout: Bool { dynamicType.isAccessibilitySize }
    private var actionLayout: AnyLayout { accessibleLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout()) }
    @State private var inputCommands = JSONEditorCommands()
    @State private var headerCommands = JSONEditorCommands()
    @State private var payloadCommands = JSONEditorCommands()
    @State private var details = false
    @State private var keyboard = false
    @State private var dragStart: Double?
    @State private var claimScrollRequest = 0
    @State private var claimScrollTarget: Int?
    @State private var copied = false
    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var claimRowHeight = 58.0
    @ScaledMetric(relativeTo: .body) private var timeClaimRowHeight = 100.0
    #else
    @ScaledMetric(relativeTo: .body) private var claimRowHeight = 68.0
    @ScaledMetric(relativeTo: .body) private var timeClaimRowHeight = 116.0
    #endif
    private var reduced: Bool { reducedMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration: 0.2) }
    private var plainOptions: JSONEditorOptions { .init(syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: workspace.preferences.wordWrap) }
    private var jsonOptions: JSONEditorOptions { .init(wordWrap: workspace.preferences.wordWrap) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            ScrollView(.vertical) {
              VStack(alignment: .leading, spacing: 8) {
                if accessibleLayout {
                    VStack(alignment: .leading, spacing: 12) { operations; privacyOptions }
                } else { ViewThatFits(in: .horizontal) {
                    HStack { operations; Spacer(); privacyOptions }
                    VStack(alignment: .leading, spacing: 6) { operations; privacyOptions }
                } }
                JWTStatusView(workspace: workspace, details: $details, show: show)
                JWTPanelLayout(horizontal: wide, fraction: !wide && keyboard ? 0.65 : workspace.fraction, collapsed: workspace.inputCollapsed) {
                    inputPanel(wide: wide)
                    split(wide: wide, length: wide ? geometry.size.width : geometry.size.height)
                    inspector
                }.animation(motion, value: workspace.inputCollapsed)
                 .frame(minHeight: accessibleLayout ? accessiblePanelHeight : 0)
            }.padding(12).animation(motion, value: details)
                .animation(motion, value: workspace.result?.issues.contains { $0.severity == .error } == true)
                .frame(minHeight: geometry.size.height, maxHeight: accessibleLayout ? nil : geometry.size.height, alignment: .topLeading)
            }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("jwt-workspace-scroll")
        }
        .toolNavigationTitle(.t020)
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { cancelJumps(); workspace.disappear() }
        .onChange(of: workspace.sourceRevision) { _, _ in cancelJumps(); details = false; copied = false }
        .onChange(of: workspace.section) { _, _ in copied = false }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        #endif
        .onChange(of: scenePhase) { _, value in if value == .active { workspace.refreshTime() } }
    }
    private var operations: some View {
        actionLayout {
            Button("Decode", systemImage: "text.magnifyingglass") { cancelJumps(); workspace.run() }
                .keyboardShortcut(.return, modifiers: .command).disabled(workspace.masked || workspace.busy || workspace.input.isEmpty)
                .accessibilityIdentifier("jwt-decode")
            if workspace.busy { Button("Cancel") { cancelJumps(); workspace.cancel() }.accessibilityIdentifier("jwt-cancel") }
        }.fixedSize(horizontal: !accessibleLayout, vertical: true)
    }
    private var privacyOptions: some View {
        actionLayout {
            Button(workspace.masked ? "Reveal data" : "Hide sensitive data", systemImage: workspace.masked ? "eye" : "eye.slash") {
                inputCommands.resignFocus?(); headerCommands.resignFocus?(); payloadCommands.resignFocus?(); cancelJumps()
                workspace.setMasked(!workspace.masked)
            }.accessibilityIdentifier("jwt-mask")
            Menu {
                Toggle("Decode automatically on paste", isOn: $workspace.preferences.decodeOnPaste)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
                Divider()
                Text("Local inspection only. Signatures and issuer/audience are not verified.")
            } label: { Label("Options", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("jwt-options")
        }.fixedSize(horizontal: !accessibleLayout, vertical: true)
         .multilineTextAlignment(.leading)
    }
    private func inputPanel(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            actionLayout {
                Button {
                    inputCommands.resignFocus?(); inputCommands.cancelNavigation?()
                    withAnimation(motion) { workspace.inputCollapsed.toggle() }
                } label: { Label(workspace.inputCollapsed ? "Edit Input" : "Input", systemImage: workspace.inputCollapsed ? "chevron.right" : "chevron.down") }
                .buttonStyle(.plain).font(.headline).accessibilityIdentifier("jwt-collapse-input")
                Spacer(minLength: 0)
                if !workspace.inputCollapsed {
                    Menu {
                        Button("Copy Token") { copy(.token) }.disabled(workspace.result?.token == nil)
                    } label: { Image(systemName: "doc.on.doc") }.disabled(workspace.masked).accessibilityLabel("Copy token")
                    Button("Clear", systemImage: "trash") { inputCommands.clear?(); workspace.clear() }
                        .disabled(workspace.input.isEmpty || workspace.masked).accessibilityIdentifier("jwt-clear")
                }
            }.frame(minHeight: 30).lineLimit(accessibleLayout ? nil : 1)
            ZStack {
                JSONTextEditor(text: $workspace.input, diagnostic: workspace.inputDiagnostic, jumpTarget: workspace.inputTarget,
                    jumpRequest: workspace.jumpRequest, animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                    onPaste: { workspace.didPaste() }, commands: inputCommands, options: plainOptions,
                    presentationHidden: workspace.masked || workspace.inputCollapsed, usesPrivacyContainer: true,
                    placeholder: "Paste a JWT or Bearer token. Processing stays on this device.", contentName: "JWT")
                    .accessibilityHidden(workspace.masked || workspace.inputCollapsed).allowsHitTesting(!workspace.masked && !workspace.inputCollapsed)
                if workspace.masked { maskCover }
            }.clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .opacity(workspace.inputCollapsed ? 0 : 1).accessibilityHidden(workspace.masked || workspace.inputCollapsed)
        }.clipped()
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 6) {
            actionLayout {
                Picker("Section", selection: $workspace.section) {
                    ForEach(JWTWorkspaceSession.Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("jwt-section").fixedSize()
                Spacer(minLength: 0)
                Menu {
                    switch workspace.section {
                    case .header, .payload:
                        let component: JWTComponent = workspace.section == .header ? .header : .payload
                        Button(workspace.result?.parts[component]?.document == nil ? "Copy Raw Decoded Text" : "Copy Raw JSON") { copy(.raw(component)) }.disabled(workspace.result?.parts[component]?.text == nil)
                        Button("Copy Formatted JSON") { copy(.formatted(component)) }.disabled(workspace.result?.parts[component]?.presentation == nil)
                    case .signature:
                        Button("Copy Encoded Signature") { copy(.signature) }.disabled(workspace.result?.parts[.signature]?.encoded.isEmpty != false)
                    case .claims:
                        if let id = workspace.selection { claimActions(id) } else { Text("Select a claim") }
                    }
                } label: { Label(copied ? "Copied" : "Copy / Actions", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .disabled(workspace.masked || workspace.result == nil).accessibilityIdentifier("jwt-copy")
            }.frame(minHeight: 30)
            ZStack {
                if workspace.section == .claims && !workspace.masked && workspace.result != nil { claims }
                if workspace.section == .signature && !workspace.masked && workspace.result != nil { signature }
                decodedEditor(.header, commands: headerCommands)
                decodedEditor(.payload, commands: payloadCommands)
                if workspace.masked { maskCover }
                else if workspace.result == nil { ContentUnavailableView("Inspect a token", systemImage: "text.magnifyingglass", description: Text("Paste or enter a JWT, then choose Decode.")) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.clipped()
    }
    private func decodedEditor(_ part: JWTComponent, commands: JSONEditorCommands) -> some View {
        let active = (part == .header && workspace.section == .header) || (part == .payload && workspace.section == .payload)
        let visible = active && !workspace.masked && workspace.result != nil
        let data = workspace.result?.parts[part]
        let raw = workspace.preferences.jsonPresentation == .raw || data?.presentation == nil
        return VStack(alignment: .leading, spacing: 5) {
            Picker("JSON presentation", selection: $workspace.preferences.jsonPresentation) {
                ForEach(JWTPreferences.Presentation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("jwt-json-presentation")
            if data?.text != nil && data?.presentation == nil && workspace.preferences.jsonPresentation == .formatted {
                Text(data?.document == nil ? "Raw decoded text · no claims interpretation available" : "Formatted view exceeds display budget · showing complete Raw JSON").font(.caption).foregroundStyle(.secondary)
            }
            JSONTextEditor(text: .constant(workspace.display(part)), editable: false,
                diagnostic: raw ? (part == .header ? workspace.headerDiagnostic : workspace.payloadDiagnostic) : nil,
                jumpTarget: part == .header ? workspace.headerTarget : workspace.payloadTarget, jumpRequest: workspace.jumpRequest,
                animateJumps: !reduced, highlightJumps: true, focusOnJump: false, commands: commands, options: jsonOptions,
                presentationHidden: !visible, usesPrivacyContainer: true, placeholder: "No decoded JSON available.", contentName: "JWT \(part.rawValue)")
                .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
    }
    private var claims: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack { timeControls; Spacer() }
                VStack(alignment: .leading) { timeControls }
            }
            if let evaluation = workspace.evaluation {
                Text(evaluation.evaluatedAt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let missing = workspace.result?.missingTimeClaims, !missing.isEmpty {
                    Text("Not provided: " + missing.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(evaluation.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
            JSONTreeTable(rows: workspace.result?.claimRows ?? [], rowNumbers: workspace.result?.claimRowNumbers ?? [:],
                version: workspace.renderVersion, rowsVersion: workspace.rowsVersion, changes: nil, animate: false,
                selection: workspace.selection, scrollRequest: claimScrollRequest, scrollTarget: claimScrollTarget,
                row: { id in AnyView(claimRow(id)) }, select: { workspace.selection = $0 }, key: claimKey,
                preferredRowHeight: claimRowHeight, tableIdentifier: "jwt-claims", suppressSoftwareKeyboard: true, heightForID: claimHeight)
            if let id = workspace.selection, let claim = workspace.result?.claims.first(where: { $0.id == id }) {
                actionLayout {
                    Text(claim.namePreview).font(.callout).lineLimit(1); Spacer()
                    Button("Show in Payload") { cancelJumps(); withAnimation(motion) { workspace.showClaim(id) } }
                    Menu("Actions") { claimActions(id) }.accessibilityIdentifier("jwt-claim-actions")
                }
            }
            if workspace.result?.claims.isEmpty == true {
                Text("No claims available. An empty claims object is allowed; inspect any reported issues.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func claimRow(_ id: Int) -> some View {
        if let result = workspace.result, let number = result.claimRowNumbers[id], result.claims.indices.contains(number - 1) {
            let claim = result.claims[number - 1]
            Button { workspace.selection = id } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(claim.namePreview).fontWeight(.medium).lineLimit(1); Spacer(); Text(claim.kind.rawValue).font(.caption).foregroundStyle(.secondary) }
                    Text(claim.preview).font(.system(.callout, design: .monospaced)).foregroundStyle(claimColor(claim.kind)).lineLimit(1)
                    Text(claim.ambiguous ? "Ambiguous · duplicate claim" : claim.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let observation = workspace.evaluation?.values[id] {
                        Text(observation.status).font(.caption).fontWeight(.medium).lineLimit(1)
                        Text(observation.date).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.padding(.horizontal, 8).padding(.vertical, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(workspace.selection == id ? Color.green.opacity(0.12) : .clear).contentShape(Rectangle())
            }.buttonStyle(.plain).contextMenu { claimActions(id) }.accessibilityIdentifier("jwt-claim-\(id)")
        }
    }
    private func claimHeight(_ id: Int) -> CGFloat {
        guard let result = workspace.result, let number = result.claimRowNumbers[id], result.claims.indices.contains(number - 1) else { return claimRowHeight }
        return result.claims[number - 1].numericDate == nil ? claimRowHeight : timeClaimRowHeight
    }
    private func claimColor(_ kind: JSONStructureNode.Kind) -> Color {
        switch kind { case .string: .green; case .number: .blue; case .boolean, .null: .purple; case .object, .array: .secondary }
    }
    private func claimKey(_ key: JSONTreeTable.TreeKey) {
        guard let result = workspace.result else { return }
        if key == .copy { if let id = workspace.selection { copy(.fragment(id)) }; return }
        guard key == .up || key == .down, !result.claimRows.isEmpty else { return }
        let current = workspace.selection.flatMap { result.claimRowNumbers[$0] }.map { $0 - 1 } ?? -1
        let next = min(result.claimRows.count - 1, max(0, current + (key == .up ? -1 : 1)))
        workspace.selection = result.claimRows[next]
        claimScrollTarget = result.claimRows[next]; claimScrollRequest += 1
    }
    private var timeControls: some View {
        actionLayout {
            Picker("Time zone", selection: $workspace.preferences.timeZoneMode) {
                ForEach(JWTPreferences.Zone.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("jwt-timezone")
            Button("Refresh time", systemImage: "arrow.clockwise") { workspace.refreshTime() }.disabled(workspace.result == nil)
        }.fixedSize(horizontal: !accessibleLayout, vertical: true)
    }
    @ViewBuilder private func claimActions(_ id: Int) -> some View {
        Button("Show in Payload") { cancelJumps(); withAnimation(motion) { workspace.showClaim(id) } }
        Button("Copy Value") { copy(.value(id)) }.disabled(workspace.copy(.value(id)) == nil)
        Button("Copy JSON Fragment") { copy(.fragment(id)) }
    }
    private var signature: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(workspace.result?.trust ?? "Signature not verified", systemImage: "exclamationmark.shield").font(.headline)
                Text("The declaration and signature are untrusted. No key, algorithm policy or cryptographic verification is applied.").foregroundStyle(.secondary)
                if let result = workspace.result {
                    Text("Declared algorithm: \(JSONTreePreview.make(result.algorithm ?? "Unknown", budget: 80).text)")
                    if let part = result.parts[.signature] {
                        Text(part.bytes.map { "Signature: \($0.count) decoded bytes" } ?? "Signature bytes unavailable")
                        Text(part.bytes?.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ") ?? "Not decoded")
                            .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Text("Hex preview · at most 64 bytes. Copy Encoded Signature returns the original full segment.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
    private var maskCover: some View {
        VStack(spacing: 10) { Image(systemName: "eye.slash").font(.title2); Text("Sensitive content hidden"); Text("Use Reveal data to inspect or copy.").font(.caption) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background).accessibilityElement(children: .combine)
    }
    private func split(wide: Bool, length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.35))
            .frame(width: wide ? 4 : 34, height: wide ? 34 : 4).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                guard !workspace.inputCollapsed else { return }
                if dragStart == nil { dragStart = workspace.fraction }
                workspace.fraction = min(0.75, max(0.25, (dragStart ?? 0.4) + (wide ? value.translation.width : value.translation.height) / max(1, length - 16)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Panel proportions").accessibilityAdjustableAction { direction in workspace.fraction = min(0.75, max(0.25, workspace.fraction + (direction == .increment ? 0.05 : -0.05))) }
    }
    private func cancelJumps() { inputCommands.cancelNavigation?(); headerCommands.cancelNavigation?(); payloadCommands.cancelNavigation?() }
    private func show(_ anchor: JWTAnchor) { cancelJumps(); withAnimation(motion) { workspace.show(anchor) } }
    private func copy(_ kind: JWTWorkspaceSession.Copy) {
        guard let text = workspace.copy(kind) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copied = true
    }
}

/// Input collapses; all native editors keep stable identities across axis changes.
struct JWTPanelLayout: Layout {
    var horizontal: Bool
    var fraction: Double
    var collapse: Double
    init(horizontal: Bool, fraction: Double, collapsed: Bool) { self.horizontal = horizontal; self.fraction = fraction; collapse = collapsed ? 1 : 0 }
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(fraction, collapse) }
        set { fraction = newValue.first; collapse = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let total = max(0, (horizontal ? bounds.width : bounds.height) - 16)
        // A wide collapsed input retains enough width for its Edit Input control.
        let minimum = min(total, horizontal ? 110.0 : 36.0)
        let first = total * fraction * (1 - collapse) + minimum * collapse
        let sizes: [CGFloat] = [first, 16, max(0, total - first)]
        var offset: CGFloat = 0
        for index in 0..<3 {
            subviews[index].place(at: .init(x: bounds.minX + (horizontal ? offset : 0), y: bounds.minY + (horizontal ? 0 : offset)), anchor: .topLeading,
                proposal: .init(width: horizontal ? sizes[index] : bounds.width, height: horizontal ? bounds.height : sizes[index]))
            offset += sizes[index]
        }
    }
}
