import SwiftUI

struct Base64StatusView: View {
    let workspace: Base64WorkspaceSession
    let expanded: Bool
    let toggleDetails: () -> Void
    let show: (NSRange) -> Void
    private var issue: Base64Issue? { workspace.result?.issues.first { $0.severity == .error } ?? workspace.result?.issues.first }
    private var showsByteDetails: Bool {
        guard let result = workspace.result, result.status == .success, !result.preview.isEmpty else { return false }
        return result.issues.contains { $0.code == .controls || $0.code == .leadingBOM }
    }
    private var title: String {
        if workspace.busy { return workspace.lastIntent == .check ? "Checking" : workspace.options.direction == .encode ? "Encoding" : "Decoding" }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .success:
            if result.byteCount == 0 { return "Empty result · 0 bytes" }
            if workspace.lastIntent == .check { return "Checked · \(result.byteCount) bytes" }
            return "\(workspace.options.direction == .encode ? "Encoded" : "Decoded") · \(result.byteCount) bytes"
        case .bytesOnly: return "Decoded bytes only · \(result.byteCount) bytes"
        case .invalidBase64: return "Invalid \(workspace.options.alphabet.title)"
        case .unrepresentableText: return "Cannot encode text"
        case .resourceLimit: return "Processing limit reached"
        case .cancelled: return "Cancelled"
        case .processingFailure: return "Processing failed"
        }
    }
    private var color: Color {
        if workspace.busy || workspace.wasCancelled || workspace.result == nil { return .secondary }
        if workspace.result?.status == .resourceLimit || workspace.result?.status == .bytesOnly { return .orange }
        return issue?.severity == .error ? .red : .secondary
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(title, systemImage: issue == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium)).foregroundStyle(color)
                    .lineLimit(2).accessibilityIdentifier("base64-status")
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Button("Cancel") { workspace.cancel() }.controlSize(.small)
                }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy)
                    .accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 30)
            if let issue {
                Text(issue.message).font(.callout).lineLimit(3).help(issue.message).textSelection(.enabled)
                    .accessibilityIdentifier("base64-message")
                HStack {
                    if let line = issue.line, let column = issue.column {
                        Text("Line \(line), column \(column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let range = issue.range {
                        Button("Show Input") { show(range) }.accessibilityIdentifier("base64-show-input")
                    }
                    if let count = workspace.result?.issues.count, count > 1 || showsByteDetails {
                        Button(expanded ? "Hide details" : "Details") { toggleDetails() }
                    }
                }.controlSize(.small)
                if expanded, let result = workspace.result, result.issues.count > 1 || showsByteDetails {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(result.issues.dropFirst().enumerated()), id: \.offset) { _, note in
                                Text(note.message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if showsByteDetails {
                                Text("Bytes preview · first \(min(result.byteCount, Base64Limits.previewBytes)) of \(result.byteCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(result.preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 82)
                }
            }
        }
    }
}
