import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct IdentifierGeneratorView: View {
    @Bindable var workspace: IdentifierWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var alphabetCommands = IdentifierAlphabetCommands()
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var alphabetHeight = 68.0
    private var animate: Bool { !reduceMotion && !ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { animate ? .easeInOut(duration: 0.2) : nil }
    private var customVisible: Bool { workspace.preferences.kind == .nanoID && workspace.preferences.nanoAlphabetPreset == .custom }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                form(wide: geometry.size.width >= 720 && !typeSize.isAccessibilitySize)
                status
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Results").font(.headline)
                        Text(workspace.batch?.options.caption ?? "No identifiers yet").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Button("One per line") { workspace.copyAll(.lines, publish: publish) }.accessibilityIdentifier("identifier-copy-lines")
                        Button("JSON array") { workspace.copyAll(.json, publish: publish) }.accessibilityIdentifier("identifier-copy-json")
                    } label: { Label(copied ? "Copied" : "Copy All", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .disabled(!workspace.canCopy).accessibilityIdentifier("identifier-copy-all")
                }
                ZStack {
                    IdentifierResultsView(workspace: workspace, animate: animate, copy: copy)

                    if workspace.batch == nil {
                        ContentUnavailableView("Generate identifiers", systemImage: "number", description: Text("Choose a format and press Generate. Everything stays on this device."))
                            .allowsHitTesting(false).accessibilityIdentifier("identifier-empty")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
                details
            }.padding(14)
                .animation(motion, value: customVisible)
                .animation(motion, value: workspace.preferences.kind)
                .animation(motion, value: workspace.validationIssue?.message)
                .animation(motion, value: workspace.issue?.message)
                .animation(motion, value: workspace.showDetails)
                .animation(motion, value: workspace.batch?.options)
                .animation(motion, value: workspace.batch?.notes)
        }
        .navigationTitle("UUID v4/v7, ULID, NanoID Generator")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
        #endif
        .onDisappear { alphabetCommands.resignFocus?() }
        .onChange(of: workspace.batch?.id) { _, _ in copied = false }
    }
    private func form(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            layout {
                Picker("Format", selection: Binding(get: { workspace.preferences.kind }, set: { alphabetCommands.resignFocus?(); workspace.preferences.kind = $0 })) {
                    ForEach(IdentifierKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("identifier-kind")
                HStack(spacing: 10) {
                    Text("Count").fixedSize()
                    TextField("1–10,000", text: $workspace.countText)
                        .textFieldStyle(.roundedBorder).frame(width: 90).accessibilityLabel("Count").accessibilityIdentifier("identifier-count")
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Stepper("Count", onIncrement: { stepCount(1) }, onDecrement: { stepCount(-1) })
                        .labelsHidden().fixedSize().accessibilityIdentifier("identifier-count-stepper")
                }
                HStack(spacing: 10) {
                    Button("Generate", systemImage: "sparkles") { workspace.run(); copied = false }
                        .keyboardShortcut(.return, modifiers: .command).disabled(!workspace.canGenerate).accessibilityIdentifier("identifier-generate")
                    Button("Clear", systemImage: "trash") { alphabetCommands.resignFocus?(); alphabetCommands.clear?(); workspace.clear(); copied = false }
                        .help("Clear results and the custom alphabet. Cannot be undone.").accessibilityIdentifier("identifier-clear")
                }.fixedSize(horizontal: true, vertical: false)
            }
            modeOptions(wide: wide)
            // Remains mounted across mode/layout changes; native text, IME and Undo retain identity.
            IdentifierAlphabetEditor(text: $workspace.customAlphabet, commands: alphabetCommands, visible: customVisible)
                .frame(height: customVisible ? alphabetHeight : 0).clipped()
                .overlay { if customVisible { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)).allowsHitTesting(false) } }
                .accessibilityHidden(!customVisible).allowsHitTesting(customVisible)
            Text(explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("identifier-explanation")
            if let issue = workspace.validationIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("identifier-option-error")
            }
        }
    }
    @ViewBuilder private func modeOptions(wide: Bool) -> some View {
        switch workspace.preferences.kind {
        case .uuidV4, .uuidV7:
            Picker("UUID case", selection: $workspace.preferences.uuidCase) {
                ForEach(IdentifierCase.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("identifier-case")
        case .ulid:
            Toggle("Monotonic within this session", isOn: $workspace.preferences.ulidMonotonic)
                .toggleStyle(.switch).fixedSize().accessibilityIdentifier("identifier-monotonic")
        case .nanoID:
            let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            layout { lengthField; alphabetPicker }
            if workspace.preferences.nanoAlphabetPreset != .custom {
                Text(workspace.options.symbols).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }
    private var lengthField: some View {
        HStack {
            Text("Length").fixedSize()
            TextField("1–256", text: $workspace.lengthText).textFieldStyle(.roundedBorder).frame(width: 72)
                .accessibilityLabel("Length").accessibilityIdentifier("identifier-length")
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
    private var alphabetPicker: some View {
        Picker("Alphabet", selection: Binding(get: { workspace.preferences.nanoAlphabetPreset }, set: { alphabetCommands.resignFocus?(); workspace.preferences.nanoAlphabetPreset = $0 })) {
            ForEach(IdentifierAlphabet.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("identifier-alphabet")
    }
    private var explanation: String {
        switch workspace.preferences.kind {
        case .uuidV4: return "Random identifiers using secure system randomness. Collisions are possible; identifiers are not authentication secrets."
        case .uuidV7: return "Contains creation time. Time-ordered; order within a millisecond is not guaranteed."
        case .ulid: return workspace.preferences.ulidMonotonic
            ? "Contains creation time. Monotonic only within this window’s sequence; Clear starts a new sequence. Not an authentication secret."
            : "Contains creation time. Random order within the same millisecond."
        case .nanoID:
            guard workspace.validationIssue == nil else { return "Choose a preset or enter an exact alphabet. Spaces, Unicode and repeated characters are not accepted." }
            let symbols = workspace.options.symbols
            let bits = Double(workspace.options.nanoLength) * log2(Double(symbols.utf8.count))
            let safe = symbols.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
            return "\(symbols.utf8.count) symbols · Random bits ≈ \(Int(bits.rounded())) · \(safe ? "URL-safe" : "Not URL-safe")." + (bits < 122 ? " Smaller identifier space than UUID v4." : "")
        }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(workspace.issue == nil || workspace.issue?.status == .cancelled ? workspace.statusText : "Generation failed", systemImage: workspace.issue == nil ? "info.circle" : "exclamationmark.circle")
                    .font(.subheadline).lineLimit(2).accessibilityIdentifier("identifier-status")
                Spacer(minLength: 0)
                if workspace.busy || workspace.copying {
                    Button("Cancel") { workspace.cancel() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("identifier-cancel")
                }
            }.frame(minHeight: 30)
            if let issue = workspace.issue, issue.status != .cancelled {
                Text(issue.message).font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("identifier-error")
            }
            if let batch = workspace.batch {
                ForEach(batch.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { workspace.showDetails.toggle() } label: {
                    HStack {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(workspace.showDetails ? 90 : 0))
                        Text("Selected ID")
                    }
                }.accessibilityLabel(workspace.showDetails ? "Collapse selected ID" : "Expand selected ID")
                    .disabled(workspace.selectedValue == nil).accessibilityIdentifier("identifier-details")
                Spacer(minLength: 0)
                Button("Copy ID", systemImage: "doc.on.doc") { if let index = workspace.selection { copy(index) } }
                    .disabled(!workspace.canCopy || workspace.selectedValue == nil).accessibilityIdentifier("identifier-copy-selected")
            }
            if let batch = workspace.batch, batch.options.kind == .nanoID {
                Text("Batch alphabet: " + batch.options.symbols).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled).accessibilityIdentifier("identifier-batch-alphabet")
            }
            if workspace.showDetails, let value = workspace.selectedValue {
                ScrollView {
                    Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("identifier-full-value")
                }.frame(maxHeight: 120)
            }
        }
    }
    private func stepCount(_ delta: Int) { workspace.countText = String(min(10_000, max(1, (IdentifierWorkspaceSession.number(workspace.countText) ?? 1) + delta))) }
    private func copy(_ index: Int) { if let value = workspace.copyValue(at: index) { publish(value) } }
    private func publish(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true])
        #endif
        copied = true
    }
}

