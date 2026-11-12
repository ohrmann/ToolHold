import Foundation
import Testing
import CToml
@testable import JSONCore

struct JSONTOMLTests {
    private func run(_ source: String, _ direction: JSONTOMLDirection = .tomlToJSON, _ options: JSONTOMLOptions = .init()) -> JSONTOMLResult {
        JSONTOMLConverter.process(source, direction: direction, options: options)
    }
    private func compact(_ text: String) -> String? { JSONProcessor.process(text, operation: .minify).output }
    @Test func ordinaryTablesDottedKeysAndArraysOfTables() throws {
        let source = "title = 'Example'\nversion = 2\n[server]\nport=8080\nssl=true\n[database.settings]\nusers=['Ada','Bob']\n[[products]]\nname='one'\n[[products]]\nname='two'"
        let result = run(source)
        let output = try #require(result.output)
        #expect(result.status == .success)
        #expect(compact(output) == #"{"title":"Example","version":2,"server":{"port":8080,"ssl":true},"database":{"settings":{"users":["Ada","Bob"]}},"products":[{"name":"one"},{"name":"two"}]}"#)
        let reversed = try #require(run(output, .jsonToTOML).output)
        #expect(reversed.contains("[\"server\"]") && reversed.contains("[[\"products\"]]"))
        #expect(compact(try #require(run(reversed).output)) == compact(output))
    }
    @Test func inlineStylePreservesOrderAndExactNumbers() throws {
        let source = #"{"nested":{"x":1},"after":-0,"float":1.2300e+002,"integer":9007199254740993,"min":-9223372036854775808,"max":9223372036854775807,"mixed":[{"a":1},true,[],{}]}"#
        var options = JSONTOMLOptions(); options.tables = .inline
        let toml = try #require(run(source, .jsonToTOML, options).output)
        #expect(toml.contains("1.2300e+002") && toml.contains("9007199254740993"))
        #expect(compact(try #require(run(toml).output)) == source)
        #expect(run(source, .jsonToTOML).notes.contains { $0.contains("order can change") })
    }
    @Test func numberLexemesAreNeverSerializedViaDouble() throws {
        let output = try #require(run("a=+1_234\nb=-0\nc=+1.230_0e+002\nd=0x7fff_ffff_ffff_ffff\ne=0o10\nf=0b11\ng=0.12345678901234567890123456789\nh=5e-324").output)
        #expect(compact(output) == #"{"a":1234,"b":-0,"c":1.2300e+002,"d":9223372036854775807,"e":8,"f":3,"g":0.12345678901234567890123456789,"h":5e-324}"#)
        for literal in ["nan", "+nan", "-inf", "+inf"] {
            let result = run("v=" + literal)
            #expect(result.status == .unsupported && result.output == nil)
        }
        for literal in ["9223372036854775808", "-9223372036854775809", "1e999", "1e-999"] {
            #expect(run("{\"v\":" + literal + "}", .jsonToTOML).status == .unsupported)
            let result = run("v=" + literal)
            #expect(result.status == .unsupported && result.diagnostics.first?.message.contains("range supported") == true)
        }
    }
    @Test func nullDuplicateAndRootPoliciesAreExplicit() {
        for input in ["null", "[1]", "1", #"{"a":null}"#, #"{"a":[null]}"#, #"{"a":1,"\u0061":2}"#] {
            let result = run(input, .jsonToTOML)
            #expect(result.status == .unsupported && result.output == nil)
        }
        for input in ["x=1\nx=2", "a=1\na.b=2", "[a]\n[a]", "a={x=1,x=2}", "a=1\n\"\\u0061\"=2"] {
            #expect(run(input).status == .invalid)
        }
        #expect(run("{", .jsonToTOML).status == .invalid)
        #expect(run("{}", .jsonToTOML).output == "")
        #expect(run("").output == "{}")
        #expect(run("# only comment\n").output == "{}")
    }
    @Test func stringsEscapesUnicodeAndScalarDistinctKeys() throws {
        let source = #"{"é":1,"é":2,"a.b":{"quote\"\\":"😀é\r\n\t\u0000\b\f"},"":{},"n":["yes","true","1979-05-27"]}"#
        var options = JSONTOMLOptions(); options.tables = .inline
        let toml = try #require(run(source, .jsonToTOML, options).output)
        let restored = try #require(run(toml).output)
        let original = try #require(JSONProcessor.inspectStructure(source).document)
        let converted = try #require(JSONProcessor.inspectStructure(restored).document)
        #expect(try JSONStructuralDiff.compare(original, converted).changes.isEmpty)
        let escaped = run("\"a\\u0000b\"=\"x\\u0000y\"\n\"é\"=1\n\"é\"=2")
        let output = try #require(escaped.output)
        let doc = try #require(JSONProcessor.inspectStructure(output).document)
        #expect(doc.nodes.count == 4 && doc.nodes[1].key == "a\0b" && doc.nodes[1].scalar == "x\0y")
        #expect(doc.nodes[2].occurrences == 1 && doc.nodes[3].occurrences == 1)
        for bad in [#"v="\uD800""#, #"v="\U00110000""#, #""\U00110000"=1"#] {
            #expect(run(bad).status == .invalid)
        }
    }
    @Test func TOML11MultilineStringsInlineTablesAndEscapes() throws {
        let source = "name = \"\"\"\nhello\\\n    world\"\"\"\nliteral = '''\nline 1\nline 2'''\ninline = {\n x = 1,\n y = [1, true, 'x'],\n}\nescape = \"\\e\\x41\""
        let result = run(source)
        let output = try #require(result.output)
        let doc = try #require(JSONProcessor.inspectStructure(output).document)
        #expect(result.status == .success)
        #expect(doc.nodes.first { $0.key == "name" }?.scalar == "helloworld")
        #expect(doc.nodes.first { $0.key == "literal" }?.scalar == "line 1\nline 2")
        #expect(doc.nodes.first { $0.key == "escape" }?.scalar == "\u{1B}A")
    }
    @Test func datesKeepOriginalFractionOffsetAndLocalMeaning() throws {
        let literals = ["1979-05-27", "07:32:00.123456789123", "1979-05-27T07:32:00.999999999-07:00", "1979-05-27 07:32:00.123456789", "07:32"]
        for literal in literals {
            let source = "date=" + literal
            let result = run(source)
            let output = try #require(result.output)
            let doc = try #require(JSONProcessor.inspectStructure(output).document)
            #expect(doc.nodes[1].scalar == literal)
            let warning = try #require(result.diagnostics.first)
            #expect(warning.severity == .warning && warning.range == NSRange(location: 5, length: literal.utf16.count))
            var options = JSONTOMLOptions(); options.datesAsStrings = false
            #expect(run(source, .tomlToJSON, options).status == .unsupported)
        }
        #expect(run("d=2026-02-30").status == .invalid)
        #expect(run(#"{"d":"1979-05-27"}"#, .jsonToTOML).output?.contains("\"1979-05-27\"") == true)
    }
    @Test func diagnosticsRangesHandleBOMCRLFAndUTF8() throws {
        let source = "\u{FEFF}\"😀é\"=1\r\nvalue=nan"
        let result = run(source)
        let issue = try #require(result.diagnostics.first)
        #expect(issue.range == (source as NSString).range(of: "nan"))
        #expect(issue.line == 2 && issue.column == 7 && issue.precision == .exact)
        let malformed = "\"😀\"=1\r\nnext=[1 2]"
        let error = try #require(run(malformed).diagnostics.first)
        #expect(error.precision == .region && error.line == 2)
        #expect(NSMaxRange(error.range) <= malformed.utf16.count)
        for (text,expected) in [("value=[1", "expected ']'"), ("value={a=1", "expected '}'")] {
            let result = run(text)
            #expect(result.status == .invalid && result.diagnostics.first?.message.contains(expected) == true)
            #expect(result.diagnostics.first?.range == NSRange(location: text.utf16.count, length: 0))
        }
        for source in ["a=[1", "a=\"unfinished", "a=01", "a=1__2", "a='bad\nline'", "a=\"\\q\"", "a=\0"] {
            #expect(run(source).status == .invalid)
        }
    }
    @Test func quotedPathsEmptyObjectsAndNestedArrayTablesRoundTrip() throws {
        let source = #"{"a.b":{"x.y":{},"z":[{"nested":{"s":"one"}},{"nested":{"s":"two"}}]},"empty":[],"arr":[{},{"a":[]}]}"#
        let toml = try #require(run(source, .jsonToTOML).output)
        let output = try #require(run(toml).output)
        var inline = JSONTOMLOptions(); inline.tables = .inline
        // Compare via exact structure/diff: sections can legitimately regroup object fields.
        let before = try #require(JSONProcessor.inspectStructure(source).document)
        let after = try #require(JSONProcessor.inspectStructure(output).document)
        #expect(try JSONStructuralDiff.compare(before, after).changes.isEmpty)
        let inlineText = try #require(run(source, .jsonToTOML, inline).output)
        let restored = try #require(run(inlineText).output)
        #expect(compact(restored) == source)
    }
    @Test func boundsCheckOnlyAndLibraryLimitsAreDistinctStatuses() throws {
        #expect(run(String(repeating: "x", count: 262_145)).status == .resourceLimit)
        let valid = "v=" + String(repeating: "[", count: 63) + "0" + String(repeating: "]", count: 63)
        #expect(run(valid).status == .success)
        #expect(run("v=[" + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 65)).status == .resourceLimit)
        #expect(run("v=1." + String(repeating: "0", count: 120)).status == .resourceLimit)
        let huge = "v=[" + Array(repeating: "0", count: 60_000).joined(separator: ",") + "]"
        #expect(run(huge).status == .resourceLimit) // Formatted JSON expansion; not a 16k-node library cap.
        let result = JSONTOMLConverter.process("v=1", direction: .tomlToJSON, produceOutput: false)
        #expect(result.status == .success && result.output == nil)
    }
    @Test func nativeCancellationNeverReturnsPartialTree() {
        let source = Array(repeating: "v", count: 10_000).enumerated().map { "\($0.offset)=1" }.joined(separator: "\n")
        var calls = 0
        let result = source.withCString { text in
            withUnsafeMutablePointer(to: &calls) { context in
                toml_toolbox_parse(text, Int32(source.utf8.count), { pointer in
                    let count = pointer!.assumingMemoryBound(to: Int.self); count.pointee += 1
                    return count.pointee >= 3 ? 1 : 0
                }, context)
            }
        }
        defer { toml_free(result) }
        #expect(!result.ok && result.toolbox_error_kind == 3)
    }
    @Test func asyncCancellationHasNoOutput() async {
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return JSONTOMLConverter.process("x=1", direction: .tomlToJSON)
        }
        worker.cancel(); let result = await worker.value
        #expect(result.status == .cancelled && result.output == nil && result.diagnostics.isEmpty)
    }
}

@MainActor struct JSONTOMLWorkspaceTests {
    @Test func revisionsPasteOutputAndPrivacy() async throws {
        let suite = "JSONTOMLTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = JSONPreferencesRepository(defaults: defaults), session = JSONTOMLWorkspaceSession(repository: .init(defaults: defaults))
        session.input = #"{"n":9007199254740993}"#
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        await session.run().value; let output = session.output
        #expect(output?.contains("9007199254740993") == true)
        await session.run(convert: false).value; #expect(session.output == output)
        let cancellation = session.run(); session.cancel(); await cancellation.value
        #expect(session.output == output && session.wasCancelled)
        let stale = session.run(); session.options.tables = .inline; await stale.value
        #expect(session.result == nil && session.output == nil && !session.busy)
        session.direction = .tomlToJSON; session.input = "v=1"
        await session.run().value
        session.preferences.wordWrap = false; #expect(session.output != nil)
        session.preferences.indentation = .four; #expect(session.output == nil)
        await session.run().value; #expect(session.output?.contains("    \"v\"") == true)
        session.input = "\"é\"=1"; let older = session.run(); session.input = "\"é\"=2"; await older.value
        #expect(session.output == nil && session.result == nil)
        session.input = ""; await session.run().value
        #expect(session.output == "{}")
        session.clear(); #expect(session.output == nil && session.result == nil)
        session.preferences.validateOnPaste = false; #expect(session.didPaste() == nil)
        let fresh = JSONTOMLWorkspaceSession(repository: repository)
        #expect(fresh.input.isEmpty && fresh.output == nil && fresh.result == nil && fresh.options == JSONTOMLOptions())
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox") } == [JSONPreferencesRepository.key])
    }
}
