import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public struct CalendarDelta: Equatable, Codable, Sendable {
  public var years = 0, months = 0, weeks = 0, days = 0, hours = 0, minutes = 0, seconds = 0
  public init() {}
}
public struct CalendarArithmeticResult: Sendable {
  public let civil: CivilTime
  public let notes: [String]
}
public enum DateArithmetic {
  public static func calendar(
    _ start: CivilTime, delta: CalendarDelta, subtract: Bool = false, clamp: Bool = true
  ) throws -> CalendarArithmeticResult {
    guard
      [
        delta.years, delta.months, delta.weeks, delta.days, delta.hours, delta.minutes,
        delta.seconds,
      ].allSatisfy({ (0...1_000_000).contains($0) })
    else { throw CalculationIssue(.resource, "Each calendar component must be 0…1,000,000.") }
    let sign = subtract ? -1 : 1
    var date = start.date
    var notes: [String] = []
    func moved(_ y: Int, _ m: Int, _ old: CivilDate) throws -> CivilDate {
      guard (1...9999).contains(y) else {
        throw CalculationIssue(.unsupported, "Outside supported calendar years.")
      }
      let maxDay = CivilDate.daysInMonth(y, m)
      if old.day > maxDay {
        guard clamp else {
          throw CalculationIssue(
            .invalid, "Target date does not exist. Choose Clamp or change the offset.")
        }
        notes.append(
          "Clamped day \(old.day) to \(maxDay) in \(y)-\(m). Calendar arithmetic is not always reversible."
        )
      }
      return try .init(y, m, min(old.day, maxDay))
    }
    date = try moved(date.year + sign * delta.years, date.month, date)
    let months = Int64(date.year - 1) * 12 + Int64(date.month - 1 + sign * delta.months)
    guard months >= 0 && months < 9999 * 12 else {
      throw CalculationIssue(.unsupported, "Outside supported calendar years.")
    }
    date = try moved(Int(months / 12) + 1, Int(months % 12) + 1, date)
    let days = date.dayIndex + Int64(sign) * Int64(delta.weeks * 7 + delta.days)
    let time =
      Int64(start.hour * 3600 + start.minute * 60 + start.second) + Int64(sign)
      * Int64(delta.hours * 3600 + delta.minutes * 60 + delta.seconds)
    let civil = try CivilTime.from(seconds: days * 86400 + time, nanos: start.nanosecond)
    return .init(civil: civil, notes: notes)
  }
  public static func elapsed(
    _ start: ExactInstant, days: Int, hours: Int, minutes: Int, secondsText: String, subtract: Bool
  ) throws -> ExactInstant {
    guard [days, hours, minutes].allSatisfy({ (0...1_000_000).contains($0) }) else {
      throw CalculationIssue(.resource, "Duration components must be 0…1,000,000.")
    }
    let sec = try ExactInstant.parse(secondsText.isEmpty ? "0" : secondsText)
    guard sec.seconds >= 0, sec.seconds <= 1_000_000 else {
      throw CalculationIssue(
        .invalid, "Duration seconds must be 0…1,000,000; choose Add or Subtract separately.")
    }
    let delta = Int64(days) * 86400 + Int64(hours) * 3600 + Int64(minutes) * 60 + sec.seconds
    return try start.adding(
      seconds: subtract ? -delta : delta,
      nanos: subtract ? -Int64(sec.nanosecond) : Int64(sec.nanosecond))
  }
  public static func difference(start: ExactInstant, end: ExactInstant) throws -> ExactInstant {
    let delta = end.seconds.subtractingReportingOverflow(start.seconds)
    guard !delta.overflow else {
      throw CalculationIssue(.resource, "Difference exceeds supported duration range.")
    }
    return try ExactInstant(seconds: delta.partialValue).adding(
      seconds: 0, nanos: Int64(end.nanosecond) - Int64(start.nanosecond))
  }
}
