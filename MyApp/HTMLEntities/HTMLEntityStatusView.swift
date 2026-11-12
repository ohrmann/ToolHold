import SwiftUI

struct HTMLEntityStatusView: View {
    let workspace: HTMLEntityWorkspaceSession
    let expanded: Bool
    let toggleDetails: () -> Void
    let show: (NSRange) -> Void
    let cancel: () -> Void
    private var issue: HTMLEntityIssue? { workspace.result?.issues.first { $0.severity == .error } ?? workspace.result?.issues.first }
    private var title: String {
        if workspace.busy { return workspace.lastIntent == .check ? "Checking" : workspace.options.direction == .encode ? "Encoding" : "Decoding" }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .success, .successWithWarnings:
            let action = workspace.lastIntent == .check ? "Checked" : workspace.options.direction == .encode ? "Encoded" : "Decoded"
            return action + (result.issueCount > 0 ? " with warnings · \(result.issueCount)" : " · \(result.outputCount) UTF-16 units")
        case .invalidReferences: return "Cannot convert"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        case .processingFailure: return "Processing failed"
        }
    }
    private var color: Color {
        if workspace.busy || workspace.wasCancelled || workspace.result == nil { return .secondary }
        if workspace.result?.status == .invalidReferences || workspace.result?.status == .processingFailure { return .red }
        return issue == nil ? .secondary : .orange
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(title, systemImage: issue == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium)).foregroundStyle(color).lineLimit(2)
                    .accessibilityIdentifier("html-entity-status")
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ZStack { if workspace.busy { ProgressView().controlSize(.mini) } }.frame(width: 14, height: 14)
                    Button("Cancel", action: cancel).controlSize(.small)
                }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 30)
            if let issue {
                Text(issue.message).font(.callout).lineLimit(3).help(issue.message).textSelection(.enabled)
                    .accessibilityIdentifier("html-entity-message")
                HStack {
                    if let line = issue.line, let column = issue.column {
                        Text("Line \(line), column \(column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let range = issue.range { Button("Show Input") { show(range) }.accessibilityIdentifier("html-entity-show-input") }
                    Button(expanded ? "Hide details" : "Details", action: toggleDetails).accessibilityIdentifier("html-entity-details")
                }.controlSize(.small)
                if expanded, let result = workspace.result {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if let context = issue.context {
                                Text(context).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                            ForEach(Array(result.issues.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top) {
                                    Text(note.message).font(.caption).textSelection(.enabled)
                                    if let range = note.range { Button("Show Input") { show(range) }.font(.caption) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if result.issueCount > result.issues.count {
                                Text("Showing \(result.issues.count) of \(result.issueCount) issues.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
            }
        }
    }
}
