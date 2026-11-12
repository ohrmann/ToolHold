import SwiftUI
import UniformTypeIdentifiers

struct TextDiffView: View {
  @Bindable var workspace: TextWorkspace<TextDiffOptions>
  @State private var unified = false
  @State private var showAll = false
  @State private var visible: [DiffDisplayRow] = []
  @State private var selected: Int?
  @State private var expanded = Set<Int>()
  @State private var exporting = false
  @State private var document: TextExportDocument?
  @State private var filename = "comparison.patch"
  @State private var issue: String?
  @Environment(\.accessibilityReduceMotion) private var reduced
  struct DiffDisplayRow: Identifiable {
    let id: Int
    let row: TextDiffRow?
    let hidden: Range<Int>?
  }
  var body: some View {
    TextToolSurface(workspace: workspace, action: "Compare", twoInputs: true) {
      TextOptionsBar {
        TextComparisonControls(options: $workspace.options.comparison)
        Toggle("Ignore line endings", isOn: $workspace.options.ignoreEndings)
        Toggle("Unified", isOn: $unified)
        Toggle("All context", isOn: $showAll)
      }
    } results: {
      VStack(alignment: .leading, spacing: 6) {
        ViewThatFits(in: .horizontal) {
          actions
          ScrollView(.horizontal) { actions }.scrollIndicators(.visible)
        }
        if let result = workspace.artifact?.diff {
          GeometryReader { g in
            ScrollViewReader { proxy in
              List(selection: $selected) {
                ForEach(visible) { item in
                  if let row = item.row {
                    diffRow(row, result: result, wide: g.size.width >= 560 && !unified).tag(row.id)
                      .id(row.id).contentShape(Rectangle()).onTapGesture(count: 2) {
                        selected = row.id
                        show(row, both: true)
                      }.contextMenu {
                        Button("Show Before") { show(row, before: true) }.disabled(row.left == nil)
                        Button("Show After") { show(row) }.disabled(row.right == nil)
                        Button("Show Both") { show(row, both: true) }
                      }
                  } else if let range = item.hidden {
                    Button("Show \(range.count) unchanged lines") {
                      withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) {
                        expanded.insert(range.lowerBound)
                        project()
                      }
                    }.buttonStyle(.borderless)
                  }
                }.listRowSeparator(.hidden)
              }.listStyle(.plain)
                .onChange(of: selected) { _, id in
                  if let id {
                    withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) {
                      proxy.scrollTo(id, anchor: .center)
                    }
                  }
                }
            }
          }
        } else {
          ContentUnavailableView(
            "Compare two texts", systemImage: "arrow.left.arrow.right",
            description: Text(
              "Empty text is supported. Comparison preserves Unicode and line endings."))
        }
        if let issue { Text(issue).font(.caption).foregroundStyle(.orange) }
      }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }.navigationTitle("Text Diff")
      .onChange(of: workspace.publication) { _, _ in
        expanded = []
        selected = nil
        project()
      }.onChange(of: showAll) { _, _ in project() }.onAppear { project() }
      .fileExporter(
        isPresented: $exporting, document: document, contentType: .data, defaultFilename: filename
      ) { r in if case .failure = r { issue = "Export did not complete." } }
  }
  private var actions: some View {
    HStack {
      Button("Previous") { move(-1) }
      Button("Next") { move(1) }
      Button("Show Before") { if let row = current { show(row, before: true) } }.disabled(
        current?.left == nil)
      Button("Show After") { if let row = current { show(row) } }.disabled(current?.right == nil)
      Button("Show Both") { if let row = current { show(row, both: true) } }.disabled(
        current == nil)
      Menu("Copy") {
        Button("Unified Patch") { copy(patch: true) }
        Button("Readable Report") { copy(patch: false) }
      }.disabled(workspace.artifact?.diff == nil)
      Menu("Export") {
        Button("Unified Patch") { export(patch: true) }
        Button("Readable Report") { export(patch: false) }
      }.disabled(workspace.artifact?.diff == nil)
    }
  }
  private var current: TextDiffRow? {
    guard let selected, let rows = workspace.artifact?.diff?.rows, rows.indices.contains(selected)
    else { return nil }
    return rows[selected]
  }
  @ViewBuilder private func diffRow(_ row: TextDiffRow, result: TextDiffResult, wide: Bool)
    -> some View
  {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(row.kind).font(.caption).foregroundStyle(.secondary)
        if let l = row.left, let r = row.right,
          result.before.lines[l].ending != result.after.lines[r].ending
        {
          Text("Line ending changed").font(.caption).foregroundStyle(.orange)
        }
      }
      if wide {
        HStack(alignment: .top) {
          cell(
            row.leftPreview, index: row.left, ranges: row.leftInline,
            kind: row.kind == "Equal" ? "" : "−"
          ).frame(maxWidth: .infinity, alignment: .leading)
          Divider()
          cell(
            row.rightPreview, index: row.right, ranges: row.rightInline,
            kind: row.kind == "Equal" ? "" : "+"
          ).frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        if row.left != nil {
          cell(
            row.leftPreview, index: row.left, ranges: row.leftInline,
            kind: row.kind == "Equal" ? "" : "−")
        }
        if row.kind != "Equal", row.right != nil {
          cell(row.rightPreview, index: row.right, ranges: row.rightInline, kind: "+")
        }
      }
    }.padding(4).background(
      row.kind == "Equal" ? Color.clear : Color.orange.opacity(0.07),
      in: RoundedRectangle(cornerRadius: 4))
  }
  private func cell(_ preview: String, index: Int?, ranges: [NSRange], kind: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(index.map { String($0 + 1) } ?? "–").foregroundStyle(.secondary).frame(
        minWidth: 24, alignment: .trailing)
      Text(kind).foregroundStyle(.secondary)
      Text(marked(preview, ranges: ranges)).textSelection(.enabled).lineLimit(5)
    }.font(.system(.caption, design: .monospaced))
  }
  private func marked(_ value: String, ranges: [NSRange]) -> AttributedString {
    // Row previews escape controls; source ranges cannot be applied after escaping/truncation.
    var a = AttributedString(value)
    for r in ranges {
      guard NSMaxRange(r) <= value.utf16.count, let range = Range(r, in: value),
        let lower = AttributedString.Index(range.lowerBound, within: a),
        let upper = AttributedString.Index(range.upperBound, within: a)
      else { continue }
      a[lower..<upper].backgroundColor = .orange.opacity(0.24)
    }
    return a
  }
  private func show(_ row: TextDiffRow, before: Bool = false, both: Bool = false) {
    guard let r = workspace.artifact?.diff else { return }
    let l = row.left.map { r.before.lines[$0].range }
    let a = row.right.map { r.after.lines[$0].range }
    workspace.navigate(before || both ? l : nil, before ? nil : a)
  }
  private func move(_ delta: Int) {
    guard let changes = workspace.artifact?.diff?.changed, !changes.isEmpty else { return }
    let i = changes.firstIndex(of: selected ?? -1) ?? (delta > 0 ? -1 : 0)
    selected = changes[(i + delta + changes.count) % changes.count]
  }
  private func project() {
    guard let result = workspace.artifact?.diff else {
      visible = []
      return
    }
    if showAll {
      visible = result.rows.map { .init(id: $0.id, row: $0, hidden: nil) }
      return
    }
    var keep = Set<Int>()
    for i in result.changed {
      for j in max(0, i - 3)...min(result.rows.count - 1, i + 3) { keep.insert(j) }
    }
    var out: [DiffDisplayRow] = []
    var i = 0
    while i < result.rows.count {
      if keep.contains(i) {
        out.append(.init(id: i, row: result.rows[i], hidden: nil))
        i += 1
      } else {
        let start = i
        while i < result.rows.count && !keep.contains(i) { i += 1 }
        if expanded.contains(start) {
          out.append(
            contentsOf: (start..<i).map { .init(id: $0, row: result.rows[$0], hidden: nil) })
        } else {
          out.append(.init(id: start, row: nil, hidden: start..<i))
        }
      }
    }
    visible = out
  }
  private func copy(patch: Bool) {
    guard let r = workspace.artifact?.diff else { return }
    do {
      TextClipboard.copy(try patch ? r.patch() : r.report())
      issue = nil
    } catch { issue = (error as? TextFailure)?.message ?? "Copy failed" }
  }
  private func export(patch: Bool) {
    guard let r = workspace.artifact?.diff else { return }
    do {
      document = TextExportDocument(try patch ? r.patch() : r.report())
      filename = patch ? "comparison.patch" : "comparison.txt"
      exporting = true
      issue = nil
    } catch { issue = (error as? TextFailure)?.message ?? "Export failed" }
  }
}
