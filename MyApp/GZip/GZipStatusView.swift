import SwiftUI

struct GZipStatusView: View {
    let workspace: GZipWorkspaceSession
    @Binding var details: Bool
    let show: (NSRange) -> Void
    let cancel: () -> Void
    private var title: String {
        if workspace.busy { return "Processing" }
        if let saved = workspace.exportMessage { return saved }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty && workspace.selectedFile == nil ? "Ready" : "Not checked" }
        switch result.status {
        case .success: return workspace.lastIntent == .check ? (workspace.options.direction == .compress ? "Ready to compress" : "Valid gzip · checked") : "Completed"
        case .invalidBase64: return "Invalid Base64"
        case .invalidGZip: return "Invalid gzip"
        case .unsupportedFormat: return "Unsupported format"
        case .resourceLimit: return "Resource limit reached"
        case .sourceChanged: return "Source changed"
        case .ioFailure: return "File operation failed"
        case .cancelled: return "Cancelled"
        case .internalFailure: return "Processing failed"
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(spacing:6) {
                Label(title,systemImage:workspace.result?.failure == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium)).lineLimit(2).accessibilityIdentifier("gzip-status")
                Spacer(minLength:0)
                HStack(spacing:6) {
                    ZStack {
                        if workspace.busy {
                            if let total = workspace.progress.total, total > 0 {
                                ProgressView(value:Double(min(total,workspace.progress.bytes)),total:Double(total)).frame(width:55)
                            } else { ProgressView().controlSize(.small) }
                        }
                    }.frame(width:55,height:16)
                    Button("Cancel",action:cancel).controlSize(.small).accessibilityIdentifier("gzip-cancel")
                }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight:30)
            Text(workspace.options.direction == .compress ? "Gzip · \(workspace.preferences.compressionLevel.title) · 256 MiB file limit" : "Gzip only · maximum output \(workspace.preferences.maxOutput.title)")
                .font(.caption).foregroundStyle(.secondary)
            if let warning = workspace.cleanupWarning {
                HStack { Text(warning).font(.caption).textSelection(.enabled); Button("Dismiss") { workspace.dismissCleanupWarning() } }
            }
            if let failure = workspace.result?.failure {
                Text(failure.message).font(.callout).lineLimit(3).help(failure.message).textSelection(.enabled).accessibilityIdentifier("gzip-error")
                ViewThatFits(in:.horizontal) {
                    HStack { failureActions(failure) }
                    VStack(alignment:.leading,spacing:4) { failureActions(failure) }
                }.controlSize(.small)
                if details && !failure.context.isEmpty {
                    Text(failure.context).font(.system(.caption,design:.monospaced)).lineLimit(4).textSelection(.enabled)
                }
            }
            Text(workspace.result.map { $0.status == .success ? metrics($0) : " " } ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight:16).accessibilityIdentifier("gzip-metrics")
            if let result = workspace.result, result.status == .success {
                if !result.notes.isEmpty {
                    Button(details ? "Hide notes" : "Notes (\(result.notes.count))") { details.toggle() }.font(.caption)
                    if details { ForEach(result.notes,id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary) } }
                }
            }
        }
    }
    @ViewBuilder private func failureActions(_ failure:GZipFailure) -> some View {
        if let line = failure.line, let column = failure.column {
            Text("Line \(line), column \(column) (UTF-16)").font(.caption).foregroundStyle(.secondary)
        } else if let offset = failure.offset {
            Text(failure.exact ? "Compressed byte offset \(offset) (0-based)" : "Detected in compressed bytes \(offset)–\(offset + Int64(failure.length))")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let member = failure.member { Text("Member \(member)").font(.caption).foregroundStyle(.secondary) }
        HStack {
            if let range = failure.textRange { Button("Show Input") { show(range) }.accessibilityIdentifier("gzip-show-input") }
            if !failure.context.isEmpty { Button(details ? "Hide details" : "Details") { details.toggle() }.accessibilityIdentifier("gzip-details") }
        }.fixedSize()
    }
    private func metrics(_ result:GZipResult) -> String {
        let sizes = "\(ByteCountFormatter.string(fromByteCount:result.inputBytes,countStyle:.file)) → \(ByteCountFormatter.string(fromByteCount:result.outputBytes,countStyle:.file)) · \(result.members) member\(result.members == 1 ? "" : "s")"
        guard result.inputBytes > 0 else { return sizes + " · saving —" }
        if workspace.options.direction == .decompress { return sizes + String(format:" · Expansion ×%.2f",Double(result.outputBytes) / Double(result.inputBytes)) }
        let saving = 100 * (1 - Double(result.outputBytes) / Double(result.inputBytes))
        return sizes + String(format:saving >= 0 ? " · Saved %.1f%%" : " · Increased %.1f%%",abs(saving))
    }
}
