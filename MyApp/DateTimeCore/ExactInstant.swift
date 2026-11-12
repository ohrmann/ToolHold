import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public enum TimestampUnit: Int, CaseIterable, Codable, Sendable {
  case seconds = 0
  case milliseconds = 3
  case microseconds = 6
  public var label: String {
    switch self {
    case .seconds: "Seconds"
    case .milliseconds: "Milliseconds"
    case .microseconds: "Microseconds"
    }
  }
}
public struct ExactInstant: Hashable, Comparable, Sendable, Codable {
  public let seconds: Int64
  public let nanosecond: UInt32
  public init(seconds: Int64, nanosecond: UInt32 = 0) throws {
    guard nanosecond < 1_000_000_000 else {
      throw CalculationIssue(.invalid, "Invalid fractional second.")
    }
    self.seconds = seconds
    self.nanosecond = nanosecond
  }
  public static func < (a: Self, b: Self) -> Bool {
    a.seconds == b.seconds ? a.nanosecond < b.nanosecond : a.seconds < b.seconds
  }
  public static func parse(_ raw: String, unit: TimestampUnit = .seconds) throws -> Self {
    let s = try CalculationInput.trimmed(raw, limit: 256)
    guard !s.isEmpty && s != "+" && s != "-" else {
      throw CalculationIssue(.notReady, "Enter a timestamp.")
    }
    let b = Array(s.utf8)
    var i = 0
    var negative = false
    if b[0] == 45 || b[0] == 43 {
      negative = b[0] == 45
      i += 1
    }
    let start = i
    while i < b.count && (48...57).contains(b[i]) { i += 1 }
    guard i > start else { throw CalculationIssue(.invalid, "Expected decimal digits.") }
    let whole = Array(b[start..<i])
    var fraction: [UInt8] = []
    if i < b.count && b[i] == 46 {
      i += 1
      let f = i
      while i < b.count && (48...57).contains(b[i]) { i += 1 }
      guard i > f else {
        throw CalculationIssue(.notReady, "Enter digits after the decimal point.")
      }
      fraction = Array(b[f..<i])
    }
    guard i == b.count else {
      throw CalculationIssue(.invalid, "Use decimal digits and a dot; no exponent or separators.")
    }
    let all = whole + fraction
    let scale = fraction.count + unit.rawValue
    let split = max(0, all.count - scale)
    let integerText = split == 0 ? "0" : String(decoding: all[..<split], as: UTF8.self)
    var frac = Array(repeating: UInt8(48), count: max(0, scale - all.count)) + Array(all[split...])
    guard frac.dropFirst(9).allSatisfy({ $0 == 48 }) else {
      throw CalculationIssue(
        .unsupported, "Precision unsupported: smallest supported unit is one nanosecond.")
    }
    frac = Array(frac.prefix(9))
    frac += Array(repeating: 48, count: 9 - frac.count)
    let nanos = UInt32(String(decoding: frac, as: UTF8.self))!
    guard let magnitude = UInt64(integerText), magnitude <= (UInt64(Int64.max) + (negative ? 1 : 0))
    else { throw CalculationIssue(.resource, "Timestamp seconds exceed Int64 range.") }
    if !negative { return try .init(seconds: Int64(magnitude), nanosecond: nanos) }
    if nanos == 0 {
      return try .init(seconds: magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude))
    }
    guard magnitude <= UInt64(Int64.max) else {
      throw CalculationIssue(.resource, "Timestamp seconds exceed Int64 range.")
    }
    return try .init(seconds: -Int64(magnitude) - 1, nanosecond: 1_000_000_000 - nanos)
  }
  public func text(unit: TimestampUnit = .seconds) throws -> String {
    let minus = seconds < 0
    let whole = minus && nanosecond != 0 ? seconds.magnitude - 1 : seconds.magnitude
    let fraction = minus && nanosecond != 0 ? 1_000_000_000 - nanosecond : nanosecond
    var magnitude = BoundedMagnitude(whole)
    let factor: UInt32 = unit == .seconds ? 1 : unit == .milliseconds ? 1000 : 1_000_000
    try magnitude.multiply(factor)
    try magnitude.add(fraction / (1_000_000_000 / factor))
    let remaining = fraction % (1_000_000_000 / factor)
    var tail = String(format: "%0*u", 9 - unit.rawValue, remaining)
    while tail.last == "0" { tail.removeLast() }
    return (minus ? "-" : "") + (try magnitude.digits(radix: 10)) + (tail.isEmpty ? "" : "." + tail)
  }
  public func adding(seconds delta: Int64, nanos: Int64 = 0) throws -> Self {
    let ns = Int64(nanosecond) + nanos
    let carry = floorDivide(ns, 1_000_000_000)
    let a = seconds.addingReportingOverflow(delta)
    let b = a.partialValue.addingReportingOverflow(carry)
    guard !a.overflow && !b.overflow else {
      throw CalculationIssue(.resource, "Date arithmetic overflow.")
    }
    return try .init(seconds: b.partialValue, nanosecond: UInt32(ns - carry * 1_000_000_000))
  }
  public static func now() -> Self {
    let ms = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    return try! .init(
      seconds: floorDivide(ms, 1000),
      nanosecond: UInt32(ms - floorDivide(ms, 1000) * 1000) * 1_000_000)
  }
}
public func floorDivide(_ a: Int64, _ b: Int64) -> Int64 { a / b - (a % b < 0 ? 1 : 0) }
