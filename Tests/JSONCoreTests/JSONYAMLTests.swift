import Foundation
import Testing
@testable import JSONCore

struct JSONYAMLTests {
    private func convert(_ source: String, _ direction: JSONYAMLDirection = .yamlToJSON) -> JSONYAMLResult { JSONYAMLConverter.process(source, direction: direction) }
    private func scalar(_ yaml: String) throws -> String {
        let result = convert(yaml)
        #expect(result.status == .success, "\(yaml): \(result.diagnostics)")
        return try #require(result.output)
    }
    @Test func losslessJSONValuesRoundTrip() throws {
        for source in [#"{"n":90071992547409931234567890,"minus":-0,"exponent":1.234567890123456789e+1000,"s":"yes","quoted":"001","nil":null,"empty":{},"array":[],"b":true}"#,
            ##"{"emoji":"\uD83D\uDE00","controls":"\u0000\n\t\u0085\u2028\u2029","e\u0301":"é","é":"different","punctuation":"# : [] {} & * !"}"##,
            #"[1,"true",false,null,[{}],{"a":[1,2]}]"#, "42", "-0", "1e10000", #""root""#, "null", "true", "{}", "[]"] {
            let yaml = convert(source, .jsonToYAML)
            #expect(yaml.status == .success)
            let back = convert(try #require(yaml.output))
            #expect(back.status == .success)
            let before = try #require(JSONProcessor.inspectStructure(source).document)
            let backSource = try #require(back.output)
            let after = try #require(JSONProcessor.inspectStructure(backSource).document)
            #expect(before.nodes.count == after.nodes.count)
            for (a,b) in zip(before.nodes, after.nodes) {
                #expect(a.kind == b.kind && a.children == b.children)
                #expect(a.scalar?.unicodeScalars.elementsEqual(b.scalar?.unicodeScalars ?? "".unicodeScalars) ?? (b.scalar == nil))
                #expect(a.key?.unicodeScalars.elementsEqual(b.key?.unicodeScalars ?? "".unicodeScalars) ?? (b.key == nil))
            }
        }
    }
    @Test func coreTypesAndExactNumbers() throws {
        for (yaml, expected) in [("yes", #""yes""#), ("off", #""off""#), ("2026-10-18", #""2026-10-18""#),
            ("true", "true"), ("FALSE", "false"), ("Null", "null"), ("~", "null"), ("-0", "-0"),
            ("+000123", "123"), (".5", "0.5"), ("-.5", "-0.5"), ("1.", "1.0"), ("1.e+1234", "1.0e+1234"),
            ("0xFFFFFFFFFFFFFFFFFFFFFFFF", "79228162514264337593543950335"), ("0o777", "511"),
            ("900719925474099300000000000", "900719925474099300000000000"), ("!!str 123", #""123""#),
            ("'null'", #""null""#), ("!!float 1", "1"), ("! true", #""true""#)] {
            #expect(try scalar(yaml) == expected)
        }
    }
    @Test func aliasesBlockScalarsAndMappingOrder() throws {
        let source = "first: &a {x: 1}\nsecond: *a\nmultiline: |\n  hello\n  world\nfolded: >-\n  one\n  two\n"
        let result = convert(source)
        let resultSource = try #require(result.output)
        let doc = try #require(JSONProcessor.inspectStructure(resultSource).document)
        #expect(doc.nodes[0].children.map { doc.nodes[$0].key! } == ["first", "second", "multiline", "folded"])
        #expect(doc.nodes.first { $0.key == "multiline" }?.scalar == "hello\nworld\n")
        #expect(doc.nodes.first { $0.key == "folded" }?.scalar == "one two")
        #expect(doc.nodes.filter { $0.key == "x" }.count == 2)
        #expect(try scalar("---\n...") == "null")
        #expect(try scalar("%YAML 1.2\n---\nyes") == #""yes""#)
        let merged = convert("base: &base {a: 1}\nother: {<<: *base}")
        #expect(merged.status == .success && merged.diagnostics.first?.severity == .warning)
        #expect(merged.output?.contains("\"<<\"") == true)
        #expect(convert("'<<': 1").diagnostics.isEmpty)
        #expect(convert("'<<': 1").status == .success) // Core schema doesn't invent merge semantics.
    }
    @Test func unsupportedAndInvalidConstructsAreExplicit() {
        for source in ["a: 1\na: 2", "1: value", "true: value", "? [a,b]\n: c", "!!timestamp 2026-10-18", ".nan", ".inf", "-.Inf",
            "---\na: 1\n---\nb: 2", "a: &a [*a]", "!!set {a: null}", "%YAML 1.1\n---\nyes"] {
            let result = convert(source)
            #expect(result.status == .unsupported, "\(source): \(result.status)")
            #expect(result.output == nil && !result.diagnostics.isEmpty)
        }
        for source in ["a: [1,", "a: \"unterminated", "a: *unknown", "\tkey: 1", "!!bool yes", "!!int 1.2", "!!float 0xFF", "!!float nope", #""\uD800""#] {
            let result = convert(source)
            #expect(result.status == .invalid, "\(source): \(result.status)")
            #expect(result.output == nil && !result.diagnostics.isEmpty)
        }
        #expect(convert(#"{"a":1,"\u0061":2}"#, .jsonToYAML).status == .unsupported)
        #expect(convert("a: 1\n'\\u0061': 2").status == .success)
        #expect(convert("é: 1\né: 2").status == .success) // scalar distinct
        #expect(convert("a: 1\n\"\\u0061\": 2").status == .unsupported)
    }
    @Test func anchorsUseUTF16IncludingEmojiCRLFAndEOF() throws {
        let source = "emoji: 😀\r\ncombining: é\r\nbad: [1,"
        let issue = try #require(convert(source).diagnostics.first)
        #expect(issue.range.location == source.utf16.count && issue.range.length == 0)
        #expect(issue.line == 3 && issue.column == 9)
        let controls = "emoji: 😀\r\nbad: \u{0001}"
        let controlIssue = try #require(convert(controls).diagnostics.first)
        #expect(controlIssue.range.location == controls.utf16.count - 1 && controlIssue.range.length == 1)
        #expect(controlIssue.line == 2 && controlIssue.column == 6)
        let keySource = "emoji: 😀\r\n1: bad"
        let keyIssue = try #require(convert(keySource).diagnostics.first)
        #expect(keyIssue.range.location == (keySource as NSString).range(of: "1:").location)
        #expect(keyIssue.line == 2 && keyIssue.column == 1)
    }
    @Test func inputDepthExpansionAndOutputLimits() throws {
        #expect(convert(String(repeating: "x", count: JSONProcessor.maximumUTF16Length + 1)).status == .resourceLimit)
        #expect(convert(String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)).status == .success)
        #expect(convert(String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)).status == .resourceLimit)
        let bomb = "a0: &a0 [0,0]\n" + (1..<23).map { "a\($0): &a\($0) [*a\($0-1),*a\($0-1)]" }.joined(separator: "\n")
        let expanded = convert(bomb)
        #expect(expanded.status == .resourceLimit && expanded.output == nil)
        #expect(convert("0x" + String(repeating: "f", count: 4097)).status == .resourceLimit)
        let full = "[" + Array(repeating: "0", count: 131_071).joined(separator: ",") + "]"
        #expect(full.utf16.count == 262_143)
        #expect(convert(full, .jsonToYAML).status == .resourceLimit) // bounded output inflation
        #expect(convert(" ").status == .invalid)
    }
    @Test func cancellationAndCheckDoNotPublishPartialOutput() async {
        let result = JSONYAMLConverter.process("key: value", direction: .yamlToJSON, produceOutput: false)
        #expect(result.status == .success && result.output == nil)
        let task = Task.detached { () -> JSONYAMLResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return JSONYAMLConverter.process("key: value", direction: .yamlToJSON)
        }
        #expect(await task.value.status == .cancelled)
    }
}

@MainActor struct JSONYAMLWorkspaceTests {
    @Test func revisionsPasteValidationOutputAndPrivacy() async throws {
        let suite = "JSONYAMLTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = JSONPreferencesRepository(defaults: defaults)
        let model = JSONYAMLWorkspaceSession(repository: repository)
        model.input = #"{"name":"é"}"#
        #expect(model.result == nil)
        await model.didPaste()?.value
        #expect(model.result?.status == .success && model.output == nil)
        await model.run().value
        let output = try #require(model.output)
        await model.run(convert: false).value
        #expect(model.output == output)
        let task = model.run(); model.cancel(); await task.value
        #expect(model.wasCancelled && model.output == output)
        model.input = #"{"name":"é"}"#
        #expect(model.output == nil && model.result == nil)
        let stale = model.run(); model.direction = .yamlToJSON
        await stale.value
        #expect(model.output == nil && model.result == nil && !model.busy)
        model.input = "key: value"; await model.run().value
        #expect(model.output != nil)
        model.preferences.wordWrap = false
        #expect(model.output != nil) // presentation changes keep current result
        model.preferences.indentation = .four
        #expect(model.output == nil)
        await model.run().value
        #expect(model.output?.contains("    \"key\"") == true)
        model.preferences.validateOnPaste = false
        model.input = "["; #expect(model.didPaste() == nil)
        #expect(model.result == nil)
        let fresh = JSONYAMLWorkspaceSession(repository: repository)
        #expect(fresh.input.isEmpty && fresh.output == nil && fresh.result == nil)
        #expect(!fresh.preferences.wordWrap && !fresh.preferences.validateOnPaste)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox") } == [JSONPreferencesRepository.key])
    }
}
