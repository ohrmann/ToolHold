import SwiftUI

struct CalculationPanels<Input: View, Output: View>: View {
  @ViewBuilder var input: () -> Input
  @ViewBuilder var output: () -> Output
  @State private var fraction = 0.43
  var body: some View {
    GeometryReader { geometry in
      TextToolPanelLayout(wide: geometry.size.width >= 780, fraction: fraction, collapse: 0) {
        ScrollView { input().frame(maxWidth: .infinity, alignment: .leading).padding(12) }
          .background(.background, in: RoundedRectangle(cornerRadius: 10))
        TextToolDivider(
          wide: geometry.size.width >= 780,
          length: geometry.size.width >= 780 ? geometry.size.width : geometry.size.height,
          fraction: $fraction)
        output().background(.background, in: RoundedRectangle(cornerRadius: 10))
      }
    }.padding(12)
  }
}
struct CalculationResults<Request: Sendable>: View {
  @Bindable var workspace: CalculationWorkspace<Request>
  var choose: (String, Bool) -> Void = { _, _ in }
  var reference = false
  @State private var details: Set<String> = []
  @Environment(\.accessibilityReduceMotion) private var reduced
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(workspace.status).font(.headline).lineLimit(2)
        Spacer()
        if workspace.showProgress { ProgressView().controlSize(.small) }
        if workspace.busy { Button("Cancel") { workspace.cancel() } }
        Button("Copy Results", systemImage: "doc.on.doc") {
          if let report = workspace.report { TextClipboard.copy(report.text) }
        }.disabled(workspace.report?.rows.isEmpty != false)
      }.padding([.top, .horizontal], 12)
      Group {
        if reference {
          List { resultContent }.listStyle(.plain)
        } else {
          ScrollView { LazyVStack(alignment: .leading, spacing: 10) { resultContent }.padding(12) }
        }
      }
    }
  }
  @ViewBuilder private var resultContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let issue = workspace.issue {
        Label(
          workspace.status,
          systemImage: issue.kind == .notReady ? "text.cursor" : "exclamationmark.triangle"
        ).font(.subheadline.weight(.semibold))
        Text(issue.field + ": " + issue.message).textSelection(.enabled)
        if let range = issue.range {
          Text("UTF-16 position \(range.location+1)").font(.caption).foregroundStyle(.secondary)
        }
      }
    }.animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.issue)
    if let report = workspace.report {
      ForEach(report.choices) { c in
        Button(c.label) { choose(c.id, report.choicesForResult) }.buttonStyle(.bordered)
      }
      ForEach(report.rows) { row in
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .top) {
            Text(row.label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
              TextClipboard.copy(row.value)
            } label: {
              Image(systemName: "doc.on.doc")
            }.buttonStyle(.borderless).help("Copy " + row.label).accessibilityLabel(
              "Copy " + row.label)
            if !row.detail.isEmpty {
              Button {
                withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) {
                  if !details.insert(row.id).inserted { details.remove(row.id) }
                }
              } label: {
                Image(systemName: details.contains(row.id) ? "chevron.up" : "info.circle")
              }.buttonStyle(.borderless).accessibilityLabel("Details for " + row.label)
            }
          }
          // Bounded visual preview; Copy always uses the complete exact result.
          Text(row.value.count > 600 ? String(row.value.prefix(600)) + "…" : row.value).font(
            .system(.body, design: .monospaced)
          ).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          if row.value.count > 600 {
            Text("\(row.value.count) characters · Copy includes the full value").font(.caption)
              .foregroundStyle(.secondary)
          }
          if details.contains(row.id) {
            Text(row.detail).font(.caption).textSelection(.enabled).transition(.opacity)
          }
        }.padding(10).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
          .contextMenu {
            Button("Copy Label") { TextClipboard.copy(row.label) }
            Button("Copy Value") { TextClipboard.copy(row.value) }
            Button("Copy Details") {
              TextClipboard.copy(row.label + "\n" + row.value + "\n" + row.detail)
            }
          }
      }
      ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
        Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    } else if workspace.issue == nil && !workspace.busy {
      Text("Enter input to see the result. All processing stays on this device.").foregroundStyle(
        .secondary)
    }
  }
}
