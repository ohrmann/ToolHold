import SwiftUI

struct TextComparisonControls: View {
  @Binding var options: TextComparisonOptions
  var body: some View {
    HStack {
      Toggle("Ignore case", isOn: $options.ignoreCase)
      Toggle("Trim edges", isOn: $options.trim)
      Toggle("Ignore spaces / tabs", isOn: $options.ignoreSpaces)
    }.toggleStyle(.checkboxCompatible)
  }
}
struct TextOptionsBar<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    ScrollView(.horizontal) { HStack(spacing: 14, content: content).padding(.vertical, 3) }
      .scrollIndicators(.visible)
  }
}
struct TextCaseView: View {
  @Bindable var workspace: TextWorkspace<TextCaseOptions>
  @State private var commands = JSONEditorCommands()
  var body: some View {
    TextToolSurface(workspace: workspace, action: "Convert", inputCommands: commands) {
      TextOptionsBar {
        TextChoice(
          title: "Case", value: $workspace.options.mode,
          choices: [
            "camelCase", "PascalCase", "snake_case", "kebab-case", "CONSTANT_CASE", "Train-Case",
            "lowercase", "UPPERCASE",
          ])
        Toggle("Each line separately", isOn: $workspace.options.perLine)
      }
    } results: {
      TextOutputPanel(
        output: workspace.artifact?.output, wrap: workspace.wordWrap,
        apply: {
          if let output = workspace.artifact?.output {
            commands.replace?(.init(location: 0, length: workspace.input.utf16.count), output)
          }
        })
    }.navigationTitle("Case Converter")
  }
}
struct TextListView: View {
  @Bindable var workspace: TextWorkspace<ListComparisonOptions>
  @State private var details = false
  var body: some View {
    TextToolSurface(workspace: workspace, action: "Compare", twoInputs: true) {
      VStack(alignment: .leading, spacing: 4) {
        TextOptionsBar {
          TextChoice(
            title: "Operation", value: $workspace.options.operation,
            choices: ["Intersection", "A only", "B only", "Union", "Symmetric difference"])
          Toggle("Multiset", isOn: $workspace.options.multiset)
          Toggle("Ignore empty items", isOn: $workspace.options.ignoreEmpty)
          Toggle("Details", isOn: $details)
        }
        TextOptionsBar {
          TextComparisonControls(options: $workspace.options.comparison)
          Picker("Output endings", selection: $workspace.options.ending) {
            Text("LF").tag("\n")
            Text("CRLF").tag("\r\n")
          }
          Toggle("Final newline", isOn: $workspace.options.terminal)
        }
      }
    } results: {
      if details {
        TextRowsPanel(rows: workspace.artifact?.rows ?? [], selection: $workspace.selection) {
          workspace.navigate($0.left, $0.right)
        }
      } else {
        TextOutputPanel(output: workspace.artifact?.output, wrap: workspace.wordWrap)
      }
    }.navigationTitle("List Comparison")
  }
}
struct TextSortView: View {
  @Bindable var workspace: TextWorkspace<LineSortOptions>
  @State private var commands = JSONEditorCommands()
  var body: some View {
    TextToolSurface(workspace: workspace, action: "Process", inputCommands: commands) {
      VStack(alignment: .leading, spacing: 4) {
        TextOptionsBar {
          TextChoice(
            title: "Operation", value: $workspace.options.operation,
            choices: ["Sort & Deduplicate", "Sort", "Deduplicate"])
          TextChoice(
            title: "Order", value: $workspace.options.order,
            choices: ["Ordinal", "Natural numeric", "Locale-aware"])
          Toggle("Descending", isOn: $workspace.options.descending)
        }
        TextOptionsBar {
          Toggle("Keep last duplicate", isOn: $workspace.options.last)
          Toggle("Ignore empty", isOn: $workspace.options.ignoreEmpty)
          Toggle("Trim output", isOn: $workspace.options.trimOutput)
          TextComparisonControls(options: $workspace.options.comparison)
        }
        TextOptionsBar {
          Picker("Line endings", selection: $workspace.options.ending) {
            Text("Preserve").tag("Preserve")
            Text("CR").tag("\r")
            Text("LF").tag("\n")
            Text("CRLF").tag("\r\n")
          }
          if workspace.options.order == "Locale-aware" {
            TextField("Locale identifier", text: $workspace.options.locale).frame(width: 150)
            Text("System collation; may vary by OS").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    } results: {
      TextOutputPanel(
        output: workspace.artifact?.output, wrap: workspace.wordWrap,
        apply: {
          if let output = workspace.artifact?.output {
            commands.replace?(.init(location: 0, length: workspace.input.utf16.count), output)
          }
        })
    }.navigationTitle("Line Sort / Deduplicate")
  }
}
struct TextUnicodeView: View {
  @Bindable var workspace: TextWorkspace<UnicodeWorkspaceOptions>
  @State private var preview = false
  var body: some View {
    TextToolSurface(workspace: workspace, action: "Inspect") {
      TextOptionsBar {
        TextChoice(
          title: "Show", value: $workspace.options.filter,
          choices: ["All", "Invisible & controls", "Non-ASCII", "Confusable hints"])
        TextChoice(
          title: "Normalization", value: $workspace.options.normalization,
          choices: ["Original", "NFC", "NFD", "NFKC", "NFKD"])
        Toggle("Normalization preview", isOn: $preview)
      }
    } results: {
      if preview {
        TextOutputPanel(
          output: workspace.artifact?.output, title: "Normalization Preview",
          wrap: workspace.wordWrap)
      } else {
        VStack(alignment: .leading) {
          HStack {
            Text("Scalars · select for details").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let row = workspace.artifact?.rows.first(where: { $0.id == workspace.selection }),
              let range = row.left
            {
              Menu("Copy") {
                Button("Character") {
                  TextClipboard.copy(TextDisplay.substring(workspace.input, range))
                }
                Button("Code point") { TextClipboard.copy(row.label) }
                Button("Escaped form") {
                  let s = TextDisplay.substring(workspace.input, range)
                  TextClipboard.copy(
                    s.unicodeScalars.map { String(format: "\\u{%X}", $0.value) }.joined())
                }
                Button("UTF-8 bytes") {
                  TextClipboard.copy(
                    TextDisplay.substring(workspace.input, range).utf8.map {
                      String(format: "%02X", $0)
                    }.joined(separator: " "))
                }
              }
            }
          }
          TextRowsPanel(rows: workspace.artifact?.rows ?? [], selection: $workspace.selection) {
            workspace.navigate($0.left)
          }
        }
      }
    }.navigationTitle("Unicode Inspector")
  }
}
struct TextStatisticsView: View {
  @Bindable var workspace: TextWorkspace<StatisticsOptions>
  @State private var summary = false
  var body: some View {
    TextToolSurface(workspace: workspace, action: "Count") {
      HStack {
        Toggle("Copy / export summary", isOn: $summary)
        Spacer()
      }
    } results: {
      if summary {
        TextOutputPanel(
          output: workspace.artifact?.output, title: "Summary", wrap: workspace.wordWrap)
      } else {
        TextRowsPanel(rows: workspace.artifact?.rows ?? [], selection: $workspace.selection) {
          workspace.navigate($0.left)
        }
      }
    }.navigationTitle("Text Statistics")
  }
}
struct TextRegexView: View {
  @Bindable var workspace: TextWorkspace<RegexWorkspaceOptions>
  var replacement = false
  @State private var outputPreview = false
  @State private var commands = JSONEditorCommands()
  var body: some View {
    TextToolSurface(
      workspace: workspace, action: replacement ? "Preview Replace" : "Find Matches",
      inputCommands: commands
    ) {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Pattern").font(.headline)
          TextField(
            "Raw PCRE2 pattern (without / delimiters)", text: $workspace.options.pattern,
            axis: .vertical
          )
          .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).lineLimit(1...3)
        }
        TextOptionsBar {
          Text("PCRE2 10.49 · UTF / UCP").font(.caption).foregroundStyle(.secondary)
          Toggle("i", isOn: $workspace.options.regex.ignoreCase).help("Case insensitive")
          Toggle("m", isOn: $workspace.options.regex.multiline).help("Multiline anchors")
          Toggle("s", isOn: $workspace.options.regex.dotAll).help("Dot matches newline")
          Toggle("x", isOn: $workspace.options.regex.extended).help("Extended pattern")
          Toggle("Literal", isOn: $workspace.options.regex.literal)
          Toggle("First only", isOn: $workspace.options.regex.first)
        }
        if replacement {
          HStack {
            Text("Replacement")
            TextField("$0, $1, ${name}, $$", text: $workspace.options.replacement, axis: .vertical)
              .textFieldStyle(
                .roundedBorder
              ).font(.system(.body, design: .monospaced))
          }
          TextOptionsBar {
            Toggle("Literal replacement", isOn: $workspace.options.literalReplacement)
            Toggle("Output preview", isOn: $outputPreview)
            Button("Replace All") {
              workspace.options.current = nil
              workspace.run()
              outputPreview = true
            }
            Button("Replace Current") {
              workspace.options.current = workspace.selection
              workspace.run()
              outputPreview = true
            }.disabled(workspace.selection == nil)
          }
        }
      }.toggleStyle(.checkboxCompatible)
    } results: {
      if replacement && outputPreview {
        TextOutputPanel(
          output: workspace.artifact?.output, wrap: workspace.wordWrap,
          apply: {
            if let output = workspace.artifact?.output {
              commands.replace?(.init(location: 0, length: workspace.input.utf16.count), output)
            }
          })
      } else {
        VStack(alignment: .leading) {
          Text("Pattern Matches").font(.headline)
          Text("Text fragments matched by your pattern.")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Spacer()
            Button("Copy Match") {
              if let result = workspace.artifact?.regex, let id = workspace.selection,
                let match = result.matches.first(where: { $0.id == id })
              {
                TextClipboard.copy(TextDisplay.substring(result.source, match.range))
              }
            }.disabled(workspace.selection == nil)
            Button("Previous") { move(-1) }.keyboardShortcut("g", modifiers: [.command, .shift])
              .disabled(
                workspace.artifact?.regex?.matches.isEmpty ?? true)
            Button("Next") { move(1) }.keyboardShortcut("g", modifiers: .command).disabled(
              workspace.artifact?.regex?.matches.isEmpty ?? true)
          }
          TextRowsPanel(rows: workspace.artifact?.rows ?? [], selection: $workspace.selection) {
            workspace.navigate($0.left)
          }
          .overlay {
            if !workspace.busy, workspace.artifact?.regex?.matches.isEmpty == true {
              VStack(spacing: 8) {
                Text("No matches").font(.headline)
                Text(
                  "The pattern is valid, but it did not match the input. This does not mean the input is invalid."
                )
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
              }.padding(24).allowsHitTesting(false)
            }
          }
          if let result = workspace.artifact?.regex, let id = workspace.selection,
            let match = result.matches.first(where: { $0.id == id })
          {
            ScrollView {
              VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(match.groups.enumerated()), id: \.offset) { g, r in
                  HStack(alignment: .top) {
                    Text("$\(g)" + (result.names[g].map { " · " + $0 } ?? "")).font(.caption)
                    Text(
                      r.map { TextDisplay.safe(TextDisplay.substring(result.source, $0)) }
                        ?? "Unmatched"
                    ).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    if let r {
                      Button("Show") {
                        workspace.captureMarker = r
                        workspace.navigate(r)
                      }
                      Button("Copy") { TextClipboard.copy(TextDisplay.substring(result.source, r)) }
                    }
                  }
                }
              }
            }.frame(maxHeight: 150)
          }
        }.padding(8).onKeyPress(.return, phases: .down) { press in
          move(press.modifiers.contains(.shift) ? -1 : 1)
          return .handled
        }
      }
    }.navigationTitle(replacement ? "Find & Replace with Regex" : "Regex Tester")
  }
  private func move(_ delta: Int) {
    guard let result = workspace.artifact?.regex, !result.matches.isEmpty else { return }
    let n = result.matches.count
    let i = ((workspace.selection ?? (delta > 0 ? -1 : 0)) + delta + n) % n
    workspace.selection = i
    workspace.navigate(result.matches[i].range)
  }
}
