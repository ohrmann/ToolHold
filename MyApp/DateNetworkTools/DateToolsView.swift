import SwiftUI

struct DateToolsView: View {
  @Bindable var workspace: CalculationWorkspace<DateCalculationRequest>
  @State private var zoneSearch = ""
  @State private var formats = false
  @AppStorage("developerToolbox.date.unit") private var preferredUnit = 0
  @AppStorage("developerToolbox.date.cronDialect") private var preferredCron = CronDialect.unix
    .rawValue
  @Environment(\.accessibilityReduceMotion) private var reduced
  private var tool: DateTool { workspace.request.tool }
  var body: some View {
    CalculationPanels {
      VStack(alignment: .leading, spacing: 14) {
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        if tool == .unix {
          Picker("Input", selection: $workspace.request.mode) {
            ForEach(DateInputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented)
          if workspace.request.mode == .timestamp {
            Picker("Unit", selection: $workspace.request.unit) {
              ForEach(TimestampUnit.allCases, id: \.self) { Text($0.label).tag($0) }
            }.onChange(of: workspace.request.unit) { _, v in preferredUnit = v.rawValue }
          }
        }
        if tool == .zones {
          Picker("Source format", selection: $workspace.request.profile) {
            Text("Auto · local or offset").tag(DateTextProfile.auto)
            Text("Local date and time").tag(DateTextProfile.local)
            Text("RFC 3339 instant").tag(DateTextProfile.rfc3339)
          }
          Text(
            "For local input, changing the source zone changes the interpreted instant. An explicit offset identifies the instant independently."
          ).font(.caption).foregroundStyle(.secondary)
        }
        if tool == .iso {
          Picker("Format", selection: $workspace.request.profile) {
            ForEach(DateTextProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
        }
        if tool == .cron {
          Picker("Dialect", selection: $workspace.request.cronDialect) {
            ForEach(CronDialect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.onChange(of: workspace.request.cronDialect) { _, v in preferredCron = v.rawValue }
        }
        UtilityLabeledField(
          title: tool == .cron ? "Expression" : "Input", text: $workspace.request.input,
          placeholder: placeholder)
        if tool != .cron {
          HStack {
            Button("Use Now · Device clock", systemImage: "clock") { useNow() }
            Button("Clear") {
              workspace.request.input = ""
              workspace.request.choice = ""
              workspace.cancel()
            }
          }.buttonStyle(.borderless)
        }
        UtilityLabeledField(
          title: tool == .cron ? "Schedule time zone" : "Time zone for local input / display",
          text: $workspace.request.zone, placeholder: "UTC, Europe/Prague or +05:45")
        if tool == .iso || (tool == .unix && workspace.request.mode == .date) || tool == .zones {
          UtilityLabeledField(
            title: "Time for date-only input (optional)", text: $workspace.request.dateOnlyTime,
            placeholder: "HH:mm:ss — never assumed")
        }
        if tool == .zones { destinationControls }
        if tool == .arithmetic { arithmeticControls }
        if tool == .cron {
          UtilityLabeledField(
            title: "Reference instant (exclusive)", text: $workspace.request.secondInput,
            placeholder: "2026-10-25T00:00:00Z")
          Button("Use Now · Device clock") {
            workspace.request.secondInput =
              (try? ToolTimeZone("UTC").display(ExactInstant.now())) ?? ""
          }
          Stepper(
            "Occurrences: \(workspace.request.occurrenceCount)",
            value: $workspace.request.occurrenceCount, in: 1...100)
          HStack {
            Button("Explain") {
              workspace.request.findOccurrences = false
              workspace.run()
            }
            Button("Find Next") {
              workspace.request.findOccurrences = true
              workspace.run()
            }.keyboardShortcut(.return, modifiers: .command)
          }
          Text(
            "Five fields by default. Seconds-first is a Toolbox profile, not Quartz. Next occurrences are calculated only on request."
          ).font(.caption).foregroundStyle(.secondary)
        } else {
          Button(tool == .iso ? "Parse & Convert" : "Calculate") { workspace.run() }
            .keyboardShortcut(.return, modifiers: .command)
          Toggle("Calculate after editing", isOn: $workspace.automatic)
        }
        DisclosureGroup("Supported formats & limits", isExpanded: $formats) {
          Text(
            "Timestamp: exact seconds / milliseconds / microseconds. Date-time: YYYY-MM-DDTHH:mm:ss[.fraction]Z or numeric offset; local date-time with an explicit zone. ISO basic calendar and date-time, week dates and ordinal dates are supported. Date-only conversion requires a time. Up to 9 fractional digits (extra zeros allowed); years 0001–9999. Leap-second conversion, durations, intervals and zone annotations are not supported. Input 256 UTF-16 units; Cron 1024, up to 100 results and 8 years / 1 second search budget. Time-zone rules use this device’s tzdb: \(ToolTimeZone.dataVersion)."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.animation(reduced ? nil : .easeInOut(duration: 0.2), value: formats)
      }
    } output: {
      CalculationResults(workspace: workspace) { id, target in
        if target { workspace.request.targetChoice = id } else { workspace.request.choice = id }
        workspace.run()
      }
    }
  }

  private var placeholder: String {
    if tool == .cron { return "*/15 * * * *" }
    if tool == .unix && workspace.request.mode == .timestamp { return "e.g. 0 or -0.000001" }
    return "2026-10-25T02:30:00 or 2026-10-25T00:30:00Z"
  }
  private var subtitle: String {
    switch tool {
    case .unix: "Exact epoch units and calendar dates."
    case .iso: "Inspect supported ISO / RFC date representations."
    case .zones: "One instant across selected time zones."
    case .arithmetic: "Elapsed duration, calendar changes, or exact difference."
    case .cron: "Explain a schedule and find its next clock occurrences."
    }
  }
  private func useNow() {
    let now = ExactInstant.now()
    workspace.request.input =
      (tool == .unix && workspace.request.mode == .timestamp
        ? try? now.text(unit: workspace.request.unit) : try? ToolTimeZone("UTC").display(now)) ?? ""
  }
  @ViewBuilder private var arithmeticControls: some View {
    Picker("Operation", selection: $workspace.request.arithmetic) {
      ForEach(ArithmeticMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }
    if workspace.request.arithmetic == .difference {
      UtilityLabeledField(
        title: "End instant", text: $workspace.request.secondInput,
        placeholder: "Date-time with Z or offset")
    } else {
      Picker("Direction", selection: $workspace.request.subtract) {
        Text("Add").tag(false)
        Text("Subtract").tag(true)
      }.pickerStyle(.segmented)
      if workspace.request.arithmetic == .calendar {
        component("Years", value: $workspace.request.delta.years)
        component("Months", value: $workspace.request.delta.months)
        component("Weeks", value: $workspace.request.delta.weeks)
        Toggle("Clamp end of month", isOn: $workspace.request.clamp)
      }
      component("Days", value: $workspace.request.delta.days)
      component("Hours", value: $workspace.request.delta.hours)
      component("Minutes", value: $workspace.request.delta.minutes)
      if workspace.request.arithmetic == .calendar {
        component("Seconds", value: $workspace.request.delta.seconds)
      } else {
        UtilityLabeledField(
          title: "Seconds (fraction allowed)", text: $workspace.request.secondsText)
      }
    }
  }
  private func component(_ title: String, value: Binding<String>) -> some View {
    HStack {
      Text(title)
      Spacer()
      UtilityField(title: title, text: value).frame(minHeight: 30).frame(
        maxWidth: 140
      ).accessibilityLabel(title)
    }
  }
  private var destinationControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Destination zones (up to 12)").font(.headline)
      Button("Add Device Zone") {
        let systemID = TimeZone.current.identifier
        let id = systemID == "GMT" ? "UTC" : systemID
        if !workspace.request.destinationZones.contains(id) {
          workspace.request.destinationZones.append(id)
        }
      }.disabled(workspace.request.destinationZones.count >= 12)
      ForEach(Array(workspace.request.destinationZones.enumerated()), id: \.element) {
        index, zone in
        HStack {
          Text(zone).lineLimit(1)
          Spacer()
          Button {
            if index > 0 { workspace.request.destinationZones.swapAt(index, index - 1) }
          } label: {
            Image(systemName: "arrow.up")
          }.disabled(index == 0).accessibilityLabel("Move \(zone) up")
          Button {
            workspace.request.destinationZones.remove(at: index)
          } label: {
            Image(systemName: "minus.circle")
          }.accessibilityLabel("Remove \(zone)")
          Button("Swap") { swap(zone, index: index) }.disabled(
            workspace.report?.rows.isEmpty != false || workspace.report?.choices.isEmpty != true)
        }.buttonStyle(.borderless)
      }
      UtilityLabeledField(
        title: "Find a time zone", text: $zoneSearch, placeholder: "City or IANA zone name")
      if !zoneSearch.isEmpty {
        ForEach(
          (["UTC"] + TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }).filter {
            $0.localizedCaseInsensitiveContains(zoneSearch)
          }.prefix(15), id: \.self
        ) { zone in
          Button("Add " + zone) {
            if !workspace.request.destinationZones.contains(zone) {
              workspace.request.destinationZones.append(zone)
            }
            zoneSearch = ""
          }.disabled(workspace.request.destinationZones.count >= 12)
        }
        Text("Showing up to 15 matches; refine the query.").font(.caption).foregroundStyle(
          .secondary)
      }
    }
  }
  private func swap(_ target: String, index: Int) {
    guard let (instant, _) = try? DateCalculations.source(workspace.request), let instant,
      let zone = try? ToolTimeZone(target), let civil = try? zone.civil(instant)
    else { return }
    let previous = workspace.request.zone
    workspace.request.input = civil.text
    workspace.request.zone = target
    workspace.request.profile = .local
    workspace.request.choice = DateCalculations.choiceID(instant)
    workspace.request.destinationZones[index] = previous
    workspace.request.destinationZones = workspace.request.destinationZones.reduce(into: []) {
      if !$0.contains($1) { $0.append($1) }
    }
  }
}
