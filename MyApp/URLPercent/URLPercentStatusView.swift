import SwiftUI

struct URLPercentStatusView: View {
    let workspace: URLPercentWorkspaceSession
    let expanded: Bool
    let toggleDetails: () -> Void
    let show: (NSRange) -> Void
    let cancel: () -> Void
    private var issue: URLPercentIssue? { workspace.result?.issues.first { $0.severity == .error } ?? workspace.result?.issues.first }
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
            if workspace.lastIntent == .check { return "Percent encoding checked · \(result.byteCount) bytes" }
            return "\(workspace.options.direction == .encode ? "Encoded" : "Decoded") · \(result.byteCount) bytes"
        case .bytesOnly: return "Decoded bytes only · \(result.byteCount) bytes"
        case .invalidPercentEncoding: return "Invalid percent encoding"
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
                    .lineLimit(2).accessibilityIdentifier("url-percent-status")
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ZStack { if workspace.busy { ProgressView().controlSize(.mini) } }.frame(width: 14, height: 14)
                    Button("Cancel", action: cancel).controlSize(.small)
                }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy)
                    .accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 30)
            if let issue {
                Text(issue.message).font(.callout).lineLimit(3).help(issue.message).textSelection(.enabled)
                    .accessibilityIdentifier("url-percent-message")
                HStack {
                    if let line = issue.line, let column = issue.column {
                        Text("Line \(line), column \(column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let range = issue.range {
                        Button("Show Input") { show(range) }.accessibilityIdentifier("url-percent-show-input")
                    }
                    if let count = workspace.result?.issues.count, count > 1 || showsByteDetails || issue.context != nil {
                        Button(expanded ? "Hide details" : "Details") { toggleDetails() }
                    }
                }.controlSize(.small)
                if expanded, let result = workspace.result, result.issues.count > 1 || showsByteDetails || issue.context != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if let context = issue.context {
                                Text(context).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(Array(result.issues.dropFirst().enumerated()), id: \.offset) { _, note in
                                Text(note.message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if showsByteDetails {
                                Text("Bytes preview · first \(min(result.byteCount, URLPercentLimits.previewBytes)) of \(result.byteCount)")
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
