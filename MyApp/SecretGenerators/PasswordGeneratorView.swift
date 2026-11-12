import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PasswordGeneratorView: View {
    let workspace: SecretGeneratorWorkspaceSession
    var body: some View { SecretGeneratorView(workspace: workspace).navigationTitle("Secure Password Generator") }
}
struct SecretGeneratorView: View {
    @Bindable var workspace: SecretGeneratorWorkspaceSession
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var alphabetCommands = IdentifierAlphabetCommands()
    @State private var exclusionCommands = IdentifierAlphabetCommands()
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var editorHeight = 54.0
    private var password: Bool { workspace.kind == .password }
    private var customVisible: Bool { password && workspace.advanced && workspace.mode == .custom }
    private var animate: Bool { !reduceMotion && !ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { animate ? .easeInOut(duration: 0.2) : nil }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760 && !typeSize.isAccessibilitySize
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    form(wide: wide).padding(.bottom, 2)
                }.frame(height: min(formHeight(wide: wide), max(120, geometry.size.height * 0.52)))
                status
                resultsHeader
                result
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
                metadata
            }.padding(14)
                .animation(motion, value: workspace.advanced)
                .animation(motion, value: workspace.mode)
                .animation(motion, value: workspace.validationIssue?.message)
                .animation(motion, value: workspace.showDetails)
                .animation(motion, value: workspace.batch?.options)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { resign() } } }
        #endif
        .onDisappear { resign() }
        .onChange(of: phase) { _, value in if value == .background { resign(); workspace.concealSecrets() } }
        .onChange(of: workspace.batch?.id) { _, _ in copied = false }
    }
    private func formHeight(wide: Bool) -> CGFloat {
        let base: CGFloat = password ? (wide ? 184 : 295) : (wide ? 110 : 225)
        let extra: CGFloat = workspace.advanced ? (password ? (customVisible ? editorHeight * 2 + 130 : editorHeight + 130) : 90) : 0
        return (base + extra + (workspace.validationIssue == nil ? 0 : 42)) * (typeSize.isAccessibilitySize ? 1.5 : 1)
    }
    private func form(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !password { Text("English · EFF · 7,776 words").font(.subheadline).foregroundStyle(.secondary) }
            let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            layout {
                let counts = wide ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                counts {
                    if password { number("Length", text: $workspace.lengthText, range: 8...128, id: "secret-length") }
                    else { number("Words", text: $workspace.wordsText, range: 4...16, id: "secret-words") }
                    number("Count", text: $workspace.countText, range: 1...1000, id: "secret-count")
                }
                HStack(spacing: 12) {
                    Button("Generate", systemImage: "sparkles") { workspace.run(); copied = false }
                        .keyboardShortcut(.return, modifiers: .command).disabled(!workspace.canGenerate).accessibilityIdentifier("secret-generate")
                    Button("Clear", systemImage: "trash") { resign(); alphabetCommands.clear?(); exclusionCommands.clear?(); workspace.clear(); copied = false }
                        .help("Clear results and custom character fields. Cannot be undone.").accessibilityIdentifier("secret-clear")
                }
            }
            if password { passwordOptions(wide: wide) } else { phraseOptions }
            Button {
                resign(); workspace.advanced.toggle()
            } label: {
                Label(workspace.advanced ? "Fewer options" : "More options", systemImage: workspace.advanced ? "chevron.up" : "chevron.down")
            }.accessibilityIdentifier("secret-advanced")
            advancedOptions
            if let issue = workspace.validationIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle").font(.caption)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("secret-option-error")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func number(_ label: String, text: Binding<String>, range: ClosedRange<Int>, id: String) -> some View {
        HStack(spacing: 6) {
            Text(label).fixedSize()
            TextField("\(range.lowerBound)–\(range.upperBound)", text: text)
                .textFieldStyle(.roundedBorder).frame(width: label == "Count" ? 66 : 52)
                .accessibilityLabel(label).accessibilityIdentifier(id)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Stepper(label, onIncrement: { step(text, 1, range) }, onDecrement: { step(text, -1, range) })
                .labelsHidden().fixedSize().accessibilityIdentifier(id + "-stepper")
        }
    }
    private func step(_ text: Binding<String>, _ delta: Int, _ range: ClosedRange<Int>) {
        text.wrappedValue = String(min(range.upperBound, max(range.lowerBound, (SecretGeneratorWorkspaceSession.number(text.wrappedValue) ?? range.lowerBound) + delta)))
    }
    private func passwordOptions(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = wide ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            layout {
                HStack(spacing: 16) {
                    Toggle("a–z", isOn: $workspace.preferences.lowercase).accessibilityLabel("Lowercase")
                    Toggle("A–Z", isOn: $workspace.preferences.uppercase).accessibilityLabel("Uppercase")
                }
                HStack(spacing: 16) {
                    Toggle("0–9", isOn: $workspace.preferences.digits).accessibilityLabel("Digits")
                    Toggle("Symbols", isOn: $workspace.preferences.symbols)
                        .help(PasswordOptions.punctuation)
                }
            }.toggleStyle(.checkboxIfAvailable).disabled(workspace.mode == .custom)
            Toggle("Require every selected group", isOn: $workspace.preferences.requireEveryGroup)
                .disabled(workspace.mode == .custom).accessibilityIdentifier("secret-require-groups")
            Text(workspace.mode == .custom ? "Uses your exact character alphabet." : "Group requirements help match website rules. Repeated characters are allowed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var phraseOptions: some View {
        Picker("Separator", selection: $workspace.preferences.separator) {
            ForEach(PassphraseSeparator.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("secret-separator")
    }
    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if password {
                if workspace.advanced {
                    Picker("Alphabet", selection: Binding(get: { workspace.mode }, set: { resign(); workspace.mode = $0 })) {
                        ForEach(PasswordAlphabetMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("secret-alphabet")
                }
                Text("Custom alphabet · printable ASCII, no spaces").font(.caption)
                    .frame(height: customVisible ? nil : 0).clipped().accessibilityHidden(!customVisible)
                IdentifierAlphabetEditor(text: $workspace.customAlphabet, commands: alphabetCommands, visible: customVisible,
                    fieldLabel: "Custom alphabet", fieldIdentifier: "secret-custom-alphabet")
                    .frame(height: customVisible ? editorHeight : 0).clipped().accessibilityHidden(!customVisible).allowsHitTesting(customVisible)
                    .overlay { if customVisible { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.25)).allowsHitTesting(false) } }
                if workspace.advanced {
                    Toggle("Exclude similar characters", isOn: $workspace.preferences.excludeSimilar)
                        .help("Excludes 0, O, 1, I, l and |.").accessibilityIdentifier("secret-exclude-similar")
                    Text("Exclude characters · printable ASCII, no spaces").font(.caption)
                }
                IdentifierAlphabetEditor(text: $workspace.exclusions, commands: exclusionCommands, visible: workspace.advanced,
                    fieldLabel: "Excluded characters", fieldIdentifier: "secret-exclusions")
                    .frame(height: workspace.advanced ? editorHeight : 0).clipped().accessibilityHidden(!workspace.advanced).allowsHitTesting(workspace.advanced)
                    .overlay { if workspace.advanced { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.25)).allowsHitTesting(false) } }
            } else if workspace.advanced {
                Picker("Case", selection: $workspace.preferences.letterCase) {
                    ForEach(PassphraseCase.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("secret-case")
                Toggle("Append a random digit", isOn: $workspace.preferences.appendDigit).accessibilityIdentifier("secret-append-digit")
            }
            if workspace.advanced {
                Button("Reset Settings") { resign(); alphabetCommands.clear?(); exclusionCommands.clear?(); workspace.resetSettings() }
                    .accessibilityIdentifier("secret-reset")
            }
        }
    }
    private var status: some View {
        HStack(alignment: .center) {
            Label(workspace.statusText, systemImage: workspace.issue == nil || workspace.issue?.status == .cancelled ? "info.circle" : "exclamationmark.triangle")
                .font(.caption).lineLimit(2).accessibilityIdentifier("secret-status")
            Spacer(minLength: 0)
            if workspace.busy || workspace.copying {
                Button("Cancel") { workspace.cancel() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("secret-cancel")
            }
        }.frame(minHeight: 30)
    }
    private var resultsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Results").font(.headline)
                Text(workspace.batch?.options.caption ?? "No results yet").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(workspace.hidden ? "Reveal" : "Hide", systemImage: workspace.hidden ? "eye" : "eye.slash") { workspace.toggleVisibility() }
                .disabled(workspace.batch == nil).accessibilityIdentifier("secret-visibility")
            Menu {
                Button("One per line") { workspace.copyAll(.lines, publish: publish) }.accessibilityIdentifier("secret-copy-lines")
                Button("JSON array") { workspace.copyAll(.json, publish: publish) }.accessibilityIdentifier("secret-copy-json")
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel(copied ? "Copied" : "Copy All").disabled(!workspace.canCopy).accessibilityIdentifier("secret-copy-all")
        }
    }
    @ViewBuilder private var result: some View {
        if let batch = workspace.batch, batch.values.count == 1 {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    secretText(batch.values[0], font: .system(.title3, design: .monospaced), id: "secret-single-value")
                    Button("Copy", systemImage: copied ? "checkmark" : "doc.on.doc") { copy(0) }
                        .frame(minHeight: 44).disabled(!workspace.canCopy).accessibilityIdentifier("secret-copy-single")
                }.padding(12)
            }
        } else {
            ZStack {
                SecretResultsView(workspace: workspace, animate: animate, copy: copy)
                if workspace.batch == nil {
                    ContentUnavailableView(password ? "Generate a password" : "Generate a passphrase", systemImage: "key",
                        description: Text("Choose settings and press Generate. Results stay in this window’s memory."))
                        .allowsHitTesting(false).accessibilityIdentifier("secret-empty")
                }
            }
        }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let batch = workspace.batch {
                Text("Generator entropy ≈ \(String(format: "%.1f", floor(batch.entropyBits * 10) / 10)) bits")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("secret-entropy")
                if batch.duplicateCount > 0 { Text("\(batch.duplicateCount) repeated results; repeats are allowed.").font(.caption).foregroundStyle(.secondary) }
            }
            if !password {
                Text(workspace.preferences.wordCount < 6 ? "Consider 6 or more words. Repeated words are allowed." : "Words are chosen independently; repeated words are allowed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if workspace.preferences.separator == .hyphen {
                    Text("Internal word hyphens are doubled to keep word boundaries unambiguous.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if workspace.batch != nil {
                HStack {
                    Button {
                        workspace.showDetails.toggle()
                    } label: { Label("Details", systemImage: workspace.showDetails ? "chevron.up" : "chevron.down") }
                        .accessibilityIdentifier("secret-details")
                    Spacer()
                    Button("Copy Selected") { if let index = workspace.selection { copy(index) } }
                        .disabled(!workspace.canCopy || workspace.selection == nil).accessibilityIdentifier("secret-copy-selected")
                }
                if workspace.showDetails {
                    Text("Entropy describes this generator’s choices, assuming secure uniform randomness. It does not predict cracking time.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let value = workspace.selectedValue {
                        ScrollView {
                            secretText(value, font: .system(.body, design: .monospaced), id: "secret-full-value")
                        }.frame(maxHeight: 100)
                    }
                }
            }
        }
    }
    @ViewBuilder private func secretText(_ value: String, font: Font, id: String) -> some View {
        Group {
            if workspace.hidden {
                // Remove the selectable native accessibility subtree entirely when concealing.
                Text("••••••••").accessibilityLabel("Hidden result")
            } else {
                Text(value).textSelection(.enabled).accessibilityLabel(value)
            }
        }.font(font).frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(id)
            .transaction { $0.animation = nil }
    }
    private func resign() {
        alphabetCommands.resignFocus?(); exclusionCommands.resignFocus?()
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    private func copy(_ index: Int) { if let value = workspace.copyValue(at: index) { publish(value) } }
    private func publish(_ value: String) { SecretClipboard.copy(value); copied = true }
}

private struct SecretGroupToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(configuration).toggleStyle(.checkbox)
        #else
        Toggle(configuration).toggleStyle(.switch)
        #endif
    }
}
private extension ToggleStyle where Self == SecretGroupToggleStyle {
    static var checkboxIfAvailable: Self { .init() }
}
