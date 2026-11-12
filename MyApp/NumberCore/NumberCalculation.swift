import Foundation

public struct NumberCalculationRequest: Sendable {
  public var integerDraft = "", patternDraft = ""
  public var input = "", radix = 10, outputRadix = 16
  public var width = "32"
  public var signed = true, uppercase = true, bitPattern = false, group = false, prefix = false,
    encode = false
  public init() {}
}
public enum NumberCalculation {
  public static func process(_ r: NumberCalculationRequest) throws -> CalculationReport {
    let width =
      (r.bitPattern || r.encode)
      ? try CalculationInput.integer(r.width, field: "Bit width", range: 1...4096) : 32
    if r.bitPattern {
      guard [2, 8, 16].contains(r.radix) else {
        throw CalculationIssue(.invalid, "Bit patterns use base 2, 8 or 16.")
      }
      let value = try RadixInteger(r.input, radix: r.radix, signed: false)
      return try RadixInteger.bitReport(value.magnitude, width: width)
    }
    let n = try RadixInteger(r.input, radix: r.radix, signed: r.signed)
    if r.encode {
      return try RadixInteger.bitReport(n.encoded(width: width, signed: r.signed), width: width)
    }
    let bases = Array(Set([2, 8, 10, 16, r.outputRadix])).sorted()
    var report = CalculationReport(status: "Converted")
    for base in bases {
      let canonical = try n.text(base: base, uppercase: r.uppercase)
      report.rows.append(.init("base\(base)", "Base \(base) · canonical", canonical))
      if r.group || r.prefix {
        let negative = canonical.hasPrefix("-")
        let digits = negative ? String(canonical.dropFirst()) : canonical
        let size = base == 10 ? 3 : 4
        let grouped =
          r.group
          ? stride(from: 0, to: digits.count, by: size).map { offset in
            String(digits.reversed().dropFirst(offset).prefix(size).reversed())
          }.reversed().joined(separator: "_") : digits
        let p = r.prefix ? ([2: "0b", 8: "0o", 16: "0x"][base] ?? "") : ""
        report.rows.append(
          .init("display\(base)", "Base \(base) · displayed", (negative ? "-" : "") + p + grouped))
      }
    }
    report.notes = [
      "Exact integer conversion. Up to 4096 digits, bases 2–36. Copy a canonical row to omit presentation grouping."
    ]
    return report
  }
}
