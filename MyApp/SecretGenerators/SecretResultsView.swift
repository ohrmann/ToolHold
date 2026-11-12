import SwiftUI

struct SecretResultsView: View {
    @Bindable var workspace: SecretGeneratorWorkspaceSession
    let animate: Bool
    let copy: (Int) -> Void
    @State private var scrollRequest = 0
    @State private var scrollTarget: Int?
    @ScaledMetric(relativeTo: .body) private var rowHeight = 48.0
    var body: some View {
        JSONTreeTable(rows: workspace.rows, rowNumbers: workspace.rowNumbers,
            version: workspace.renderVersion, rowsVersion: workspace.batchVersion, changes: nil, animate: animate,
            selection: workspace.selection, scrollRequest: scrollRequest, scrollTarget: scrollTarget,
            row: { AnyView(row($0)) }, select: { workspace.selection = $0 }, key: key,
            preferredRowHeight: max(48, rowHeight), tableIdentifier: "secret-results", suppressSoftwareKeyboard: true,
            heightForID: { _ in max(48, rowHeight) }, smoothScrolling: true, fadeReplacements: workspace.batch != nil && !workspace.hidden,
            alwaysShowScrollers: true, accessibilityScrollName: "generated results", clearsOffscreenRowContent: true)
            .onChange(of: workspace.batch?.id) { _, _ in scrollTarget = nil }
    }
    @ViewBuilder private func row(_ index: Int) -> some View {
        if let batch = workspace.batch, batch.values.indices.contains(index) {
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                Text(workspace.hidden ? "••••••••" : preview(batch.values[index]))
                    .font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(workspace.hidden ? "Hidden result" : batch.values[index])
                Button { copy(index) } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).disabled(!workspace.canCopy)
                    .accessibilityLabel("Copy result \(index + 1)").accessibilityIdentifier("secret-copy-row-\(index)")
            }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: max(48, rowHeight))
                .background(workspace.selection == index ? Color.green.opacity(0.14) : .clear)
                .contentShape(Rectangle()).onTapGesture { workspace.selection = index }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Result \(index + 1), \(batch.options.kind.rawValue), \(workspace.hidden ? "hidden" : "revealed")")
                .accessibilityIdentifier("secret-row-\(index)")
                .accessibilityAddTraits(workspace.selection == index ? .isSelected : [])
                .accessibilityAction(.default) { workspace.selection = index }
                .contextMenu { Button("Copy result") { copy(index) }.disabled(!workspace.canCopy) }
        }
    }
    private func preview(_ value: String) -> String { value.count > 64 ? String(value.prefix(63)) + "…" : value }
    private func key(_ key: JSONTreeTable.TreeKey) {
        switch key {
        case .copy: if let index = workspace.selection { copy(index) }
        case .up, .down:
            guard !workspace.rows.isEmpty else { return }
            let selected = workspace.selection ?? (key == .down ? -1 : workspace.rows.count)
            let next = min(workspace.rows.count - 1, max(0, selected + (key == .down ? 1 : -1)))
            workspace.selection = next; scrollTarget = next; scrollRequest &+= 1
        default: break
        }
    }
}
