import SwiftUI
import UniformTypeIdentifiers

struct NetworkToolsView: View {
  @Bindable var workspace: CalculationWorkspace<NetworkCalculationRequest>
  @State private var focus = 0
  @State private var undoModes: [UInt16] = []
  private var tool: NetworkTool { workspace.request.tool }
  var body: some View {
    CalculationPanels {
      VStack(alignment: .leading, spacing: 14) {
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        if tool == .http || tool == .mime {
          HStack {
            UtilityField(
              title: workspace.request.contentType ? "Content-Type value" : "Search",
              text: $workspace.request.input, focusToken: focus
            ).frame(minHeight: 32)
            Button {
              workspace.request.input = ""
            } label: {
              Image(systemName: "xmark.circle")
            }.accessibilityLabel("Clear search")
          }
          Button("Focus Search") { focus += 1 }.keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.borderless)
        } else {
          UtilityLabeledField(
            title: tool == .cidr ? "Address / prefix" : "Mode", text: $workspace.request.input,
            placeholder: tool == .cidr
              ? "192.168.1.130/25 or 2001:db8::/32"
              : workspace.request.symbolic ? "rwxr-xr-x" : "0755")
        }
        if tool == .cidr {
          UtilityLabeledField(
            title: "Compare address / network (optional)", text: $workspace.request.comparison,
            placeholder: "Same-family CIDR or individual address")
          Text(
            "IPv4 and IPv6. No hostname lookup, host enumeration, ports or zone IDs. Maximum 256 UTF-16 units per field."
          ).font(.caption).foregroundStyle(.secondary)
        }
        if tool == .http {
          Picker("Class", selection: $workspace.request.category) {
            Text("All").tag(0)
            Text("1xx · Informational").tag(1)
            Text("2xx · Success").tag(2)
            Text("3xx · Redirection").tag(3)
            Text("4xx · Client error").tag(4)
            Text("5xx · Server error").tag(5)
          }
          Text(
            "Search by code or registered name. Unassigned ranges are shown explicitly. Expand an entry’s details for explanation and source references."
          ).font(.caption).foregroundStyle(.secondary)
        }
        if tool == .mime {
          Toggle("Parse Content-Type header value", isOn: $workspace.request.contentType)
          if !workspace.request.contentType {
            Picker("Search in", selection: $workspace.request.mimeMode) {
              ForEach(["All", "Media Types", "Extensions"], id: \.self) { Text($0).tag($0) }
            }
            Text(
              "Search a media type, extension or filename. Registered types and curated extension hints are labelled separately."
            ).font(.caption).foregroundStyle(.secondary)
            if let suggestion = systemSuggestion {
              Text("OS suggestion (UTType, not IANA): \(suggestion)").font(.caption)
                .foregroundStyle(.secondary)
            }
          } else {
            Text(
              "Parameters retain order and duplicates. Quoted separators are supported; CR/LF is rejected. Limit: 8192 UTF-16 units / 128 parameters."
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
        if tool == .chmod { permissionControls }
        HStack {
          Button(tool == .http || tool == .mime ? "Search / Parse" : "Calculate") {
            workspace.run()
          }.keyboardShortcut(.return, modifiers: .command)
          Button("Clear") {
            workspace.request.input = ""
            workspace.request.comparison = ""
            workspace.request.expression = ""
            undoModes = []
            workspace.cancel()
          }
        }
        Toggle("Calculate after editing", isOn: $workspace.automatic)
      }
    } output: {
      if tool == .http || (tool == .mime && !workspace.request.contentType) {
        ReferenceResultsView(workspace: workspace)
      } else {
        CalculationResults(workspace: workspace)
      }
    }
    .onChange(of: workspace.request.input) { _, _ in
      if tool == .chmod, let parsedMode, parsedMode.bits != workspace.request.lastPermissionBits {
        workspace.request.lastPermissionBits = parsedMode.bits
      }
    }
    .onAppear {
      if workspace.report == nil && workspace.issue == nil && (tool == .http || tool == .mime) {
        workspace.run()
      }
    }
  }
  private var subtitle: String {
    switch tool {
    case .cidr: "Exact IPv4 / IPv6 networks and range relations."
    case .http: "Offline IANA HTTP status reference."
    case .mime: "Offline media types, filename hints and header parameters."
    case .chmod: "Calculate permission bits without changing files."
    }
  }
  private var systemSuggestion: String? {
    let q = workspace.request.input
    guard q.count <= 256, !q.isEmpty, !q.contains("/"), !q.contains(";"),
      let ext = q.split(separator: ".").last
    else { return nil }
    return UTType(filenameExtension: String(ext))?.preferredMIMEType
  }
  private var parsedMode: PermissionMode? {
    try? workspace.request.symbolic
      ? PermissionMode(symbolic: workspace.request.input)
      : PermissionMode(octal: workspace.request.input)
  }
  private var mode: PermissionMode? {
    parsedMode ?? .init(bits: workspace.request.lastPermissionBits)
  }
  private var permissionControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker(
        "Mode syntax",
        selection: Binding(
          get: { workspace.request.symbolic },
          set: { symbolic in
            let existing = mode!
            if workspace.request.symbolic {
              workspace.request.symbolicDraft = workspace.request.input
            } else {
              workspace.request.octalDraft = workspace.request.input
            }
            workspace.request.symbolic = symbolic
            let draft = symbolic ? workspace.request.symbolicDraft : workspace.request.octalDraft
            workspace.request.input =
              draft.isEmpty ? (symbolic ? existing.symbolic : existing.octal) : draft
          })
      ) {
        Text("Octal").tag(false)
        Text("Symbolic").tag(true)
      }.pickerStyle(.segmented)
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
        GridRow {
          Text("Who")
          Text("Read")
          Text("Write")
          Text("Execute")
        }
        ForEach(0..<3) { row in
          GridRow {
            Text(["Owner", "Group", "Others"][row])
            ForEach(0..<3) { column in
              permissionToggle(
                ["Read", "Write", "Execute"][column] + " " + ["owner", "group", "others"][row],
                mask: 1 << (8 - row * 3 - column)
              ).labelsHidden()
            }
          }
        }
      }
      permissionToggle("Set user ID", mask: 0o4000)
      permissionToggle("Set group ID", mask: 0o2000)
      permissionToggle("Sticky", mask: 0o1000)
      Text(
        parsedMode == nil
          ? "Input is incomplete or invalid. Grid retains the last valid mask; changing a bit replaces the draft explicitly."
          : "Grid and mode share the same 12 bits."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        ForEach(["0644", "0755", "0700"], id: \.self) { value in
          Button(value) { setMode(try! PermissionMode(octal: value)) }
        }
      }
      UtilityLabeledField(
        title: "Symbolic change (preview)", text: $workspace.request.expression,
        placeholder: "u+x,g=u,o-rwx")
      Toggle("Directory semantics for X", isOn: $workspace.request.directory)
      HStack {
        Button("Apply Preview") {
          if let row = workspace.report?.rows.first(where: { $0.id == "previewOctal" }),
            let value = try? PermissionMode(octal: row.value)
          {
            setMode(value)
          }
        }.disabled(workspace.report?.rows.contains(where: { $0.id == "previewOctal" }) != true)
        Button("Undo Mode Change") {
          if let previous = undoModes.popLast() {
            setMode(.init(bits: previous), recordUndo: false)
          }
        }.disabled(undoModes.isEmpty)
      }
      Text(
        "Explicit u/g/o/a required. Operators + − =; permissions rwxXst or one copy operand u/g/o. Expressions are applied sequentially to the declared bits, not to a real filesystem."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  private func permissionToggle(_ title: String, mask: UInt16) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { mode.map { $0.bits & mask != 0 } ?? false },
        set: { checked in
          if let mode { setMode(.init(bits: checked ? mode.bits | mask : mode.bits & ~mask)) }
        })
    ).disabled(mode == nil).accessibilityLabel(title)
  }
  private func setMode(_ value: PermissionMode, recordUndo: Bool = true) {
    if recordUndo, let mode { undoModes.append(mode.bits) }
    workspace.request.lastPermissionBits = value.bits
    workspace.request.octalDraft = value.octal
    workspace.request.symbolicDraft = value.symbolic
    workspace.request.input = workspace.request.symbolic ? value.symbolic : value.octal
  }
}
