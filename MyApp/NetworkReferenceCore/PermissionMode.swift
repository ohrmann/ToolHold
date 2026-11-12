import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public struct PermissionMode: Equatable, Sendable {
  public let bits: UInt16
  public init(bits: UInt16) { self.bits = bits & 0o7777 }
  public init(octal: String) throws {
    let s = try CalculationInput.trimmed(octal, limit: 16)
    guard !s.isEmpty else { throw CalculationIssue(.notReady, "Enter an octal mode.") }
    guard (3...4).contains(s.count), s.utf8.allSatisfy({ (48...55).contains($0) }),
      let n = UInt16(s, radix: 8)
    else { throw CalculationIssue(.invalid, "Use 3 or 4 octal digits (0…7).") }
    self.init(bits: n)
  }
  public init(symbolic: String) throws {
    let s = Array(try CalculationInput.trimmed(symbolic, limit: 16))
    guard s.count == 9 else {
      throw CalculationIssue(
        .invalid, "Use exactly nine permission characters, without file type or ACL suffix.")
    }
    var bits: UInt16 = 0
    for i in 0..<9 {
      let c = s[i]
      let ordinary: Character = ["r", "w", "x"][i % 3]
      if c == ordinary {
        bits |= 1 << (8 - i)
      } else if c == "-" {
      } else if i == 2 || i == 5, c == "s" || c == "S" {
        bits |= i == 2 ? 0o4000 : 0o2000
        if c == "s" { bits |= 1 << (8 - i) }
      } else if i == 8, c == "t" || c == "T" {
        bits |= 0o1000
        if c == "t" { bits |= 1 }
      } else {
        throw CalculationIssue(
          .invalid, "Invalid permission character at position \(i + 1).",
          range: .init(location: i, length: 1))
      }
    }
    self.init(bits: bits)
  }
  public var octal: String { String(format: "%04o", bits) }
  public var symbolic: String {
    var out = Array("---------")
    for i in 0..<9 where bits & (1 << (8 - i)) != 0 { out[i] = ["r", "w", "x"][i % 3] }
    for (index, mask, on, off) in [
      (2, UInt16(0o4000), Character("s"), Character("S")), (5, UInt16(0o2000), "s", "S"),
      (8, UInt16(0o1000), "t", "T"),
    ] where bits & mask != 0 { out[index] = out[index] == "x" ? on : off }
    return String(out)
  }
  public func applying(_ expression: String, directory: Bool = false) throws -> Self {
    let s = try CalculationInput.trimmed(expression, limit: 1024, field: "Symbolic change")
    guard !s.isEmpty else {
      throw CalculationIssue(.notReady, "Enter a symbolic change.", field: "Symbolic change")
    }
    var mode = bits
    var operations = 0
    for clause in s.split(separator: ",", omittingEmptySubsequences: false) {
      let c = Array(clause)
      let size = c.count
      var i = 0
      var who: UInt16 = 0
      while i < size, "ugoa".contains(c[i]) {
        switch c[i] {
        case "u": who |= 0o4700
        case "g": who |= 0o2070
        case "o": who |= 0o1007
        default: who = 0o7777
        }
        i += 1
      }
      guard who != 0 else {
        throw CalculationIssue(
          .invalid, "Specify u, g, o or a. The system umask is not inferred.",
          field: "Symbolic change")
      }
      guard i < size else {
        throw CalculationIssue(.invalid, "Expected +, - or = after who.", field: "Symbolic change")
      }
      while i < size {
        let op = c[i]
        guard "+-=".contains(op) else {
          throw CalculationIssue(.invalid, "Expected +, - or =.", field: "Symbolic change")
        }
        i += 1
        let start = i
        while i < size && !"+-=".contains(c[i]) { i += 1 }
        let operand = Array(c[start..<i])
        var permissions: UInt16 = 0
        if operand.count == 1 && "ugo".contains(operand[0]) {
          let shift = operand[0] == "u" ? 6 : operand[0] == "g" ? 3 : 0
          let v = (mode >> shift) & 7
          permissions = v | v << 3 | v << 6
        } else {
          for v in operand {
            switch v {
            case "r": permissions |= 0o444
            case "w": permissions |= 0o222
            case "x": permissions |= 0o111
            case "X": if directory || mode & 0o111 != 0 { permissions |= 0o111 }
            case "s": permissions |= 0o6000
            case "t": permissions |= 0o1000
            default:
              throw CalculationIssue(
                .invalid, "Use rwxXst or one permission-copy operand u/g/o.",
                field: "Symbolic change")
            }
          }
        }
        operations += 1
        guard operations <= 64 else {
          throw CalculationIssue(.resource, "Limit: 64 symbolic operations.")
        }
        let value = permissions & who
        if op == "=" {
          mode = (mode & ~who) | value
        } else if op == "+" {
          mode |= value
        } else {
          mode &= ~value
        }
      }
    }
    return .init(bits: mode)
  }
}
