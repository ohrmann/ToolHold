import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public enum DateTool: Int, CaseIterable, Sendable {
  case unix = 43
  case iso, zones, arithmetic, cron
}
public enum DateInputMode: String, CaseIterable, Sendable {
  case timestamp = "Timestamp"
  case date = "Date / time"
}
public enum ArithmeticMode: String, CaseIterable, Sendable {
  case elapsed = "Elapsed"
  case calendar = "Calendar"
  case difference = "Difference"
}
public struct CalendarDeltaDraft: Sendable {
  public var years = "0", months = "0", weeks = "0", days = "0", hours = "0", minutes = "0",
    seconds = "0"
  public init() {}
  public func parsed(calendar: Bool) throws -> CalendarDelta {
    var d = CalendarDelta()
    func number(_ s: String, _ field: String) throws -> Int {
      try CalculationInput.integer(s, field: field, range: 0...1_000_000)
    }
    if calendar {
      d.years = try number(years, "Years")
      d.months = try number(months, "Months")
      d.weeks = try number(weeks, "Weeks")
      d.seconds = try number(seconds, "Seconds")
    }
    d.days = try number(days, "Days")
    d.hours = try number(hours, "Hours")
    d.minutes = try number(minutes, "Minutes")
    return d
  }
}
public struct DateCalculationRequest: Sendable {
  public var tool: DateTool
  public var input = "", secondInput = "", zone = "UTC", destinationZones = ["UTC"]
  public var mode: DateInputMode = .timestamp
  public var unit: TimestampUnit = .seconds
  public var profile: DateTextProfile = .auto
  public var choice = "", targetChoice = "", dateOnlyTime = ""
  public var arithmetic: ArithmeticMode = .elapsed
  public var delta = CalendarDeltaDraft()
  public var secondsText = "0", subtract = false, clamp = true
  public var cronDialect: CronDialect = .unix
  public var occurrenceCount = 10
  public var findOccurrences = false
  public init(tool: DateTool) { self.tool = tool }
}
public enum DateCalculations {
  public static func choiceID(_ instant: ExactInstant) -> String {
    "\(instant.seconds):\(instant.nanosecond)"
  }
  static func resolve(_ civil: CivilTime, zone: ToolTimeZone, choice: String) throws -> (
    ExactInstant?, CalculationReport?
  ) {
    let candidates = try zone.resolve(civil)
    if candidates.isEmpty {
      throw CalculationIssue(
        .invalid,
        "This local time does not exist in \(zone.identifier) (clock gap). Choose another local time; it will not be shifted automatically."
      )
    }
    if candidates.count == 1 { return (candidates[0], nil) }
    if let selected = candidates.first(where: { choiceID($0) == choice }) { return (selected, nil) }
    let utc = try ToolTimeZone("UTC")
    return (
      nil,
      .init(
        notes: [
          "This local time occurs more than once. Select the intended instant. Input is unchanged."
        ],
        choices: try candidates.map {
          .init(choiceID($0), try utc.display($0) + " · " + zone.display($0))
        }, status: "Choose an occurrence")
    )
  }
  static func source(_ r: DateCalculationRequest) throws -> (ExactInstant?, CalculationReport?) {
    let p = try DateTextParser.parse(r.input, profile: r.profile)
    if let instant = try p.instant() { return (instant, nil) }
    var civil = p.time
    if civil == nil && !r.dateOnlyTime.isEmpty {
      civil = try DateTextParser.parse(p.date.text + "T" + r.dateOnlyTime, profile: .local).time
    }
    guard let civil else {
      return (
        nil,
        .init(
          rows: [.init("date", "Calendar date", p.date.text)],
          notes: [
            "A date alone has no instant. Enter an explicit time and select a time zone to convert."
          ], status: "Date only")
      )
    }
    return try resolve(civil, zone: ToolTimeZone(r.zone), choice: r.choice)
  }
  public static func instantReport(_ instant: ExactInstant, zone: ToolTimeZone) throws
    -> CalculationReport
  {
    var rows: [CalculationRow] = try TimestampUnit.allCases.map {
      .init("unit\($0.rawValue)", $0.label, try instant.text(unit: $0))
    }
    var notes = [
      "Exact integer seconds + nanoseconds. Calendar: proleptic Gregorian, years 0001–9999. System tzdb: \(ToolTimeZone.dataVersion)."
    ]
    do {
      rows.insert(.init("utc", "UTC", try ToolTimeZone("UTC").display(instant)), at: 0)
      rows.insert(.init("local", zone.identifier, try zone.display(instant)), at: 1)
    } catch let issue as CalculationIssue {
      notes.append(issue.message + " Exact unit conversions remain available.")
    }
    return .init(rows: rows, notes: notes, status: "Converted")
  }
  public static func process(_ r: DateCalculationRequest) throws -> CalculationReport {
    try Task.checkCancellation()
    let zone = try ToolTimeZone(r.zone)
    if r.tool == .cron {
      let expression = try CronExpression(r.input, dialect: r.cronDialect)
      let labels = ["Second", "Minute", "Hour", "Day of month", "Month", "Day of week"]
      var report = CalculationReport(
        rows: expression.fields.enumerated().map {
          .init(
            "field\($0.offset)", labels[$0.offset], $0.element.source,
            detail: "Allowed: " + $0.element.values.map(String.init).joined(separator: ", "))
        },
        notes: [
          expression.usesDayOR
            ? "Day of month OR day of week (both restricted)."
            : "Day of month AND day of week (wildcard-origin field present).",
          "\(r.cronDialect.rawValue). Clock gaps are skipped; both repeated instants are included. No Quartz, command, or year fields.",
          "Zone: \(zone.identifier) · tzdb \(ToolTimeZone.dataVersion).",
        ], status: "Schedule explained")
      if !r.findOccurrences {
        report.notes.append(
          "Enter a reference instant with UTC/offset and choose Find Next. Reference is exclusive.")
        return report
      }
      guard let reference = try DateTextParser.parse(r.secondInput, profile: .rfc3339).instant()
      else { throw CalculationIssue(.invalid, "Reference requires a UTC/offset instant.") }
      let result = try CronEngine.next(
        expression, after: reference, zone: zone, count: r.occurrenceCount)
      report.rows += try result.instants.enumerated().map {
        CalculationRow(
          "occ\($0.offset)", "Occurrence \($0.offset+1)", try zone.display($0.element),
          detail: try ToolTimeZone("UTC").display($0.element))
      }
      report.status = result.status
      report.notes.append(
        "Examined through: \(try ToolTimeZone("UTC").display(result.examinedThrough)). \(result.complete ? "Search completed within the declared horizon." : "Partial results only; not proof that no further occurrence exists.")"
      )
      return report
    }
    if r.tool == .iso {
      let p = try DateTextParser.parse(r.input, profile: r.profile)
      var report = CalculationReport(
        rows: [
          .init("format", "Recognized format", p.format),
          .init("date", "Calendar date", p.date.text),
        ], status: "Parsed")
      if p.hasTime {
        report.rows.append(
          .init(
            "time", "Time components",
            String(format: "%02d:%02d:%02d", p.hour!, p.minute!, p.second!)))
        if !p.fraction.isEmpty {
          report.rows.append(.init("fraction", "Original fraction", p.fraction))
        }
      }
      if let marker = p.offsetMarker {
        report.rows.append(.init("offset", "Original offset", marker))
        if marker == "-00:00" || marker == "-0000" {
          report.notes.append(
            "Unknown local offset marker preserved. UTC instant is known; original local offset is not."
          )
        }
      }
      if r.input.contains(",") {
        report.notes.append(
          "ISO comma fraction is preserved in the input; normalized previews use a decimal point.")
      }
      if let unsupported = p.unsupported {
        report.notes.append(unsupported)
        report.status = "Conversion unsupported"
        return report
      }
      let (instant, choice) = try source(r)
      if let choice {
        report.rows += choice.rows
        report.notes += choice.notes
        report.choices = choice.choices
        report.status = choice.status
      }
      if let instant {
        let converted = try instantReport(instant, zone: zone)
        report.rows += converted.rows
        report.notes += converted.notes
      }
      return report
    }
    let instant: ExactInstant
    if r.tool == .unix && r.mode == .timestamp {
      instant = try ExactInstant.parse(r.input, unit: r.unit)
    } else {
      let (value, choice) = try source(r)
      if let choice { return choice }
      guard let value else { throw CalculationIssue(.notReady, "Enter a complete date and time.") }
      instant = value
    }
    if r.tool == .zones {
      guard r.destinationZones.count <= 12 else {
        throw CalculationIssue(.resource, "Limit: 12 destination zones.")
      }
      let origin = try zone.civil(instant).date.dayIndex
      let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
      return .init(
        rows: try r.destinationZones.enumerated().map {
          let z = try ToolTimeZone($0.element)
          let civil = try z.civil(instant)
          let days = civil.date.dayIndex - origin
          return .init(
            "zone\($0.offset)", z.identifier, try z.display(instant),
            detail:
              "\(weekdays[civil.date.weekday]) · \(try z.abbreviation(at:instant)) · calendar-day difference from \(zone.identifier): \(days >= 0 ? "+":"")\(days)"
          )
        },
        notes: [
          "Same instant: \(try instant.text()) seconds since epoch. Day differences use the source/display zone (\(zone.identifier)). System tzdb \(ToolTimeZone.dataVersion)."
        ], status: "Converted")
    }
    if r.tool == .arithmetic {
      if r.arithmetic == .difference {
        guard let end = try DateTextParser.parse(r.secondInput, profile: .rfc3339).instant() else {
          throw CalculationIssue(.invalid, "End requires an instant with UTC/offset.")
        }
        let difference = try DateArithmetic.difference(start: instant, end: end)
        let text = try difference.text()
        let negative = text.hasPrefix("-")
        let absolute = negative ? String(text.dropFirst()) : text
        let parts = absolute.split(separator: ".", omittingEmptySubsequences: false)
        let whole = UInt64(parts[0])!
        let fraction = parts.count == 2 ? "." + parts[1] : ""
        let fixed =
          (negative ? "-" : "") + String(whole / 86400) + " d "
          + String(
            format: "%02d:%02d:%02d", Int(whole % 86400 / 3600), Int(whole % 3600 / 60),
            Int(whole % 60)) + fraction
        var rows = try TimestampUnit.allCases.map {
          CalculationRow(
            "diff\($0.rawValue)", "Difference · " + $0.label, try difference.text(unit: $0))
        }
        rows.append(.init("duration", "Fixed-unit duration", fixed))
        let boundaries = try zone.civil(end).date.dayIndex - zone.civil(instant).date.dayIndex
        rows.append(
          .init(
            "boundaries", "Calendar date boundaries", String(boundaries),
            detail: zone.identifier + "; date boundaries are not elapsed 24-hour days."))
        return .init(
          rows: rows,
          notes: [
            "End minus Start. Fixed days are exactly 86,400 seconds. No ambiguous month-period calculation."
          ], status: "Calculated")
      }
      var notes: [String] = []
      let result: ExactInstant
      let delta = try r.delta.parsed(calendar: r.arithmetic == .calendar)
      if r.arithmetic == .elapsed {
        result = try DateArithmetic.elapsed(
          instant, days: delta.days, hours: delta.hours, minutes: delta.minutes,
          secondsText: r.secondsText, subtract: r.subtract)
      } else {
        let calculated = try DateArithmetic.calendar(
          zone.civil(instant), delta: delta, subtract: r.subtract, clamp: r.clamp)
        notes = calculated.notes
        let (value, choice) = try resolve(calculated.civil, zone: zone, choice: r.targetChoice)
        if var choice {
          choice.choicesForResult = true
          choice.status = "Choose result occurrence"
          return choice
        }
        result = value!
      }
      var report = try instantReport(result, zone: zone)
      report.notes += notes
      report.rows.append(
        .init(
          "elapsed", "Actual elapsed seconds",
          try DateArithmetic.difference(start: instant, end: result).text()))
      return report
    }
    return try instantReport(instant, zone: zone)
  }
}
