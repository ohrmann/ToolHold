import Foundation
import Testing
@testable import JSONEditor

struct MarkupSyntaxLexerTests {
    @Test func partialDocumentsUnicodeAndNoInventedPairs() throws {
        for (syntax,source) in [(EditorSyntax.sql,"select '😀é[]' -- unclosed {\r\nfrom t"),(.javascript,"const x = `😀${x}`; /* [ unclosed"),(.css,".a { content: '😀'; --x: ["),(.markup,"<p title='😀'>é</p><!-- {"),(.markdown,"# 😀 heading\n```js\nconst a = 1;")] {
            let result=try #require(MarkupSyntaxLexer.scan(source,syntax:syntax,limit:262144))
            #expect(result.utf16Length == source.utf16.count);#expect(result.partners.isEmpty)
            for t in result.tokens {#expect(t.range.location >= 0);#expect(NSMaxRange(t.range)<=source.utf16.count);#expect(!(source as NSString).substring(with:t.range).contains("�"))}
            #expect(!result.tokens.isEmpty)
        }
    }
    @Test func boundedPresentationAndCancellation() async {
        #expect(MarkupSyntaxLexer.scan(String(repeating:"x",count:262145),syntax:.sql,limit:262144) == nil)
        #expect(MarkupSyntaxLexer.scan(String(repeating:"{}",count:20000),syntax:.css,limit:262144) == nil)
        let task=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return MarkupSyntaxLexer.scan("select a",syntax:.sql,limit:262144)}
        #expect(await task.value == nil)
    }
}
