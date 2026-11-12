import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public struct CivilDate: Equatable, Sendable {
  public let year: Int, month: Int, day: Int
  public init(_ year: Int, _ month: Int, _ day: Int) throws {
    guard (1...9999).contains(year) else {
      throw CalculationIssue(.unsupported, "Supported calendar years: 0001…9999.")
    }
    guard (1...12).contains(month), (1...Self.daysInMonth(year, month)).contains(day) else {
      throw CalculationIssue(.invalid, "This calendar date does not exist.")
    }
    self.year = year
    self.month = month
    self.day = day
  }
  public static func leap(_ y: Int) -> Bool { y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }
  public static func daysInMonth(_ y: Int, _ m: Int) -> Int {
    guard (1...12).contains(m) else { return 0 }
    return [31, leap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
  }
  static func beforeYear(_ y: Int) -> Int64 {
    let a = Int64(y - 1)
    return 365 * a + a / 4 - a / 100 + a / 400
  }
  public var dayIndex: Int64 {
    Self.beforeYear(year) - Self.beforeYear(1970)
      + Int64((1..<month).reduce(0) { $0 + Self.daysInMonth(year, $1) } + day - 1)
  }
  public static func from(dayIndex: Int64) throws -> Self {
    let n = dayIndex.addingReportingOverflow(beforeYear(1970))
    guard !n.overflow, n.partialValue >= 0, n.partialValue < beforeYear(10000) else {
      throw CalculationIssue(.unsupported, "Outside supported calendar range (0001…9999).")
    }
    var lo = 1
    var hi = 10000
    while lo + 1 < hi {
      let mid = (lo + hi) / 2
      if beforeYear(mid) <= n.partialValue { lo = mid } else { hi = mid }
    }
    var d = Int(n.partialValue - beforeYear(lo))
    var month = 1
    while d >= daysInMonth(lo, month) {
      d -= daysInMonth(lo, month)
      month += 1
    }
    return try Self(lo, month, d + 1)
  }
  public var weekday: Int { Int((dayIndex + 4) % 7 + 7) % 7 }  // Sunday=0
  public var text: String { String(format: "%04d-%02d-%02d", year, month, day) }
}
public struct CivilTime: Equatable, Sendable {
  public let date: CivilDate
  public let hour: Int, minute: Int, second: Int
  public let nanosecond: UInt32
  public init(
    date: CivilDate, hour: Int = 0, minute: Int = 0, second: Int = 0, nanosecond: UInt32 = 0
  ) throws {
    guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
      nanosecond < 1_000_000_000
    else { throw CalculationIssue(.invalid, "Time components are outside their valid ranges.") }
    self.date = date
    self.hour = hour
    self.minute = minute
    self.second = second
    self.nanosecond = nanosecond
  }
  public var wallSeconds: Int64 {
    date.dayIndex * 86400 + Int64(hour * 3600 + minute * 60 + second)
  }
  public static func from(seconds: Int64, nanos: UInt32 = 0) throws -> Self {
    let day = floorDivide(seconds, 86400)
    let date = try CivilDate.from(dayIndex: day)
    let remainder = seconds - day * 86400
    return try .init(
      date: date, hour: Int(remainder / 3600), minute: Int(remainder % 3600 / 60),
      second: Int(remainder % 60), nanosecond: nanos)
  }
  public var text: String {
    var frac = String(format: "%09u", nanosecond)
    while frac.last == "0" { frac.removeLast() }
    return date.text + String(format: "T%02d:%02d:%02d", hour, minute, second)
      + (frac.isEmpty ? "" : "." + frac)
  }
}
