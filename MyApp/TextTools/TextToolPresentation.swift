import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TextExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  let data: Data
  init(_ text: String) { data = Data(text.utf8) }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
enum TextClipboard {
  static func copy(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif
  }
}
struct TextToolPanelLayout: Layout {
  var wide: Bool, fraction: Double, collapse: Double
  var animatableData: AnimatablePair<Double, Double> {
    get { .init(fraction, collapse) }
    set {
      fraction = newValue.first
      collapse = newValue.second
    }
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions(by: .init(width: 700, height: 500))
  }
  func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
  {
    guard subviews.count == 3 else { return }
    let length = wide ? b.width : b.height
    let gap = 10 * (1 - collapse)
    let first = max(0, (length - gap) * fraction * (1 - collapse))
    for (i, offset, size) in [
      (0, 0.0, first), (1, first, gap), (2, first + gap, max(0, length - first - gap)),
    ] {
      subviews[i].place(
        at: .init(x: b.minX + (wide ? offset : 0), y: b.minY + (wide ? 0 : offset)),
        anchor: .topLeading,
        proposal: .init(width: wide ? size : b.width, height: wide ? b.height : size))
    }
  }
}
struct TextToolDivider: View {
  var wide: Bool, length: CGFloat
  @Binding var fraction: Double
  @State private var start: Double?
  var body: some View {
    Rectangle().fill(.secondary.opacity(0.2)).frame(width: wide ? 1 : nil, height: wide ? nil : 1)
      .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()).gesture(
        DragGesture(minimumDistance: 3).onChanged { v in
          if start == nil { start = fraction }
          fraction = min(
            0.75,
            max(0.25, start! + (wide ? v.translation.width : v.translation.height) / max(1, length))
          )
        }.onEnded { _ in start = nil }
      ).accessibilityLabel("Panel proportions").accessibilityAdjustableAction { d in
        fraction = min(0.75, max(0.25, fraction + (d == .increment ? 0.05 : -0.05)))
      }
  }
}
struct TextDualInputLayout: Layout {
  let wide: Bool
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }
  func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
  {
    guard !subviews.isEmpty else { return }
    let count = CGFloat(subviews.count)
    let gap = 8.0
    let length = ((wide ? b.width : b.height) - gap * (count - 1)) / count
    for (i, v) in subviews.enumerated() {
      v.place(
        at: .init(
          x: b.minX + (wide ? CGFloat(i) * (length + gap) : 0),
          y: b.minY + (wide ? 0 : CGFloat(i) * (length + gap))), anchor: .topLeading,
        proposal: .init(width: wide ? length : b.width, height: wide ? b.height : length))
    }
  }
}
struct TextInputPanel: View {
  var title: String
  @Binding var text: String
  var wrap: Bool
  var target: NSRange?, jump: Int = 0, highlights: TextEditorHighlights?
  var paste: () -> Void
  var suppliedCommands: JSONEditorCommands?
  @State private var localCommands = JSONEditorCommands()
  private var commands: JSONEditorCommands { suppliedCommands ?? localCommands }
  @State private var importing = false
  @State private var issue: String?
  @Environment(\.accessibilityReduceMotion) private var reduced
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        Button("Open", systemImage: "folder") { importing = true }
        Button("Clear", systemImage: "xmark.circle") { commands.clear?() }.disabled(text.isEmpty)
      }.buttonStyle(.borderless)
      JSONTextEditor(
        text: $text, jumpTarget: target, jumpRequest: jump, animateJumps: !reduced,
        highlightJumps: true, focusOnJump: false, onPaste: paste, commands: commands,
        options: .init(
          syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false,
          matchingBrackets: false, wordWrap: wrap), placeholder: "Enter or paste text",
        contentName: title, matchHighlights: highlights
      )
      .frame(minWidth: 17, minHeight: 17).clipShape(RoundedRectangle(cornerRadius: 6))
      if let issue { Text(issue).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
    }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(
      RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.2))
    )
    .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
      guard case .success(let url) = result else { return }
      let snapshot = text
      Task {
        do {
          let value = try await Task.detached { try TextFileIO.read(url) }.value
          guard text.utf16.elementsEqual(snapshot.utf16) else {
            issue = "Input changed while opening the file."
            return
          }
          commands.replace?(.init(location: 0, length: text.utf16.count), value)
          issue = value.hasPrefix("\u{FEFF}") ? "UTF-8 BOM preserved as U+FEFF." : nil
          paste()
        } catch { issue = (error as? TextFailure)?.message ?? "Could not read file." }
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard urls.count == 1, let url = urls.first else { return false }
      let snapshot = text
      Task {
        do {
          let value = try await Task.detached { try TextFileIO.read(url) }.value
          guard text.utf16.elementsEqual(snapshot.utf16) else { return }
          commands.replace?(.init(location: 0, length: text.utf16.count), value)
          paste()
        } catch { issue = (error as? TextFailure)?.message ?? "Could not read file." }
      }
      return true
    }
  }
}
struct TextOutputPanel: View {
  let output: String?
  var title = "Output", filename = "result.txt"
  var wrap = true
  var apply: (() -> Void)?
  @State private var exporting = false
  @State private var document: TextExportDocument?
  @State private var issue: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        if let apply {
          Button("Apply to Input", action: apply).disabled(
            output == nil || (output?.utf16.count ?? 0) > TextBounds.input)
        }
        Button("Copy", systemImage: "doc.on.doc") { if let output { TextClipboard.copy(output) } }
          .disabled(output == nil)
        Button("Export", systemImage: "square.and.arrow.up") {
          if let output {
            document = TextExportDocument(output)
            exporting = true
          }
        }.disabled(output == nil)
      }.buttonStyle(.borderless)
      JSONTextEditor(
        text: .constant(output ?? ""), editable: false,
        options: .init(
          syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false,
          matchingBrackets: false), highlightingLimit: TextBounds.output,
        placeholder: output == nil ? "Run an operation to see the result" : "Empty result",
        contentName: title, showsLineNumbers: false
      ).frame(minWidth: 17, minHeight: 17)
      if apply != nil, (output?.utf16.count ?? 0) > TextBounds.input {
        Text("Output exceeds the Input processing limit; Copy and Export remain available.").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
    }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(
      RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.2))
    )
    .fileExporter(
      isPresented: $exporting, document: document, contentType: .data, defaultFilename: filename
    ) { r in if case .failure = r { issue = "Export did not complete." } }
  }
}
struct TextToolSurface<O: Codable & Equatable & Sendable, Controls: View, Results: View>: View {
  @Bindable var workspace: TextWorkspace<O>
  var action = "Run", twoInputs = false
  var inputCommands: JSONEditorCommands?
  @State private var firstCommands = JSONEditorCommands()
  @State private var secondCommands = JSONEditorCommands()
  @ViewBuilder var controls: () -> Controls
  @ViewBuilder var results: () -> Results
  @Environment(\.accessibilityReduceMotion) private var reduced
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        toolbar
        ScrollView(.horizontal) { toolbar }.scrollIndicators(.visible)
      }
      controls()
      GeometryReader { g in
        TextToolPanelLayout(
          wide: !twoInputs && g.size.width >= 760, fraction: workspace.fraction,
          collapse: workspace.collapsed ? 1 : 0
        ) {
          TextDualInputLayout(wide: twoInputs && g.size.width >= 760) {
            TextInputPanel(
              title: twoInputs ? "Before / A" : "Input", text: $workspace.input,
              wrap: workspace.wordWrap, target: workspace.target, jump: workspace.jumpRequest,
              highlights: highlights, paste: { workspace.paste() },
              suppliedCommands: inputCommands ?? firstCommands)
            if twoInputs {
              TextInputPanel(
                title: "After / B", text: $workspace.second, wrap: workspace.wordWrap,
                target: workspace.secondTarget, jump: workspace.jumpRequest,
                paste: { workspace.paste() }, suppliedCommands: secondCommands)
            }
          }.clipped().allowsHitTesting(!workspace.collapsed).accessibilityHidden(
            workspace.collapsed)
          TextToolDivider(
            wide: !twoInputs && g.size.width >= 760,
            length: !twoInputs && g.size.width >= 760 ? g.size.width : g.size.height,
            fraction: $workspace.fraction)
          results().frame(maxWidth: .infinity, maxHeight: .infinity)
        }.animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.collapsed)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          if workspace.showProgress { ProgressView().controlSize(.small) }
          Text(workspace.showProgress ? "Processing…" : workspace.status).font(.caption)
            .foregroundStyle(
              workspace.isError ? .orange : .secondary)
          Spacer()
        }
        if let notes = workspace.artifact?.notes {
          ForEach(notes, id: \.self) {
            Text($0).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }
      }.animation(reduced ? nil : .easeInOut(duration: 0.2), value: workspace.status)
    }.padding(12)
  }
  private var toolbar: some View {
    HStack(spacing: 12) {
      Button(action) { workspace.run() }.keyboardShortcut(.return, modifiers: .command)
      Button("Cancel") { workspace.cancel() }.keyboardShortcut(.escape, modifiers: []).disabled(
        !workspace.busy)
      Toggle("Auto", isOn: $workspace.automatic).toggleStyle(.checkboxCompatible)
      Toggle("Word Wrap", isOn: $workspace.wordWrap).toggleStyle(.checkboxCompatible)
      Spacer(minLength: 8)
      Button(workspace.collapsed ? "Edit Input" : "Hide Input") {
        if !workspace.collapsed {
          (inputCommands ?? firstCommands).resignFocus?()
          secondCommands.resignFocus?()
        }
        workspace.collapsed.toggle()
      }
    }
  }
  private var highlights: TextEditorHighlights? {
    guard let a = workspace.artifact, !a.highlights.isEmpty else { return nil }
    return .init(
      id: workspace.publication, source: workspace.input, ranges: a.highlights,
      active: workspace.selection.flatMap { i in a.regex?.matches.first { $0.id == i }?.range },
      capture: workspace.captureMarker)
  }
}
// A platform-native checkbox on Mac and switch on touch.
struct TextToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    #if os(macOS)
      Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
    #else
      Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch).fixedSize()
    #endif
  }
}
extension ToggleStyle where Self == TextToggleStyle {
  static var checkboxCompatible: Self { .init() }
}
struct TextChoice: View {
  let title: String
  @Binding var value: String
  let choices: [String]
  var body: some View {
    Picker(title, selection: $value) { ForEach(choices, id: \.self) { Text($0).tag($0) } }
      .fixedSize(horizontal: true, vertical: false)
  }
}
struct TextRowsPanel: View {
  let rows: [TextRow]
  @Binding var selection: Int?
  var navigate: (TextRow) -> Void
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Details").font(.headline)
        Spacer()
        if let row = rows.first(where: { $0.id == selection }) {
          Button("Show Source") { navigate(row) }.disabled(row.left == nil && row.right == nil)
          Button("Copy Details") { TextClipboard.copy(row.detail.isEmpty ? row.value : row.detail) }
        }
      }
      List(selection: $selection) {
        ForEach(rows) { row in
          HStack {
            Text(row.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(row.value).font(.system(.body, design: .monospaced)).lineLimit(1)
          }.tag(row.id).contentShape(Rectangle()).onTapGesture(count: 2) {
            selection = row.id
            navigate(row)
          }.accessibilityAction(named: "Show Source") { navigate(row) }
        }
      }.listStyle(.plain)
      if let row = rows.first(where: { $0.id == selection }), !row.detail.isEmpty {
        ScrollView {
          Text(row.detail).font(.caption).textSelection(.enabled).frame(
            maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 140)
      }
    }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 10))
  }
}
