import Foundation
import Testing
@testable import JSONEditor

struct YAMLSyntaxLexerTests {
    @Test func keysCommentsQuotedAndBlockScalarsAreOpaque() throws {
        let source = "key: true # [comment]\n\"quoted\": 'value # []'\ntext: |\n  [not structure]\nnumber: 123\nemoji: 😀\n"
        let snapshot = try #require(YAMLSyntaxLexer.scan(source, limit: 262_144))
        #expect(snapshot.partners.isEmpty)
        #expect(snapshot.tokens.filter { $0.kind == .key }.count == 5)
        #expect(snapshot.tokens.filter { $0.kind == .comment }.count == 1)
        #expect(snapshot.tokens.filter { $0.kind == .number }.count == 1)
        #expect(!snapshot.tokens.contains { $0.kind == .bracket })
        for token in snapshot.tokens { #expect(NSMaxRange(token.range) <= source.utf16.count) }
        #expect(snapshot.tokens.contains { token in token.kind == .string && (source as NSString).substring(with: token.range) == "😀" })
    }
    @Test func boundedPartialInputAndNoInventedMatches() async {
        for source in ["'unfinished [", "{a: [1,", "a: \"escape\\", "- yes\n- no", "a: text:with:colons\n"] {
            #expect(YAMLSyntaxLexer.scan(source, limit: 262_144)?.partners.isEmpty == true)
        }
        #expect(YAMLSyntaxLexer.scan(String(repeating: "x", count: 262_145), limit: 262_144) == nil)
        let task = Task.detached { withUnsafeCurrentTask { $0?.cancel() }; return YAMLSyntaxLexer.scan("a: b", limit: 262_144) }
        #expect(await task.value == nil)
    }
}
