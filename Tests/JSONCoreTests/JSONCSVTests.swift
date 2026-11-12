import Foundation
import Testing
@testable import JSONCore

struct JSONCSVTests {
    private func run(_ source: String, _ direction: JSONCSVDirection = .toJSON, _ options: JSONCSVOptions = .init()) -> JSONCSVResult {
        JSONCSVConverter.process(source, direction: direction, options: options)
    }
    private func compact(_ text: String) -> String? { JSONProcessor.process(text, operation: .minify).output }
    @Test func RFCQuotesMultilineWhitespaceBOMAndTSV() throws {
        let source = "\u{FEFF}name,note,last\r\n\"a,b\",\"line1\r\nline2 \"\"quoted\"\"\",\r\n x ,\"\",end\r\n"
        let table = try DelimitedTextParser.parse(source, format: .csv)
        #expect(table.records.count == 3 && table.cells.count == 9)
        #expect(table.cells[3].value == "a,b")
        #expect(table.cells[4].value == "line1\r\nline2 \"quoted\"")
        #expect(table.cells[5].value == "" && table.cells[6].value == " x ")
        #expect(table.cells[7].value == "")
        #expect(table.cells[0].range.location == 1)
        for source in ["a,b\nc,d\n", "a,b\rc,d\r", "a,b\r\nc,d", "a,b\r\nc,d\r\n"] {
            #expect(try DelimitedTextParser.parse(source, format: .csv).records.count == 2)
        }
        #expect(try DelimitedTextParser.parse("a,", format: .csv).cells.map(\.value) == ["a", ""])
        #expect(try DelimitedTextParser.parse("\n\n", format: .csv).records.count == 2)
        #expect(try DelimitedTextParser.parse("\"\"\r\n", format: .csv).records.count == 1)
        var tsv = JSONCSVOptions(); tsv.format = .tsv
        let result = run("key\tnote\nhello\t\"a\tb\"\n", .toJSON, tsv)
        #expect(result.status == .success)
        let json = try #require(result.output)
        let document = try #require(JSONProcessor.inspectStructure(json).document)
        #expect(document.nodes.first { $0.key == "note" }?.scalar == "a\tb")
    }
    @Test func columnUnionOrderExactNumbersAndPlainTextPolicy() throws {
        let result = run(#"[{"b":90071992547409931234567890,"a":"x,y"},{"c":true,"a":"line\nnext"},{"a":""}]"#, .toDelimited)
        #expect(result.status == .success && result.rowCount == 3 && result.columnCount == 3)
        let csv = try #require(result.output)
        #expect(csv.hasPrefix("b,a,c\r\n90071992547409931234567890,\"x,y\",\"\"\r\n"))
        let back = run(csv)
        let text = try #require(back.output)
        #expect(text.contains("\"90071992547409931234567890\""))
        #expect(back.rowCount == 3 && back.columnCount == 3)
        #expect(!result.notes.isEmpty)
    }
    @Test func stringsInferenceAndEmptyPolicies() throws {
        let csv = "id,value,empty\n001,1e999999,\nnull,true,\n"
        var options = JSONCSVOptions()
        let allStrings = try #require(run(csv, .toJSON, options).output)
        #expect(allStrings.contains("\"1e999999\"") && allStrings.contains("\"null\""))
        options.inferScalars = true; options.empty = .null
        let typed = try #require(run(csv, .toJSON, options).output)
        #expect(typed.contains("\"id\": \"001\"") && typed.contains("\"value\": 1e999999") && typed.contains("\"id\": null"))
        #expect(typed.contains("\"empty\": null"))
        options.empty = .omit
        let omitted = try #require(run(csv, .toJSON, options).output)
        #expect(!omitted.contains("\"empty\":"))
        let spaces = try #require(run("v\n 1 \n", .toJSON, options).output)
        #expect(spaces.contains("\" 1 \""))
        options.shape = .arrays
        #expect(run(csv, .toJSON, options).status == .unsupported)
    }
    @Test func JSONCellsPreserveTypesMissingNullEscapesAndNumbers() throws {
        let source = #"[{"s":"","n":null,"num":-0,"ex":1.2300e+999,"nested":{"a":[true,"\u0061"]}},{"s":"null","num":90071992547409931234567890}]"#
        var options = JSONCSVOptions(); options.cells = .json
        let result = run(source, .toDelimited, options)
        #expect(result.status == .success)
        let exported = try #require(result.output)
        let restored = run(exported, .toJSON, options)
        #expect(restored.status == .success)
        #expect(compact(try #require(restored.output)) == source)
        #expect(restored.rowCount == 2)
        let sparse = run(#"[{}, {"s":"","n":null}]"#, .toDelimited, options)
        let sparseCSV = try #require(sparse.output)
        #expect(compact(try #require(run(sparseCSV, .toJSON, options).output)) == #"[{},{"s":"","n":null}]"#)
    }
    @Test func flattenObjectsUsesPointersAndRetainsContainers() throws {
        let source = #"[{"user":{"name":"é","roles":["admin"],"empty":{}},"a/b":{"~x":1},"":null},{"user":{"name":"é"}}]"#
        var options = JSONCSVOptions(); options.cells = .flatten
        let output = try #require(run(source, .toDelimited, options).output)
        #expect(output.hasPrefix("/user/name,/user/roles,/user/empty,/a~1b/~0x,/\r\n"))
        #expect(compact(try #require(run(output, .toJSON, options).output)) == source)
        #expect(run(#"[{"a":1},{"a":{"b":2}}]"#, .toDelimited, options).status == .unsupported)
        #expect(run("/a,/a/b\n1,2", .toJSON, options).status == .unsupported)
        #expect(run("/a~2b\n1", .toJSON, options).status == .invalid)
        #expect(run("a\n1", .toJSON, options).status == .unsupported)
        let boundary = String(repeating: "/k", count: 63) + "\n1"
        #expect(run(boundary, .toJSON, options).status == .success)
        #expect(run("/k" + boundary, .toJSON, options).status == .resourceLimit)
        options.hasHeader = false
        #expect(run(source, .toDelimited, options).status == .unsupported)
    }
    @Test func arrayRowsHeaderlessAndHeaderOnly() throws {
        var options = JSONCSVOptions(); options.shape = .arrays; options.hasHeader = false; options.cells = .json; options.format = .tsv
        let source = #"[["😀",1,null],["é",-0,true]]"#
        let exported = try #require(run(source, .toDelimited, options).output)
        #expect(compact(try #require(run(exported, .toJSON, options).output)) == source)
        #expect(run("1\t", .toJSON, options).status == .invalid)
        #expect(run("[[1],[1,2]]", .toDelimited, options).status == .unsupported)
        options.cells = .text; options.shape = .objects
        #expect(compact(try #require(run("x\ty", .toJSON, options).output)) == #"[{"column1":"x","column2":"y"}]"#)
        #expect(run("a,b\n").output == "[]")
        #expect(run("[]", .toDelimited).output == "")
        #expect(run("[{}]", .toDelimited).status == .unsupported)
    }
    @Test func duplicateHeadersAndKeysUseScalarIdentity() throws {
        #expect(run("a,a\nx,y").status == .unsupported)
        #expect(run("é,é\nx,y").status == .success)
        #expect(run(#"[{"a":1,"\u0061":2}]"#, .toDelimited).status == .unsupported)
        #expect(run(#"[{"é":1,"é":2}]"#, .toDelimited).columnCount == 2)
        var options = JSONCSVOptions(); options.cells = .json
        // Duplicate keys within an opaque JSON cell remain exact; row-column identity stays unique.
        let source = #"[{"value":{"a":1,"a":2}}]"#
        let output = try #require(run(source, .toDelimited, options).output)
        #expect(compact(try #require(run(output, .toJSON, options).output)) == source)
        #expect(compact(try #require(run("\"\"\nx").output)) == #"[{"":"x"}]"#)
    }
    @Test func malformedQuotesRaggedRowsAndCoordinates() throws {
        for text in ["a\n\"bad", "a\nx\"y", "a\n\"ok\" bad", "a,b\nx", "a,b\nx,y,z"] {
            let result = run(text)
            #expect(result.status == .invalid && result.output == nil && !result.diagnostics.isEmpty)
        }
        let text = "emoji,note\r\n😀,\"unfinished é"
        let issue = try #require(run(text).diagnostics.first)
        #expect(issue.range.location == text.utf16.count && issue.range.length == 0)
        #expect(issue.line == 2 && !issue.related.isEmpty)
        var options = JSONCSVOptions(); options.cells = .json
        let inner = "v\n\"{\"\"emoji\"\":\"\"😀\"\",\"\"bad\"\":}\""
        let mapped = try #require(run(inner, .toJSON, options).diagnostics.first)
        #expect((inner as NSString).substring(with: mapped.range) == "}")
        let unicode = "v\n\"\"\"\\uD800\"\"\""
        let unicodeIssue = try #require(run(unicode, .toJSON, options).diagnostics.first)
        #expect(unicodeIssue.precision == .region && !unicodeIssue.related.isEmpty)
        #expect(NSMaxRange(unicodeIssue.range) <= unicode.utf16.count)
        options.cells = .flatten; options.hasHeader = false
        #expect(run(inner, .toJSON, options).diagnostics.first?.code == "TABLE-OPTIONS")
    }
    @Test func trailingDelimiterDiagnosticPreservesInternalEmptyFields() throws {
        for format in DelimitedFormat.allCases {
            var options = JSONCSVOptions(); options.format = format
            let separator = format.text
            let header = ["name", "optional", "reference", "id"].joined(separator: separator)
            let row = ["😀é", "", "\"note, with comma\"", "abc"].joined(separator: separator)
            let source = header + "\r\n" + row + separator + "\r\n"
            let result = run(source, .toJSON, options)
            let issue = try #require(result.diagnostics.first)
            #expect(result.status == .invalid && result.output == nil)
            #expect(issue.message.contains("5 fields; the header has 4"))
            #expect(issue.message.contains(format == .tsv ? "trailing TAB" : "trailing comma"))
            #expect(issue.range == NSRange(location: (header + "\r\n" + row).utf16.count, length: 1))
            #expect((source as NSString).substring(with: issue.range) == separator)
            #expect(issue.line == 2 && issue.related.first?.range == NSRange(location: 0, length: header.utf16.count))
            // Explicitly removing just the terminal delimiter retains the intentional internal blank.
            let corrected = run(header + "\r\n" + row + "\r\n", .toJSON, options)
            let json = try #require(corrected.output)
            let document = try #require(JSONProcessor.inspectStructure(json).document)
            #expect(document.nodes.first { $0.key == "optional" }?.scalar == "")
            #expect(document.nodes.first { $0.key == "reference" }?.scalar == "note, with comma")
        }
        #expect(run("a,b\nx,y,\"\"").diagnostics.first?.message.contains("trailing comma") == false)
        #expect(run("a,b\nx,,z").diagnostics.first?.message.contains("trailing comma") == false)
        #expect(run("a,b,\nx,y,").status == .success) // Matching empty header is an actual column.
        var headerless = JSONCSVOptions(); headerless.hasHeader = false
        #expect(run("a,b\nx,y,", .toJSON, headerless).diagnostics.first?.message.contains("first record has 2") == true)
    }
    @Test func TSVDialectSuggestionIsAdvisoryAndQuoteAware() throws {
        let source = "name\toptional\treference\r\n😀\t\tfee, extra\t\r\n"
        let csv = run(source)
        #expect(csv.status == .invalid && csv.suggestedFormat == .tsv && csv.output == nil)
        var options = JSONCSVOptions(); options.format = .tsv
        let tsv = run(source, .toJSON, options)
        #expect(tsv.status == .invalid && tsv.suggestedFormat == nil)
        #expect(tsv.diagnostics.first?.message.contains("trailing TAB") == true)
        // A legal one-column CSV is kept valid, even if TSV is also a plausible interpretation.
        let ambiguous = run("a\tb\nx\ty")
        #expect(ambiguous.status == .success && ambiguous.columnCount == 1 && ambiguous.suggestedFormat == .tsv)
        #expect(ambiguous.output?.contains("a\\u0009b") == true)
        #expect(run("\"a\tb\"\n\"x\ty\"").suggestedFormat == nil) // Quoted tabs are data.
        #expect(run("a,b\nx\ty,z").suggestedFormat == nil) // Valid multi-column CSV.
        #expect(run("a\tb\nx\ty\tz\nw\tz").suggestedFormat == nil) // Not a coherent alternate table.
        #expect(run("a\tb\n\"unfinished").suggestedFormat == nil)
        #expect(run("a\tb").suggestedFormat == nil) // Insufficient evidence from a single record.
    }
    @Test func elevenColumnTSVWithInternalBlanksAndCommasConverts() throws {
        // Synthetic statement-shaped data: no user financial data in fixtures or logs.
        let names = ["Date", "Credit", "Debit", "Balance", "Currency", "Counterpart Name", "Counterpart IBAN", "Reference", "Type", "Scheme", "TransactionId"]
        let rows = (0..<24).map { index in
            ["01/02/2026 10:30:13", "10000.00", "0.0", "9996.12", "EUR", "Example", index == 0 ? "" : "example-account",
             index % 3 == 0 ? "fee, reference" : "currency -> currency", "Example type", index == 0 ? "Example scheme" : "", "synthetic-id-\(index)"]
                .joined(separator: "\t")
        }
        let source = ([names.joined(separator: "\t")] + rows).joined(separator: "\n")
        var options = JSONCSVOptions(); options.format = .tsv
        for ending in ["", "\n", "\r\n"] {
            let result = run(source + ending, .toJSON, options)
            #expect(result.status == .success && result.rowCount == 24 && result.columnCount == 11)
            #expect(result.diagnostics.isEmpty)
            let output = try #require(result.output)
            let document = try #require(JSONProcessor.inspectStructure(output).document)
            #expect(document.nodes.first { $0.key == "Credit" }?.scalar == "10000.00")
            #expect(document.nodes.first { $0.key == "Counterpart IBAN" }?.scalar == "")
            #expect(document.nodes.first { $0.key == "Reference" }?.scalar == "fee, reference")
        }
        let csv = run(source)
        #expect(csv.status == .invalid && csv.suggestedFormat == .tsv)
    }
    @Test func spreadsheetWarningsAndExplicitProtection() throws {
        let source = #"[{"=HEADER":"=SUM(A1)","normal":"safe","number":-1}]"#
        let original = run(source, .toDelimited)
        #expect(original.status == .success && original.diagnostics.first?.severity == .warning)
        #expect(original.output?.contains("=SUM(A1)") == true)
        var options = JSONCSVOptions(); options.protectFormulas = true
        let protected = run(source, .toDelimited, options)
        #expect(protected.output?.contains("'=HEADER") == true && protected.output?.contains("'=SUM(A1)") == true)
        #expect(protected.output?.contains(",-1") == true)
        #expect(protected.diagnostics.first?.message.contains("added an apostrophe") == true)
        #expect(run(#"[{"number":-1}]"#, .toDelimited).diagnostics.isEmpty)
    }
    @Test func quotedTextRoundTripsAcrossBothDialects() throws {
        let strings = ["", "plain", "a,b", "a\tb", "a\"b", "\r\n", "😀é", " leading ", "\\t", "true", "null", "0001", "a\u{202E}b"]
        for format in DelimitedFormat.allCases {
            var options = JSONCSVOptions(); options.format = format; options.cells = .json
            let source = "[" + strings.map { "{\"value\":" + JSONTextEncoding.quote($0) + "}" }.joined(separator: ",") + "]"
            let result = run(source, .toDelimited, options)
            let table = try #require(result.output)
            let output = try #require(run(table, .toJSON, options).output)
            #expect(compact(output) == source)
        }
    }
    @Test func resourceLimitsAndCancellation() async {
        #expect(run(String(repeating: "x", count: 262_145)).status == .resourceLimit)
        var options = JSONCSVOptions(); options.cells = .json
        let sparse = "[" + (0..<8_000).map { "{\"k\($0)\":1}" }.joined(separator: ",") + "]"
        #expect(run(sparse, .toDelimited, options).status == .resourceLimit)
        let deeplyNested = String(repeating: "[", count: 63) + "0" + String(repeating: "]", count: 63)
        let csv = "v\n" + deeplyNested
        #expect(run(csv, .toJSON, options).status == .resourceLimit) // cells alone valid, root+row exceed depth
        let task = Task.detached { withUnsafeCurrentTask { $0?.cancel() }; return JSONCSVConverter.process("a\nx", direction: .toJSON) }
        #expect(await task.value.status == .cancelled)
        #expect(run("").status == .invalid)
        #expect(run("\u{FEFF}").status == .invalid)
    }
}

@MainActor struct JSONCSVWorkspaceTests {
    @Test func pasteCheckRevisionsOptionsAndPrivacy() async throws {
        let suite = "JSONCSVTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = JSONPreferencesRepository(defaults: defaults)
        let session = JSONCSVWorkspaceSession(repository: repository)
        session.input = #"[{"s":"é"}]"#
        #expect(session.result == nil)
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        await session.run().value
        let output = session.output
        #expect(output != nil)
        await session.run(convert: false).value; #expect(session.output == output)
        let cancelled = session.run(); session.cancel(); await cancelled.value
        #expect(session.output == output && session.wasCancelled)
        session.input = #"[{"s":"é"}]"#; #expect(session.output == nil && session.result == nil)
        let stale = session.run(); session.options.format = .tsv; await stale.value
        #expect(!session.busy && session.output == nil && session.result == nil)
        await session.run().value
        session.preferences.wordWrap = false
        #expect(session.output != nil)
        session.preferences.indentation = .four; #expect(session.output == nil)
        session.direction = .toJSON; session.input = "name\nhello"
        await session.run().value; #expect(session.output?.contains("    {") == true)
        session.preferences.validateOnPaste = false; session.input = "invalid\"quote"
        #expect(session.didPaste() == nil && session.result == nil)
        let fresh = JSONCSVWorkspaceSession(repository: repository)
        #expect(fresh.input.isEmpty && fresh.output == nil && fresh.result == nil && fresh.options == JSONCSVOptions())
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox") } == [JSONPreferencesRepository.key])
    }
}
