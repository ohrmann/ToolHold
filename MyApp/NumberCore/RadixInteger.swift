import Foundation

public struct RadixInteger: Equatable, Sendable {
  public let magnitude: BoundedMagnitude
  public let negative: Bool
  public init(magnitude: BoundedMagnitude, negative: Bool = false) {
    self.magnitude = magnitude
    self.negative = negative && !magnitude.isZero
  }
  public init(_ raw: String, radix: Int, signed: Bool = true, maxDigits: Int = 4096) throws {
    guard (2...36).contains(radix) else {
      throw CalculationIssue(.invalid, "Choose a base from 2 through 36.")
    }
    let s = try CalculationInput.trimmed(raw, limit: maxDigits * 2 + 4)
    guard !s.isEmpty && s != "+" && s != "-" else {
      throw CalculationIssue(.notReady, "Enter an integer.")
    }
    let leading = raw.unicodeScalars.prefix { CharacterSet.whitespacesAndNewlines.contains($0) }
      .reduce(0) { $0 + $1.utf16.count }
    let units = Array(s.utf16)
    var i = 0
    var minus = false
    var count = 0
    var v = BoundedMagnitude()
    if units[i] == 43 || units[i] == 45 {
      minus = units[i] == 45
      i += 1
    }
    if minus && !signed {
      throw CalculationIssue(.invalid, "Unsigned input cannot have a minus sign.")
    }
    if i + 1 < units.count, units[i] == 48 {
      let c = units[i + 1] | 32
      if (radix == 2 && c == 98) || (radix == 8 && c == 111) || (radix == 16 && c == 120) { i += 2 }
    }
    let start = i
    func digit(_ c: UInt16) -> Int? {
      if (48...57).contains(c) { return Int(c - 48) }
      let lower = c | 32
      if (97...122).contains(lower) { return Int(lower - 97 + 10) }
      return nil
    }
    while i < units.count {
      if i % 128 == 0 { try Task.checkCancellation() }
      if units[i] == 95 {
        guard i > start, i + 1 < units.count, let a = digit(units[i - 1]), a < radix,
          let b = digit(units[i + 1]), b < radix
        else {
          throw CalculationIssue(
            .invalid, "Use underscores only between digits.",
            range: .init(location: leading + i, length: 1))
        }
      } else {
        guard let d = digit(units[i]), d < radix else {
          throw CalculationIssue(
            .invalid, "Digit is not valid in base \(radix).",
            range: .init(location: leading + i, length: 1))
        }
        count += 1
        guard count <= maxDigits else {
          throw CalculationIssue(.resource, "Input limit: \(maxDigits) digits.")
        }
        try v.multiply(UInt32(radix))
        try v.add(UInt32(d))
      }
      i += 1
    }
    guard count > 0 else { throw CalculationIssue(.notReady, "Enter digits after the prefix.") }
    self.init(magnitude: v, negative: minus)
  }
  public func text(base: Int = 10, uppercase: Bool = false) throws -> String {
    (negative ? "-" : "") + (try magnitude.digits(radix: base, uppercase: uppercase))
  }
  public func encoded(width: Int, signed: Bool) throws -> BoundedMagnitude {
    guard (1...4096).contains(width) else {
      throw CalculationIssue(.invalid, "Bit width must be 1…4096.")
    }
    let limit = try BoundedMagnitude.powerOfTwo(signed ? width - 1 : width)
    guard negative ? signed && magnitude <= limit : magnitude < limit else {
      throw CalculationIssue(
        .invalid, "Value does not fit the selected \(signed ? "signed" : "unsigned") width.")
    }
    return negative ? try BoundedMagnitude.powerOfTwo(width).subtracting(magnitude) : magnitude
  }
  public static func bitReport(_ pattern: BoundedMagnitude, width: Int, uppercase: Bool = false)
    throws -> CalculationReport
  {
    guard (1...4096).contains(width) else {
      throw CalculationIssue(.invalid, "Bit width must be 1…4096.")
    }
    guard pattern.bitLength <= width else {
      throw CalculationIssue(.invalid, "Pattern exceeds \(width) bits. No bits were discarded.")
    }
    let binary = try pattern.digits(radix: 2)
    let hex = try pattern.digits(radix: 16, uppercase: uppercase)
    let negative = pattern >= (try BoundedMagnitude.powerOfTwo(width - 1))
    let signedValue =
      negative
      ? RadixInteger(
        magnitude: try BoundedMagnitude.powerOfTwo(width).subtracting(pattern), negative: true)
      : RadixInteger(magnitude: pattern)
    return .init(
      rows: [
        .init(
          "bin", "Binary · \(width) bits",
          String(repeating: "0", count: width - binary.count) + binary),
        .init(
          "hex", "Hexadecimal", String(repeating: "0", count: (width + 3) / 4 - hex.count) + hex),
        .init("unsigned", "Unsigned decimal", try pattern.digits(radix: 10)),
        .init("signed", "Signed two’s complement", try signedValue.text()),
      ], status: "Converted")
  }
}
