import Foundation
import Testing
@testable import JSONEditor

struct JSONSyntaxLexerTests {
    @Test func tokenKindsAndExactUnicodeRanges() throws {
        let source = #"{"😀":"é \uD83D\uDE00 \"[]\"","n":-1.2300E+999,"a":[true,false,null]}"#
        let snapshot = try #require(JSONSyntaxLexer.scan(source))
        let text = source as NSString
        func values(_ kind: JSONSyntaxKind) -> [String] {
            snapshot.tokens.filter { $0.kind == kind }.map { text.substring(with: $0.range) }
        }
        #expect(values(.key) == [#""😀""#, #""n""#, #""a""#])
        #expect(values(.string) == [#""é \uD83D\uDE00 \"[]\"""#])
        #expect(values(.number) == ["-1.2300E+999"])
        #expect(values(.literal) == ["true", "false", "null"])
        #expect(values(.bracket) == ["{", "[", "]", "}"])
        #expect(values(.separator).count == 7)
        #expect(snapshot.utf16Length == source.utf16.count)
        for (offset, partner) in snapshot.partners {
            #expect(snapshot.partners[partner] == offset)
            let opening = min(offset, partner), closing = max(offset, partner)
            #expect(["{}", "[]"].contains(text.substring(with: NSRange(location: opening, length: 1)) + text.substring(with: NSRange(location: closing, length: 1))))
        }
    }

    @Test func nestedPairsAndCaretPriority() throws {
        let source = #"[{"x":[]}]"#
        let snapshot = try #require(JSONSyntaxLexer.scan(source))
        let braces = snapshot.tokens.filter { $0.kind == .bracket }
        #expect(braces.map(\.depth) == [0, 1, 2, 2, 1, 0])
        #expect(snapshot.matchingRanges(at: NSRange(location: 0, length: 0)) == [NSRange(location: 0, length: 1), NSRange(location: 9, length: 1)])
        #expect(snapshot.matchingRanges(at: NSRange(location: 8, length: 0)) == [NSRange(location: 7, length: 1), NSRange(location: 6, length: 1)])
        #expect(snapshot.matchingRanges(at: NSRange(location: 2, length: 3)).isEmpty)
        #expect(snapshot.matchingRanges(at: NSRange(location: NSNotFound, length: 0)).isEmpty)
    }

    @Test(arguments: ["{[}]", "[{]}", #"{"a":[1}]}"#, #"{"a":"unclosed [ ] }"#, #"{'[fake]':1}"#, "{“[fake]”:1}"])
    func malformedStructureNeverInventsPairs(_ source: String) throws {
        let snapshot = try #require(JSONSyntaxLexer.scan(source))
        #expect(snapshot.partners.isEmpty)
        #expect(snapshot.tokens.filter { $0.kind == .bracket }.allSatisfy { $0.depth == nil })
    }

    @Test func partialInputAndIndependentBalancedRegions() throws {
        let snapshot = try #require(JSONSyntaxLexer.scan(#"{ "x": [1,] "y": tru, "n": 1e+ "z": "partial"#))
        #expect(snapshot.partners.count == 2) // [1,] is a structural pair, not a validity claim
        #expect(snapshot.tokens.contains { $0.kind == .number })
        #expect(snapshot.tokens.last?.kind == .string)
        let later = try #require(JSONSyntaxLexer.scan("{[}] []"))
        #expect(later.partners == [5: 6, 6: 5])
    }

    @Test func escapedBackslashAndQuotesAreNotStructuralBrackets() throws {
        for source in [#"["\\", "\"[]\"", "\\\"{}"]"#, "[\r\n\"😀\",\r\n\"é\"]"] {
            let snapshot = try #require(JSONSyntaxLexer.scan(source))
            #expect(snapshot.partners == [0: source.utf16.count - 1, source.utf16.count - 1: 0])
        }
    }

    @Test func limitsCancellationAndLongSingleLine() async throws {
        let long = #"{"x":""# + String(repeating: "😀é", count: 20_000) + #""}"#
        let snapshot = try #require(JSONSyntaxLexer.scan(long))
        #expect(snapshot.tokens.count == 5)
        #expect(snapshot.partners[0] == long.utf16.count - 1)
        #expect(JSONSyntaxLexer.scan(String(repeating: "x", count: 262_145)) == nil)
        #expect(JSONSyntaxLexer.scan(String(repeating: "[]", count: JSONSyntaxLexer.maximumTokens)) == nil)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return JSONSyntaxLexer.scan("{}")
        }
        #expect(await task.value == nil)
    }

    @Test func tokenLookupOnlyIntersectsRequestedRange() throws {
        let snapshot = try #require(JSONSyntaxLexer.scan("[ 1, true, null ]"))
        let range = NSRange(location: 5, length: 4)
        let indices = snapshot.tokenIndices(intersecting: range)
        #expect(Array(indices).count == 1)
        #expect(snapshot.tokens[indices.lowerBound].kind == .literal)
        #expect(snapshot.tokenIndices(intersecting: NSRange(location: 1, length: 1)).isEmpty)
    }
}
