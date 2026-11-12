import Foundation

/// Sample data only. SplitMix64 reference: Sebastiano Vigna, public-domain dedication.
struct SampleRandom: Sendable {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }
  mutating func below(_ bound: UInt64) -> UInt64 {
    precondition(bound > 0)
    let threshold = (0 &- bound) % bound
    while true {
      let n = next()
      if n >= threshold { return n % bound }
    }
  }
  mutating func integer(_ min: Int64, _ max: Int64) -> Int64 {
    let a = UInt64(bitPattern: min) ^ 0x8000_0000_0000_0000
    let b = UInt64(bitPattern: max) ^ 0x8000_0000_0000_0000
    let width = b &- a &+ 1
    let n = width == 0 ? next() : below(width)
    return Int64(bitPattern: (a &+ n) ^ 0x8000_0000_0000_0000)
  }
}
struct LoremOptions: Equatable, Sendable, Codable {
  var unit = "Paragraphs", count = 3, sentences = 4, words = 12, start = true, seed: String = ""
}
enum LoremProcessor {
  // Project-authored Latin-like sample vocabulary, not a copied modern text corpus.
  static let vocabulary =
    "lorem ipsum dolor amet nova terra lumen porta via aqua vita tempus sol luna mare ventus arbor folium flumen orbis forma linea punctum valor vox liber carta numerus color campus mons vallis aurora stella nubes ignis lapis radix ramus fructus manus oculus auris memoria causa initium finis motus spatium arcus nexus opus cura ars pax lux verbum iter unda silva domus locus civis fortis clarus altus brevis longus parvus magnus apertus verus bonus lenis vivus plenus purus"
    .split(separator: " ").map(String.init)
  static func seed(_ s: String) throws -> UInt64 {
    if s.isEmpty { return UInt64.random(in: .min ... .max) }
    guard let n = UInt64(s), s.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      throw TextFailure.invalid("Seed must be an unsigned 64-bit decimal integer.")
    }
    return n
  }
  static func words(_ count: Int, rng: inout SampleRandom) -> String {
    (0..<count).map { _ in vocabulary[Int(rng.below(UInt64(vocabulary.count)))] }.joined(
      separator: " ")
  }
  static func process(_ o: LoremOptions) throws -> TextArtifact {
    let max = o.unit == "Words" ? 50000 : o.unit == "Sentences" ? 5000 : 1000
    guard (1...max).contains(o.count), (1...10).contains(o.sentences), (3...30).contains(o.words)
    else { throw TextFailure.invalid("Count or sentence size is outside the supported range.") }
    let seed = try seed(o.seed)
    var rng = SampleRandom(state: seed)
    var first = true
    func sentence(_ count: Int, period: Bool) -> String {
      var values = (0..<count).map { _ in vocabulary[Int(rng.below(UInt64(vocabulary.count)))] }
      if first && o.start {
        for (i, s) in ["lorem", "ipsum"].enumerated() where i < values.count { values[i] = s }
      }
      first = false
      var s = values.joined(separator: " ")
      if let c = s.first { s = String(c).uppercased() + s.dropFirst() }
      return s + (period ? "." : "")
    }
    var parts: [String] = []
    if o.unit == "Words" {
      parts = [sentence(o.count, period: false)]
    } else {
      for i in 0..<o.count {
        try TextBounds.checkpoint(i)
        parts.append(
          (0..<(o.unit == "Paragraphs" ? o.sentences : 1)).map { _ in
            sentence(o.words, period: true)
          }.joined(separator: " "))
      }
    }
    let output = parts.joined(separator: o.unit == "Paragraphs" ? "\n\n" : " ")
    try TextBounds.check(output, max: TextBounds.output)
    return .init(
      output: output, message: "\(o.count) \(o.unit.lowercased())",
      notes: ["Seed: \(seed) · Generator v1 · Sample data only"])
  }
}
enum MockFieldKind: String, CaseIterable, Codable, Sendable {
  case sequence = "Sequence"
  case integer = "Integer"
  case decimal = "Decimal"
  case boolean = "Boolean"
  case uuid = "UUID"
  case date = "Date & Time"
  case enumeration = "Enum"
  case text = "Text"
  case person = "Person Name"
  case email = "Email"
  case url = "URL"
  case ipv4 = "IPv4"
}
struct MockField: Identifiable, Equatable, Codable, Sendable {
  var id = UUID()
  var name: String
  var kind: MockFieldKind
  init(name: String, kind: MockFieldKind) {
    self.name = name
    self.kind = kind
  }
  var minimum = "0", maximum = "100", scale = 2, nullPercent = 0, truePercent = 50, wordCount = 6,
    enumValues = "Alpha\nBeta\nGamma", start = "1", step = "1"
  var dateStart = "2020-01-01T00:00:00Z", dateEnd = "2030-01-01T00:00:00Z", domain = "example.com"
}
struct MockOptions: Equatable, Codable, Sendable {
  var fields: [MockField] = [
    .init(name: "id", kind: .sequence), .init(name: "name", kind: .person),
    .init(name: "email", kind: .email), .init(name: "active", kind: .boolean),
  ]
  var count = 100, seed = "", format = "JSON", nullText = false, spreadsheetSafe = false
}
enum MockValue: Sendable {
  case string(String)
  case number(String)
  case boolean(Bool)
  case null
  var text: String {
    switch self {
    case .string(let s), .number(let s): s
    case .boolean(let b): b ? "true" : "false"
    case .null: "null"
    }
  }
  var isString: Bool {
    if case .string = self { return true }
    return false
  }
}
struct MockDataset: Sendable {
  let fields: [String], rows: [[MockValue]], seed: UInt64
  func serialize(format: String, nullText: Bool = false, spreadsheetSafe: Bool = false) throws
    -> String
  {
    var out = ""
    var size = 0
    func add(_ s: String) throws {
      size += s.utf16.count
      guard size <= TextBounds.output else {
        throw TextFailure.resource(
          "Serialized output exceeds 1,048,576 UTF-16 units. Choose another format or reduce rows.")
      }
      out += s
    }
    if format == "JSON" {
      try add("[")
      for (i, row) in rows.enumerated() {
        try TextBounds.checkpoint(i)
        try add(i == 0 ? "\n" : " ,\n")
        try add("  {\n")
        for (j, v) in row.enumerated() {
          try add(j == 0 ? "" : " ,\n")
          try add(
            "    " + Self.quote(fields[j]) + ": " + (v.isString ? Self.quote(v.text) : v.text))
        }
        try add("\n  }")
      }
      try add(rows.isEmpty ? "]" : "\n]")
    } else {
      let separator = format == "TSV" ? "\t" : ","
      func cell(_ text: String, string: Bool) -> String {
        var s = text
        if spreadsheetSafe && string, let first = s.first, "=+-@\t\r".contains(first) {
          s = "'" + s
        }
        if s.contains(separator) || s.contains("\"") || s.contains("\r") || s.contains("\n") {
          s = "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
      }
      try add(fields.map { cell($0, string: true) }.joined(separator: separator) + "\r\n")
      for (i, row) in rows.enumerated() {
        try TextBounds.checkpoint(i)
        try add(
          row.map { v in
            if case .null = v { return nullText ? "null" : "" }
            return cell(v.text, string: v.isString)
          }.joined(separator: separator) + "\r\n")
      }
    }
    return out
  }
  static func quote(_ text: String) -> String {
    var out = "\""
    for s in text.unicodeScalars {
      switch s.value {
      case 34: out += "\\\""
      case 92: out += "\\\\"
      case 0..<32: out += String(format: "\\u%04x", s.value)
      default: out.unicodeScalars.append(s)
      }
    }
    return out + "\""
  }
}
enum MockDataProcessor {
  static func generate(_ o: MockOptions) throws -> MockDataset {
    guard (0...10000).contains(o.count), (1...32).contains(o.fields.count) else {
      throw TextFailure.invalid("Use 0–10,000 rows and 1–32 fields.")
    }
    var names = Set<Data>()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    struct Prepared {
      let field: MockField
      var min: Int64 = 0, max: Int64 = 100, start: Int64 = 1, step: Int64 = 1, values: [String] = []
    }
    let prepared = try o.fields.map { f throws -> Prepared in
      guard !f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        names.insert(Data(f.name.utf8)).inserted, f.name.utf16.count <= 256
      else {
        throw TextFailure.invalid(
          "Field names must be nonempty, unique and at most 256 UTF-16 units.")
      }
      guard (0...100).contains(f.nullPercent), (0...100).contains(f.truePercent),
        (0...6).contains(f.scale), (1...100).contains(f.wordCount)
      else { throw TextFailure.invalid("Invalid field parameters.") }
      var p = Prepared(field: f)
      if f.kind == .integer || f.kind == .decimal {
        guard let a = Int64(f.minimum), let b = Int64(f.maximum), a <= b else {
          throw TextFailure.invalid("Integer/scaled decimal bounds must be ordered Int64 values.")
        }
        p.min = a
        p.max = b
      }
      if f.kind == .sequence {
        guard let a = Int64(f.start), let b = Int64(f.step) else {
          throw TextFailure.invalid("Sequence start/step must be Int64.")
        }
        p.start = a
        p.step = b
        let mul = b.multipliedReportingOverflow(by: Int64(max(0, o.count - 1)))
        guard !mul.overflow && !a.addingReportingOverflow(mul.partialValue).overflow else {
          throw TextFailure.invalid("Sequence overflows Int64.")
        }
      }
      if f.kind == .enumeration {
        p.values = TextSnapshot(f.enumValues).lines.map { TextSnapshot(f.enumValues).text($0) }
        guard (1...100).contains(p.values.count), p.values.allSatisfy({ !$0.isEmpty }),
          Set(p.values.map { Data($0.utf8) }).count == p.values.count
        else { throw TextFailure.invalid("Enum needs 1–100 distinct, nonempty lines.") }
      }
      if f.kind == .date {
        guard let a = formatter.date(from: f.dateStart), let b = formatter.date(from: f.dateEnd),
          a <= b, a.timeIntervalSince1970 >= 0, b.timeIntervalSince1970 < 253_402_300_800
        else { throw TextFailure.invalid("Use ordered UTC dates from 1970 through 9999.") }
        p.min = Int64(a.timeIntervalSince1970)
        p.max = Int64(b.timeIntervalSince1970)
      }
      if f.kind == .email && !["example.com", "example.net", "example.org"].contains(f.domain) {
        throw TextFailure.invalid("Use an example.com/.net/.org domain.")
      }
      return p
    }
    let seed = try LoremProcessor.seed(o.seed)
    var rng = SampleRandom(state: seed)
    var rows: [[MockValue]] = []
    var total = 0
    for i in 0..<o.count {
      try TextBounds.checkpoint(i)
      var row: [MockValue] = []
      for p in prepared {
        let f = p.field
        let isNull = Int(rng.below(100)) < f.nullPercent && f.kind != .sequence
        let v: MockValue
        if isNull {
          v = .null
        } else {
          switch f.kind {
          case .sequence: v = .number(String(p.start + Int64(i) * p.step))
          case .integer: v = .number(String(rng.integer(p.min, p.max)))
          case .decimal:
            let n = rng.integer(p.min, p.max)
            var digits = String(n.magnitude)
            if f.scale > 0 {
              digits = String(repeating: "0", count: max(0, f.scale + 1 - digits.count)) + digits
              digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -f.scale))
            }
            v = .number((n < 0 ? "-" : "") + digits)
          case .boolean: v = .boolean(Int(rng.below(100)) < f.truePercent)
          case .uuid:
            var bytes = (0..<16).map { _ in UInt8(rng.below(256)) }
            bytes[6] = (bytes[6] & 15) | 64
            bytes[8] = (bytes[8] & 63) | 128
            let hex = bytes.enumerated().map { i, b in
              ([4, 6, 8, 10].contains(i) ? "-" : "") + String(format: "%02x", b)
            }.joined()
            v = .string(hex)
          case .date:
            v = .string(
              formatter.string(from: Date(timeIntervalSince1970: Double(rng.integer(p.min, p.max))))
            )
          case .enumeration: v = .string(p.values[Int(rng.below(UInt64(p.values.count)))])
          case .text: v = .string(LoremProcessor.words(f.wordCount, rng: &rng))
          case .person:
            let a = ["Alex", "Morgan", "Sam", "Taylor", "Robin", "Casey"]
            let b = ["Vale", "Brook", "Reed", "Lane", "Stone", "Lake"]
            v = .string(a[Int(rng.below(6))] + " " + b[Int(rng.below(6))])
          case .email: v = .string("user" + String(format: "%016llx", rng.next()) + "@" + f.domain)
          case .url:
            v = .string("https://example.com/items/" + String(format: "%016llx", rng.next()))
          case .ipv4:
            v = .string(
              ["192.0.2.", "198.51.100.", "203.0.113."][Int(rng.below(3))]
                + String(rng.below(254) + 1))
          }
        }
        total += v.text.utf16.count
        guard total <= TextBounds.output else {
          throw TextFailure.resource(
            "Generated value content limit reached; reduce rows or field sizes.")
        }
        row.append(v)
      }
      rows.append(row)
    }
    return .init(fields: o.fields.map(\.name), rows: rows, seed: seed)
  }
}
