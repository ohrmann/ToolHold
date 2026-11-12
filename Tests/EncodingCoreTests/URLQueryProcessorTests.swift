import Foundation
import Testing
@testable import EncodingCore

struct URLQueryProcessorTests {
    private func parsed(_ source: String, _ profile: URLQueryProfile = .percent) throws -> URLQuerySnapshot {
        let result = URLQueryProcessor.inspect(source,profile:profile)
        #expect(result.status == .parsed, "\(result.issues.map(\.code))")
        return try #require(result.snapshot)
    }
    @Test func exactRoundTripsAndComponentBoundaries() throws {
        for source in ["https://EXAMPLE.com:00080/a/../b?x=%2f&x=%41#", "/p", "/p?", "/p#", "/p?#", "?", "#", "?a=b=c&&flag&empty=&=v&=&", "../path?x=/?:@!$'()*+,;#f", "//h:999999999999999999/p?x=1", "urn:abc:def?x=%FF", "http://[::1]:80/a?x=1", "http://[v1.foo]/", "http://[fe80::1%25en0]/", "http://%65xample.com:00000080/%2f"] {
            let value = try parsed(source)
            let built = URLQueryProcessor.build(value,draft:.init(value))
            #expect(built.status == .parsed)
            #expect(built.artifact?.preserve.utf16.elementsEqual(source.utf16) == true)
            #expect(built.artifact?.ascii == source)
        }
        let snapshot = try parsed("https://u:p@h:80/path?q=a?b#f?x")
        #expect(snapshot.slice(snapshot.components.userinfo) == "u:p")
        #expect(snapshot.slice(snapshot.components.query) == "q=a?b")
        #expect(snapshot.slice(snapshot.components.fragment) == "f?x")
    }
    @Test func orderedOccurrencesAndSinglePassProfiles() throws {
        let source = "?flag&empty=&=value&=&x=a+b&y=a%20b&z=%2B&x=%2520&&"
        let p = try parsed(source), f = try parsed(source,.form)
        #expect(p.rows.count == 10 && Set(p.rows.map(\.id)).count == 10)
        #expect(p.rows[0].rawValue == nil && p.rows[1].value == "")
        #expect(p.rows[2].name == "" && p.rows[2].value == "value")
        #expect(p.rows[4].value == "a+b" && f.rows[4].value == "a b")
        #expect(p.rows[6].value == "+" && f.rows[6].value == "+")
        #expect(p.rows[7].value == "%20")
        #expect(p.rows[8].rawValue == nil && p.rows[9].rawValue == nil)
        let split = try parsed("?x=%26%3D%23&y=a=b;c")
        #expect(split.rows[0].value == "&=#" && split.rows[1].value == "a=b;c")
    }
    @Test func UnicodeIDNAAndSourceMap() throws {
        let source = "https://例え.テスト/путь?q=😀#раздел"
        let snapshot = try parsed(source)
        #expect(snapshot.components.asciiHost == "xn--r8jz45g.xn--zckzah")
        #expect(snapshot.rows[0].value == "😀")
        let result = try #require(URLQueryProcessor.build(snapshot,draft:.init(snapshot)).artifact)
        #expect(result.preserve.utf16.elementsEqual(source.utf16))
        #expect(result.ascii == "https://xn--r8jz45g.xn--zckzah/%D0%BF%D1%83%D1%82%D1%8C?q=%F0%9F%98%80#%D1%80%D0%B0%D0%B7%D0%B4%D0%B5%D0%BB")
        for source in ["/é?q=e\u{301}%2f😀", "//例え.テスト./", "https://faß.de/", "https://xn--r8jz45g.xn--zckzah/", "http://%E4%BE%8B%E3%81%88.%E3%83%86%E3%82%B9%E3%83%88/", "custom://пример/é?q=x"] {
            let snapshot = try parsed(source)
            #expect(URLQueryProcessor.build(snapshot,draft:.init(snapshot)).artifact?.preserve.utf16.elementsEqual(source.utf16) == true)
        }
        let reference = try URLReferenceAdapter.capture("https://例え.テスト/😀")
        let host = try #require(reference.mapping.first { !$0.exact })
        #expect(reference.sourceRegion(for:.init(location:host.derived.location+1,length:1)) == host.source)
        #expect(reference.mapping.count < 8)
        #expect(try URLReferenceAdapter.capture("/abc").sourceRegion(for:.init(location:2,length:1)) == .init(location:2,length:1))
        let nfd = try parsed("/e\u{301}")
        #expect(URLQueryProcessor.build(nfd,draft:.init(nfd)).artifact?.ascii == "/e%CC%81")
        #expect(try URLReferenceAdapter.capture("custom://пример/").ascii == "custom://%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/")
        #expect(try URLReferenceAdapter.capture("custom://é/").components.asciiHost == "%C3%A9")
    }
    @Test func malformedInputAndTrustworthyAnchors() throws {
        for source in ["https://h/a b", "https://h/\\", "http://[::1", "https:///path", "1abc:path", "http://h:abc/", "http://xn--invalid-/", "http://a\u{200D}b.com/", "http://%2Fh/", "/" + String(UnicodeScalar(0xFDD0)!), "/\u{E000}", "?q=\n"] {
            let result = URLQueryProcessor.inspect(source)
            #expect(result.status == .invalidSyntax,"\(source) \(result.issues)")
            #expect(result.snapshot == nil)
        }
        let input = "https://h/😀?x=%A#f"
        let error = URLQueryProcessor.inspect(input).issues.first
        #expect(error?.code == "escapeEOF")
        #expect(error?.range == NSRange(location:(input as NSString).range(of:"#").location,length:0))
        #expect(URLQueryProcessor.inspect("?x=%G0").issues.first?.range == .init(location:3,length:3))
        #expect(URLQueryProcessor.inspect("?x=\u{E000}").status == .parsed)
        #expect(URLQueryProcessor.inspect("").status == .ready)
        #expect(!URLQueryProcessor.inspect("http://h:00000080/").issues.contains { $0.code == "portRange" })
    }
    @Test func bytesOnlyFieldsAreNotRepaired() throws {
        let snapshot = try parsed("?%FF=%C0%AF&x=%ED%A0%80&good=%F0%9F%98%80")
        #expect(snapshot.rows[0].rawOnlyName && snapshot.rows[0].rawOnlyValue)
        #expect(snapshot.rows[1].rawOnlyValue)
        #expect(snapshot.rows[2].value == "😀")
        #expect(snapshot.issues.contains { $0.code == "rawOnly" })
        #expect(URLQueryProcessor.build(snapshot,draft:.init(snapshot)).artifact?.preserve == snapshot.source)
    }
    @Test func mutationsPreserveUnchangedFieldsAndEncodeNewValues() throws {
        for profile in URLQueryProfile.allCases {
            let snapshot = try parsed("https://h/a?%61=%2f&tag=2#é",profile)
            var draft = URLQueryDraft(snapshot)
            draft.rows[0].changedValue = "a b+&=#😀"
            draft.rows.swapAt(0,1)
            let built = try #require(URLQueryProcessor.build(snapshot,draft:draft).artifact)
            let expected = profile == .percent ? "a%20b%2B%26%3D%23%F0%9F%98%80" : "a+b%2B%26%3D%23%F0%9F%98%80"
            #expect(built.preserve == "https://h/a?tag=2&%61="+expected+"#é")
            #expect(built.ascii?.hasSuffix("#%C3%A9") == true)
            draft.rows.removeAll()
            #expect(URLQueryProcessor.build(snapshot,draft:draft).artifact?.preserve == "https://h/a?#é")
            draft.queryPresent = false
            #expect(URLQueryProcessor.build(snapshot,draft:draft).artifact?.preserve == "https://h/a#é")
        }
    }
    @Test func budgetsAndPartialASCIIResourceOutcome() throws {
        #expect(URLQueryProcessor.inspect(String(repeating:"a",count:32),limits:.init(input:31)).status == .resourceLimit)
        #expect(URLQueryProcessor.inspect(String(repeating:"a",count:32),limits:.init(input:32)).status == .parsed)
        let snapshot = try parsed("/"+String(repeating:"界",count:100))
        let result = URLQueryProcessor.build(snapshot,draft:.init(snapshot),limits:.init(output:110))
        #expect(result.status == .parsed && result.artifact?.preserve == snapshot.source)
        #expect(result.artifact?.ascii == nil && result.artifact?.asciiIssue?.code == "asciiLimit")
        #expect(URLQueryProcessor.inspect(snapshot.source,limits:.init(validation:100)).status == .resourceLimit)
        var draft = URLQueryDraft(snapshot); draft.queryPresent = true
        draft.rows = [.init(id:0,rawName:"",rawValue:"",name:"",value:"",changedValue:String(repeating:" ",count:200))]
        #expect(URLQueryProcessor.build(snapshot,draft:draft,limits:.init(output:300)).status == .resourceLimit)
    }
    @Test func generatedLosslessPropertyFixtures() throws {
        let chunks = ["a", "%2f", "%41", "é", "e\u{301}", "😀", "", "a=b", "%FF", "+"]
        for a in chunks { for b in chunks {
            let source = "/p?"+a+"="+b+"&&flag#é"
            let snapshot = try parsed(source)
            #expect(URLQueryProcessor.build(snapshot,draft:.init(snapshot)).artifact?.preserve.utf16.elementsEqual(source.utf16) == true)
        } }
    }
    @Test func cancellationNeverPublishesPartialSnapshot() async {
        let task = Task.detached { () -> URLQueryInspection in
            while !Task.isCancelled { await Task.yield() }
            return URLQueryProcessor.inspect("?a=1")
        }
        task.cancel(); let result = await task.value
        #expect(result.status == .cancelled && result.snapshot == nil)
    }
}
