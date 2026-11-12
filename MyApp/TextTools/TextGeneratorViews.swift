import SwiftUI

struct LoremGeneratorView: View {
  @Bindable var workspace: TextWorkspace<LoremOptions>
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextOptionsBar {
        Button("Generate") { workspace.run() }.keyboardShortcut(.return, modifiers: .command)
        Button("Cancel") { workspace.cancel() }.disabled(!workspace.busy)
        TextChoice(
          title: "Unit", value: $workspace.options.unit,
          choices: ["Words", "Sentences", "Paragraphs"])
        TextField("Count", value: $workspace.options.count, format: .number).frame(width: 80)
        Toggle("Start with Lorem ipsum", isOn: $workspace.options.start)
      }
      TextOptionsBar {
        if workspace.options.unit != "Words" {
          Stepper(
            "Words per sentence: \(workspace.options.words)", value: $workspace.options.words,
            in: 3...30)
        }
        if workspace.options.unit == "Paragraphs" {
          Stepper(
            "Sentences per paragraph: \(workspace.options.sentences)",
            value: $workspace.options.sentences, in: 1...10)
        }
        TextField("Seed (optional)", text: $workspace.options.seed).frame(width: 210)
      }
      TextOutputPanel(output: workspace.artifact?.output, filename: "lorem.txt")
      Text(workspace.busy ? "Generating…" : workspace.status).font(.caption).foregroundStyle(
        workspace.isError ? .orange : .secondary)
      ForEach(workspace.artifact?.notes ?? [], id: \.self) {
        Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }.padding(12).navigationTitle("Lorem Ipsum Generator")
  }
}
struct MockDataView: View {
  @Bindable var workspace: TextWorkspace<MockOptions>
  @State private var selected: UUID?
  @State private var table = false
  @AppStorage("developerToolbox.text.040.format") private var format = "JSON"
  @AppStorage("developerToolbox.text.040.nullText") private var nullText = false
  @AppStorage("developerToolbox.text.040.spreadsheetSafe") private var safe = false
  @State private var serialized: String?
  @State private var serializationIssue: String?
  @State private var serializationRevision = UUID()
  @State private var serialization: Task<Void, Never>?
  @Environment(\.accessibilityReduceMotion) private var reduced
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextOptionsBar {
        Button("Generate") { workspace.run() }.keyboardShortcut(.return, modifiers: .command)
        Button("Cancel") { workspace.cancel() }.disabled(!workspace.busy)
        Text("Rows")
        TextField("Rows", value: $workspace.options.count, format: .number).frame(width: 80)
        TextField("Seed (optional)", text: $workspace.options.seed).frame(width: 180)
        Toggle("Table preview", isOn: $table)
      }
      GeometryReader { g in
        TextToolPanelLayout(wide: g.size.width >= 800, fraction: 0.4, collapse: 0) {
          schema
          Rectangle().fill(.secondary.opacity(0.15)).frame(width: 1)
          VStack(alignment: .leading, spacing: 6) {
            TextOptionsBar {
              TextChoice(title: "Format", value: $format, choices: ["JSON", "CSV", "TSV"])
              if format != "JSON" {
                Toggle("Null as ‘null’", isOn: $nullText)
                Toggle("Spreadsheet-safe strings", isOn: $safe)
              }
            }
            if table {
              tablePreview
            } else {
              TextOutputPanel(output: serialized, filename: "sample." + format.lowercased())
            }
            if let serializationIssue {
              Text(serializationIssue).font(.caption).foregroundStyle(.orange)
            }
          }
        }
      }
      Text(workspace.busy ? "Generating…" : workspace.status).font(.caption).foregroundStyle(
        workspace.isError ? .orange : .secondary)
      ForEach(workspace.artifact?.notes ?? [], id: \.self) {
        Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }.padding(12).navigationTitle("Mock Data Generator")
      .onChange(of: workspace.publication) { _, _ in serialize() }.onChange(of: format) { _, _ in
        serialize()
      }.onChange(of: nullText) { _, _ in serialize() }.onChange(of: safe) { _, _ in serialize() }
      .onAppear { serialize() }.onDisappear { serialization?.cancel() }
  }
  private var schema: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Fields").font(.headline)
        Spacer()
        Button("Add field", systemImage: "plus") {
          let f = MockField(name: "field\(workspace.options.fields.count+1)", kind: .text)
          workspace.options.fields.append(f)
          selected = f.id
        }.disabled(workspace.options.fields.count >= 32)
      }
      List(selection: $selected) {
        ForEach($workspace.options.fields) { $field in
          VStack(alignment: .leading) {
            HStack {
              TextField("Name", text: $field.name)
              Picker("Type", selection: $field.kind) {
                ForEach(MockFieldKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
              }.labelsHidden()
              Button {
                selected = selected == field.id ? nil : field.id
              } label: {
                Image(systemName: selected == field.id ? "chevron.up" : "slider.horizontal.3")
              }.buttonStyle(.borderless).accessibilityLabel("Configure \(field.name)")
            }
            if selected == field.id { fieldOptions($field) }
          }.tag(field.id)
        }.onMove { workspace.options.fields.move(fromOffsets: $0, toOffset: $1) }
      }.listStyle(.plain)
      HStack {
        Button("Move up") { move(-1) }.disabled(selected == nil)
        Button("Move down") { move(1) }.disabled(selected == nil)
        Spacer()
        Button("Remove", role: .destructive) {
          workspace.options.fields.removeAll { $0.id == selected }
          selected = nil
        }.disabled(workspace.options.fields.count <= 1 || selected == nil)
      }.buttonStyle(.borderless)
      Text(
        "Synthetic flat data · 32 fields / 10,000 rows maximum · Versioned seed, not cryptographic randomness"
      ).font(.caption2).foregroundStyle(.secondary)
    }.padding(8)
  }
  @ViewBuilder private func fieldOptions(_ f: Binding<MockField>) -> some View {
    let kind = f.wrappedValue.kind
    VStack(alignment: .leading, spacing: 6) {
      if kind == .sequence {
        TextField("Start", text: f.start)
        TextField("Step", text: f.step)
      }
      if kind == .integer || kind == .decimal {
        TextField("Minimum integer", text: f.minimum)
        TextField("Maximum integer", text: f.maximum)
        if kind == .decimal {
          Stepper("Decimal scale: \(f.wrappedValue.scale)", value: f.scale, in: 0...6)
          Text("Bounds are scaled integers: 123 at scale 2 means 1.23.").font(.caption)
        }
      }
      if kind == .boolean {
        Stepper("True: \(f.wrappedValue.truePercent)%", value: f.truePercent, in: 0...100)
      }
      if kind == .date {
        TextField("Start UTC · yyyy-MM-dd'T'HH:mm:ssZ", text: f.dateStart)
        TextField("End UTC", text: f.dateEnd)
      }
      if kind == .enumeration {
        Text("Enum values, one per line").font(.caption)
        TextEditor(text: f.enumValues).frame(height: 100)
      }
      if kind == .text {
        Stepper("Words: \(f.wrappedValue.wordCount)", value: f.wordCount, in: 1...100)
      }
      if kind == .email {
        Picker("Domain", selection: f.domain) {
          ForEach(["example.com", "example.net", "example.org"], id: \.self) { Text($0) }
        }
      }
      if kind != .sequence {
        Stepper("Null: \(f.wrappedValue.nullPercent)%", value: f.nullPercent, in: 0...100)
      }
    }.textFieldStyle(.roundedBorder).padding(.vertical, 4)
  }
  private func move(_ d: Int) {
    guard let i = workspace.options.fields.firstIndex(where: { $0.id == selected }),
      workspace.options.fields.indices.contains(i + d)
    else { return }
    withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) {
      workspace.options.fields.swapAt(i, i + d)
    }
  }
  private var tablePreview: some View {
    GeometryReader { g in
      ScrollView(.horizontal) {
        VStack(spacing: 0) {
          if let data = workspace.artifact?.mock {
            HStack(spacing: 0) {
              ForEach(Array(data.fields.enumerated()), id: \.offset) { _, field in
                Text(field).font(.headline).lineLimit(1).frame(width: 160, alignment: .leading)
                  .padding(6)
              }
            }
            List(Array(data.rows.enumerated()), id: \.offset) { i, row in
              HStack(spacing: 0) {
                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                  Text(TextDisplay.safe(value.text)).font(.system(.body, design: .monospaced))
                    .lineLimit(1).frame(width: 160, alignment: .leading).padding(6)
                }
              }.accessibilityLabel("Row \(i+1)")
            }.listStyle(.plain)
          } else {
            ContentUnavailableView(
              "No dataset", systemImage: "tablecells",
              description: Text("Configure fields and choose Generate."))
          }
        }.frame(
          width: max(g.size.width, CGFloat(workspace.artifact?.mock?.fields.count ?? 1) * 172),
          height: g.size.height)
      }.scrollIndicators(.visible)
    }
  }
  private func serialize() {
    serialization?.cancel()
    serializationRevision = UUID()
    let rev = serializationRevision
    serialized = nil
    serializationIssue = nil
    guard let data = workspace.artifact?.mock else { return }
    let f = format
    let n = nullText
    let s = safe
    serialization = Task {
      let work = Task.detached { try data.serialize(format: f, nullText: n, spreadsheetSafe: s) }
      let result = await withTaskCancellationHandler {
        await work.result
      } onCancel: {
        work.cancel()
      }
      guard !Task.isCancelled, serializationRevision == rev else { return }
      switch result {
      case .success(let output): serialized = output
      case .failure(let e):
        serializationIssue = (e as? TextFailure)?.message ?? "Serialization failed"
      }
    }
  }
}
