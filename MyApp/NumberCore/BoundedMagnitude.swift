import Foundation

/// Conversion arithmetic only, never used for cryptography. Zero has no limbs.
public struct BoundedMagnitude: Equatable, Comparable, Sendable {
  private var limbs: [UInt32]
  public init(_ value: UInt64 = 0) {
    limbs = value == 0 ? [] : [UInt32(truncatingIfNeeded: value)]
    if value >> 32 != 0 { limbs.append(UInt32(value >> 32)) }
  }
  public var isZero: Bool { limbs.isEmpty }
  public var bitLength: Int {
    guard let last = limbs.last else { return 0 }
    return (limbs.count - 1) * 32 + 32 - last.leadingZeroBitCount
  }
  public static func < (a: Self, b: Self) -> Bool {
    if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
    return a.limbs.reversed().lexicographicallyPrecedes(b.limbs.reversed())
  }
  public mutating func multiply(_ small: UInt32) throws {
    if small == 0 {
      limbs = []
      return
    }
    var carry: UInt64 = 0
    for i in limbs.indices {
      let v = UInt64(limbs[i]) * UInt64(small) + carry
      limbs[i] = UInt32(truncatingIfNeeded: v)
      carry = v >> 32
    }
    if carry != 0 { limbs.append(UInt32(carry)) }
    guard limbs.count <= 1024 else {
      throw CalculationIssue(.resource, "Integer exceeds conversion capacity.")
    }
  }
  public mutating func add(_ small: UInt32) throws {
    var carry = UInt64(small)
    var i = 0
    while carry != 0 {
      if i == limbs.count { limbs.append(0) }
      let value = UInt64(limbs[i]) + carry
      limbs[i] = UInt32(truncatingIfNeeded: value)
      carry = value >> 32
      i += 1
    }
    guard limbs.count <= 1024 else {
      throw CalculationIssue(.resource, "Integer exceeds conversion capacity.")
    }
  }
  public static func powerOfTwo(_ bit: Int) throws -> Self {
    guard (0...32767).contains(bit) else {
      throw CalculationIssue(.resource, "Bit width exceeds conversion capacity.")
    }
    var v = Self()
    v.limbs = Array(repeating: 0, count: bit / 32 + 1)
    v.limbs[bit / 32] = 1 << (bit % 32)
    return v
  }
  public func subtracting(_ other: Self) throws -> Self {
    guard self >= other else { throw CalculationIssue(.invalid, "Negative unsigned difference.") }
    var r = self
    var borrow: UInt64 = 0
    for i in r.limbs.indices {
      let rhs = (i < other.limbs.count ? UInt64(other.limbs[i]) : 0) + borrow
      let lhs = UInt64(r.limbs[i])
      r.limbs[i] = UInt32(truncatingIfNeeded: lhs &- rhs)
      borrow = lhs < rhs ? 1 : 0
    }
    while r.limbs.last == 0 { r.limbs.removeLast() }
    return r
  }
  public func adding(_ other: Self) throws -> Self {
    var r = self
    var carry: UInt64 = 0
    for i in 0..<max(limbs.count, other.limbs.count) {
      if i == r.limbs.count { r.limbs.append(0) }
      let v = UInt64(r.limbs[i]) + (i < other.limbs.count ? UInt64(other.limbs[i]) : 0) + carry
      r.limbs[i] = UInt32(truncatingIfNeeded: v)
      carry = v >> 32
    }
    if carry > 0 { r.limbs.append(UInt32(carry)) }
    guard r.limbs.count <= 1024 else {
      throw CalculationIssue(.resource, "Integer exceeds conversion capacity.")
    }
    return r
  }
  public func uint64() -> UInt64? {
    guard limbs.count <= 2 else { return nil }
    return (limbs.first.map(UInt64.init) ?? 0) | (limbs.count == 2 ? UInt64(limbs[1]) << 32 : 0)
  }
  public func digits(radix: Int, uppercase: Bool = false) throws -> String {
    guard (2...36).contains(radix) else {
      throw CalculationIssue(.invalid, "Choose a base from 2 through 36.")
    }
    if isZero { return "0" }
    let alphabet = Array(
      (uppercase ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "0123456789abcdefghijklmnopqrstuvwxyz")
        .utf8)
    var value = self
    var out: [UInt8] = []
    while !value.isZero {
      if out.count % 128 == 0 { try Task.checkCancellation() }
      var remainder: UInt64 = 0
      for i in value.limbs.indices.reversed() {
        let n = remainder << 32 | UInt64(value.limbs[i])
        value.limbs[i] = UInt32(n / UInt64(radix))
        remainder = n % UInt64(radix)
      }
      while value.limbs.last == 0 { value.limbs.removeLast() }
      out.append(alphabet[Int(remainder)])
      guard out.count <= 32768 else {
        throw CalculationIssue(.resource, "Output limit: 32,768 characters.")
      }
    }
    return String(decoding: out.reversed(), as: UTF8.self)
  }
}
