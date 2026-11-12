import Foundation
import Testing

@testable import TextCore

@Suite struct TextProcessorsTests {
  @Test func recordsAndCoordinates() {
    #expect(TextSnapshot("").lines.isEmpty)
    let s = TextSnapshot("😀\r\na\n\n")
    #expect(s.lines.count == 3)
    #expect(s.lines[0].range == NSRange(location: 0, length: 2))
    #expect(s.lines[0].ending == "\r\n")
    #expect(s.location(4).0 == 2)
    #expect(s.location(7).0 == 4)
    #expect(TextSnapshot("x\u{2028}y").lines.count == 1)
  }
  @Test func exactAndFoldedKeys() throws {
    var o = TextComparisonOptions()
    #expect(try o.key("é") != o.key("e\u{301}"))
    o.ignoreCase = true
    #expect(try o.key("Straße") == o.key("STRASSE"))
    #expect(try o.key("é") != o.key("e\u{301}"))
    o.trim = true
    o.ignoreSpaces = true
    #expect(try o.key(" a\t ") == o.key("a"))
    #expect(try o.key("\u{A0}a") != o.key("a"))
  }
  @Test func multisetContracts() throws {
    var o = ListComparisonOptions()
    o.multiset = true
    let a = "a\na\nb\n"
    let b = "a\nc\nc\n"
    #expect(try ListComparisonProcessor.process(a, b, options: o).output == "a")
    o.operation = "A only"
    #expect(try ListComparisonProcessor.process(a, b, options: o).output == "a\nb")
    o.operation = "B only"
    #expect(try ListComparisonProcessor.process(a, b, options: o).output == "c\nc")
    o.operation = "Union"
    #expect(try ListComparisonProcessor.process(a, b, options: o).output == "a\na\nb\nc\nc")
    o.operation = "Symmetric difference"
    #expect(try ListComparisonProcessor.process(a, b, options: o).output == "a\nb\nc\nc")
    o.multiset = false
    o.operation = "Union"
    #expect(try ListComparisonProcessor.process(a, b, options: o).output == "a\nb\nc")
    #expect(try ListComparisonProcessor.process("\n", "", options: o).output == "\n")
  }
  @Test func sortStableAndExact() throws {
    var o = LineSortOptions()
    o.order = "Natural numeric"
    o.operation = "Sort"
    #expect(
      try LineSortProcessor.process("x10\nx2\nx02\nx1\n", options: o).output == "x1\nx2\nx02\nx10\n"
    )
    o.operation = "Deduplicate"
    o.comparison.ignoreCase = true
    o.last = true
    #expect(try LineSortProcessor.process("A\nb\na", options: o).output == "b\na")
    o.comparison.ignoreCase = false
    #expect(try LineSortProcessor.process("é\ne\u{301}", options: o).output == "é\ne\u{301}")
    #expect(try LineSortProcessor.process("b\r\na\n", options: .init()).notes.count == 1)
  }
  @Test func caseBoundaries() throws {
    var o = TextCaseOptions()
    #expect(try TextCaseProcessor.process("HTTPServer2ID", options: o).output == "httpServer2Id")
    o.mode = "snake_case"
    #expect(
      try TextCaseProcessor.process("userID\r\nJSONParser", options: o).output
        == "user_id\r\njson_parser")
    o.mode = "UPPERCASE"
    #expect(try TextCaseProcessor.process("straße  x", options: o).output == "STRASSE  X")
  }
  @Test func unicodeAndStatistics() throws {
    let s = "A😀e\u{301}\t\u{202E}\r\n"
    let u = try TextUnicodeInspector.inspect(s)
    #expect(u.rows.count == 8)
    #expect(u.rows[1].left == NSRange(location: 1, length: 2))
    #expect(u.rows.contains { $0.label == "U+202E" && $0.detail.contains("bidi") })
    #expect(
      try TextUnicodeInspector.inspect("e\u{301}", normalization: "NFC").output?.unicodeScalars
        .count == 1)
    let stats = try TextStatisticsProcessor.process("😀\r\n")
    #expect(stats.rows.first { $0.label == "UTF-16 code units" }?.value == "4")
    #expect(stats.rows.first { $0.label == "Line records" }?.value == "1")
    #expect(stats.rows.first { $0.label == "Logical editor lines" }?.value == "2")
    #expect(
      try TextStatisticsProcessor.process("").rows.first { $0.label == "Logical editor lines" }?
        .value == "0")
  }
  @Test func loremReproducibility() throws {
    var o = LoremOptions()
    o.unit = "Words"
    o.count = 13
    o.seed = "42"
    let a = try LoremProcessor.process(o)
    let b = try LoremProcessor.process(o)
    #expect(a.output == b.output)
    #expect(a.output?.split(separator: " ").count == 13)
    #expect(a.output?.hasPrefix("Lorem ipsum") == true)
    o.count = 50001
    #expect(throws: TextFailure.self) { try LoremProcessor.process(o) }
  }
  @Test func mockTypesAndSerialization() throws {
    var o = MockOptions()
    o.seed = "99"
    o.count = 5
    o.fields = MockFieldKind.allCases.enumerated().map {
      .init(name: "f\($0.offset)", kind: $0.element)
    }
    let a = try MockDataProcessor.generate(o)
    let b = try MockDataProcessor.generate(o)
    #expect(try a.serialize(format: "JSON") == b.serialize(format: "JSON"))
    let parsed =
      try JSONSerialization.jsonObject(with: Data(a.serialize(format: "JSON").utf8))
      as? [[String: Any]]
    #expect(parsed?.count == 5)
    #expect(a.rows[0].count == 12)
    #expect(
      a.rows[0][6].text == "Alpha" || a.rows[0][6].text == "Beta" || a.rows[0][6].text == "Gamma")
    let dataset = MockDataset(
      fields: ["a", "b"],
      rows: [[.string("=SUM(A1)"), .string("x,\"y\n")], [.null, .number("-0.00")]], seed: 0)
    #expect(try dataset.serialize(format: "CSV").contains("\"x,\"\"y\n\""))
    #expect(try dataset.serialize(format: "CSV", spreadsheetSafe: true).contains("'=SUM"))
    #expect(try dataset.serialize(format: "JSON").contains("-0.00"))
    o.fields = [.init(name: "a", kind: .integer), .init(name: "a", kind: .text)]
    #expect(throws: TextFailure.self) { try MockDataProcessor.generate(o) }
  }
  @Test func exactIntegerAndScaledDecimal() throws {
    var o = MockOptions()
    o.count = 1
    o.seed = "1"
    var f = MockField(name: "x", kind: .integer)
    f.minimum = String(Int64.min)
    f.maximum = f.minimum
    o.fields = [f]
    #expect(try MockDataProcessor.generate(o).rows[0][0].text == String(Int64.min))
    f.kind = .decimal
    f.scale = 6
    o.fields = [f]
    #expect(try MockDataProcessor.generate(o).rows[0][0].text == "-9223372036854.775808")
  }
  @Test func previewBoundsAndLimits() throws {
    #expect(TextDisplay.safe("a" + String(repeating: "\u{301}", count: 2000)) == "…")
    #expect(!TextDisplay.safe("\u{202E}").contains("\u{202E}"))
    #expect(throws: TextFailure.self) {
      try TextCaseProcessor.process(String(repeating: "a", count: 262145), options: .init())
    }
  }
}

@Suite struct TextDiffTests {
  @Test func exactUnicodeAndEndings() throws {
    let d = try #require(TextDiffProcessor.process("é\r\n", "e\u{301}\n", options: .init()).diff)
    #expect(d.changed.count == 1)
    #expect(d.exact)
    #expect(try d.patch().contains("-é\r\n"))
    var o = TextDiffOptions()
    o.ignoreEndings = true
    #expect(try TextDiffProcessor.process("a\r\n", "a\n", options: o).diff?.changed.isEmpty == true)
    #expect(throws: TextFailure.self) {
      try TextDiffProcessor.process("a", "b", options: o).diff!.patch()
    }
  }
  @Test func reconstructRandomDocuments() throws {
    var rng = SampleRandom(state: 187)
    for _ in 0..<300 {
      let a = (0..<Int(rng.below(35))).map { _ in String(rng.below(8)) }.joined(separator: "\n")
      let b = (0..<Int(rng.below(35))).map { _ in String(rng.below(8)) }.joined(separator: "\n")
      let r = try #require(TextDiffProcessor.process(a, b, options: .init()).diff)
      #expect(r.rows.compactMap(\.left) == Array(r.before.lines.indices))
      #expect(r.rows.compactMap(\.right) == Array(r.after.lines.indices))
      for row in r.rows where row.kind == "Equal" {
        #expect(r.before.text(r.before.lines[row.left!]) == r.after.text(r.after.lines[row.right!]))
      }
    }
  }
  @Test func boundedCoarseAndEmpty() throws {
    let e = TextDiffProcessor.Engine([Data([1]), Data([2])], [Data([3]), Data([4])], maximum: 0)
    try e.run(0..<2, 0..<2)
    #expect(e.limited)
    #expect(e.edits.count == 4)
    #expect(try TextDiffProcessor.process("", "", options: .init()).diff?.rows.isEmpty == true)
    #expect(
      try TextDiffProcessor.process("", "abc", options: .init()).diff?.patch().contains(
        "@@ -0,0 +1,1 @@") == true)
  }
}

@Suite struct TextFileTests {
  @Test func remoteURLCannotAliasLocalPath() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("synthetic local fixture".utf8).write(to: url)
    var remote = URLComponents()
    remote.scheme = "https"
    remote.host = "example.invalid"
    remote.path = url.path
    #expect(throws: TextFailure.self) { try TextFileIO.read(try #require(remote.url)) }
    #expect(try TextFileIO.read(url) == "synthetic local fixture")
  }

  @Test func boundedStrictUTF8AndBOM() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data([0xff, 0xfe, 0x61, 0]).write(to: url)
    #expect(throws: TextFailure.self) { try TextFileIO.read(url) }
    try Data("\u{FEFF}hello😀".utf8).write(to: url)
    #expect(try TextFileIO.read(url).utf16.elementsEqual("\u{FEFF}hello😀".utf16))
    try Data(repeating: 65, count: 1_048_577).write(to: url)
    #expect(throws: TextFailure.self) { try TextFileIO.read(url) }
  }
}

extension TextDiffTests {
  @Test func unbalancedAndPatchRoundTrip() throws {
    let pairs = [
      ("one", String(repeating: "other\n", count: 1000)), ("", "\n"), ("a\r\nb\r\n", "a\r\nx\r\n"),
      ("é\nlast", "e\u{301}\nlast\n"),
    ]
    for (a, b) in pairs {
      let r = try #require(TextDiffProcessor.process(a, b, options: .init()).diff)
      #expect(r.rows.compactMap(\.left) == Array(r.before.lines.indices))
      #expect(r.rows.compactMap(\.right) == Array(r.after.lines.indices))
      #if os(macOS)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
          UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("before")
        let patch = folder.appendingPathComponent("change.patch")
        try Data(a.utf8).write(to: file)
        try Data(r.patch().utf8).write(to: patch)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/patch")
        process.arguments = ["-s", file.path, patch.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try Data(contentsOf: file) == Data(b.utf8))
      #endif
    }
  }
}
