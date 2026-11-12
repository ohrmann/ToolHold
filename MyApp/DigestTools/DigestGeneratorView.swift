import SwiftUI
import UniformTypeIdentifiers

struct HashGeneratorView: View {
    let workspace: DigestWorkspaceSession
    var body: some View { DigestGeneratorView(workspace: workspace).navigationTitle("Hash & Checksum Generator") }
}
struct HMACGeneratorView: View {
    let workspace: DigestWorkspaceSession
    var body: some View { DigestGeneratorView(workspace: workspace).navigationTitle("HMAC Generator") }
}
struct DigestGeneratorView: View {
    @Bindable var workspace: DigestWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var messageCommands = DigestEditorCommands()
    @State private var keyCommands = DigestEditorCommands()
    @State private var chooseFile = false
    @State private var pickerError: String?
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var keyHeight = 100.0
    private var hmac: Bool { workspace.isHMAC }
    private var fileMode: Bool { workspace.preferences.mode == .file }
    private var motion: Animation? { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") ? nil : .easeInOut(duration: 0.2) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            VStack(alignment: .leading, spacing: 8) {
                controls(wide: wide)
                status
                layout {
                    message.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(height: wide ? nil : max(130, geometry.size.height * (hmac ? 0.25 : 0.32)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if hmac { keyPanel }
                            results
                            if !hmac { comparison }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(1)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("digest-results-scroll")
                }
            }.padding(14)
                .animation(motion, value: workspace.compareExpanded)
                .animation(motion, value: workspace.issue?.message)
                .animation(motion, value: workspace.keyIssue?.message)
        }
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result { case .success(let urls): if let url = urls.first { workspace.chooseFile(url); pickerError = nil }
            case .failure: pickerError = "File selection could not be completed. Try again." }
        }
        .onChange(of: phase) { _, phase in if phase == .background { resign(); workspace.concealSecrets() } }
        .onChange(of: workspace.current) { _, _ in copied = false }
        .onDisappear { resign() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { resign() } } }
        #endif
    }
    private func resign() { messageCommands.resignFocus?(); keyCommands.resignFocus?() }
    private func controls(wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            if hmac {
                Picker("Algorithm", selection: $workspace.preferences.hmac) {
                    ForEach(DigestAlgorithm.hmac, id: \.self) { Text("HMAC-" + $0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("digest-algorithm")
            } else {
                Menu {
                    ForEach(DigestAlgorithm.allCases, id: \.self) { algorithm in
                        Toggle(algorithm.title + " · " + algorithm.note, isOn: Binding(get: { workspace.preferences.algorithms.contains(algorithm) }, set: { selected in
                            var values = Set(workspace.preferences.algorithms)
                            if selected { values.insert(algorithm) } else { values.remove(algorithm) }
                            workspace.preferences.algorithms = DigestAlgorithm.allCases.filter { values.contains($0) }
                        }))
                    }
                } label: { Label(workspace.preferences.algorithms.isEmpty ? "Choose algorithms" : workspace.preferences.algorithms.map(\.title).joined(separator: ", "), systemImage: "number.circle").lineLimit(1) }
                    .accessibilityIdentifier("digest-algorithms")
            }
            HStack(spacing: 12) {
                Button(hmac ? "Generate HMAC" : "Calculate", systemImage: "play") { workspace.run(); copied = false }
                    .keyboardShortcut(.return, modifiers: .command).disabled(!workspace.canRun).accessibilityIdentifier("digest-run")
                Button("Clear", systemImage: "trash") { resign(); messageCommands.clear?(); keyCommands.clear?(); workspace.clear(); pickerError = nil; copied = false }
                    .help("Clear working data and input Undo history.").accessibilityIdentifier("digest-clear")
                Menu { Button("Reset Settings") { resign(); workspace.resetSettings() } } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Options")
            }
        }
    }
    private var status: some View {
        HStack(alignment: .center, spacing: 8) {
            Label(pickerError ?? workspace.status, systemImage: workspace.issue == nil || workspace.issue?.status == .cancelled ? "info.circle" : "exclamationmark.triangle")
                .font(.caption).lineLimit(2).accessibilityIdentifier("digest-status")
            Spacer(minLength: 0)
            if workspace.busy { Button("Cancel") { workspace.cancel() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("digest-cancel") }
            if let issue = workspace.issue, let range = issue.range {
                Button("Show Error") { showError(issue, range: range) }
                    .accessibilityIdentifier("digest-show-error")
            }
        }.frame(minHeight: 32)
    }
    private var message: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(hmac ? "Message" : "Input").font(.headline)
                Spacer()
                Picker("Source", selection: Binding(get: { workspace.preferences.mode }, set: { resign(); workspace.preferences.mode = $0 })) {
                    ForEach(DigestSourceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).accessibilityLabel("Message source").accessibilityIdentifier("digest-source")
            }
            ZStack(alignment: .topLeading) {
                DigestNativeEditor(text: $workspace.text, commands: messageCommands, visible: !fileMode,
                                   fieldLabel: hmac ? "HMAC message" : "Hash input", fieldIdentifier: "digest-message")
                    .opacity(fileMode ? 0 : 1).allowsHitTesting(!fileMode).accessibilityHidden(fileMode)
                if fileMode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workspace.file?.name ?? "No file selected").font(.body).lineLimit(3).accessibilityIdentifier("digest-file-name")
                        if let size = workspace.file?.size { Text("\(size) bytes").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button(workspace.file == nil ? "Choose File" : "Replace File") { resign(); chooseFile = true }.accessibilityIdentifier("digest-choose-file")
                            if workspace.file != nil { Button("Remove") { workspace.removeFile() } }
                        }
                        Text("Reads original bytes locally. No file contents are saved.").font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.background)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)).allowsHitTesting(false))
            Text(fileMode ? "Choose one regular file. Calculate reads it again each time." : workspace.preferences.mode == .text ? "Exact UTF-8 · spaces, Unicode, BOM and line endings are preserved." : "Strict encoding · no whitespace or automatic repairs.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var keyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Secret key").font(.headline)
                Spacer()
                Button(workspace.keyHidden ? "Reveal" : "Hide", systemImage: workspace.keyHidden ? "eye" : "eye.slash") {
                    keyCommands.resignFocus?(); workspace.keyHidden.toggle()
                }.accessibilityIdentifier("digest-key-visibility")
            }
            Picker("Key encoding", selection: $workspace.preferences.keyProfile) {
                ForEach(ExactByteProfile.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("digest-key-profile")
            ZStack {
                DigestNativeEditor(text: $workspace.key, commands: keyCommands, visible: !workspace.keyHidden, fieldLabel: "Secret key", fieldIdentifier: "digest-key")
                    .opacity(workspace.keyHidden ? 0 : 1).allowsHitTesting(!workspace.keyHidden).accessibilityHidden(workspace.keyHidden)
                if workspace.keyHidden { Text("Secret key hidden").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background) }
            }.frame(height: max(80, keyHeight)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
            if let count = workspace.keyCount {
                Text("\(count) decoded key bytes\(count > 0 && count < workspace.preferences.hmac.count ? " · short key, use sufficient random bytes for security" : "")")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("digest-key-count")
            }
            if let issue = workspace.keyIssue { Label(issue.message, systemImage: "exclamationmark.triangle").font(.caption).fixedSize(horizontal: false, vertical: true) }
            Toggle("Allow empty key for test vectors", isOn: $workspace.allowEmptyKey).font(.caption).accessibilityIdentifier("digest-empty-key")
            if workspace.allowEmptyKey { Text("Test mode permits an empty key. It provides no secret-key protection.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(hmac ? "HMAC" : "Results").font(.headline)
                Spacer()
                if hmac {
                    Button(workspace.resultHidden ? "Reveal" : "Hide", systemImage: workspace.resultHidden ? "eye" : "eye.slash") { workspace.resultHidden.toggle() }.accessibilityIdentifier("digest-result-visibility")
                } else { Button("Copy All") { workspace.copyAll(publish: publish) }.disabled(!workspace.canCopy).accessibilityIdentifier("digest-copy-all") }
            }
            Picker("Output", selection: $workspace.preferences.format) {
                ForEach(DigestFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("digest-output-format")
            if workspace.preferences.format == .hex { Toggle("Uppercase hex", isOn: $workspace.preferences.uppercase).font(.caption) }
            if workspace.artifact == nil {
                Text(hmac ? "Enter a message and key, then Generate HMAC." : "Choose input and algorithms, then Calculate. Empty input is valid.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }
            ForEach(workspace.displayedAlgorithms, id: \.self) { algorithm in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text((hmac ? "HMAC-" : "") + algorithm.title).font(.subheadline.bold())
                        Spacer()
                        Button("Copy", systemImage: copied ? "checkmark" : "doc.on.doc") { workspace.copy(algorithm, publish: publish) }
                            .disabled(!workspace.canCopy).accessibilityIdentifier("digest-copy-" + algorithm.rawValue)
                    }
                    if !hmac { Text(algorithm.note).font(.caption).foregroundStyle(.secondary) }
                    if hmac && workspace.resultHidden { Text("••••••••").font(.body.monospaced()).accessibilityLabel("HMAC hidden") }
                    else { Text(workspace.value(algorithm) ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("digest-value-" + algorithm.rawValue) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
            }
        }
    }
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { workspace.compareExpanded.toggle() } label: {
                Label("Compare expected digest", systemImage: workspace.compareExpanded ? "chevron.down" : "chevron.right")
            }.accessibilityIdentifier("digest-compare-toggle")
            if workspace.compareExpanded {
                Picker("Algorithm", selection: $workspace.expectedAlgorithm) {
                    ForEach(workspace.displayedAlgorithms.isEmpty ? DigestAlgorithm.allCases : workspace.displayedAlgorithms, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("digest-compare-algorithm")
                Picker("Expected encoding", selection: $workspace.preferences.expectedProfile) {
                    ForEach([ExactByteProfile.hex, .base64, .base64URL], id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("digest-expected-encoding")
                TextField("Expected digest", text: $workspace.expected).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().accessibilityIdentifier("digest-expected")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Label(workspace.comparison, systemImage: workspace.comparison == "Match" ? "checkmark.circle" : "info.circle")
                    .font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("digest-comparison")
                Text("Matching a digest does not establish file trust or verify a signature.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func showError(_ issue: DigestIssue, range: NSRange) {
        let source = issue.field == "key" ? workspace.key : workspace.text
        if issue.field == "key" { workspace.keyHidden = false }
        Task { @MainActor in
            // Wait cooperatively for a hidden retained native editor to be reattached.
            // Responder changes happen outside representable update callbacks.
            for _ in 0..<12 {
                guard workspace.issue?.range == range,
                      (issue.field == "key" ? workspace.key : workspace.text).utf8.elementsEqual(source.utf8),
                      issue.field != "key" || !workspace.keyHidden else { return }
                let commands = issue.field == "key" ? keyCommands : messageCommands
                if commands.showRange?(range) == true { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
    private func publish(_ value: String) { SecretClipboard.copy(value); copied = true }
}
