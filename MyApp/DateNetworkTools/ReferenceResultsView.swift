import SwiftUI

/// Fixed-height list rows keep NSTableView measurement independent from expanded details.
struct ReferenceResultsView: View {
  @Bindable var workspace: CalculationWorkspace<NetworkCalculationRequest>
  @State private var selected: String?
  @State private var visibleRows: [CalculationRow] = []
  private var entry: CalculationRow? { workspace.report?.rows.first { $0.id == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(workspace.status).font(.headline)
        Spacer()
        if workspace.showProgress { ProgressView().controlSize(.small) }
        if workspace.busy { Button("Cancel") { workspace.cancel() } }
      }.padding([.horizontal, .top], 12)
      if let issue = workspace.issue {
        Text(issue.message).foregroundStyle(.secondary).padding(.horizontal, 12)
      }
      #if os(macOS)
        NativeReferenceList(rows: visibleRows, selected: $selected).allowsHitTesting(
          workspace.report != nil
        ).opacity(workspace.report == nil ? 0.5 : 1)
      #else
        List(visibleRows) { row in
          Button {
            selected = row.id
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(row.label).font(.system(.body, design: .monospaced)).lineLimit(1)
                Text(row.value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              Spacer(minLength: 4)
              if selected == row.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
              }
            }.frame(height: 48).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityAddTraits(selected == row.id ? .isSelected : [])
        }.listStyle(.plain)
          .disabled(workspace.report == nil)
      #endif
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if let entry {
            HStack(alignment: .top) {
              Text(entry.label).font(.headline).textSelection(.enabled)
              Spacer()
              Menu("Copy", systemImage: "doc.on.doc") {
                Button("Code / Type") { TextClipboard.copy(entry.label) }
                Button("Value") { TextClipboard.copy(entry.value) }
                Button("Details") {
                  TextClipboard.copy(entry.label + "\n" + entry.value + "\n" + entry.detail)
                }
              }
            }
            Text(entry.value).textSelection(.enabled)
            Text(entry.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          } else {
            Text("Select an entry for details and Copy.").foregroundStyle(.secondary)
          }
          ForEach(Array((workspace.report?.notes ?? []).enumerated()), id: \.offset) { _, note in
            Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
      }.frame(maxHeight: 180)
    }.onAppear { visibleRows = workspace.report?.rows ?? [] }
      .onChange(of: workspace.report) { _, report in if let report { visibleRows = report.rows } }
      .onChange(of: workspace.revision) { _, _ in selected = nil }
  }
}
