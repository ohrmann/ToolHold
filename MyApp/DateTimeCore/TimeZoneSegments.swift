import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public struct ToolTimeZone: Equatable, Sendable {
  public let identifier: String
  private let fixed: Int?
  public init(_ raw: String) throws {
    let id = try CalculationInput.trimmed(raw, limit: 256, field: "Time zone")
    if id == "UTC" || id == "Z" {
      identifier = "UTC"
      fixed = 0
      return
    }
    if id.first == "+" || id.first == "-" {
      let b = Array(id.utf8)
      guard b.count == 6, b[3] == 58,
        b.enumerated().allSatisfy({
          $0.offset == 0 || $0.offset == 3 || (48...57).contains($0.element)
        }), let h = Int(String(id.dropFirst().prefix(2))), let m = Int(String(id.suffix(2))),
        h < 24, m < 60
      else {
        throw CalculationIssue(
          .invalid, "Use UTC, an IANA identifier, or a fixed offset ±HH:MM.", field: "Time zone")
      }
      identifier = id
      fixed = (h * 3600 + m * 60) * (b[0] == 45 ? -1 : 1)
      return
    }
    guard id.contains("/"), TimeZone(identifier: id) != nil else {
      throw CalculationIssue(
        .invalid, "Choose an IANA time zone; abbreviations are ambiguous.", field: "Time zone")
    }
    identifier = id
    fixed = nil
  }
  public func offset(at seconds: Int64) throws -> Int {
    guard seconds >= -62_135_769_600, seconds < 253_402_473_600 else {
      throw CalculationIssue(.unsupported, "Outside supported calendar range.")
    }
    let v =
      fixed
      ?? TimeZone(identifier: identifier)!.secondsFromGMT(
        for: Date(timeIntervalSince1970: Double(seconds)))
    guard abs(v) < 86400 else {
      throw CalculationIssue(.unsupported, "Time zone offset outside supported range.")
    }
    return v
  }
  public struct Segment: Sendable { public let start: Int64, end: Int64, offset: Int }
  public func segments(from start: Int64, to end: Int64, limit: Int = 1024) throws -> [Segment] {
    guard start < end else { return [] }
    var cursor = start
    var out: [Segment] = []
    while cursor < end {
      try Task.checkCancellation()
      guard out.count < limit else {
        throw CalculationIssue(.resource, "Time zone transition limit reached.")
      }
      let offset = try offset(at: cursor)
      var boundary = end
      if fixed == nil,
        let next = TimeZone(identifier: identifier)!.nextDaylightSavingTimeTransition(
          after: Date(timeIntervalSince1970: Double(cursor)))
      {
        let t = next.timeIntervalSince1970
        guard t.isFinite, t.rounded() == t, t > Double(cursor) else {
          throw CalculationIssue(
            .unsupported, "System time zone transition could not be resolved reliably.")
        }
        if t < Double(end) { boundary = Int64(t) }
      }
      out.append(.init(start: cursor, end: boundary, offset: offset))
      cursor = boundary
    }
    return out
  }
  public func resolve(_ civil: CivilTime) throws -> [ExactInstant] {
    let w = civil.wallSeconds
    let parts = try segments(from: w - 172800, to: w + 172801)
    var candidates: [ExactInstant] = []
    for part in parts {
      let seconds = w - Int64(part.offset)
      if seconds >= part.start && seconds < part.end {
        guard try offset(at: seconds) == part.offset else { continue }
        let instant = try ExactInstant(seconds: seconds, nanosecond: civil.nanosecond)
        if !candidates.contains(instant) { candidates.append(instant) }
      }
    }
    return candidates.sorted()
  }
  public func civil(_ instant: ExactInstant) throws -> CivilTime {
    try CivilTime.from(
      seconds: instant.seconds + Int64(offset(at: instant.seconds)), nanos: instant.nanosecond)
  }
  public func display(_ instant: ExactInstant) throws -> String {
    try civil(instant).text + Self.offsetText(offset(at: instant.seconds))
  }
  public static func offsetText(_ seconds: Int) -> String {
    if seconds == 0 { return "Z" }
    let a = abs(seconds)
    return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", a / 3600, a % 3600 / 60)
      + (a % 60 == 0 ? "" : String(format: ":%02d", a % 60))
  }
  public func abbreviation(at instant: ExactInstant) throws -> String {
    let offset = try offset(at: instant.seconds)
    if fixed != nil { return identifier == "UTC" ? "UTC" : Self.offsetText(offset) }
    return TimeZone(identifier: identifier)!.abbreviation(
      for: Date(timeIntervalSince1970: Double(instant.seconds))) ?? Self.offsetText(offset)
  }
  public static var dataVersion: String { TimeZone.timeZoneDataVersion }
}
