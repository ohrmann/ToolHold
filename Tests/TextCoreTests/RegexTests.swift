import Foundation
import Testing

@testable import TextCore

@Suite struct RegexTests {
  @Test func anchoredAllowlistReportsNoMatches() throws {
    let pattern = #"^[A-Za-z0-9][A-Za-z0-9/.,()+: -]*$"#
    let input =
      #"QEWD#$(#$JF#O$F@#$%ON@KERF""cercq34435f 45f245f 245f2r3f2 54f245f234d234f245 3456g345f 45"#
    let result = try TextRegexProcessor.run(input, pattern: pattern)
    #expect(result.matches.isEmpty)
    #expect(TextRegexProcessor.artifact(result).message == "No matches")
    let allowed = "QEWD cercq34435f /.,()+: -45"
    let match = try TextRegexProcessor.run(allowed, pattern: pattern)
    #expect(match.matches.map(\.range) == [NSRange(location: 0, length: allowed.utf16.count)])
  }
  @Test func groupsAndEmpty() throws {
    let r = try TextRegexProcessor.run("ab a", pattern: "(?<letter>a)(b)?")
    #expect(r.matches.count == 2)
    #expect(r.names[1] == "letter")
    #expect(r.matches[1].groups[2] == nil)
    #expect(try TextReplacement.replace(r, template: "${letter}-$2-$$") == "a-b-$ a--$")
    let e = try TextRegexProcessor.run("😀", pattern: "(?=.)|$")
    #expect(e.matches.map(\.range.location) == [0, 2])
  }
  @Test func budgets() throws {
    #expect(throws: TextFailure.self) {
      try TextRegexProcessor.run(
        String(repeating: "a", count: 20000) + "!", pattern: "(*NO_AUTO_POSSESS)(a+)+$")
    }
    #expect(throws: TextFailure.self) { try TextRegexProcessor.run("a", pattern: "(") }
  }
}
@Suite struct RegexContractTests {
  @Test func unicodeFlagsAndZeroMatches() throws {
    let r = try TextRegexProcessor.run("e\u{301} 😀\r\nx", pattern: "\\X")
    #expect(r.matches.map(\.range.length) == [2, 1, 2, 2, 1])
    let z = try TextRegexProcessor.run("aa", pattern: "(?:|a)")
    #expect(z.matches.map(\.range.length) == [0, 1, 0, 1, 0])
    var o = TextRegexOptions()
    o.multiline = true
    #expect(
      try TextRegexProcessor.run("a\r\nb", pattern: "^", options: o).matches.map(\.range.location)
        == [0, 3])
    #expect(
      try TextReplacement.replace(TextRegexProcessor.run("x", pattern: "(a)"), template: "$1")
        == "x")
  }
  @Test func literalAndReplacementContracts() throws {
    var o = TextRegexOptions()
    o.literal = true
    #expect(try TextRegexProcessor.run("[x].", pattern: "[x].", options: o).matches.count == 1)
    let r = try TextRegexProcessor.run("a a", pattern: "(a)")
    #expect(try TextReplacement.replace(r, template: "\\n-$1", current: 1) == "a \\n-a")
    #expect(throws: TextFailure.self) { try TextReplacement.replace(r, template: "$2") }
    #expect(throws: TextFailure.self) { try TextReplacement.replace(r, template: "${unknown}") }
    #expect(try TextReplacement.replace(r, template: "$1", literal: true) == "$1 $1")
  }
  @Test func cancellationAndLimits() throws {
    let c = TextRegexCancellation()
    c.cancel()
    do {
      _ = try TextRegexProcessor.run("a", pattern: "a", cancellation: c)
      Issue.record("Cancellation ignored")
    } catch { #expect(error as? TextFailure == .cancelled) }
    #expect(throws: TextFailure.self) {
      try TextRegexProcessor.run(String(repeating: "a", count: 10001), pattern: "a")
    }
    #expect(throws: TextFailure.self) {
      try TextRegexProcessor.run("a", pattern: String(repeating: "(a)", count: 129))
    }
    #expect(throws: TextFailure.self) { try TextRegexProcessor.run("a", pattern: "\\C") }
  }
}
