import SwiftUI

struct IdentifierResultsView: View {
    @Bindable var workspace: IdentifierWorkspaceSession
    let animate: Bool
    let copy: (Int) -> Void
    @State private var scrollRequest = 0
    @State private var scrollTarget: Int?
    @ScaledMetric(relativeTo: .body) private var rowHeight = 48.0
    var body: some View {
        JSONTreeTable(rows: workspace.rows, rowNumbers: workspace.rowNumbers,
            version: workspace.renderVersion, rowsVersion: workspace.batchVersion, changes: nil, animate: animate,
            selection: workspace.selection, scrollRequest: scrollRequest, scrollTarget: scrollTarget,
            row: { index in AnyView(row(index)) }, select: { workspace.selection = $0 }, key: key,
            preferredRowHeight: max(48, rowHeight), tableIdentifier: "identifier-results", suppressSoftwareKeyboard: true,
            heightForID: { _ in max(48, rowHeight) },
            smoothScrolling: true, fadeReplacements: true, alwaysShowScrollers: true, accessibilityScrollName: "identifiers")
            .onChange(of: workspace.batch?.id) { _, _ in scrollTarget = nil }
    }
    @ViewBuilder private func row(_ index: Int) -> some View {
        if let batch = workspace.batch, batch.values.indices.contains(index) {
            let value = batch.values[index]
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                Text(value.count > 64 ? String(value.prefix(61)) + "…" : value)
                    .font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                Button { copy(index) } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).disabled(!workspace.canCopy)
                    .accessibilityLabel("Copy ID \(index + 1)").accessibilityIdentifier("identifier-copy-row-\(index)")
            }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: max(48, rowHeight))
                .background(workspace.selection == index ? Color.green.opacity(0.14) : Color.clear)
                .contentShape(Rectangle()).onTapGesture { workspace.selection = index }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Identifier \(index + 1), \(batch.options.kind.title), \(value)")
                .accessibilityIdentifier("identifier-row-\(index)")
                .accessibilityAction(.default) { workspace.selection = index }
                .accessibilityAddTraits(workspace.selection == index ? .isSelected : [])
                .contextMenu { Button("Copy ID") { copy(index) }.disabled(!workspace.canCopy) }
        }
    }
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
