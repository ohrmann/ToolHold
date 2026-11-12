import Foundation
import Testing
@testable import JSONCore

enum JWTFixture {
    static func encode(_ text: String) -> String { Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func token(_ payload: String = "{}", header: String = "{\"alg\":\"none\"}", signature: String = "") -> String { encode(header) + "." + encode(payload) + "." + signature }
}
struct JWTProcessorTests {
    @Test func fixedUnsignedAndExactValues() throws {
        let r = JWTProcessor.inspect("eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0.")
        #expect(r.unsigned); #expect(r.trust == "Unsigned token"); #expect(r.parts[.payload]?.document?.nodes[1].scalar == "test")
        let raw = #"{"n":123456789012345678901234567890,"zero":-0,"e":1.2300e+99,"s":"\u0061\/😀","a":[],"o":{}}"#
        let p = try #require(JWTProcessor.inspect(JWTFixture.token(raw)).parts[.payload])
        #expect(p.text == raw); #expect(p.document?.fragment(1) == "123456789012345678901234567890")
        #expect(p.document?.nodes[4].scalar == "a/😀")
        #expect(p.presentation?.text.contains("1.2300e+99") == true)
    }
    // RFC 7519 section 3.1 / RFC 7515 appendix A.1. Decode only, no signature verification.
    @Test func rfc7519CompactExample() throws {
        let token = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let r = JWTProcessor.inspect(token)
        #expect(r.algorithm == "HS256" && r.trust == "Signature not verified")
        #expect(r.profile == .decoded && r.claims.count == 3)
        #expect(r.parts[.signature]?.bytes?.count == 32)
        #expect(r.parts[.payload]?.document?.nodes[2].scalar == "1300819380")
        #expect(r.parts[.header]?.text?.contains("\r\n") == true)
    }
    @Test func envelopesAndSourceOffsets() {
        let token = JWTFixture.token(), r = JWTProcessor.inspect(" \r\nBEARER  " + token + "\t")
        #expect(r.token == token); #expect(r.parts[.header]?.inputRange.location == 11)
        #expect(r.issues.contains { $0.code == "JWT-ENVELOPE" })
        let bad = JWTProcessor.inspect("Bearer Zg=.e30.")
        #expect(bad.issues.first(where: { $0.code == "JWT-BASE64URL" })?.anchor?.range == NSRange(location: 9, length: 1))
        #expect(JWTProcessor.inspect("Bearer ").issues.last?.anchor?.range.length == 0)
    }
    @Test(arguments: ["a", "a.b", "a.b.c.d", "a.b.c.d.e.f", "a.b.c~x", "Authorization: a.b.c", "a. b.c", "a.\u{200B}b.c"])
    func malformed(_ input: String) { #expect(JWTProcessor.inspect(input).profile != .decoded) }
    @Test func unsupportedAndPartial() {
        let jwe = JWTProcessor.inspect("eyJhbGciOiJub25lIn0.a.b.c.d")
        #expect(jwe.representation == .jweCandidate); #expect(jwe.parts[.payload] == nil); #expect(jwe.title.contains("not supported"))
        let partial = JWTProcessor.inspect(JWTFixture.token("{\"bad\":}"))
        #expect(partial.parts[.header]?.document != nil); #expect(partial.parts[.payload]?.document == nil)
        #expect(partial.title.contains("Partially")); #expect(partial.issues.contains { $0.anchor?.space == .json(.payload) })
        for raw in ["[]", "null", "\"text\""] { #expect(JWTProcessor.inspect(JWTFixture.token(raw)).issues.contains { $0.code == "JWT-OBJECT" }) }
    }
    @Test func strictUTF8AndBOM() {
        for (encoded, code) in [("_w", "JWT-UTF8"), (JWTFixture.encode("\u{FEFF}{}"), "JWT-BOM")] {
            let r = JWTProcessor.inspect(JWTFixture.encode("{\"alg\":\"none\"}") + "." + encoded + ".")
            #expect(r.issues.contains { $0.code == code })
        }
        #expect(JWTProcessor.inspect(JWTFixture.token(#"{"s":"\uD800"}"#)).parts[.payload]?.document == nil)
    }
    @Test func algorithmsAndSignatureShape() {
        for (header, signature) in [("{\"alg\":\"none\"}", "AA"), ("{\"alg\":\"HS256\"}", "")] {
            #expect(JWTProcessor.inspect(JWTFixture.token(header: header, signature: signature)).issues.contains { $0.code == "JWT-SIGNATURE-SHAPE" })
        }
        let unknown = JWTProcessor.inspect(JWTFixture.token(header: "{\"alg\":\"CUSTOM\"}", signature: "AA"))
        #expect(unknown.profile == .decoded); #expect(unknown.algorithm == "CUSTOM"); #expect(unknown.trust == "Signature not verified")
        for header in ["{}", "{\"alg\":null}", "{\"alg\":\"\"}"] { #expect(JWTProcessor.inspect(JWTFixture.token(header: header)).issues.contains { $0.code == "JWT-ALG" }) }
    }
    @Test func criticalExtensions() {
        let disabled = JWTProcessor.inspect(JWTFixture.token("not base64", header: #"{"alg":"none","b64":false}"#))
        #expect(disabled.profile == .unsupported); #expect(disabled.parts[.payload]?.text == nil)
        for header in [#"{"alg":"none","crit":[]}"#, #"{"alg":"none","crit":["alg"]}"#, #"{"alg":"none","crit":["x"]}"#, #"{"alg":"none","crit":["x","x"],"x":true}"#] {
            #expect(!JWTProcessor.inspect(JWTFixture.token(header: header)).interpretationAvailable)
        }
        let unsupported = JWTProcessor.inspect(JWTFixture.token(header: #"{"alg":"none","crit":["x"],"x":true}"#))
        #expect(!unsupported.interpretationAvailable)
        #expect(JWTProcessor.inspect(JWTFixture.token(header: #"{"alg":"none","b64":true,"crit":["b64"]}"#)).interpretationAvailable)
        #expect(!JWTProcessor.inspect(JWTFixture.token(header: #"{"alg":"none","cty":"JWT"}"#)).interpretationAvailable)
    }
    @Test func nestedPayloadIsUnsupportedWithoutFalseJSONError() {
        let inner = JWTFixture.token(#"{"sub":"test"}"#)
        let result = JWTProcessor.inspect(JWTFixture.token(inner, header: #"{"alg":"none","cty":"JWT"}"#))
        #expect(result.profile == .unsupported && !result.interpretationAvailable)
        #expect(result.parts[.payload]?.text == inner && result.parts[.payload]?.document == nil)
        #expect(!result.issues.contains { $0.code.hasPrefix("JSON-") })
        let object = JWTProcessor.inspect(JWTFixture.token(#"{"sub":"test"}"#, header: #"{"alg":"none","cty":"JWT"}"#))
        #expect(object.parts[.payload]?.document != nil && object.profile == .unsupported)
    }
    @Test func exactDuplicateIdentityAndAllOccurrences() {
        let r = JWTProcessor.inspect(JWTFixture.token(#"{"exp":0,"\u0065xp":1,"é":2,"é":3,"aud":["a","b"],"custom":{"a":1,"a":2}}"#))
        #expect(r.claims.count == 6); #expect(r.claims[0].ambiguous && r.claims[1].ambiguous)
        #expect(!r.claims[2].ambiguous && !r.claims[3].ambiguous); #expect(r.hasRootDuplicates)
        let header = JWTProcessor.inspect(JWTFixture.token(header: #"{"alg":"none","\u0061lg":"HS256"}"#))
        #expect(header.algorithm == nil); #expect(header.parts[.payload]?.document == nil)
        let many = "{" + (0..<160).map { _ in "\"x\":0" }.joined(separator: ",") + "}"
        let all = JWTProcessor.inspect(JWTFixture.token(many))
        #expect(all.claims.count == 160); #expect(all.claims.allSatisfy { $0.ambiguous }); #expect(all.issues.count <= 100); #expect(all.issueCount > 100)
    }
    @Test func registeredTypesAndEmptyClaims() {
        let r = JWTProcessor.inspect(JWTFixture.token(#"{"iss":null,"sub":1,"jti":false,"exp":"1","nbf":null,"iat":true,"aud":[1]}"#))
        #expect(r.issues.filter { $0.code == "JWT-CLAIM-TYPE" }.count == 7)
        #expect(JWTProcessor.inspect(JWTFixture.token()).claims.isEmpty)
        #expect(JWTProcessor.inspect(JWTFixture.token()).missingTimeClaims == ["exp", "nbf", "iat"])
        #expect(JWTProcessor.inspect(JWTFixture.token(#"{"aud":[]}"#)).issues.contains { $0.code == "JWT-AUDIENCE-EMPTY" })
    }
    @Test func sizeDepthDeadlineAndCancellation() async {
        #expect(JWTProcessor.inspect(String(repeating: "a", count: 262145)).processing == .resourceLimit)
        #expect(JWTProcessor.inspect(String(repeating: "a", count: 262144)).processing != .resourceLimit)
        #expect(JWTProcessor.inspect(JWTFixture.token(), budget: .init(seconds: 0)).processing == .resourceLimit)
        for (depth, status) in [(63, JWTInspectionResult.Processing.completed), (64, .resourceLimit)] {
            let nested = "{\"a\":" + String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth) + "}"
            #expect(JWTProcessor.inspect(JWTFixture.token(nested)).processing == status)
        }
        let task = Task { while !Task.isCancelled { await Task.yield() }; return JWTProcessor.inspect(JWTFixture.token()) }; task.cancel()
        #expect(await task.value.processing == .cancelled)
    }
}
