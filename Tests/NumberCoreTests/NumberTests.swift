import Testing

@testable import NumberCore

@Suite struct NumberTests {
  @Test func boundaries() throws {
    #expect(
      try BoundedMagnitude.powerOfTwo(128).digits(radix: 10)
        == "340282366920938463463374607431768211456")
    #expect(try RadixInteger("0b", radix: 16).text() == "11")
    #expect(try RadixInteger("0x", radix: 36).text() == "33")
    #expect(try RadixInteger("-0", radix: 10).text() == "0")
    #expect(
      try RadixInteger.bitReport(RadixInteger("FF", radix: 16).magnitude, width: 8).rows.last?.value
        == "-1")
    #expect(throws: CalculationIssue.self) {
      try RadixInteger("-129", radix: 10).encoded(width: 8, signed: true)
    }
    for base in 2...36 {
      let a = try RadixInteger("123456789012345678901234567890", radix: 10)
      #expect(try RadixInteger(a.text(base: base), radix: base) == a)
    }
  }
}
