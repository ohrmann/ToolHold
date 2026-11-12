import Foundation
import Testing
@testable import JSONCore

struct JSONDiagnosticTests {
    struct Fixture: Sendable {
        let source: String
        let code: String
        let offset: Int
        let expected: [JSONExpectedToken]
        let role: JSONRelatedLocation.Role?
        let relatedOffset: Int
        init(_ source: String, _ code: String, _ offset: Int, _ expected: [JSONExpectedToken],
             _ role: JSONRelatedLocation.Role? = .containerStart, _ relatedOffset: Int = 0) {
            self.source = source; self.code = code; self.offset = offset
            self.expected = expected; self.role = role; self.relatedOffset = relatedOffset
        }
    }
    @Test(arguments: [
        Fixture(#"{"a":1 "b":2}"#, "JSON-001", 7, [.comma, .objectEnd]),
        Fixture("[1 2]", "JSON-001", 3, [.comma, .arrayEnd]),
        Fixture(#"{"a":"text}"#, "JSON-004", 11, [.quote], .stringStart, 5),
        Fixture(#"{"a":"x""}"#, "JSON-001", 8, [.comma, .objectEnd]),
        Fixture(#"{"a":1"#, "JSON-003", 6, [.comma, .objectEnd]),
        Fixture("[1,2", "JSON-002", 4, [.comma, .arrayEnd]),
        Fixture(#"{"a":[1}"#, "JSON-002", 7, [.comma, .arrayEnd], .containerStart, 5),
        Fixture("[{]}", "JSON-003", 2, [.fieldName, .objectEnd], .containerStart, 1),
        Fixture("[1,]", "JSON-005", 3, [.value], .separator, 2),
        Fixture(#"{"a":1,}"#, "JSON-005", 7, [.fieldName], .separator, 6),
        Fixture("[1,,2]", "JSON-008", 3, [.value], .separator, 2),
        Fixture("[1,}", "JSON-002", 3, [.value], .separator, 2),
        Fixture("01", "JSON-009", 1, [.numberContinuation], .valueStart, 0),
        Fixture(#"{"a"1}"#, "JSON-COLON", 4, [.colon], .fieldName, 1),
        Fixture(#"{"a":"\x"}"#, "JSON-ESCAPE", 7, [.escape], .escapeStart, 6),
        Fixture(#"{"a":"\u12G4"}"#, "JSON-012", 10, [.hexDigit], .escapeStart, 6),
        Fixture(#"{"a":"\u12"#, "JSON-012", 10, [.hexDigit], .escapeStart, 6),
        Fixture(#"{"a":"abc\"#, "JSON-004", 10, [.escape], .escapeStart, 9),
        Fixture(#"{"a":"#, "JSON-EOF", 5, [.value], .separator, 4),
        Fixture("1.", "JSON-NUMBER", 2, [.digit], .valueStart, 0),
        Fixture("1e+", "JSON-NUMBER", 3, [.digit], .valueStart, 0),
        Fixture("-", "JSON-NUMBER", 1, [.digit], .valueStart, 0),
        Fixture("tru", "JSON-008", 3, [.trueLiteral], .valueStart, 0),
        Fixture(#""a":1}"#, "JSON-011", 3, [.endOfDocument], .valueStart, 0),
        Fixture("", "JSON-EMPTY", 0, [.value], nil)
    ])
    func goldenDetection(_ fixture: Fixture) throws {
        let result = JSONProcessor.process(fixture.source, operation: .validate)
        let captured = JSONProcessor.inspectStructure(fixture.source)
        #expect(captured.result.status == result.status && captured.result.diagnostics == result.diagnostics)
        #expect(captured.document == nil)
        let error = try #require(result.diagnostics.last)
        #expect(result.status == .invalid)
        #expect(error.code == fixture.code)
        #expect(error.precision == .exact)
        #expect(error.range.location == fixture.offset)
        #expect(error.range.length == (fixture.offset == fixture.source.utf16.count ? 0 : 1))
        #expect(error.expected == fixture.expected)
        #expect(error.line == 1)
        #expect(error.column == fixture.offset + 1)
        if let role = fixture.role {
            #expect(error.related.contains { $0.role == role && $0.range.location == fixture.relatedOffset })
        }
    }
    @Test func unicodeRegionsCRLFAndEscapes() throws {
        let unicode = JSONProcessor.process(#""\uD800""#, operation: .validate)
        let rejection = try #require(unicode.diagnostics.last)
        #expect(rejection.kind == .unicodePolicy)
        #expect(rejection.precision == .region)
        #expect(rejection.range == NSRange(location: 0, length: 8))
        let source = "{\r\n\"😀\":\"é\",\r\n\"b\":}"
        let error = try #require(JSONProcessor.process(source, operation: .format).diagnostics.last)
        #expect(error.line == 3 && error.column == 5)
        #expect(error.range.location == source.utf16.count - 1)
        let coordinates = JSONSourceCoordinates(source)
        #expect(coordinates.lineStarts.count == 3)
        #expect(coordinates.location(at: error.range.location).column == error.column)
        let escaped = #"{"a":"\r\n😀","b":}"#
        let escapedError = try #require(JSONProcessor.process(escaped, operation: .validate).diagnostics.last)
        #expect(escapedError.line == 1)
        #expect(escapedError.column == escaped.utf16.count)
    }
    @Test func duplicatesAreWarningsWithFirstOccurrenceAndNoMutation() throws {
        let source = #"{"a":9007199254740993,"\u0061":1.2300E+999}"#
        let result = JSONProcessor.process(source, operation: .minify)
        #expect(result.status == .valid)
        #expect(result.output == source)
        let warning = try #require(result.diagnostics.first)
        #expect(warning.severity == .warning)
        #expect(warning.related.contains { $0.role == .firstOccurrence && $0.range == NSRange(location: 1, length: 3) })
        let context = JSONDiagnosticContext.make(source: source, diagnostic: warning)
        #expect((context.text as NSString).substring(with: context.detectionRange) == #""\u0061""#)
    }
    @Test func resourceAndCancellationStatuses() async {
        let large = JSONProcessor.process(String(repeating: "x", count: 262_145), operation: .validate)
        #expect(large.status == .resourceLimit(.inputSize))
        let deep = JSONProcessor.process(String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65), operation: .format)
        #expect(deep.status == .resourceLimit(.nestingDepth))
        let supported = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        #expect(JSONProcessor.process(supported, operation: .validate).status == .valid)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return JSONProcessor.process("{}", operation: .format)
        }
        let cancelled = await task.value
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.diagnostics.isEmpty && cancelled.output == nil)
    }
    @Test func onlyFirstSyntaxErrorNoIntentInference() throws {
        let source = #"{"a":1 "b":, "c":[}"#
        let errors = JSONProcessor.process(source, operation: .validate).diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.range.location == 7)
        let quote = try #require(JSONProcessor.process(#"{"name":"Alice, "age":30}"#, operation: .validate).diagnostics.first)
        #expect(quote.expected == [.comma, .objectEnd])
        #expect(!quote.message.contains("missing quote"))
    }
    @Test func contextCollapsesOnlyFormattingWhitespace() throws {
        let source = "{\r\n\t  \"message\"\t : \t\"a   b\\t\\\"quoted\\\"\\\\end\" \r\n  \t\"count\": 2\r\n}"
        let error = try #require(JSONProcessor.process(source, operation: .validate).diagnostics.last)
        let context = JSONDiagnosticContext.make(source: source, diagnostic: error)
        #expect(context.text == #"{ "message" : "a   b\t\"quoted\"\\end" "count": 2 }"#)
        #expect(error.range.location == (source as NSString).range(of: "\"count\"").location)
        #expect((context.text as NSString).substring(with: context.detectionRange) == "\"")
        #expect(context.segments.contains { $0.sourceRange == error.range && $0.displayRange == context.detectionRange })

        let control = "{\n\t\"text\": \"a\t  b\"\n}"
        let invalid = try #require(JSONProcessor.process(control, operation: .validate).diagnostics.last)
        let visible = JSONDiagnosticContext.make(source: control, diagnostic: invalid)
        #expect(visible.text.contains("a⇥  b")) // a control in a string is evidence, not indentation
        #expect((visible.text as NSString).substring(with: visible.detectionRange) == "⇥")
        #expect(visible.segments.contains { $0.sourceRange == invalid.range && $0.displayRange == visible.detectionRange })

        let combined = "{ \t \u{0301}}"
        let combinedError = try #require(JSONProcessor.process(combined, operation: .validate).diagnostics.last)
        let composed = JSONDiagnosticContext.make(source: combined, diagnostic: combinedError)
        #expect(composed.text == "{ ⇥ \u{0301}}") // no splitting or duplicating a whitespace-based grapheme
    }

    @Test func compactedContextKeepsAnchorsAcrossLargeIndentation() throws {
        let prefix = "{\n\t\"a\": 1"
        let gap = String(repeating: " \t\r\n", count: 10_000)
        let source = prefix + gap + "\"b\": 2\n}"
        let error = try #require(JSONProcessor.process(source, operation: .validate).diagnostics.last)
        let context = JSONDiagnosticContext.make(source: source, diagnostic: error)
        #expect(context.text == #"{ "a": 1 "b": 2 }"#)
        #expect(error.range.location == prefix.utf16.count + gap.utf16.count)
        let collapsed = try #require(context.segments.first { $0.sourceRange == NSRange(location: prefix.utf16.count, length: gap.utf16.count) })
        #expect((context.text as NSString).substring(with: collapsed.displayRange) == " ")
        #expect(context.segments.contains { $0.sourceRange == error.range && $0.displayRange == context.detectionRange })
        let unfinished = prefix + gap
        let eof = try #require(JSONProcessor.process(unfinished, operation: .validate).diagnostics.last)
        let eofContext = JSONDiagnosticContext.make(source: unfinished, diagnostic: eof)
        #expect(eofContext.text == #"{ "a": 1 "# + "⟂ EOF")
        #expect(eofContext.segments.contains { $0.sourceRange == NSRange(location: unfinished.utf16.count, length: 0) && $0.displayRange == eofContext.detectionRange })

        let input = "{ \t   \"a\":1}"
        let insertion = JSONDiagnostic(severity: .error, code: "TEST", message: "Insertion", range: NSRange(location: 3, length: 0), line: 1, column: 4)
        let inserted = JSONDiagnosticContext.make(source: input, diagnostic: insertion)
        #expect(inserted.text == #"{ │ "a":1}"#)
        #expect(inserted.segments.contains { $0.sourceRange == insertion.range && $0.displayRange == inserted.detectionRange })
        let token = JSONDiagnostic(severity: .error, code: "TEST", message: "Tab", range: NSRange(location: 2, length: 1), line: 1, column: 3)
        let protected = JSONDiagnosticContext.make(source: input, diagnostic: token)
        #expect((protected.text as NSString).substring(with: protected.detectionRange) == "⇥")
        #expect(protected.segments.contains { $0.sourceRange == token.range && $0.displayRange == protected.detectionRange })
    }

    @Test func contextIsBoundedMappedAndSanitized() throws {
        let source = "[\"" + String(repeating: "😀é", count: 4000) + "\u{202E}\u{0009}\" 2]"
        let error = try #require(JSONProcessor.process(source, operation: .validate).diagnostics.last)
        let context = JSONDiagnosticContext.make(source: source, diagnostic: error)
        #expect(context.text.utf16.count <= 220)
        #expect(context.text.hasPrefix("…"))
        #expect(!context.text.unicodeScalars.contains { $0.value == 0x202E || $0.value == 9 })
        #expect(context.text.contains("U+202E"))
        #expect(context.segments.contains { $0.sourceRange?.location == error.range.location && $0.displayRange == context.detectionRange })
        for segment in context.segments {
            #expect(NSMaxRange(segment.displayRange) <= context.text.utf16.count)
            if let range = segment.sourceRange { #expect(NSMaxRange(range) <= source.utf16.count) }
        }
        let unfinished = "\"" + String(repeating: "x", count: 5000)
        let eof = try #require(JSONProcessor.process(unfinished, operation: .validate).diagnostics.last)
        let eofContext = JSONDiagnosticContext.make(source: unfinished, diagnostic: eof)
        #expect((eofContext.text as NSString).substring(with: eofContext.detectionRange) == "⟂ EOF")
        #expect(eofContext.segments.contains { $0.sourceRange == NSRange(location: unfinished.utf16.count, length: 0) })
        let cluster = "a" + String(repeating: "\u{0301}", count: 2000)
        let region = JSONDiagnostic(severity: .error, code: "TEST", message: "Region", range: NSRange(location: 500, length: 0), line: 1, column: 501)
        let bounded = JSONDiagnosticContext.make(source: cluster, diagnostic: region)
        #expect(bounded.text.utf16.count < 220)
        #expect(bounded.text.contains("long grapheme"))
    }
}
