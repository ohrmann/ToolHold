import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct BasicAuthHeaderView: View {
    @Bindable var workspace: BasicAuthWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var usernameCommands = BasicAuthFieldCommands()
    @State private var passwordCommands = BasicAuthFieldCommands()
    @State private var copied: String?
    @ScaledMetric(relativeTo: .body) private var fieldHeight = 36.0
    private var motion: Animation? { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") ? nil : .easeInOut(duration: 0.2) }
    private var errorCount: Int { (workspace.result?.issues.filter(\.isError).count ?? 0) + (workspace.rejectedInput == nil ? 0 : 1) }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack { operations; Spacer(minLength: 0); options }
                        VStack(alignment: .leading, spacing: 8) { operations; options }
                    }
                    let layout = geometry.size.width >= 720 && !typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                    layout { credentials; header }
                    Label("Base64 is reversible. Use Basic authentication only over HTTPS.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(14)
                    .animation(motion, value: workspace.showPassword)
                    .animation(motion, value: workspace.showHeader)
                    .animation(motion, value: errorCount)
                    .animation(motion, value: workspace.result?.issues.count ?? 0)
            }
        }.navigationTitle("HTTP Basic Auth Header Builder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { workspace.hideSensitiveData() }
        .onChange(of: workspace.sourceRevision) { _, _ in copied = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { workspace.hideSensitiveData() } }
    }
    private var operations: some View {
        HStack {
            Button("Build Header", systemImage: "key") { workspace.run() }
                .keyboardShortcut(.return, modifiers: .command).disabled(workspace.busy).accessibilityIdentifier("basic-auth-build")
            Button("Clear", systemImage: "trash") {
                usernameCommands.clear?(); passwordCommands.clear?(); workspace.clear(); copied = nil
            }.help("Clear credentials and their editing history. Cannot be undone.").accessibilityIdentifier("basic-auth-clear")
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var options: some View {
        Menu {
            Toggle("Normalize to NFC", isOn: $workspace.preferences.normalizeNFC).disabled(workspace.preferences.encoding != .utf8)
            Text("Enable for a server expecting UTF-8 with NFC. Input stays unchanged.")
        } label: { Label("Options", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("basic-auth-options")
    }
    private var credentials: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credentials").font(.headline)
            Text("Username").font(.subheadline)
            BasicAuthCredentialField(text: $workspace.username, field: .username, commands: usernameCommands, reject: workspace.reject) { passwordCommands.focus?() }
                .frame(height: fieldHeight)
            issues(.username)
            Text("Password").font(.subheadline)
            BasicAuthCredentialField(text: $workspace.password, field: .password, commands: passwordCommands, reject: workspace.reject) { workspace.run() }
                .frame(height: fieldHeight)
            issues(.password)
            Button(workspace.showPassword ? "Hide password" : "Show password", systemImage: workspace.showPassword ? "eye.slash" : "eye") { workspace.showPassword.toggle() }
                .accessibilityIdentifier("basic-auth-show-password")
            if workspace.showPassword {
                Text(BasicAuthProcessor.passwordPreview(workspace.password).isEmpty ? "Empty password" : BasicAuthProcessor.passwordPreview(workspace.password))
                    .font(.system(.body, design: .monospaced)).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("basic-auth-password-preview").transition(.identity)
            }
            Picker("Encoding", selection: $workspace.preferences.encoding) {
                ForEach(BasicAuthEncoding.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("basic-auth-encoding")
            Text(workspace.preferences.encoding == .utf8 ? "UTF-8. Server compatibility depends on its expected encoding." : "Latin-1 compatibility mode. Characters outside Latin-1 are rejected.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Header").font(.headline)
                Spacer()
                Button(workspace.showHeader ? "Hide" : "Reveal", systemImage: workspace.showHeader ? "eye.slash" : "eye") { workspace.showHeader.toggle() }
                    .disabled(workspace.result?.artifact == nil).accessibilityIdentifier("basic-auth-reveal-header")
            }
            if let artifact = workspace.result?.artifact, workspace.showHeader {
                JSONTextEditor(text: .constant(artifact.fullHeader), editable: false,
                    options: .init(syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: true), contentName: "Authorization header")
                    .frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("basic-auth-output").transition(.identity)
            } else {
                Text(workspace.result?.artifact == nil ? "Build a header from your credentials." : "Authorization: Basic ••••••••")
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).accessibilityIdentifier("basic-auth-mask")
            }
            ViewThatFits(in: .horizontal) {
                HStack { copyButtons }
                VStack(alignment: .leading) { copyButtons }
            }
            HStack {
                Label(workspace.statusText, systemImage: statusSymbol).accessibilityIdentifier("basic-auth-status")
                if workspace.busy { Button("Cancel") { workspace.cancel() }.accessibilityIdentifier("basic-auth-cancel") }
            }.font(.subheadline).frame(minHeight: 24)
            issues(.options)
            let notes = workspace.result?.issues.filter { !$0.isError } ?? []
            ForEach(Array(notes.enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
    }
    @ViewBuilder private var copyButtons: some View {
        Button(copied == "header" ? "Copied Header" : "Copy Header", systemImage: "doc.on.doc") { copy(true) }
            .disabled(!workspace.canCopy).accessibilityIdentifier("basic-auth-copy-header")
        Button(copied == "value" ? "Copied Value" : "Copy Value", systemImage: "doc.on.doc") { copy(false) }
            .disabled(!workspace.canCopy).accessibilityIdentifier("basic-auth-copy-value")
    }
    @ViewBuilder private func issues(_ field: BasicAuthField) -> some View {
        if let rejected = workspace.rejectedInput, rejected.field == field {
            Label(rejected.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("basic-auth-rejected")
        }
        ForEach(Array((workspace.result?.issues.filter { $0.isError && $0.field == field } ?? []).enumerated()), id: \.offset) { _, issue in
            Label(issue.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var statusSymbol: String {
        if workspace.busy { return "hourglass" }
        if workspace.wasCancelled { return "stop.circle" }
        if workspace.result?.status == .success { return "checkmark.circle" }
        return workspace.result == nil ? "circle.dotted" : "exclamationmark.triangle"
    }
    private func copy(_ full: Bool) {
        guard let value = workspace.copyText(fullHeader: full) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true])
        #endif
        copied = full ? "header" : "value"
    }
}
