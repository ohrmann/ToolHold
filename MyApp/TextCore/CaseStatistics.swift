import Foundation
import NaturalLanguage

struct TextCaseOptions: Codable, Equatable, Sendable { var mode = "camelCase", perLine = true }
enum TextCaseProcessor {
  static func process(_ source: String, options o: TextCaseOptions) throws -> TextArtifact {
    try TextBounds.check(source)
    var opaque = false
    func convert(_ text: String) -> String {
      let locale = Locale(identifier: "en_US_POSIX")
      if o.mode == "lowercase" { return text.lowercased(with: locale) }
      if o.mode == "UPPERCASE" { return text.uppercased(with: locale) }
      let chars = Array(text)
      let n = chars.count
      var tokens: [String] = []
      var current = ""
      func type(_ c: Character) -> Int {
        guard let s = c.unicodeScalars.first else { return 0 }
        let p = s.properties
        if p.isUppercase { return 2 }
        if p.isLowercase { return 1 }
        if p.generalCategory == .decimalNumber { return 3 }
        if p.isAlphabetic { return 4 }
        if p.generalCategory == .nonspacingMark { return 5 }
        if p.isWhitespace
          || [
            .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
            .initialPunctuation, .finalPunctuation, .otherPunctuation,
          ].contains(p.generalCategory)
        {
          return 0
        }
        return 6
      }
      func flush() {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
      }
      for i in 0..<n {
        let t = type(chars[i])
        if t == 0 {
          flush()
          continue
        }
        if t == 6 {
          flush()
          tokens.append(String(chars[i]))
          opaque = true
          continue
        }
        if i > 0 {
          let prev = type(chars[i - 1])
          let next = i + 1 < n ? type(chars[i + 1]) : 0
          if (prev == 1 && t == 2) || (prev == 2 && t == 2 && next == 1)
            || (prev == 3 && (t == 1 || t == 2 || t == 4))
            || ((prev == 1 || prev == 2 || prev == 4) && t == 3)
          {
            flush()
          }
        }
        current.append(chars[i])
      }
      flush()
      let lower = tokens.map { $0.lowercased(with: locale) }
      func capital(_ s: String) -> String {
        guard let first = s.first else { return "" }
        return String(first).uppercased(with: locale) + s.dropFirst()
      }
      switch o.mode {
      case "PascalCase": return lower.map(capital).joined()
      case "snake_case": return lower.joined(separator: "_")
      case "kebab-case": return lower.joined(separator: "-")
      case "CONSTANT_CASE": return lower.map { $0.uppercased(with: locale) }.joined(separator: "_")
      case "Train-Case": return lower.map(capital).joined(separator: "-")
      default: return (lower.first ?? "") + lower.dropFirst().map(capital).joined()
      }
    }
    let out: String
    if o.perLine {
      let snapshot = TextSnapshot(source)
      var s = ""
      for (i, l) in snapshot.lines.enumerated() {
        try TextBounds.checkpoint(i)
        s += convert(snapshot.text(l)) + l.ending
      }
      out = s
    } else {
      out = convert(source)
    }
    try TextBounds.check(out, max: TextBounds.output)
    return .init(
      output: out, message: "Converted to \(o.mode)",
      notes: opaque ? ["Symbols preserved. The result may not be a valid identifier."] : [])
  }
}
enum TextStatisticsProcessor {
  static func process(_ source: String) throws -> TextArtifact {
    try TextBounds.check(source)
    let snapshot = TextSnapshot(source)
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = source
    var words = 0
    tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { range, _ in
      if source[range].unicodeScalars.contains(where: {
        $0.properties.isAlphabetic || $0.properties.generalCategory == .decimalNumber
      }) {
        words += 1
      }
      return !Task.isCancelled
    }
    try Task.checkCancellation()
    let scalars = source.unicodeScalars
    let items: [(String, Int)] = [
      ("UTF-8 bytes (no BOM)", source.utf8.count), ("UTF-16 code units", source.utf16.count),
      ("Unicode scalars", scalars.count), ("Grapheme clusters", source.count),
      ("Words (system tokenizer)", words),
      ("Whitespace-separated tokens", source.split(whereSeparator: { $0.isWhitespace }).count),
      ("Line records", snapshot.lines.count),
      (
        "Logical editor lines",
        source.isEmpty ? 0 : snapshot.lines.filter { !$0.ending.isEmpty }.count + 1
      ), ("LF", snapshot.lines.filter { $0.ending == "\n" }.count),
      ("CRLF", snapshot.lines.filter { $0.ending == "\r\n" }.count),
      ("CR", snapshot.lines.filter { $0.ending == "\r" }.count),
      ("Empty records", snapshot.lines.filter { $0.range.length == 0 }.count),
      ("SPACE", scalars.filter { $0.value == 32 }.count),
      ("TAB", scalars.filter { $0.value == 9 }.count),
      ("Whitespace scalars", scalars.filter { $0.properties.isWhitespace }.count),
      ("Non-ASCII scalars", scalars.filter { $0.value > 127 }.count),
    ]
    var rows = items.enumerated().map {
      TextRow(id: $0.offset, label: $0.element.0, value: String($0.element.1))
    }
    rows.append(
      .init(
        id: rows.count, label: "Final newline",
        value: !(snapshot.lines.last?.ending.isEmpty ?? true) ? "Yes" : "No"))
    if let line = snapshot.lines.reduce(
      nil as TextLine?,
      { best, line in best == nil || line.range.length > best!.range.length ? line : best })
    {
      rows.append(
        .init(
          id: rows.count, label: "Longest line (UTF-16)",
          value: "\(line.range.length) units · \(snapshot.text(line).count) graphemes",
          left: line.range))
    }
    return .init(
      output: rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n"),
      message: "Text statistics",
      notes: [
        "Words and grapheme boundaries use system Unicode/language rules; word counts can vary by language and OS."
      ], rows: rows)
  }
}
