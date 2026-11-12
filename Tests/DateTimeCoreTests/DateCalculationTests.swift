import Foundation
import NumberCore
import Testing

@testable import DateTimeCore

@Suite struct DateCalculationTests {
  func instant(_ text: String) throws -> ExactInstant {
    try #require(try DateTextParser.parse(text, profile: .rfc3339).instant())
  }
  @Test func calendarAndElapsed() throws {
    let zone = try ToolTimeZone("Europe/Prague")
    let start = try instant("2026-03-28T11:00:00Z")
    var delta = CalendarDelta()
    delta.days = 1
    let local = try DateArithmetic.calendar(zone.civil(start), delta: delta)
    let result = try #require(try zone.resolve(local.civil).first)
    #expect(try DateArithmetic.difference(start: start, end: result).text() == "82800")
    #expect(
      try zone.civil(
        DateArithmetic.elapsed(
          start, days: 1, hours: 0, minutes: 0, secondsText: "0", subtract: false)
      ).hour == 13)
    delta.days = 0
    delta.months = 1
    let jan = try CivilTime(date: CivilDate(2024, 1, 31), hour: 12)
    let changed = try DateArithmetic.calendar(jan, delta: delta)
    #expect(changed.civil.date.text == "2024-02-29")
    #expect(!changed.notes.isEmpty)
    #expect(throws: CalculationIssue.self) {
      try DateArithmetic.calendar(jan, delta: delta, clamp: false)
    }
    #expect(
      try DateArithmetic.difference(
        start: ExactInstant.parse("0.1"), end: ExactInstant.parse("-0.2")
      ).text() == "-0.3")
  }
  @Test func cronGrammarAndOracle() throws {
    #expect(try CronExpression("0 0 1 * MON").usesDayOR)
    #expect(try !CronExpression("0 0 */2 * MON").usesDayOR)
    #expect(try CronExpression("@daily").expanded == "0 0 * * *")
    for invalid in [
      "*/0 * * * *", "0 0 ? * MON", "0 0 L * *", "0 0 * * MON#2", "0 0 0 * * *", "5/10 * * * *",
      "0 0 * * * command",
    ] {
      #expect(throws: CalculationIssue.self) { try CronExpression(invalid) }
    }
    let ref = try instant("2026-01-01T00:00:00Z")
    let zone = try ToolTimeZone("UTC")
    let actual = try CronEngine.next(
      CronExpression("*/7 */13 * * * *", dialect: .seconds), after: ref, zone: zone, count: 100
    ).instants.map(\.seconds)
    // Independent small brute-force predicate; no CronField or engine logic reused.
    let offsets: [Int] = (1...90000).filter { n in (n % 60) % 7 == 0 && (n / 60 % 60) % 13 == 0 }
    let expected: [Int64] = offsets.prefix(100).map { ref.seconds + Int64($0) }
    #expect(actual == expected)
    let impossible = try CronEngine.next(CronExpression("0 0 31 FEB *"), after: ref, zone: zone)
    #expect(impossible.instants.isEmpty)
    #expect(impossible.complete)
    let limited = try CronEngine.next(
      CronExpression("* * * * *"), after: ref, zone: zone, budget: .zero)
    #expect(!limited.complete)
  }
  @Test func cronDST() throws {
    let expression = try CronExpression("30 2 * * *")
    let zone = try ToolTimeZone("Europe/Prague")
    let fold = try CronEngine.next(
      expression, after: instant("2026-10-24T23:00:00Z"), zone: zone, count: 2)
    #expect(
      fold.instants == [try instant("2026-10-25T00:30:00Z"), try instant("2026-10-25T01:30:00Z")])
    let between = try CronEngine.next(
      expression, after: instant("2026-10-25T00:45:00Z"), zone: zone, count: 1)
    #expect(between.instants.first == fold.instants.last)
    let gap = try CronEngine.next(
      expression, after: instant("2026-03-29T00:00:00Z"), zone: zone, count: 1)
    #expect(gap.instants.first == (try instant("2026-03-30T00:30:00Z")))
  }
  @Test func parsingProfilesAndChoices() throws {
    #expect(
      try DateTextParser.parse("20240229T123456,123456789Z").instant()?.nanosecond == 123_456_789)
    #expect(throws: CalculationIssue.self) { try DateTextParser.parse("1900-02-29") }
    #expect(throws: CalculationIssue.self) { try DateTextParser.parse("2021-W53-7") }
    #expect(throws: CalculationIssue.self) {
      try DateTextParser.parse("2026-01-01T24:00:00Z", profile: .rfc3339)
    }
    #expect(try DateTextParser.parse("2026-01-01T00:00:00.1234567891Z").unsupported != nil)
    var r = DateCalculationRequest(tool: .zones)
    r.input = "2026-10-25T02:30:00"
    r.zone = "Europe/Prague"
    let choice = try DateCalculations.process(r)
    #expect(choice.choices.count == 2)
    r.choice = choice.choices[1].id
    #expect(try DateCalculations.process(r).status == "Converted")
    r.input = "2026-03-29T02:30:00"
    #expect(throws: CalculationIssue.self) { try DateCalculations.process(r) }
    var epoch = DateCalculationRequest(tool: .unix)
    epoch.input = "9223372036854775807"
    #expect(
      try DateCalculations.process(epoch).rows.contains {
        $0.id == "unit0" && $0.value == epoch.input
      })
  }
  @Test func displayMetadataAndNumericDrafts() throws {
    var r = DateCalculationRequest(tool: .arithmetic)
    r.input = "2026-03-28T11:00:00Z"
    r.secondInput = "2026-03-29T10:00:00Z"
    r.zone = "Europe/Prague"
    r.arithmetic = .difference
    let result = try DateCalculations.process(r)
    #expect(result.rows.first { $0.id == "boundaries" }?.value == "1")
    #expect(result.rows.first { $0.id == "duration" }?.value == "0 d 23:00:00")
    r.arithmetic = .elapsed
    r.delta.days = "x"
    #expect(throws: CalculationIssue.self) { try DateCalculations.process(r) }
    var zones = DateCalculationRequest(tool: .zones)
    zones.input = "2026-01-01T23:30:00Z"
    zones.destinationZones = ["Asia/Kathmandu"]
    #expect(try DateCalculations.process(zones).rows[0].detail.contains("+1"))
  }
  @Test func historicalAndCivilRoundTrips() throws {
    #expect(
      try ToolTimeZone("Asia/Kathmandu").display(instant("2026-01-01T00:00:00Z")).hasSuffix(
        "+05:45"))
    #expect(
      try ToolTimeZone("Europe/Paris").offset(at: instant("1900-01-01T00:00:00Z").seconds) == 561)
    for day in stride(from: Int64(-719162), through: 2_932_896, by: 311) {
      #expect(try CivilDate.from(dayIndex: day).dayIndex == day)
    }
  }
}
