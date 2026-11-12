import Foundation
import Testing
@testable import EncodingCore

struct BasicAuthProcessorTests {
    private func build(_ user: String, _ password: String, _ options: BasicAuthOptions = .init(), _ limits: BasicAuthLimits = .init()) -> BasicAuthResult {
        BasicAuthProcessor.build(.init(username: user, password: password, options: options), limits: limits)
    }
    @Test func independentRFCVectorsAndHeaderForms() {
        let r = build("Aladdin", "open sesame")
        #expect(r.status == .success)
        #expect(r.artifact?.fullHeader == "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
        #expect(build("test", "123£").artifact?.headerValue == "Basic dGVzdDoxMjPCow==")
        #expect(build("test", "123£", .init(encoding: .latin1)).artifact?.headerValue == "Basic dGVzdDoxMjOj")
        #expect(r.credentialByteCount == 19)
    }
    @Test func emptyFieldsAndPasswordColons() {
        #expect(build("", "").artifact?.headerValue == "Basic Og==")
        #expect(build("", "").issues.first?.code == .empty)
        #expect(build("user", "").artifact?.headerValue == "Basic dXNlcjo=")
        #expect(build("", "pass").artifact?.headerValue == "Basic OnBhc3M=")
        #expect(build("a", "b:c").artifact?.headerValue == "Basic YTpiOmM=")
        let bad = build("a:b", "c")
        #expect(bad.status == .invalidCredentials && bad.artifact == nil)
        #expect(bad.issues.first?.originalUTF16Range == NSRange(location: 1, length: 1))
    }
    @Test(arguments: ["\u{0}", "\t", "\n", "\r", "\u{1F}", "\u{7F}"])
    func controlsHaveOriginalFieldRanges(_ control: String) {
        for field in [BasicAuthField.username, .password] {
            let r = build(field == .username ? "😀e\u{301}" + control : "safe", field == .password ? "😀e\u{301}" + control : "safe")
            #expect(r.status == .invalidCredentials && r.artifact == nil)
            #expect(r.issues.first?.field == field)
            #expect(r.issues.first?.originalUTF16Range == NSRange(location: 4, length: 1))
            #expect(r.issues.first?.message.contains("safe") == false)
        }
    }
    @Test func preservesWhitespaceAndInvisibleCharacters() throws {
        let user = " a\u{A0} ", pass = " b  \u{200F}\u{85} "
        let r = build(user, pass)
        let encoded = try #require(r.artifact?.headerValue.dropFirst(6))
        #expect(Data(base64Encoded: String(encoded)) == Data((user + ":" + pass).utf8))
        #expect(r.issues.contains { $0.code == .boundarySpaces })
        #expect(r.issues.contains { $0.code == .invisible })
        #expect(r.issues.allSatisfy { !$0.isError })
        #expect(!BasicAuthProcessor.passwordPreview(pass).contains("\u{200F}"))
    }
    @Test func exactUnicodeAndExplicitNFC() {
        let composed = build("é", "😀"), decomposed = build("e\u{301}", "😀")
        #expect(composed.artifact?.headerValue != decomposed.artifact?.headerValue)
        let nfc = build("e\u{301}", "😀", .init(normalizeNFC: true))
        #expect(nfc.artifact?.headerValue == composed.artifact?.headerValue)
        #expect(nfc.issues.contains { $0.code == .normalized })
        let latin = build("", "é", .init(encoding: .latin1, normalizeNFC: true))
        #expect(latin.artifact?.headerValue == "Basic Ouk=")
        #expect(!latin.issues.contains { $0.code == .normalized })
    }
    @Test(arguments: ["€", "😀", "e\u{301}"])
    func latin1DoesNotRepair(_ source: String) {
        let r = build("u", source, .init(encoding: .latin1))
        #expect(r.status == .unrepresentableText && r.artifact == nil)
        #expect(r.issues.first?.field == .password)
        #expect(r.issues.first?.originalUTF16Range != nil)
        #expect(r.issues.first?.message.contains(source) == false)
    }
    @Test func limitsIncludeSeparatorExpansionAndPrefix() {
        #expect(build("a", "b", .init(), .init(inputUTF16: 3)).status == .success)
        #expect(build("a", "b", .init(), .init(inputUTF16: 2)).status == .resourceLimit)
        #expect(build("a", "bc", .init(), .init(inputUTF16: 3)).status == .resourceLimit)
        #expect(build("é", "", .init(), .init(bytes: 3)).status == .success)
        #expect(build("é", "", .init(), .init(bytes: 2)).status == .resourceLimit)
        #expect(build("a", "b", .init(), .init(fullHeaderUTF16: 25)).status == .success)
        #expect(build("a", "b", .init(), .init(fullHeaderUTF16: 24)).issues.first?.code == .outputLimit)
        #expect(build("a", "bc", .init(), .init(fullHeaderUTF16: 28)).status == .resourceLimit)
        #expect(build("a", "bc", .init(), .init(fullHeaderUTF16: 29)).status == .success)
        #expect(build("", "").artifact?.fullHeader.count == 25)
        #expect(build("", "", .init(), .init(inputUTF16: 0)).status == .resourceLimit)
    }
    @Test func nearLimitAndCancelled() async {
        #expect(build(String(repeating: "a", count: 196_589), "").artifact?.fullHeader.count == 262_141)
        #expect(build(String(repeating: "a", count: 196_590), "").issues.first?.code == .outputLimit)
        #expect(build(String(repeating: "😀", count: 65_536), "").status == .resourceLimit)
        let task = Task { () -> BasicAuthResult in
            while !Task.isCancelled { await Task.yield() }
            return build("user", "synthetic")
        }
        task.cancel(); #expect(await task.value.status == .cancelled)
    }
    @Test func previewIsBoundedEvenForOneHugeGrapheme() {
        let source = "a" + String(repeating: "\u{301}", count: 260_000)
        #expect(BasicAuthProcessor.passwordPreview(source).utf16.count == 513)
        #expect(BasicAuthProcessor.inputIssue(String(repeating: "a", count: 262_145), field: .password)?.code == .inputLimit)
        #expect(BasicAuthProcessor.passwordPreview("\u{202E}x") == "\\u{202E}x")
    }
    @Test func standardAlphabetPaddingAndNoLineBreaks() throws {
        let r = build("\u{FF}", "\u{FF}", .init(encoding: .latin1))
        #expect(r.artifact?.headerValue == "Basic /zr/")
        let text = try #require(build("x", String(repeating: "a", count: 200)).artifact?.fullHeader)
        #expect(!text.contains("\n") && !text.contains("\r") && !text.contains("charset"))
    }
}
