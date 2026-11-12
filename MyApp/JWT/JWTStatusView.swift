import SwiftUI

struct JWTStatusView: View {
    @Bindable var workspace: JWTWorkspaceSession
    @Binding var details: Bool
    let show: (JWTAnchor) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var rowLayout: AnyLayout { dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLayout {
                Image(systemName: "exclamationmark.shield").foregroundStyle(.secondary)
                Text(workspace.result?.trust ?? "Signature not verified").fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("jwt-trust")
                if workspace.busy { ProgressView().controlSize(.small) }
                Text(workspace.masked ? "Sensitive content hidden" : workspace.busy ? "Processing…" : workspace.wasCancelled ? "Cancelled" : workspace.result?.title ?? "Ready · not checked")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("jwt-status")
                Spacer(minLength: 0)
                if !workspace.masked, let result = workspace.result, result.issueCount > 0 {
                    Button { details.toggle() } label: { Label(result.issueCount == 1 ? "1 issue" : "\(result.issueCount) issues", systemImage: details ? "chevron.up" : "chevron.down") }
                        .accessibilityIdentifier("jwt-details").fixedSize()
                }
            }.font(.callout).frame(minHeight: 30)
            if !workspace.masked, let issue = workspace.result?.issues.first(where: { $0.severity == .error }) {
                rowLayout {
                    Text(issue.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let anchor = issue.anchor, case .bytes = anchor.space { Text("Decoded bytes").font(.caption) }
                    else if let anchor = issue.anchor { Button("Show Detection") { show(anchor) }.fixedSize().accessibilityIdentifier("jwt-show-detection") }
                }
            }
            if details && !workspace.masked, let result = workspace.result {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(result.issues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(issue.component.rawValue + " · " + issue.message, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle").font(.callout)
                                if let location = issue.location { Text(location).font(.caption).foregroundStyle(.secondary) }
                                if let context = issue.context {
                                    contextText(context).font(.system(.caption, design: .monospaced)).lineLimit(4)
                                }
                                HStack {
                                    if let anchor = issue.anchor, navigable(anchor) { Button("Show Detection") { show(anchor) } }
                                    ForEach(Array(issue.related.enumerated()), id: \.offset) { index, anchor in
                                        if navigable(anchor) { Button(anchor.space == .input ? "Show encoded segment" : "Show Related \(index + 1)") { show(anchor) } }
                                    }
                                }.font(.caption)
                            }.padding(.vertical, 3)
                        }
                        if result.issueCount > result.issues.count { Text("Showing \(result.issues.count) of \(result.issueCount) issues. All claims were inspected.").font(.caption) }
                    }
                }.frame(maxHeight: 170)
            }
        }
    }
    private func navigable(_ anchor: JWTAnchor) -> Bool { if case .bytes = anchor.space { return false }; return true }
    private func contextText(_ context: JSONDiagnosticContext) -> Text {
        let text = context.text as NSString, range = context.detectionRange
        return Text(text.substring(to: range.location)) + Text(text.substring(with: range)).bold().underline() + Text(text.substring(from: NSMaxRange(range)))
    }
}
