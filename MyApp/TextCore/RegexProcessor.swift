import CRegex
import Foundation

final class TextRegexCancellation: @unchecked Sendable {
  let pointer: OpaquePointer?
  init() { pointer = tr_cancel_create() }
  func cancel() { tr_cancel_request(pointer) }
  deinit { tr_cancel_free(pointer) }
}
struct TextRegexOptions: Equatable, Sendable, Codable {
  var ignoreCase = false, multiline = false, dotAll = false, extended = false, first = false,
    literal = false
  var flags: UInt32 {
    var value: UInt32 = 0
    if ignoreCase { value |= 1 }
    if multiline { value |= 2 }
    if dotAll { value |= 4 }
    if extended && !literal { value |= 8 }
    if literal { value |= 16 }
    if first { value |= 32 }
    return value
  }
}
struct TextRegexMatch: Sendable, Identifiable {
  let id: Int
  let groups: [NSRange?]
  var range: NSRange { groups[0]! }
}
struct TextRegexResult: Sendable {
  let source: String
  let matches: [TextRegexMatch]
  let names: [Int: String]
  let groupCount: Int
}
enum TextRegexProcessor {
  static func run(
    _ source: String, pattern: String, options: TextRegexOptions = .init(), automatic: Bool = false,
    cancellation: TextRegexCancellation = .init()
  ) throws -> TextRegexResult {
    try TextBounds.check(source)
    try TextBounds.check(pattern, max: 8192)
    if Task.isCancelled { cancellation.cancel() }
    let escaped =
      options.literal
      ? pattern.unicodeScalars.map { "\\x{\(String($0.value,radix:16))}" }.joined() : pattern
    let p = Array(escaped.utf16)
    let s = Array(source.utf16)
    // Empty buffers still provide a valid pointer for the C API.
    let pp = p.isEmpty ? [UInt16(0)] : p
    let ss = s.isEmpty ? [UInt16(0)] : s
    guard
      let result = pp.withUnsafeBufferPointer({ a in
        ss.withUnsafeBufferPointer { b in
          tr_run(
            a.baseAddress, p.count, b.baseAddress, s.count, options.flags, automatic ? 250 : 1000,
            cancellation.pointer)
        }
      })
    else { throw TextFailure.resource("Regex allocation limit reached.") }
    defer { tr_result_free(result) }
    let r = result.pointee
    let message = withUnsafeBytes(of: r.message) {
      String(decoding: $0.bindMemory(to: UInt16.self).prefix(Int(r.message_length)), as: UTF16.self)
    }
    switch r.status {
    case 1: throw TextFailure.invalid(message, Int(r.error_offset))
    case 2: throw TextFailure.resource(message)
    case 3: throw TextFailure.cancelled
    case 0: break
    default: throw TextFailure.invalid("Regex engine failed.")
    }
    var matches: [TextRegexMatch] = []
    var names: [Int: String] = [:]
    if let pointer = r.names {
      let u = UnsafeBufferPointer(start: pointer, count: 129 * 129)
      for g in 0...Int(r.groups) {
        let slice = u[(g * 129)..<(g * 129 + 129)].prefix { $0 != 0 }
        if !slice.isEmpty { names[g] = String(decoding: slice, as: UTF16.self) }
      }
    }
    for i in 0..<Int(r.count) {
      try TextBounds.checkpoint(i)
      var groups: [NSRange?] = []
      for g in 0...Int(r.groups) {
        let at = (i * (Int(r.groups) + 1) + g) * 2
        let a = r.ranges![at]
        let b = r.ranges![at + 1]
        groups.append(
          a == Int.max || a == (-1) || b < a || a < 0 || b > s.count
            ? nil : NSRange(location: a, length: b - a))
      }
      guard groups.first.flatMap({ $0 }) != nil else {
        throw TextFailure.invalid("Engine returned an invalid source range.")
      }
      matches.append(.init(id: i, groups: groups))
    }
    return .init(source: source, matches: matches, names: names, groupCount: Int(r.groups))
  }
  static func artifact(_ result: TextRegexResult) -> TextArtifact {
    let snapshot = TextSnapshot(result.source)
    return .init(
      message: result.matches.isEmpty ? "No matches" : "\(result.matches.count) matches",
      rows: result.matches.map { m in
        let pos = snapshot.location(m.range.location)
        return TextRow(
          id: m.id, label: "Match \(m.id+1) · \(pos.0):\(pos.1)",
          value: m.range.length == 0
            ? "Empty match" : TextDisplay.safe(TextDisplay.substring(result.source, m.range)),
          detail: "UTF-16 \(m.range.location)..<\(NSMaxRange(m.range))", left: m.range)
      }, regex: result, highlights: result.matches.map(\.range))
  }
}
enum TextReplacement {
  enum Part { case literal(String), group(Int), named(String) }
  static func parts(_ template: String, result: TextRegexResult, literal: Bool) throws -> [Part] {
    try TextBounds.check(template, max: 65536)
    if literal { return [.literal(template)] }
    let u = Array(template.utf16)
    var i = 0
    var parts: [Part] = []
    var buffer: [UInt16] = []
    func flush() {
      if !buffer.isEmpty {
        parts.append(.literal(String(decoding: buffer, as: UTF16.self)))
        buffer = []
      }
    }
    while i < u.count {
      if u[i] != 36 {
        buffer.append(u[i])
        i += 1
        continue
      }
      flush()
      let start = i
      i += 1
      guard i < u.count else {
        throw TextFailure.invalid("Use $$ for a literal dollar sign.", start)
      }
      if u[i] == 36 {
        buffer.append(36)
        i += 1
        continue
      }
      if u[i] == 123 {
        i += 1
        let a = i
        while i < u.count && u[i] != 125 { i += 1 }
        guard i < u.count else { throw TextFailure.invalid("Unclosed ${name} reference.", start) }
        let name = String(decoding: u[a..<i], as: UTF16.self)
        i += 1
        guard result.names.values.contains(name) else {
          throw TextFailure.invalid("Unknown capture name.", start)
        }
        parts.append(.named(name))
      } else {
        let a = i
        while i < u.count && (48...57).contains(u[i]) { i += 1 }
        guard i > a, let n = Int(String(decoding: u[a..<i], as: UTF16.self)), n <= result.groupCount
        else { throw TextFailure.invalid("Unknown capture reference.", start) }
        parts.append(.group(n))
      }
    }
    flush()
    return parts
  }
  static func replace(
    _ result: TextRegexResult, template: String, literal: Bool = false, current: Int? = nil
  ) throws -> String {
    let parts = try parts(template, result: result, literal: literal)
    let source = result.source as NSString
    var out = ""
    var offset = 0
    var total = 0
    func append(_ s: String) throws {
      total += s.utf16.count
      guard total <= TextBounds.output else {
        throw TextFailure.resource("Replacement output limit reached.")
      }
      out += s
    }
    for (i, m) in result.matches.enumerated() where current == nil || current == i {
      try TextBounds.checkpoint(i)
      guard m.range.location >= offset else {
        throw TextFailure.invalid("Overlapping matches cannot be replaced.")
      }
      try append(source.substring(with: .init(location: offset, length: m.range.location - offset)))
      for p in parts {
        switch p {
        case .literal(let s): try append(s)
        case .group(let g): if let r = m.groups[g] { try append(source.substring(with: r)) }
        case .named(let name):
          for g in result.names.keys.sorted() where result.names[g] == name {
            if let r = m.groups[g] {
              try append(source.substring(with: r))
              break
            }
          }
        }
      }
      offset = NSMaxRange(m.range)
    }
    try append(source.substring(from: offset))
    return out
  }
}
