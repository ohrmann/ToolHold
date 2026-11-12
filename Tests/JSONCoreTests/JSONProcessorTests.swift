import Foundation
import Testing
@testable import JSONCore

struct JSONProcessorTests {
    @Test(arguments: ["{}", "[]", "null", "123", "true", "false", #""hello""#, #"{"a":[1,{"b":false},null]}"#])
    func validRoots(_ input: String) {
        #expect(JSONProcessor.process(input, operation: .validate).isValid)
        #expect(JSONProcessor.inspectStructure(input).document != nil)
    }

    @Test func formattingAndMinification() {
        let source = #" { "a" : [1, {"b":true}], "empty": {} } "#
        let pretty = JSONProcessor.process(source, operation: .format)
        #expect(pretty.output == "{\n  \"a\": [\n    1,\n    {\n      \"b\": true\n    }\n  ],\n  \"empty\": {}\n}")
        #expect(JSONProcessor.process(pretty.output!, operation: .minify).output == #"{"a":[1,{"b":true}],"empty":{}}"#)
        #expect(JSONProcessor.process(pretty.output!, operation: .format).output == pretty.output)
    }

    @Test(arguments: JSONIndentation.allCases)
    func indentationPreservesLexemes(_ indentation: JSONIndentation) {
        let source = #"{"a":[9007199254740993,1.2300,1e999999,"\u0061"],"a":-0}"#
        let pretty = JSONProcessor.process(source, operation: .format, indentation: indentation)
        #expect(pretty.output?.contains("\n" + indentation.spaces + "\"a\": [") == true)
        #expect(pretty.output?.contains("\n" + indentation.spaces + indentation.spaces + "9007199254740993") == true)
        #expect(JSONProcessor.process(pretty.output!, operation: .minify, indentation: indentation).output == source)
        #expect(JSONProcessor.process(pretty.output!, operation: .format, indentation: indentation).output == pretty.output)
        #expect(pretty.diagnostics.first?.code == "JSON-010")
    }

    @Test func numericLexemesRemainExact() {
        let source = #"[9007199254740993,123456789012345678901234567890,-0,1.2300,1e999999,1E-99999]"#
        let pretty = JSONProcessor.process(source, operation: .format)
        #expect(pretty.isValid)
        #expect(JSONProcessor.process(pretty.output!, operation: .minify).output == source)
    }

    @Test func unicodeAndEscapes() {
        let source = #"{"😀":"Привет é \uD83D\uDE00 \n \\ \" \/ \b \f \r \t"}"#
        #expect(JSONProcessor.process(source, operation: .minify).output == source)
        let invalid = "{\"emoji\":\"😀\",\"x\":"
        let error = JSONProcessor.process(invalid, operation: .validate).diagnostics.last!
        #expect(error.range.location == invalid.utf16.count)
        #expect(error.range.length == 0)
        #expect(error.line == 1)
        #expect(error.column == invalid.utf16.count + 1)
    }

    @Test(arguments: [
        (#"{"a": 1 "b": 2}"#, "JSON-001"),
        (#"{"a": [1, 2}"#, "JSON-002"),
        (#"{"a": 1"#, "JSON-003"),
        (#"{"name": "Alice}"#, "JSON-004"),
        (#"{"a": 1,}"#, "JSON-005"),
        (#"{'a':1}"#, "JSON-006"),
        (#"{name:1}"#, "JSON-007"),
        (#"{"a":True}"#, "JSON-008"),
        (#"{"a":01}"#, "JSON-009"),
        (#"{"a":1} garbage"#, "JSON-011"),
        (#"{"a":"\uZZZZ"}"#, "JSON-012"),
        (#"{"a":"\x"}"#, "JSON-ESCAPE"),
        ("// hi\n{\"a\":1}", "JSON-008"),
        (#"{"a":1]"#, "JSON-003"),
        (#"[1,2"#, "JSON-002"),
        (#"[1,2,]"#, "JSON-005"),
        (#""a":1}"#, "JSON-011"),
        (#"1,2]"#, "JSON-011"),
        ("", "JSON-EMPTY"), (" \n\t ", "JSON-EMPTY")
    ])
    func syntaxErrors(_ example: (String, String)) {
        let result = JSONProcessor.process(example.0, operation: .format)
        #expect(!result.isValid)
        #expect(result.output == nil)
        #expect(result.diagnostics.last?.code == example.1)
        #expect(result.diagnostics.last!.range.location <= example.0.utf16.count)
    }

    @Test func duplicateKeysPreservedAndWarned() {
        let source = #"{"a":1,"\u0061":2}"#
        let result = JSONProcessor.process(source, operation: .minify)
        #expect(result.isValid)
        #expect(result.output == source)
        #expect(result.diagnostics.first?.code == "JSON-010")
        #expect(result.diagnostics.first?.severity == .warning)
    }

    @Test func linesAndCRLF() {
        let source = "{\r\n  \"😀\": 1,\r\n  bad: 2\n}"
        let error = JSONProcessor.process(source, operation: .validate).diagnostics.last!
        #expect(error.line == 3)
        #expect(error.column == 3)
        #expect((source as NSString).substring(with: error.range) == "b")
    }

    @Test(arguments: ["-", "1.", "1e", "1e+", "+1", "NaN", "[truefalse]", "[1 2]", "[}", "{\"a\" 1}", "\"raw\nnewline\"", #""\uD800""#, "“hello”"])
    func rejectsMalformedValues(_ input: String) {
        #expect(!JSONProcessor.process(input, operation: .validate).isValid)
    }

    @Test func limitsAndRepeatedInput() {
        let nested = String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)
        #expect(JSONProcessor.process(nested, operation: .format).diagnostics.last?.code == "JSON-DEPTH")
        let large = "\"" + String(repeating: "x", count: JSONProcessor.maximumUTF16Length) + "\""
        #expect(JSONProcessor.process(large, operation: .format).diagnostics.last?.code == "JSON-LIMIT")
        let supported = "[" + Array(repeating: "12345678901234567890", count: 5000).joined(separator: ",") + "]"
        #expect(JSONProcessor.process(supported, operation: .minify).output == supported)
        #expect(JSONProcessor.process("{}", operation: .format).output == "{}")
    }

    @Test func checkedInFixtures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("docs/M0_TEST_FIXTURES")
        for name in ["01-compact-valid.json", "02-equivalent-reordered.json", "03-modified.json", "10-large-integer.json"] {
            let input = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            let formatted = JSONProcessor.process(input, operation: .format)
            #expect(JSONProcessor.inspectStructure(input).result.diagnostics == formatted.diagnostics)
            #expect(formatted.isValid)
            #expect(JSONProcessor.process(formatted.output!, operation: .minify).output == JSONProcessor.process(input, operation: .minify).output)
        }
        for name in ["04-missing-comma.json", "05-missing-array-bracket.json", "06-missing-object-brace.json", "07-unterminated-string.json", "08-trailing-comma.json", "13-unicode-incomplete.json"] {
            let input = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            #expect(!JSONProcessor.process(input, operation: .validate).isValid)
            #expect(JSONProcessor.inspectStructure(input).result.diagnostics == JSONProcessor.process(input, operation: .validate).diagnostics)
        }
    }
}
