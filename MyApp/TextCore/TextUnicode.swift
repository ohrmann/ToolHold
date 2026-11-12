import Foundation

struct TextUnicodeTable: Decodable, Sendable {
  struct RangeValue: Decodable, Sendable {
    let low: UInt32, high: UInt32, value: String
    init(from decoder: Decoder) throws {
      var c = try decoder.unkeyedContainer()
      low = try c.decode(UInt32.self)
      high = try c.decode(UInt32.self)
      value = try c.decode(String.self)
    }
  }
  struct CharacterRange: Decodable, Sendable {
    let low: UInt32, high: UInt32, name: String, category: String, bidi: String
    init(from decoder: Decoder) throws {
      var c = try decoder.unkeyedContainer()
      low = try c.decode(UInt32.self)
      high = try c.decode(UInt32.self)
      name = try c.decode(String.self)
      category = try c.decode(String.self)
      bidi = try c.decode(String.self)
    }
  }
  let version: String, fold: [String: String], confusables: [String: String],
    characters: [String: [String]], characterRanges: [CharacterRange], scripts: [RangeValue],
    scriptExtensions: [RangeValue], properties: [RangeValue]
  static let shared: TextUnicodeTable? = {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle.main
    #endif
    guard let url = bundle.url(forResource: "text-unicode17", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(TextUnicodeTable.self, from: data)
  }()
  func foldText(_ source: String) -> String {
    var out = ""
    for s in source.unicodeScalars {
      if let mapping = fold[String(format: "%04X", s.value)] {
        out += Self.decode(mapping)
      } else {
        out.unicodeScalars.append(s)
      }
    }
    return out
  }
  static func decode(_ s: String) -> String {
    String(
      String.UnicodeScalarView(
        s.split(separator: " ").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }))
  }
  func script(_ value: UInt32) -> String {
    var lo = 0
    var hi = scripts.count
    while lo < hi {
      let m = (lo + hi) / 2
      if scripts[m].high < value { lo = m + 1 } else { hi = m }
    }
    return lo < scripts.count && scripts[lo].low <= value ? scripts[lo].value : "Unknown"
  }
  func info(_ scalar: Unicode.Scalar) -> [String] {
    if let c = characters[String(scalar.value)] { return c }
    if let r = characterRanges.first(where: { $0.low <= scalar.value && scalar.value <= $0.high }) {
      return [
        scalar.properties.name.map { $0 + " (system name)" }
          ?? (r.name + " range · " + String(format: "U+%04X", scalar.value)), r.category, r.bidi,
      ]
    }
    return ["Unknown in Unicode 17 dataset", "Cn", "Unknown"]
  }
  func has(_ property: String, _ value: UInt32) -> Bool {
    properties.contains { $0.value == property && $0.low <= value && value <= $0.high }
  }
}
struct TextComparisonOptions: Codable, Equatable, Sendable {
  var ignoreCase = false, trim = false, ignoreSpaces = false
  func key(_ s: String) throws -> Data {
    var text = trim ? s.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) : s
    if ignoreSpaces {
      text = String(text.unicodeScalars.filter { $0.value != 32 && $0.value != 9 })
    }
    if ignoreCase {
      guard let t = TextUnicodeTable.shared else {
        throw TextFailure.invalid("Unicode comparison data is unavailable.")
      }
      text = t.foldText(text)
    }
    guard text.utf16.count <= TextBounds.input * 4 else {
      throw TextFailure.resource("Comparison key limit reached.")
    }
    return Data(text.utf8)
  }
}
enum TextUnicodeInspector {
  static func displayScalar(_ s: Unicode.Scalar, name: String) -> String {
    let names: [UInt32: String] = [
      32: "SPACE", 9: "TAB", 10: "LF", 13: "CR", 0xA0: "NBSP", 0x200B: "ZWSP", 0xFEFF: "BOM",
      0x200C: "ZWNJ", 0x200D: "ZWJ",
    ]
    if let label = names[s.value] { return "⟨" + label + "⟩" }
    if (0xFE00...0xFE0F).contains(s.value) || (0xE0100...0xE01EF).contains(s.value)
      || s.properties.generalCategory == .control || s.properties.generalCategory == .format
    {
      return "⟨" + name + "⟩"
    }
    if s.properties.generalCategory == .nonspacingMark
      || s.properties.generalCategory == .enclosingMark
    {
      return "◌" + String(s)
    }
    return String(s)
  }

  static func inspect(_ source: String, filter: String = "All", normalization: String = "Original")
    throws -> TextArtifact
  {
    try TextBounds.check(source)
    guard let table = TextUnicodeTable.shared else {
      throw TextFailure.invalid("Unicode data is unavailable.")
    }
    var rows: [TextRow] = []
    var offset = 0
    var grapheme = 0
    var controls = 0
    var scripts: Set<String> = []
    struct Facts {
      let label: String, value: String, detail: String, script: String, invisible: Bool,
        confusable: Bool
    }
    var cache: [UInt32: Facts] = [:]
    func facts(_ scalar: Unicode.Scalar) -> Facts {
      if let known = cache[scalar.value] { return known }
      let info = table.info(scalar)
      let script = table.script(scalar.value)
      let text = String(scalar)
      let invisible =
        info[1] == "Cc" || info[1] == "Cf"
        || table.has("Default_Ignorable_Code_Point", scalar.value)
        || table.has("White_Space", scalar.value)
      let mapping = table.confusables[String(format: "%04X", scalar.value)]
      let bytes = text.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
      let units = text.utf16.map { String(format: "%04X", $0) }.joined(separator: " ")
      var detail =
        "\(info[0]) · \(info[1]) · \(script) · bidi \(info[2])\nUTF-8: \(bytes) · UTF-16: \(units)"
      if let ext = table.scriptExtensions.first(where: {
        $0.low <= scalar.value && scalar.value <= $0.high
      }) {
        detail += "\nScript extensions: \(ext.value)"
      }
      if let mapping {
        detail +=
          "\nPossible visual resemblance: \(TextDisplay.safe(TextUnicodeTable.decode(mapping))) (\(mapping)) — not a safety verdict"
      }
      let f = Facts(
        label: String(format: "U+%04X", scalar.value), value: displayScalar(scalar, name: info[0]),
        detail: detail, script: script, invisible: invisible, confusable: mapping != nil)
      cache[scalar.value] = f
      return f
    }
    var scalarIndex = 0
    for ch in source {
      grapheme += 1
      let preview = TextDisplay.safe(String(ch))
      for scalar in ch.unicodeScalars {
        try TextBounds.checkpoint(scalarIndex)
        scalarIndex += 1
        let n = scalar.utf16.count
        let f = facts(scalar)
        if f.script != "Common" && f.script != "Inherited" && f.script != "Unknown" {
          scripts.insert(f.script)
        }
        if f.invisible { controls += 1 }
        if filter == "All" || (filter == "Invisible & controls" && f.invisible)
          || (filter == "Non-ASCII" && scalar.value > 127)
          || (filter == "Confusable hints" && f.confusable)
        {
          let detail = f.detail + "\nOffset \(offset) · Grapheme \(grapheme)\nGrapheme: \(preview)"
          rows.append(
            .init(
              id: offset, label: f.label, value: f.value, detail: detail,
              left: .init(location: offset, length: n)))
        }
        offset += n
      }
    }
    let output: String
    switch normalization {
    case "NFC": output = source.precomposedStringWithCanonicalMapping
    case "NFD": output = source.decomposedStringWithCanonicalMapping
    case "NFKC": output = source.precomposedStringWithCompatibilityMapping
    case "NFKD": output = source.decomposedStringWithCompatibilityMapping
    default: output = source
    }
    try TextBounds.check(output, max: TextBounds.output)
    var notes = [
      "Properties: Unicode 17. Normalization/graphemes: system Unicode. Confusable hints do not establish safety."
    ]
    if scripts.count > 1 {
      notes.append(
        "Multiple scripts: \(scripts.sorted().joined(separator:", ")). This can be legitimate.")
    }
    if normalization != "Original" {
      notes.append(
        "Preview: \(output.unicodeScalars.count) scalars · \(output.utf8.count) UTF-8 bytes · \(output.utf16.count) UTF-16 units"
      )
      if normalization.hasPrefix("NFK") {
        notes.append("Compatibility normalization can change meaning. Input remains unchanged.")
      }
      notes.append(
        output.utf16.elementsEqual(source.utf16)
          ? "Normalization unchanged." : "Normalized preview differs. Input remains unchanged.")
    }
    return .init(
      output: output,
      message:
        "\(source.unicodeScalars.count) scalars · \(grapheme) graphemes · \(controls) whitespace/invisible",
      notes: notes, rows: rows)
  }
}
