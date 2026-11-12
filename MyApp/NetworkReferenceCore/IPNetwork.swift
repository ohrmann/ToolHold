import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public struct IPAddress: Equatable, Sendable {
  public let bytes: [UInt8]
  public var bits: Int { bytes.count * 8 }
  public init(_ source: String) throws {
    let text = try CalculationInput.trimmed(source, limit: 256, field: "Address")
    guard !text.isEmpty else { throw CalculationIssue(.notReady, "Enter an IP address.") }
    if !text.contains(":") {
      bytes = try Self.v4(text)
      return
    }
    guard !text.contains("%"), !text.contains("["), !text.contains("]") else {
      throw CalculationIssue(.unsupported, "Use an address without a zone ID, brackets or port.")
    }
    var value = text
    if value.contains(".") {
      guard let colon = value.lastIndex(of: ":") else {
        throw CalculationIssue(.invalid, "Invalid embedded IPv4 address.")
      }
      let tail = try Self.v4(String(value[value.index(after: colon)...]))
      value =
        String(value[...colon]) + String(UInt16(tail[0]) * 256 + UInt16(tail[1]), radix: 16) + ":"
        + String(UInt16(tail[2]) * 256 + UInt16(tail[3]), radix: 16)
    }
    let halves = value.components(separatedBy: "::")
    guard halves.count <= 2 else { throw CalculationIssue(.invalid, "IPv6 permits only one '::'.") }
    func words(_ part: String) throws -> [UInt16] {
      if part.isEmpty { return [] }
      return try part.split(separator: ":", omittingEmptySubsequences: false).map {
        guard (1...4).contains($0.count),
          $0.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
          }), let n = UInt16($0, radix: 16)
        else {
          throw CalculationIssue(.invalid, "Each IPv6 group must contain 1–4 hexadecimal digits.")
        }
        return n
      }
    }
    let left = try words(halves[0])
    let right = try halves.count == 2 ? words(halves[1]) : []
    let missing = 8 - left.count - right.count
    guard halves.count == 2 ? missing >= 1 : missing == 0 else {
      throw CalculationIssue(.invalid, "IPv6 must contain eight groups after expansion.")
    }
    bytes = (left + Array(repeating: 0, count: max(0, missing)) + right).flatMap {
      [UInt8($0 >> 8), UInt8($0 & 255)]
    }
  }
  init(bytes: [UInt8]) { self.bytes = bytes }
  static func v4(_ text: String) throws -> [UInt8] {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else {
      throw CalculationIssue(
        .invalid, "IPv4 requires four decimal octets; hostnames are not resolved.")
    }
    return try parts.map { p in
      guard !p.isEmpty, p.utf8.allSatisfy({ (48...57).contains($0) }),
        p.count == 1 || p.first != "0", let n = UInt8(p)
      else { throw CalculationIssue(.invalid, "IPv4 octets must be 0–255 without leading zeros.") }
      return n
    }
  }
  public var text: String {
    if bytes.count == 4 { return bytes.map(String.init).joined(separator: ".") }
    if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255 {
      return "::ffff:" + bytes.suffix(4).map(String.init).joined(separator: ".")
    }
    let words = stride(from: 0, to: 16, by: 2).map {
      UInt16(bytes[$0]) * 256 + UInt16(bytes[$0 + 1])
    }
    var bestStart = -1
    var bestCount = 1
    var index = 0
    while index < 8 {
      if words[index] != 0 {
        index += 1
        continue
      }
      let start = index
      while index < 8 && words[index] == 0 { index += 1 }
      if index - start > bestCount {
        bestStart = start
        bestCount = index - start
      }
    }
    if bestStart < 0 { return words.map { String($0, radix: 16) }.joined(separator: ":") }
    let left = words[..<bestStart].map { String($0, radix: 16) }.joined(separator: ":")
    let right = words[(bestStart + bestCount)...].map { String($0, radix: 16) }.joined(
      separator: ":")
    return left + "::" + right
  }
}
public struct IPNetwork: Equatable, Sendable {
  public let address: IPAddress
  public let prefix: Int
  public init(_ source: String) throws {
    let input = try CalculationInput.trimmed(source, limit: 256, field: "CIDR")
    let parts = input.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count <= 2 else { throw CalculationIssue(.invalid, "Use address/prefix.") }
    address = try IPAddress(String(parts.first ?? ""))
    if parts.count == 1 {
      prefix = address.bits
    } else {
      guard !parts[1].isEmpty, parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
        let n = Int(parts[1]), (0...address.bits).contains(n)
      else { throw CalculationIssue(.invalid, "Prefix must be 0…\(address.bits).") }
      prefix = n
    }
  }
  public var mask: IPAddress {
    .init(
      bytes: address.bytes.indices.map { i in
        let used = min(8, max(0, prefix - i * 8))
        return used == 0 ? 0 : UInt8(255 << (8 - used) & 255)
      })
  }
  public var network: IPAddress { .init(bytes: zip(address.bytes, mask.bytes).map { $0 & $1 }) }
  public var last: IPAddress { .init(bytes: zip(network.bytes, mask.bytes).map { $0 | ~$1 }) }
  public var canonical: String { "\(network.text)/\(prefix)" }
  public var count: BoundedMagnitude { get throws { try .powerOfTwo(address.bits - prefix) } }
  public func contains(_ other: IPNetwork) -> Bool {
    address.bits == other.address.bits && prefix <= other.prefix
      && zip(other.network.bytes, mask.bytes).map({ $0 & $1 }) == network.bytes
  }
  public func overlaps(_ other: IPNetwork) -> Bool { contains(other) || other.contains(self) }
  public func report(comparison: String = "") throws -> CalculationReport {
    let total = try count
    var rows: [CalculationRow] = [
      .init("family", "Address family", address.bits == 32 ? "IPv4" : "IPv6"),
      .init("address", "Canonical input address", address.text),
      .init("prefix", "Prefix length", String(prefix)), .init("network", "Network", canonical),
      .init("first", "First address", network.text), .init("last", "Last address", last.text),
      .init("total", "Total addresses", try total.digits(radix: 10)),
      .init("mask", "Netmask", mask.text),
    ]
    var notes: [String] = []
    let multicast = try IPNetwork(address.bits == 32 ? "224.0.0.0/4" : "ff00::/8")
    if overlaps(multicast) {
      notes.append(
        multicast.contains(self)
          ? "Multicast address range (RFC 1112 / RFC 4291)."
          : "This network partially overlaps multicast space (RFC 1112 / RFC 4291).")
    }
    if address.bits == 128 && address.text.hasPrefix("::ffff:") {
      notes.append(
        "IPv4-mapped IPv6 representation; it remains an IPv6 address for range comparisons.")
    }
    if network != address {
      notes.append(
        "Host bits are set. Calculated network: \(canonical); your input was not changed.")
    }
    if address.bits == 32 {
      rows.append(.init("wildcard", "Wildcard mask", IPAddress(bytes: mask.bytes.map { ~$0 }).text))
      if prefix < 31 {
        rows.append(.init("broadcast", "Broadcast", last.text))
        var first = network.bytes
        var end = last.bytes
        first[3] += 1
        end[3] -= 1
        rows.append(
          .init(
            "usable", "Conventional usable range",
            "\(IPAddress(bytes:first).text) – \(IPAddress(bytes:end).text)",
            detail: try total.subtracting(.init(2)).digits(radix: 10) + " addresses"))
      } else {
        notes.append(
          prefix == 31
            ? "Both /31 addresses are usable point-to-point endpoints (RFC 3021)."
            : "A /32 identifies one address.")
      }
    } else {
      notes.append(
        "IPv6 has no broadcast address. This is the complete mathematical range, not a host availability estimate."
      )
    }
    if !comparison.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let other = try IPNetwork(comparison)
      let relation =
        address.bits != other.address.bits
        ? "Different address families"
        : canonical == other.canonical
          ? "Equal networks"
          : contains(other)
            ? "Contains comparison" : other.contains(self) ? "Contained by comparison" : "Disjoint"
      rows.append(.init("relation", "Comparison", relation, detail: other.canonical))
    }
    return .init(rows: rows, notes: notes, status: "Calculated")
  }
}
