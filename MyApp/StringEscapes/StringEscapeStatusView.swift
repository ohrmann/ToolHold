import SwiftUI

struct StringEscapeStatusView: View {
    let workspace: StringEscapeWorkspaceSession
    let expanded: Bool
    let toggleDetails: () -> Void
    let show: (NSRange) -> Void
    let cancel: () -> Void
    private var issue: StringEscapeIssue? { workspace.result?.issues.first { $0.severity == .error } ?? workspace.result?.issues.first }
    private var title: String {
        if workspace.busy { return workspace.lastIntent == .check ? "Checking" : workspace.options.direction == .escape ? "Escaping" : "Unescaping" }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .success, .successWithWarnings:
            let action = workspace.lastIntent == .check ? "Checked" : workspace.options.direction == .escape ? "Escaped" : "Unescaped"
            return action + (result.issueCount > 0 ? " with warnings · \(result.issueCount)" : " · \(result.outputCount) UTF-16 units")
        case .invalidSyntax: return "Invalid string syntax"
        case .unsupportedSyntax: return "Unsupported string syntax"
        case .notRepresentableAsText: return "Cannot represent as text"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        case .processingFailure: return "Processing failed"
        }
    }
    private var color: Color {
        if workspace.busy || workspace.wasCancelled || workspace.result == nil { return .secondary }
        if issue?.severity == .error { return .red }
        return issue == nil ? .secondary : .orange
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(title, systemImage: issue == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium)).foregroundStyle(color).lineLimit(2)
                    .accessibilityIdentifier("string-escape-status")
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ZStack { if workspace.busy { ProgressView().controlSize(.mini) } }.frame(width: 14, height: 14)
                    Button("Cancel", action: cancel).controlSize(.small)
                }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 30)
            if let issue {
                Text(issue.message).font(.callout).lineLimit(3).help(issue.message).textSelection(.enabled)
                    .accessibilityIdentifier("string-escape-message")
                ViewThatFits(in: .horizontal) {
                    HStack { locationActions }
                    VStack(alignment: .leading, spacing: 4) { locationActions }
                }.controlSize(.small)
                if expanded, let result = workspace.result {
                    notes(result)
                }
            }
        }
    }
    @ViewBuilder private var locationActions: some View {
        if let issue {
            if let line = issue.line, let column = issue.column {
                Text("Line \(line), column \(column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let range = issue.range { Button("Show Input") { show(range) }.accessibilityIdentifier("string-escape-show-input") }
                if let related = issue.related { Button("Show Related") { show(related) }.accessibilityIdentifier("string-escape-show-related") }
                Button(expanded ? "Hide details" : "Details", action: toggleDetails).accessibilityIdentifier("string-escape-details")
            }.fixedSize()
        }
    }
    private func notes(_ result: StringEscapeResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let context = issue?.context {
                    Text(context).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                ForEach(Array(result.issues.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top) {
                        Text(note.message + (note.occurrences > 1 ? " (\(note.occurrences) occurrences)" : "")).font(.caption).textSelection(.enabled)
                        if let range = note.range { Button("Show Input") { show(range) }.font(.caption) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if result.issueCount > result.issues.count {
                    Text("\(result.issueCount) issue occurrences · grouped by type.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 100)
    }
}
