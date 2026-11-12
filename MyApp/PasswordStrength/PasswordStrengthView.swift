import SwiftUI

struct PasswordStrengthView: View {
    @Bindable var workspace: PasswordStrengthWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var secureCommands = PasswordStrengthFieldCommands()
    @State private var plainCommands = PasswordStrengthFieldCommands()
    @State private var personalCommands = JSONEditorCommands()
    @State private var scenarios = false
    @State private var personal = false
    @State private var privacyCover = false
    @Environment(\.scenePhase) private var phase
    private var reduced: Bool { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration:0.2) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("Password").font(.headline); Spacer()
                    Toggle("Auto estimate",isOn:$workspace.autoEstimate).toggleStyle(.switch).font(.callout).fixedSize()
                }
                HStack(spacing:8) {
                    ZStack {
                        field(.concealed,commands:secureCommands).opacity(!workspace.revealed && !workspace.hidden ? 1 : 0).allowsHitTesting(!workspace.revealed && !workspace.hidden).accessibilityHidden(workspace.revealed || workspace.hidden)
                        field(.revealed,commands:plainCommands).opacity(workspace.revealed && !workspace.hidden ? 1 : 0).allowsHitTesting(workspace.revealed && !workspace.hidden).accessibilityHidden(!workspace.revealed || workspace.hidden)
                        if workspace.hidden { Text("Sensitive content hidden").foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
                    }.frame(height:44)
                    Button(workspace.revealed ? "Hide" : "Show") {
                        secureCommands.resignFocus?(); plainCommands.resignFocus?()
                        workspace.hidden = false; workspace.revealed.toggle()
                    }.accessibilityIdentifier("password-strength-reveal")
                }
                HStack {
                    Button("Estimate") { workspace.estimate() }.keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("password-strength-estimate")
                    Button("Paste") { (workspace.revealed ? plainCommands : secureCommands).paste?() }.disabled(workspace.hidden)
                    Button("Clear") { secureCommands.clear?(); plainCommands.clear?(); personalCommands.clear?(); personalCommands.purgeUndo?(); workspace.clear() }.accessibilityIdentifier("password-strength-clear")
                    Spacer(minLength:0)
                    Button(workspace.hidden ? "Reveal content" : "Hide sensitive content",systemImage:workspace.hidden ? "eye" : "eye.slash") {
                        secureCommands.resignFocus?(); plainCommands.resignFocus?(); personalCommands.resignFocus?(); workspace.hidden.toggle()
                    }.labelStyle(.iconOnly).help("Hide password and personal words")
                }.buttonStyle(.bordered).controlSize(.small)
                if let rejection = workspace.rejection { Label(rejection,systemImage:"exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                VStack(alignment:.leading,spacing:10) {
                    HStack {
                        if workspace.busy { ProgressView().controlSize(.small) }
                        Text(workspace.busy ? "Estimating…" : workspace.result?.message ?? "Enter a password to estimate.").font(.headline).accessibilityIdentifier("password-strength-status")
                        Spacer()
                        if let score = workspace.result?.score { Text("\(score) / 4").monospacedDigit().font(.headline) }
                    }.frame(minHeight:26)
                    HStack(spacing:5) {
                        ForEach(0..<5) { index in Capsule().fill((workspace.result?.score).map { index <= $0 ? Color.green.opacity(0.3+Double(index)*0.13) : Color.secondary.opacity(0.12) } ?? Color.secondary.opacity(0.12)).frame(height:6) }
                    }.accessibilityHidden(true)
                    Text("Estimated resistance to guessing · a model, not a security guarantee.").font(.caption).foregroundStyle(.secondary)
                    if let result = workspace.result, result.status == .estimated {
                        Text("\(result.characters) characters · \(result.utf8Bytes) UTF-8 bytes").font(.caption).foregroundStyle(.secondary)
                        if !result.warning.isEmpty { Label(result.warning,systemImage:"info.circle").font(.callout) }
                        ForEach(Array(result.suggestions.enumerated()),id:\.offset) { _,text in Text(text).font(.callout) }
                        if !result.patterns.isEmpty { Text("Patterns considered: "+result.patterns.joined(separator:", ")).font(.caption).foregroundStyle(.secondary) }
                        if result.limitedLanguageCoverage { Text("Unicode is preserved. The Common + English model has limited coverage for other languages and emoji.").font(.callout).foregroundStyle(.secondary) }
                    }
                }.securityToolPanel().animation(motion,value:workspace.result?.status)
                DisclosureGroup(isExpanded:Binding(get:{scenarios},set:{value in withAnimation(motion) {scenarios = value} })) {
                    VStack(alignment:.leading,spacing:12) {
                        if let guesses = workspace.result?.guesses {
                            Text(guesses.isFinite ? "Estimated guesses: ≈ 10^\(String(format:"%.1f",log10(max(1,guesses))))" : "Estimated guesses exceed the numeric display range.").font(.callout)
                            ForEach(PasswordAttackScenario.allCases,id:\.rawValue) { scenario in
                                VStack(alignment:.leading,spacing:2) { Text(scenario.rawValue).font(.caption).foregroundStyle(.secondary); Text(scenario.duration(guesses:guesses)).font(.callout) }
                            }
                        } else { Text("Estimate a password to compare attack scenarios.").foregroundStyle(.secondary) }
                        Text("These fixed guess rates are illustrative assumptions. They do not measure a real service, hash configuration or attacker's hardware.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,10)
                } label: { Text("Attack scenarios").font(.headline) }
                DisclosureGroup(isExpanded:Binding(get:{personal},set:{value in withAnimation(motion) {personal = value} })) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("Optional names, email or words an attacker may know. One per line, up to 10. Kept only in this session.").font(.caption).foregroundStyle(.secondary)
                        JSONTextEditor(text:$workspace.personalWords,commands:personalCommands,options:.init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false),presentationHidden:workspace.hidden,usesPrivacyContainer:true,privateUndo:true,placeholder:"Personal words (optional)",contentName:"Personal words",showsLineNumbers:false).frame(height:120).accessibilityHidden(workspace.hidden)
                    }.padding(.top,8)
                } label: { Text("Personal words (optional)").font(.headline) }
                Text("Entirely local · Common + English dictionaries · No breach lookup · No history").font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity,alignment:.topLeading)
        }.navigationTitle("Password Strength Estimator")
            .overlay { privacyOverlay }
            .onChange(of:phase) { _,value in privacyCover = value == .background }
    }
    @ViewBuilder private var privacyOverlay: some View {
        if privacyCover { Rectangle().fill(.background).overlay { Label("Sensitive content hidden",systemImage:"eye.slash").foregroundStyle(.secondary) } }
    }
    private func field(_ role: PasswordStrengthFieldRole,commands:PasswordStrengthFieldCommands) -> some View {
        PasswordStrengthField(text:$workspace.password,field:role,commands:commands,reject:{ workspace.rejection = $0.message },submit:{ workspace.estimate() },pasted:{ workspace.pasted() })
    }
}

