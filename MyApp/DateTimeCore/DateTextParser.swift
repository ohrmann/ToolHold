import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public enum DateTextProfile: String, Codable, CaseIterable, Sendable {
  case auto = "Auto"
  case rfc3339 = "RFC 3339"
  case iso = "ISO supported profile"
  case local = "Local date and time"
}
public struct ParsedDateText: Sendable {
  public let format: String
  public let date: CivilDate
  public let time: CivilTime?
  public let hour: Int?, minute: Int?, second: Int?
  public let fraction: String
  public let zone: ToolTimeZone?
  public let offsetMarker: String?
  public let unsupported: String?
  public var hasTime: Bool { hour != nil }
  public func instant() throws -> ExactInstant? {
    if let unsupported { throw CalculationIssue(.unsupported, unsupported) }
    guard let time, let zone else { return nil }
    return try zone.resolve(time).first
  }
}
public enum DateTextParser {
  static func groups(_ pattern: String, _ input: String) -> [String]? {
    let regex = try! NSRegularExpression(pattern: pattern)
    let ns = input as NSString
    guard let m = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)),
      m.range.length == ns.length
    else { return nil }
    return (0..<m.numberOfRanges).map {
      m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0))
    }
  }
  public static func parse(_ raw: String, profile: DateTextProfile = .auto) throws -> ParsedDateText
  {
    var s = try CalculationInput.trimmed(raw, limit: 256)
    guard !s.isEmpty else { throw CalculationIssue(.notReady, "Enter a date or timestamp.") }
    if profile == .local { s = s.replacingOccurrences(of: " ", with: "T") }
    let rfcPattern =
      #"\A([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?([Zz]|[+-][0-9]{2}:[0-9]{2})\z"#
    if let g = groups(rfcPattern, s), profile != .local {
      return try calendar(g, format: "RFC 3339", rfc: true)
    }
    if profile == .rfc3339 {
      throw CalculationIssue(
        .invalid, "Expected YYYY-MM-DDTHH:mm:ss[.fraction]Z or a numeric offset.")
    }
    if let g = groups(
      #"\A([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:[.,]([0-9]+))?)?([Zz]|[+-][0-9]{2}:?[0-9]{2})?\z"#,
      s)
    {
      if profile == .local && !g[8].isEmpty {
        throw CalculationIssue(.invalid, "Choose the time zone separately for local input.")
      }
      return try calendar(g, format: "ISO extended date-time", rfc: false)
    }
    if profile != .local,
      let g = groups(
        #"\A([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})(?:([0-9]{2})(?:[.,]([0-9]+))?)?([Zz]|[+-][0-9]{2}:?[0-9]{2})?\z"#,
        s)
    {
      return try calendar(g, format: "ISO basic date-time", rfc: false)
    }
    if profile == .local {
      throw CalculationIssue(
        .invalid, "Use YYYY-MM-DD HH:mm:ss[.fraction], with the time zone selected separately.")
    }
    if let g = groups(#"\A([0-9]{4})(?:-([0-9]{2})-([0-9]{2})|([0-9]{2})([0-9]{2}))\z"#, s) {
      let date = try CivilDate(
        Int(g[1])!, Int(g[2].isEmpty ? g[4] : g[2])!, Int(g[3].isEmpty ? g[5] : g[3])!)
      return dateOnly(date, format: "ISO calendar date")
    }
    if let g = groups(#"\A([0-9]{4})(?:-W([0-9]{2})-([1-7])|W([0-9]{2})([1-7]))\z"#, s) {
      let y = Int(g[1])!
      let week = Int(g[2].isEmpty ? g[4] : g[2])!
      let weekday = Int(g[3].isEmpty ? g[5] : g[3])!
      let jan4 = try CivilDate(y, 1, 4)
      let monday = jan4.dayIndex - Int64((jan4.weekday + 6) % 7)
      let jan1 = try CivilDate(y, 1, 1)
      let maxWeek = (jan1.weekday == 4 || (CivilDate.leap(y) && jan1.weekday == 3)) ? 53 : 52
      guard (1...maxWeek).contains(week) else {
        throw CalculationIssue(.invalid, "This ISO week does not exist in the selected week-year.")
      }
      return dateOnly(
        try CivilDate.from(dayIndex: monday + Int64((week - 1) * 7 + weekday - 1)),
        format: "ISO week date")
    }
    if let g = groups(#"\A([0-9]{4})-?([0-9]{3})\z"#, s) {
      let y = Int(g[1])!
      let n = Int(g[2])!
      let first = try CivilDate(y, 1, 1)
      guard (1...(CivilDate.leap(y) ? 366 : 365)).contains(n) else {
        throw CalculationIssue(.invalid, "Ordinal day is outside this year.")
      }
      return dateOnly(
        try CivilDate.from(dayIndex: first.dayIndex + Int64(n - 1)), format: "ISO ordinal date")
    }
    if s.hasPrefix("P") || s.contains("/") || s.contains("[") || s.first == "+" || s.first == "-"
      || groups(#"\A[0-9]{4}(?:-[0-9]{2})?\z"#, s) != nil || s.contains(":")
    {
      throw CalculationIssue(
        .unsupported,
        "Unsupported format. See Supported Formats for this tool’s explicit ISO profile.")
    }
    throw CalculationIssue(.invalid, "Date does not match a supported date format.")
  }
  static func dateOnly(_ date: CivilDate, format: String) -> ParsedDateText {
    .init(
      format: format, date: date, time: nil, hour: nil, minute: nil, second: nil, fraction: "",
      zone: nil, offsetMarker: nil, unsupported: nil)
  }
  static func calendar(_ g: [String], format: String, rfc: Bool) throws -> ParsedDateText {
    let date = try CivilDate(Int(g[1])!, Int(g[2])!, Int(g[3])!)
    let h = Int(g[4])!
    let m = Int(g[5])!
    let sec = Int(g[6]) ?? 0
    let fraction = g[7]
    guard h <= 24 && m <= 59 && sec <= 60 else {
      throw CalculationIssue(.invalid, "Time components are outside their valid ranges.")
    }
    if h == 24 {
      throw CalculationIssue(
        rfc ? .invalid : .unsupported, "24:00 is outside this tool’s date-time profile.")
    }
    var issue: String?
    if sec == 60 {
      issue =
        "Leap second conversion unsupported; actual leap-second validity has not been established."
    }
    if fraction.dropFirst(9).contains(where: { $0 != "0" }) {
      issue =
        "Precision unsupported: conversion supports at most nanoseconds. Original fraction is preserved."
    }
    let n = String(fraction.prefix(9))
    let nano = UInt32(n + String(repeating: "0", count: 9 - n.count))!
    var marker: String? = g[8].isEmpty ? nil : g[8]
    var zone: ToolTimeZone?
    if let offset = marker {
      var canonical = offset
      if canonical.lowercased() == "z" {
        canonical = "UTC"
      } else if canonical.count == 5 {
        canonical.insert(":", at: canonical.index(canonical.startIndex, offsetBy: 3))
      }
      zone = try ToolTimeZone(canonical)
      marker = offset
    }
    let time =
      issue == nil
      ? try CivilTime(date: date, hour: h, minute: m, second: sec, nanosecond: nano) : nil
    return .init(
      format: format, date: date, time: time, hour: h, minute: m, second: sec, fraction: fraction,
      zone: zone, offsetMarker: marker, unsupported: issue)
  }
}
