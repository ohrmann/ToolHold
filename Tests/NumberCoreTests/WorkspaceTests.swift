import Foundation
import Testing

@testable import NumberCore

@Suite struct WorkspaceTests {
  @Test @MainActor func revisionAndPrivacy() async throws {
    let w = CalculationWorkspace("", automatic: false) { value in
      if value == "old" { Thread.sleep(forTimeInterval: 0.04) }
      return CalculationReport(rows: [.init("v", "Value", value)], status: "Done")
    }
    w.request = "old"
    w.run()
    try await Task.sleep(for: .milliseconds(5))
    w.request = "new"
    w.run()
    for _ in 0..<100 {
      if !w.busy { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(w.report?.rows.first?.value == "new")
    w.request = "changed"
    #expect(w.report == nil)
    w.run()
    w.cancel()
    try await Task.sleep(for: .milliseconds(30))
    #expect(w.report == nil)
    #expect(w.status == "Cancelled")
    let fresh = CalculationWorkspace("", automatic: false) { _ in CalculationReport() }
    #expect(fresh.request.isEmpty && fresh.report == nil)
  }
  @Test @MainActor func cancelRetainsCurrentResult() async throws {
    let w = CalculationWorkspace("same", automatic: false) { value in
      CalculationReport(rows: [.init("v", "Value", value)])
    }
    w.run()
    for _ in 0..<50 {
      if !w.busy { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(w.report != nil)
    w.run()
    w.cancel()
    #expect(w.report?.rows.first?.value == "same")
  }
  @Test func invalidWidthDraft() throws {
    var r = NumberCalculationRequest()
    r.input = "FF"
    r.radix = 16
    r.bitPattern = true
    r.width = "8x"
    #expect(throws: CalculationIssue.self) { try NumberCalculation.process(r) }
    r.width = "8"
    #expect(try NumberCalculation.process(r).rows.last?.value == "-1")
  }
  @Test func exactBoundariesAndOffsets() throws {
    for invalid in ["_1", "1_", "1__2", "0x_FF", "12.3", "1e3", "１２"] {
      #expect(throws: CalculationIssue.self) { try RadixInteger(invalid, radix: 10) }
    }
    #expect(
      try RadixInteger("-128", radix: 10).encoded(width: 8, signed: true).digits(radix: 16) == "80")
    #expect(
      try RadixInteger.bitReport(RadixInteger("FF", radix: 16).magnitude, width: 16).rows.last?
        .value == "255")
    #expect(throws: CalculationIssue.self) {
      try RadixInteger("1", radix: 10).encoded(width: 0, signed: true)
    }
    let big = String(repeating: "Z", count: 4096)
    let n = try RadixInteger(big, radix: 36)
    let binary = try n.text(base: 2)
    #expect(binary.count == 21177)
    // Binary exceeds input-digit limit; round-trip in another radix that stays under it.
    #expect(try RadixInteger(n.text(base: 36), radix: 36) == n)
    #expect(throws: CalculationIssue.self) { try RadixInteger(big + "Z", radix: 36) }
  }
}
