import SwiftUI
import UniformTypeIdentifiers

struct JWTVerifierView: View {
    @Bindable var workspace: JWTVerifierWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var tokenCommands = JSONEditorCommands()
    @State private var keyCommands = JWTSigningKeyCommands()
    @State private var fraction = 0.46
    @State private var policyExpanded = false
    @State private var headerExpanded = false
    @State private var payloadExpanded = false
    @State private var importing = false
    @State private var privacyCover = false
    private var reduced: Bool { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration:0.2) }
    private var plain: JSONEditorOptions { .init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:workspace.wordWrap) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack { operations; Spacer(); options }
                VStack(alignment:.leading) { operations; options }
            }
            HStack {
                if workspace.busy { ProgressView().controlSize(.small) }
                Text(workspace.busy ? "Verifying…" : workspace.cancelled ? "Cancelled" : workspace.result?.signature.rawValue ?? "Ready · choose an expected algorithm and key")
                    .font(.callout).accessibilityIdentifier("jwt-verifier-status")
                Spacer(minLength:0)
            }.frame(minHeight:26)
            GeometryReader { area in
                let wide = area.size.width >= 800
                SecurityToolPanelLayout(wide:wide,fraction:fraction,collapsed:false) {
                    input
                    SecurityPanelDivider(wide:wide,length:wide ? area.size.width : area.size.height,fraction:$fraction)
                    output
                }
            }
        }.padding(12).navigationTitle("JWT Signature Verifier")
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.plainText,.json],allowsMultipleSelection:false) { result in
                if case .success(let urls) = result, let url = urls.first { workspace.importKey(url) }
            }
            .overlay { if privacyCover { Rectangle().fill(.background).overlay { Label("Sensitive content hidden",systemImage:"eye.slash").foregroundStyle(.secondary) } } }
            .onChange(of:phase) { _,value in privacyCover = value == .background; if value == .active { workspace.checkClock() } }
    }
    private var operations: some View {
        HStack {
            Button("Verify") { workspace.run() }.keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("jwt-verifier-verify")
            Button("Paste Token") { if let text = SecurityToolClipboard.paste() { tokenCommands.replace?(.init(location:0,length:workspace.token.utf16.count),text); workspace.inspectPaste() } }.disabled(workspace.hidden)
            if workspace.busy { Button("Cancel") { workspace.cancel() } }
            Button("Clear") { tokenCommands.clear?(); tokenCommands.purgeUndo?(); keyCommands.clear?(); workspace.clear() }
        }.buttonStyle(.bordered).controlSize(.small)
    }
    private var options: some View {
        HStack {
            Toggle("Wrap",isOn:$workspace.wordWrap).toggleStyle(.button).controlSize(.small)
            Button(workspace.hidden ? "Reveal content" : "Hide sensitive content",systemImage:workspace.hidden ? "eye" : "eye.slash") {
                tokenCommands.resignFocus?(); keyCommands.resignFocus?(); workspace.hidden.toggle()
            }.labelStyle(.iconOnly).help("Hide token and key without clearing the session")
        }
    }
    private var input: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text("Token").font(.headline).id("token")
                    JSONTextEditor(text:$workspace.token,jumpTarget:workspace.target,jumpRequest:workspace.jumpRequest,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,onPaste:{ workspace.inspectPaste() },commands:tokenCommands,options:plain,presentationHidden:workspace.hidden,usesPrivacyContainer:true,privateUndo:true,placeholder:"Paste a compact signed JWT.",contentName:"JWT Verifier token",showsLineNumbers:false).frame(height:180).accessibilityHidden(workspace.hidden)
                    HStack {
                        Text("Token declares: "+(workspace.inspection?.algorithm ?? "Not inspected")+(workspace.result?.signature == .matches ? " · signature checked" : " · unverified")).font(.caption).foregroundStyle(.secondary)
                        Spacer(); Button("Inspect") { workspace.inspectPaste() }.controlSize(.small).disabled(workspace.hidden)
                    }
                    Text("Expected algorithm").font(.caption).foregroundStyle(.secondary)
                    Picker("Expected algorithm",selection:$workspace.algorithm) {
                        Text("Select algorithm").tag(nil as JWTSigningAlgorithm?)
                        ForEach(JWTSigningAlgorithm.allCases.filter { $0 != .none },id:\.self) { alg in Text(alg.title).tag(Optional(alg)) }
                    }.accessibilityIdentifier("jwt-verifier-algorithm")
                    Text("Verification uses your selected algorithm. The token cannot select it.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack { Text("Verification Key").font(.headline); Spacer(); Button("Open…") { importing = true }.controlSize(.small).disabled(workspace.hidden) }
                    Picker("Key source",selection:$workspace.format) { ForEach(JWTVerificationKeyFormat.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("jwt-verifier-key-source")
                    JWTSigningKeyEditor(text:$workspace.key,commands:keyCommands,visible:!workspace.hidden,contentName:"Verification key",identifier:"jwt-verifier-key").frame(height:155).accessibilityLabel("Verification key").accessibilityHidden(workspace.hidden)
                    if workspace.hidden { Text("Sensitive content hidden").font(.caption).foregroundStyle(.secondary) }
                    if workspace.format == .jwk {
                        Button("Read Local Keys") { workspace.loadKeys() }.disabled(workspace.hidden)
                        Picker("Selected key",selection:$workspace.keyIndex) {
                            Text("Select an entry explicitly").tag(nil as Int?)
                            ForEach(workspace.keyChoices) { key in Text(key.title+(key.supported ? "" : " · unsupported")).tag(Optional(key.id)).disabled(!key.supported) }
                        }.disabled(workspace.hidden || workspace.keyChoices.isEmpty)
                    }
                    if let issue = workspace.keyIssue { Label(issue,systemImage:"exclamationmark.triangle").font(.callout) }
                    DisclosureGroup(isExpanded:Binding(get:{policyExpanded},set:{value in withAnimation(motion) {policyExpanded = value} })) { policy.padding(.top,8) } label: { Text("Claims policy").font(.headline) }
                }.padding(2)
            }.onChange(of:workspace.jumpRequest) { _,_ in if workspace.target != nil { withAnimation(motion) { proxy.scrollTo("token",anchor:.top) } } }
        }.securityToolPanel()
    }
    private var policy: some View {
        VStack(alignment:.leading,spacing:10) {
            Toggle("Check exp / nbf when present",isOn:$workspace.policy.checkTime)
            Toggle("Require exp",isOn:$workspace.policy.requireExp)
            Toggle("Require nbf",isOn:$workspace.policy.requireNbf)
            Toggle("Require iat",isOn:$workspace.policy.requireIat)
            Toggle("Reject future iat",isOn:$workspace.policy.checkFutureIat)
            Stepper("Clock skew: \(workspace.policy.skew) s",value:$workspace.policy.skew,in:0...300)
            Toggle("Expected issuer",isOn:$workspace.policy.issuerEnabled)
            TextField("Exact issuer",text:$workspace.policy.issuer).textFieldStyle(.roundedBorder).disabled(!workspace.policy.issuerEnabled || workspace.hidden).privacySensitive().opacity(workspace.hidden ? 0 : 1).accessibilityHidden(workspace.hidden)
            Toggle("Expected audience",isOn:$workspace.policy.audienceEnabled)
            TextField("Exact audience",text:$workspace.policy.audience).textFieldStyle(.roundedBorder).disabled(!workspace.policy.audienceEnabled || workspace.hidden).privacySensitive().opacity(workspace.hidden ? 0 : 1).accessibilityHidden(workspace.hidden)
            Toggle("Expected subject",isOn:$workspace.policy.subjectEnabled)
            TextField("Exact subject",text:$workspace.policy.subject).textFieldStyle(.roundedBorder).disabled(!workspace.policy.subjectEnabled || workspace.hidden).privacySensitive().opacity(workspace.hidden ? 0 : 1).accessibilityHidden(workspace.hidden)
            Toggle("Custom reference time",isOn:$workspace.policy.customTime)
            if workspace.policy.customTime { DatePicker("Reference UTC",selection:$workspace.policy.reference).environment(\.timeZone,TimeZone(secondsFromGMT:0)!) }
            Text("Policy values are kept only in this session. Issuer/audience are not checked unless configured.").font(.caption).foregroundStyle(.secondary)
        }.font(.callout)
    }
    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if let result = workspace.result {
                        Label(result.signature.rawValue,systemImage:result.signature == .matches ? "checkmark.shield" : result.signature == .doesNotMatch ? "xmark.shield" : "shield.lefthalf.filled").font(.headline)
                        Text(result.message).font(.callout)
                        if !result.keyIdentity.isEmpty { Text(result.keyIdentity).font(.system(.caption,design:.monospaced)).textSelection(.enabled).lineLimit(4) }
                        ForEach(Array(result.keyNotes.enumerated()),id:\.offset) { _,note in Text(note).font(.caption).foregroundStyle(.secondary) }
                        if result.claimsEvaluated {
                            Text(workspace.timeStale ? "Recheck required · time verdict has expired" : result.claimsPassed ? "Configured claims checks passed" : "Claims checks failed").font(.headline).accessibilityIdentifier("jwt-verifier-claims-status")
                            ForEach(result.checks) { check in
                                Label("\(check.id): \(check.message)",systemImage:check.state == .passed ? "checkmark.circle" : check.state == .failed ? "xmark.circle" : "minus.circle").font(.callout)
                            }
                        } else { Text("Claims are unauthenticated / not evaluated.").font(.callout).foregroundStyle(.secondary) }
                        Text("Reference \(CertificateDisplay.date(result.referenceTime))").font(.caption).foregroundStyle(.secondary)
                        Text(result.policySummary).font(.caption).foregroundStyle(.secondary)
                        Button("Copy summary") { SecurityToolClipboard.copy(result.summary+(workspace.timeStale ? "\nTime checks require recheck." : "")) }
                    }
                    if let inspection = workspace.inspection {
                        ForEach(inspection.issues) { issue in
                            VStack(alignment:.leading,spacing:4) {
                                Label(issue.message,systemImage:issue.severity == .error ? "exclamationmark.triangle" : "info.circle").font(.callout)
                                if let location = issue.location { Text(location).font(.caption).foregroundStyle(.secondary) }
                                if !workspace.hidden, let context = issue.context { diagnosticContext(context).font(.system(.caption,design:.monospaced)).lineLimit(4) }
                                HStack {
                                    if issue.anchor != nil { Button("Show Detection") { reveal(issue) }.disabled(workspace.hidden) }
                                    if !issue.related.isEmpty { Button("Show Related") { reveal(issue,related:true) }.disabled(workspace.hidden) }
                                }.controlSize(.small)
                            }
                        }
                        jsonPart(.header,expanded:$headerExpanded).id("header")
                        jsonPart(.payload,expanded:$payloadExpanded).id("payload")
                    } else { ContentUnavailableView("Verify a signed JWT",systemImage:"signature",description:Text("Supply a token, an expected algorithm and your own verification key.")) }
                    Text("A matching signature does not establish key provenance, issuer trust, revocation or application authorization.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(2)
            }.onChange(of:workspace.jumpRequest) { _,_ in
                let id = workspace.headerTarget != nil ? "header" : workspace.payloadTarget != nil ? "payload" : nil
                if let id { withAnimation(motion) { proxy.scrollTo(id,anchor:.top) } }
            }
        }.securityToolPanel()
    }
    private func diagnosticContext(_ context: JSONDiagnosticContext) -> Text {
        let text = context.text as NSString, range = context.detectionRange
        return Text(text.substring(to:range.location)) + Text(text.substring(with:range)).bold().underline() + Text(text.substring(from:NSMaxRange(range)))
    }
    private func reveal(_ issue: JWTIssue,related:Bool = false) {
        withAnimation(motion) {
            workspace.show(issue,related:related)
            if workspace.headerTarget != nil { headerExpanded = true }; if workspace.payloadTarget != nil { payloadExpanded = true }
        }
    }
    private func jsonPart(_ part: JWTComponent,expanded:Binding<Bool>) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Button { withAnimation(motion) { expanded.wrappedValue.toggle() } } label: { Label(part.rawValue,systemImage:expanded.wrappedValue ? "chevron.down" : "chevron.right").font(.headline) }.buttonStyle(.plain)
            JSONTextEditor(text:.constant(workspace.inspection?.parts[part]?.text ?? ""),editable:false,jumpTarget:part == .header ? workspace.headerTarget : workspace.payloadTarget,jumpRequest:workspace.jumpRequest,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,options:.init(wordWrap:workspace.wordWrap),presentationHidden:workspace.hidden,usesPrivacyContainer:true,contentName:"JWT Verifier decoded \(part.rawValue)")
                .frame(height:expanded.wrappedValue ? 240 : 0).opacity(expanded.wrappedValue ? 1 : 0).clipped().allowsHitTesting(expanded.wrappedValue && !workspace.hidden).accessibilityHidden(!expanded.wrappedValue || workspace.hidden)
        }
    }
}
