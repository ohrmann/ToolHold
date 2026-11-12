import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public enum CronDialect: String, CaseIterable, Codable, Sendable {
  case unix = "Unix · 5 fields"
  case seconds = "Toolbox · 6 fields, seconds first"
}
public struct CronField: Sendable, Equatable {
  public let values: [Int]
  public let wildcard: Bool
  public let source: String
  public func contains(_ value: Int) -> Bool { values.contains(value) }
  public func next(_ value: Int) -> Int? { values.first { $0 >= value } }
}
public struct CronExpression: Sendable, Equatable {
  public let fields: [CronField]  // seconds, minutes, hours, DOM, month, DOW
  public let expanded: String
  public let dialect: CronDialect
  public var usesDayOR: Bool { !fields[3].wildcard && !fields[5].wildcard }
  public init(_ raw: String, dialect: CronDialect = .unix) throws {
    let s = try CalculationInput.trimmed(raw, limit: 1024, field: "Cron expression")
    guard !s.isEmpty else { throw CalculationIssue(.notReady, "Enter a schedule expression.") }
    let macros = [
      "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
      "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *",
      "@hourly": "0 * * * *",
    ]
    if s.lowercased() == "@reboot" {
      throw CalculationIssue(
        .unsupported, "@reboot is an event schedule; future clock occurrences cannot be calculated."
      )
    }
    let expanded = macros[s.lowercased()].map { (dialect == .seconds ? "0 " : "") + $0 } ?? s
    let pieces = expanded.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard pieces.count == (dialect == .unix ? 5 : 6) else {
      throw CalculationIssue(
        .invalid,
        "Expected \(dialect == .unix ? 5 : 6) fields for the selected profile; no command or year field.",
        field: "Cron expression")
    }
    let parts = dialect == .unix ? ["0"] + pieces : pieces
    let bounds = [(0, 59), (0, 59), (0, 23), (1, 31), (1, 12), (0, 7)]
    let months = Dictionary(
      uniqueKeysWithValues: [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
      ].enumerated().map { ($0.element, $0.offset + 1) })
    let weekdays = Dictionary(
      uniqueKeysWithValues: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"].enumerated().map {
        ($0.element, $0.offset)
      })
    var fields: [CronField] = []
    for index in 0..<6 {
      let token = parts[index].uppercased()
      let items = token.split(separator: ",", omittingEmptySubsequences: false)
      if token.contains("?") || token.contains("#") || token.contains("~") || token == "H"
        || token.hasPrefix("H/") || (index == 3 && (token.contains("L") || token.contains("W")))
        || (index == 5 && token.hasSuffix("L"))
      {
        throw CalculationIssue(
          .unsupported,
          "Quartz / hashed / nearest-day modifiers are outside the selected Cron profile.")
      }
      guard items.count <= 128 else {
        throw CalculationIssue(.resource, "Limit: 128 items per field.")
      }
      let range = bounds[index]
      let names = index == 4 ? months : index == 5 ? weekdays : [:]
      func number(_ s: Substring) throws -> Int {
        if let n = names[String(s)] { return n }
        guard !s.isEmpty, s.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(s),
          n >= range.0 && n <= range.1
        else {
          throw CalculationIssue(
            .invalid,
            "Expected \(range.0)…\(range.1)\(names.isEmpty ? "" : " or a supported three-letter name").",
            field: "Cron field \(index + 1)")
        }
        return n
      }
      var values = Set<Int>()
      for item in items {
        let stepParts = item.split(separator: "/", omittingEmptySubsequences: false)
        guard stepParts.count <= 2, let base = stepParts.first, !base.isEmpty else {
          throw CalculationIssue(
            .invalid, "Malformed range or step.", field: "Cron field \(index + 1)")
        }
        var step = 1
        if stepParts.count == 2 {
          guard stepParts[1].utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(stepParts[1]),
            n > 0, n <= 1_000_000
          else {
            throw CalculationIssue(.invalid, "Step must be a positive integer at most 1,000,000.")
          }
          step = n
        }
        var low: Int
        var high: Int
        if base == "*" {
          guard items.count == 1 else {
            throw CalculationIssue(.unsupported, "Wildcard must occupy the entire field.")
          }
          low = range.0
          high = range.1
        } else {
          let endpoints = base.split(separator: "-", omittingEmptySubsequences: false)
          guard endpoints.count <= 2 else { throw CalculationIssue(.invalid, "Malformed range.") }
          if endpoints.count == 1 && stepParts.count == 2 {
            throw CalculationIssue(.unsupported, "Steps require * or an explicit a-b range.")
          }
          low = try number(endpoints[0])
          high = try endpoints.count == 2 ? number(endpoints[1]) : low
          guard low <= high else {
            throw CalculationIssue(.invalid, "Ranges cannot wrap. Use two ranges in a list.")
          }
        }
        for n in stride(from: low, through: high, by: step) {
          values.insert(index == 5 && n == 7 ? 0 : n)
        }
      }
      fields.append(
        .init(values: values.sorted(), wildcard: token.hasPrefix("*"), source: parts[index]))
    }
    self.fields = fields
    self.expanded = expanded
    self.dialect = dialect
  }
  public func dayMatches(_ date: CivilDate) -> Bool {
    let dom = fields[3].contains(date.day)
    let dow = fields[5].contains(date.weekday)
    return usesDayOR ? dom || dow : dom && dow
  }
}
public struct CronOccurrences: Sendable {
  public let instants: [ExactInstant]
  public let status: String
  public let complete: Bool
  public let examinedThrough: ExactInstant
}
public enum CronEngine {
  public static func next(
    _ expression: CronExpression, after reference: ExactInstant, zone: ToolTimeZone,
    count: Int = 10, budget: Duration = .seconds(1)
  ) throws -> CronOccurrences {
    guard (1...100).contains(count) else {
      throw CalculationIssue(.invalid, "Choose 1…100 occurrences.")
    }
    let startCivil = try CivilTime.from(seconds: reference.seconds)
    let endYear = min(9999, startCivil.date.year + 8)
    let endDate = try CivilDate(
      endYear, startCivil.date.month,
      min(startCivil.date.day, CivilDate.daysInMonth(endYear, startCivil.date.month)))
    let end = min(
      253_402_300_800,
      endDate.dayIndex * 86400
        + Int64(startCivil.hour * 3600 + startCivil.minute * 60 + startCivil.second))
    let clock = ContinuousClock.now
    var steps = 0
    var out: [ExactInstant] = []
    var examined = reference.seconds
    func check() throws {
      steps += 1
      if steps % 16 == 0 { try Task.checkCancellation() }
      if steps > 100_000 || clock.duration(to: .now) > budget {
        throw CalculationIssue(.resource, "Search budget reached; results are incomplete.")
      }
    }
    do {
      for segment in try zone.segments(from: reference.seconds, to: max(reference.seconds, end)) {
        try check()
        var utc = max(segment.start, reference.seconds + 1)
        while utc < segment.end {
          try check()
          let wall = utc + Int64(segment.offset)
          let c = try CivilTime.from(seconds: wall)
          let d = c.date
          let f = expression.fields
          var nextWall: Int64?
          if !f[4].contains(d.month) {
            if let month = f[4].next(d.month + 1) {
              nextWall = try CivilDate(d.year, month, 1).dayIndex * 86400
            } else if d.year < 9999 {
              nextWall = try CivilDate(d.year + 1, f[4].values[0], 1).dayIndex * 86400
            } else {
              break
            }
          } else if !expression.dayMatches(d) {
            nextWall = (d.dayIndex + 1) * 86400
          } else if !f[2].contains(c.hour) {
            nextWall =
              f[2].next(c.hour + 1).map { d.dayIndex * 86400 + Int64($0 * 3600) }
              ?? (d.dayIndex + 1) * 86400
          } else if !f[1].contains(c.minute) {
            nextWall =
              f[1].next(c.minute + 1).map { d.dayIndex * 86400 + Int64(c.hour * 3600 + $0 * 60) }
              ?? d.dayIndex * 86400 + Int64((c.hour + 1) * 3600)
          } else if !f[0].contains(c.second) {
            nextWall =
              f[0].next(c.second + 1).map {
                d.dayIndex * 86400 + Int64(c.hour * 3600 + c.minute * 60 + $0)
              } ?? d.dayIndex * 86400 + Int64(c.hour * 3600 + (c.minute + 1) * 60)
          }
          if let n = nextWall {
            utc = n - Int64(segment.offset)
            continue
          }
          let instant = try ExactInstant(seconds: utc)
          out.append(instant)
          examined = utc
          if out.count == count {
            return .init(
              instants: out, status: "\(count) occurrences · strictly after reference",
              complete: true, examinedThrough: instant)
          }
          utc += 1
        }
        examined = segment.end
      }
      return .init(
        instants: out, status: "No further occurrences within searched interval (up to 8 years).",
        complete: true, examinedThrough: try .init(seconds: end))
    } catch let issue as CalculationIssue where issue.kind == .resource {
      return .init(
        instants: out, status: "Incomplete · search limit reached", complete: false,
        examinedThrough: try .init(seconds: examined))
    }
  }
}
