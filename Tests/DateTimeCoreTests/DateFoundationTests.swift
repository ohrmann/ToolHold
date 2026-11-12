import Foundation
import NumberCore
import Testing

@testable import DateTimeCore

@Suite struct DateFoundationTests {
  @Test func exactEpochs() throws {
    #expect(try ExactInstant.parse("-0.001").seconds == -1)
    #expect(try ExactInstant.parse("-1", unit: .microseconds).text() == "-0.000001")
    #expect(try ExactInstant.parse("1.5").text(unit: .milliseconds) == "1500")
    #expect(try ExactInstant.parse("0.001", unit: .milliseconds).text(unit: .microseconds) == "1")
    for value in [
      "-9223372036854775808", "9223372036854775807.999999999", "-0.999999999", "0", "-1.1",
    ] { #expect(try ExactInstant.parse(value).text() == value) }
    #expect(throws: CalculationIssue.self) { try ExactInstant.parse("0.0000000001") }
    #expect(try ExactInstant.parse("1.00000000000").text() == "1")
  }
  @Test func civilAndISO() throws {
    #expect(try CivilDate(1970, 1, 1).dayIndex == 0)
    for y in [1, 1582, 1900, 2000, 2026, 9999] {
      for m in 1...12 {
        let d = try CivilDate(y, m, 1)
        #expect(try CivilDate.from(dayIndex: d.dayIndex) == d)
      }
    }
    #expect(try DateTextParser.parse("2020-W53-7").date.text == "2021-01-03")
    #expect(try DateTextParser.parse("2024-060").date.text == "2024-02-29")
    #expect(throws: CalculationIssue.self) { try DateTextParser.parse("2021-W53-1") }
    #expect(
      try DateTextParser.parse("2000-01-01T12:30:00.123456789-00:00").offsetMarker == "-00:00")
    #expect(try DateTextParser.parse("2016-12-31T23:59:60Z").unsupported != nil)
  }
  @Test func systemTransitions() throws {
    let prague = try ToolTimeZone("Europe/Prague")
    let gap = try DateTextParser.parse("2026-03-29T02:30:00", profile: .local).time!
    #expect(try prague.resolve(gap).isEmpty)
    let fold = try DateTextParser.parse("2026-10-25T02:30:00", profile: .local).time!
    let values = try prague.resolve(fold)
    #expect(values.count == 2)
    #expect(try ToolTimeZone("UTC").display(values[0]) == "2026-10-25T00:30:00Z")
    #expect(values[1].seconds - values[0].seconds == 3600)
    let apia = try ToolTimeZone("Pacific/Apia")
    #expect(
      try apia.resolve(DateTextParser.parse("2011-12-30T12:00:00", profile: .local).time!).isEmpty)
    let lord = try ToolTimeZone("Australia/Lord_Howe").resolve(
      DateTextParser.parse("2026-04-05T01:45:00", profile: .local).time!)
    #expect(lord.count == 2)
    #expect(lord[1].seconds - lord[0].seconds == 1800)
  }
}
