import SwiftUI

struct JSONDiagnosticsPanel: View {
    private let workspace: JSONDiagnosticsPresentation
    let cancel: () -> Void
    private var compact = false
    @State private var expanded = false

    init(workspace: JSONWorkspaceSession, show: @escaping (NSRange) -> Void) {
        self.workspace = JSONDiagnosticsPresentation(input: workspace.input, result: workspace.result, context: workspace.context, busy: workspace.busy, wasCancelled: workspace.wasCancelled)
        self.cancel = workspace.cancel; self.show = show
    }
    init(workspace: JSONTreeWorkspaceSession, show: @escaping (NSRange) -> Void) {
        self.workspace = JSONDiagnosticsPresentation(input: workspace.input, result: workspace.result, context: workspace.context, busy: workspace.busy, wasCancelled: workspace.wasCancelled)
        self.cancel = workspace.cancel; self.show = show
    }
    init(input: String, result: JSONResult?, context: JSONDiagnosticContext?, busy: Bool,
         wasCancelled: Bool, compact: Bool = false, cancel: @escaping () -> Void, show: @escaping (NSRange) -> Void) {
        self.workspace = JSONDiagnosticsPresentation(input: input, result: result, context: context,
                                                    busy: busy, wasCancelled: wasCancelled)
        self.compact = compact
        self.cancel = cancel; self.show = show
    }
    let show: (NSRange) -> Void
    private var diagnostic: JSONDiagnostic? {
        workspace.result?.diagnostics.first { $0.severity == .error } ?? workspace.result?.diagnostics.first
    }
    private var title: String {
        if workspace.busy { return "Processing" }
        if workspace.wasCancelled || workspace.result?.status == .cancelled { return "Cancelled" }
        guard let result = workspace.result else { return workspace.input.isEmpty ? "Ready" : "Not checked" }
        switch result.status {
        case .valid: return result.diagnostics.isEmpty ? "Valid JSON" : "Valid JSON with warnings"
        case .invalid: return "Invalid JSON"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        }
    }
    private var symbol: String {
        if workspace.busy { return "hourglass" }
        if workspace.wasCancelled { return "stop.circle" }
        if workspace.result == nil { return "info.circle" }
        if diagnostic != nil { return "exclamationmark.triangle" }
        return "checkmark.circle"
    }
    private var color: Color {
        if workspace.busy || workspace.wasCancelled || workspace.result == nil { return .secondary }
        if workspace.resourceLimited || diagnostic?.severity == .warning { return .orange }
        return workspace.result?.isValid == true ? .green : .red
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol).font(.callout.weight(.medium)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if compact, diagnostic != nil {
                    Button(expanded ? "Less" : "Details", systemImage: expanded ? "chevron.up" : "chevron.down") {
                        expanded.toggle()
                    }.controlSize(.small)
                    .popover(isPresented: $expanded) {
                        JSONDiagnosticsPanel(input: workspace.input, result: workspace.result, context: workspace.context,
                            busy: workspace.busy, wasCancelled: workspace.wasCancelled, cancel: cancel,
                            show: { range in expanded = false; show(range) })
                            .padding().frame(idealWidth: 360)
                            .presentationCompactAdaptation(.sheet)
                    }
                }
                HStack {
                    ProgressView().controlSize(.mini)
                    Button("Cancel") { cancel() }.controlSize(.small)
                }
                .opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy)
                .allowsHitTesting(workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight: 26)
            if let diagnostic {
                VStack(alignment: .leading, spacing: 4) {
                    // The factual message and explicit navigation stay visible; long details scroll.
                    Text(diagnostic.message).font(.callout).lineLimit(2).help(diagnostic.message)
                        .accessibilityLabel(diagnostic.message).textSelection(.enabled)
                    if !compact {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if let context = workspace.context {
                                Text(snippet(context)).font(.system(.caption, design: .monospaced))
                                    .accessibilityLabel("Context. " + context.text)
                                    .accessibilityIdentifier("json-diagnostic-context")
                            }
                            if workspace.resourceLimited {
                                Text("Processing limit reached; JSON validity has not been established.")
                            } else {
                                Text("\(diagnostic.precision == .region ? "Reported region starts at" : "Detected at") line \(diagnostic.line), column \(diagnostic.column) (UTF-16) · \(diagnostic.code)")
                            }
                            if !diagnostic.expected.isEmpty {
                                Text("Expected: " + diagnostic.expected.map(\.rawValue).joined(separator: ", "))
                                    .textSelection(.enabled)
                            }
                            if let count = workspace.result?.diagnostics.count, count > 1 {
                                Text("\(count - 1) additional warning(s). Duplicate fields are preserved.")
                            }
                            if diagnostic.precision == .region {
                                Text("The affected region is known; the exact offending code unit is not established.")
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: workspace.resourceLimited ? 30 : 68)
                    }
                    if !workspace.resourceLimited {
                        ViewThatFits(in: .horizontal) {
                            HStack { navigation(diagnostic) }
                            VStack(alignment: .leading, spacing: 4) { navigation(diagnostic) }
                        }.controlSize(.small)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private func navigation(_ diagnostic: JSONDiagnostic) -> some View {
        Button(diagnostic.precision == .region ? "Show Region" : "Show Detection") { show(diagnostic.range) }
            .accessibilityIdentifier("json-show-detection")
        if !diagnostic.related.isEmpty {
            Menu("Show Related") {
                ForEach(Array(diagnostic.related.enumerated()), id: \.offset) { _, location in
                    Button("\(location.role.rawValue) · UTF-16 offset \(location.range.location)") { show(location.range) }
                }
            }.accessibilityIdentifier("json-show-related")
        }
    }
    private func snippet(_ context: JSONDiagnosticContext) -> AttributedString {
        var text = AttributedString(context.text)
        if diagnostic?.precision == .exact,
           let range = Range(context.detectionRange, in: context.text),
           let converted = Range(range, in: text) {
            text[converted].foregroundColor = color
            text[converted].underlineStyle = .single
            text[converted].font = .system(.caption, design: .monospaced).bold()
        }
        return text
    }
}

/// Only presentation fields are shared; neither tool owns or changes the other's session.
private struct JSONDiagnosticsPresentation {
    let input: String
    let result: JSONResult?
    let context: JSONDiagnosticContext?
    let busy: Bool
    let wasCancelled: Bool
    var resourceLimited: Bool { if case .resourceLimit = result?.status { return true }; return false }
}
