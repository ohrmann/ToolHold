import Foundation

enum TextFailure: Error, Sendable, Equatable {
  case invalid(String, Int? = nil)
  case resource(String)
  case cancelled
  var message: String {
    switch self {
    case .invalid(let s, let offset): offset.map { s + " (UTF-16 offset \($0))" } ?? s
    case .resource(let s): s
    case .cancelled: "Cancelled"
    }
  }
}
enum TextBounds {
  static let input = 262_144, output = 1_048_576
  static func check(_ s: String, max: Int = input) throws {
    if s.utf16.count > max {
      throw TextFailure.resource("Text exceeds the \(max) UTF-16 unit limit.")
    }
    try Task.checkCancellation()
  }
  static func checkpoint(_ n: Int) throws { if n & 1023 == 0 { try Task.checkCancellation() } }
}
struct TextLine: Sendable {
  let ordinal: Int
  let range: NSRange
  let endRange: NSRange
  let ending: String
  var fullRange: NSRange { .init(location: range.location, length: range.length + endRange.length) }
}
struct TextSnapshot: Sendable {
  let source: String
  let lines: [TextLine]
  private let units: [UInt16]
  init(_ source: String) {
    self.source = source
    let u = Array(source.utf16)
    self.units = u
    var rows: [TextLine] = []
    var start = 0
    var i = 0
    while i < u.count {
      if u[i] == 10 || u[i] == 13 {
        let n = u[i] == 13 && i + 1 < u.count && u[i + 1] == 10 ? 2 : 1
        rows.append(
          .init(
            ordinal: rows.count + 1, range: .init(location: start, length: i - start),
            endRange: .init(location: i, length: n),
            ending: String(decoding: u[i..<i + n], as: UTF16.self)))
        i += n
        start = i
      } else {
        i += 1
      }
    }
    if start < u.count {
      rows.append(
        .init(
          ordinal: rows.count + 1, range: .init(location: start, length: u.count - start),
          endRange: .init(location: u.count, length: 0), ending: ""))
    }
    lines = rows
  }
  func text(_ row: TextLine) -> String {
    String(decoding: units[row.range.location..<NSMaxRange(row.range)], as: UTF16.self)
  }
  func location(_ offset: Int) -> (Int, Int) {
    var lo = 0
    var hi = lines.count
    while lo < hi {
      let m = (lo + hi) / 2
      if lines[m].range.location <= offset { lo = m + 1 } else { hi = m }
    }
    if let last = lines.last, offset == source.utf16.count, !last.ending.isEmpty {
      return (lines.count + 1, 1)
    }
    let row = lines.isEmpty ? nil : lines[max(0, lo - 1)]
    return (row?.ordinal ?? 1, offset - (row?.range.location ?? 0) + 1)
  }
}
struct TextRow: Identifiable, Sendable {
  let id: Int
  var label: String
  var value: String
  var detail: String = ""
  var left: NSRange?
  var right: NSRange?
}
struct TextArtifact: Sendable {
  var output: String?
  var message = "Done"
  var notes: [String] = []
  var rows: [TextRow] = []
  var regex: TextRegexResult?
  var diff: TextDiffResult?
  var mock: MockDataset?
  var highlights: [NSRange] = []
  var filename = "result.txt"
}
enum TextDisplay {
  static func safe(_ text: String, limit: Int = 240) -> String {
    var out = ""
    var count = 0
    var units = 0
    for ch in text {
      let n = ch.utf16.count
      if count >= limit || units + n > 1024 {
        out += "…"
        break
      }
      for s in ch.unicodeScalars {
        if s.value == 10 {
          out += "↵"
        } else if s.value == 13 {
          out += "␍"
        } else if s.value == 9 {
          out += "⇥"
        } else if s.properties.generalCategory == .control
          || s.properties.generalCategory == .format
        {
          out += String(format: "⟨U+%04X⟩", s.value)
        } else {
          out.unicodeScalars.append(s)
        }
      }
      count += 1
      units += n
    }
    return out
  }
  static func substring(_ s: String, _ range: NSRange) -> String {
    guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= s.utf16.count else {
      return ""
    }
    return (s as NSString).substring(with: range)
  }
  static func lines(_ values: [String], ending: String = "\n", terminal: Bool = false) -> String {
    guard !values.isEmpty else { return "" }
    return values.joined(separator: ending) + ((terminal || values.last == "") ? ending : "")
  }
}
