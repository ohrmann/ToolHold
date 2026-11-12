import Foundation
import Testing
@testable import JSONCore

struct JWTEncoderProcessorTests {
    func request(_ payload: String = "{}", header: String = #"{"alg":"HS256","typ":"JWT"}"#) -> JWTEncoderRequest {
        .init(header: header, payload: payload, key: String(repeating: "k", count: 32))
    }
    @Test func exactNumbersEscapesOrderAndSerialization() throws {
        let payload = #"{ "z": 900719925474099312345, "a": -0, "e": 1.20e+99, "s": "\u0061\/😀", "nested": [{"x":true}] }"#
        var input = request(payload)
        let result = JWTEncoderProcessor.process(input)
        let token = try #require(result.artifact?.token), decoded = JWTProcessor.inspect(token)
        #expect(decoded.parts[.payload]?.text == #"{"z":900719925474099312345,"a":-0,"e":1.20e+99,"s":"\u0061\/😀","nested":[{"x":true}]}"#)
        input.serialization = .preserve
        let preserved = JWTEncoderProcessor.process(input)
        #expect(JWTProcessor.inspect(try #require(preserved.artifact?.token)).parts[.payload]?.text == payload)
        #expect(input.payload == payload)
    }
    @Test func strictGrammarRootsBomAndAnchors() {
        for source in ["", "[1]", "true", "1", "null", "{\"x\":1,}", "{\"x\":\"\\x\"}", "\u{feff}{}"] {
            let result = JWTEncoderProcessor.process(request(source))
            #expect(result.status == .invalidInput && result.artifact == nil)
            #expect(result.issues.contains { $0.component == .payload && $0.diagnostic != nil })
        }
        let source = "{\r\n\"😀e\u{301}\": 1,\r\n\"a\": "
        let result = JWTEncoderProcessor.process(request(source))
        let anchor = result.issues.first?.diagnostic
        #expect(anchor?.range == NSRange(location: source.utf16.count, length: 0))
        #expect(anchor?.line == 3)
        #expect(anchor?.related.isEmpty == false)
    }
    @Test func duplicateSemanticsAndCapNeverAllowAmbiguity() {
        for text in [#"{"x":1,"x":2}"#, #"{"x":1,"\u0078":2}"#, #"{"a":{"x":1,"x":2}}"#] {
            #expect(JWTEncoderProcessor.process(request(text)).status == .invalidInput)
        }
        #expect(JWTEncoderProcessor.process(request("{\"é\":1,\"e\u{301}\":2}")).status == .generated)
        let many = "{" + (0..<300).map { _ in "\"a\":0" }.joined(separator: ",") + "}"
        let result = JWTEncoderProcessor.process(request(many))
        #expect(result.status == .invalidInput && result.issues.count == 100 && result.issueCount >= 300)
    }
    @Test func algorithmsAndExtensionsAreExplicit() {
        for header in [#"{}"#, #"{"alg":"none"}"#, #"{"alg":1}"#, #"{"alg":"HS256","typ":1}"#, #"{"alg":"HS256","kid":1}"#] {
            #expect(JWTEncoderProcessor.process(request(header: header)).status == .invalidInput)
        }
        for field in [#""crit":[]"#, #""b64":true"#, #""cty":"JWT""#, #""cty":"jwt""#, #""cty":"application/jwt""#, #""jku":"https://example.invalid/key""#, #""jwk":{}"#, #""enc":"x""#] {
            #expect(JWTEncoderProcessor.process(request(header: "{\"alg\":\"HS256\"," + field + "}")).status == .unsupported)
        }
        let header = #"{"alg":"HS256","kid":"opaque","custom":"value"}"#
        #expect(JWTEncoderProcessor.process(request(header: header)).status == .generated)
    }
    @Test func claimsTypesTimeWarningsAndOptionalFields() {
        for payload in [#"{"exp":"1"}"#, #"{"aud":[1]}"#, #"{"iss":2}"#, #"{"jti":false}"#] {
            #expect(JWTEncoderProcessor.process(request(payload)).status == .invalidInput)
        }
        let input = request(#"{"exp":1.5,"nbf":4e99,"iat":3,"aud":[]}"#)
        let result = JWTEncoderProcessor.process(input, now: .init(timeIntervalSince1970: 2))
        #expect(result.status == .generated && result.issues.contains { $0.code == "JWT-TIME-NOTE" })
        #expect(result.issues.contains { $0.code == "JWT-TIME-WINDOW" })
    }
    @Test func checkPasteAndUnsignedNeverSignImplicitly() {
        var input = request(); input.key = ""
        #expect(JWTEncoderProcessor.process(input, mode: .jsonOnly).status == .checked)
        #expect(JWTEncoderProcessor.process(input, mode: .check).issues.contains { $0.code == "KEY-EMPTY" })
        input = request(); #expect(JWTEncoderProcessor.process(input, mode: .check).artifact == nil)
        input.header = #"{"alg":"none"}"#
        #expect(JWTEncoderProcessor.process(input).status == .invalidInput)
        input.unsignedConsent = true
        let result = JWTEncoderProcessor.process(input)
        #expect(result.status == .generated && result.artifact?.token.hasSuffix(".") == true)
        #expect(result.issues.contains { $0.code == "UNSIGNED" })
    }
    @Test func headerIsTheOnlyAlgorithmSourceAndNeverFallsBack() throws {
        var input = request(header: #"{"alg":"HS512","kid":"keep","typ":"custom"}"#)
        input.key = String(repeating: "k", count: 64)
        let result = JWTEncoderProcessor.process(input)
        #expect(result.artifact?.algorithm == .hs512)
        let inspected = JWTProcessor.inspect(try #require(result.artifact?.token))
        #expect(inspected.algorithm == "HS512")
        #expect(inspected.parts[.header]?.text == input.header)
        for value in ["hs256", "HS1024", "", "RS256 "] {
            input.header = "{\"alg\":\"\(value)\"}"
            let failure = JWTEncoderProcessor.process(input)
            #expect(failure.status == .unsupported && failure.artifact == nil)
            #expect(failure.issues.contains { $0.code == "JWT-ALG-UNSUPPORTED" && $0.component == .header && $0.diagnostic != nil })
        }
        for (source, code) in [("{}", "JWT-ALG-MISSING"), (#"{"alg":null}"#, "JWT-ALG-TYPE"), (#"{"alg":"HS256","alg":"HS512"}"#, "JWT-DUPLICATE")] {
            input.header = source
            let failure = JWTEncoderProcessor.process(input)
            #expect(failure.artifact == nil && failure.issues.contains { $0.code == code })
        }
        input.header = #"{"\u0061lg":"\u0048S512"}"#
        #expect(JWTEncoderProcessor.process(input).artifact?.algorithm == .hs512)
        input.header = #"{"alg":"HS512"}"#; input.key = String(repeating: "k", count: 32)
        #expect(JWTEncoderProcessor.process(input).issues.contains { $0.code == "KEY-HMAC-SHORT" })
    }
    @Test func selectorProjectionAndEditPreserveUnrelatedHeaderBytes() throws {
        let source = #"{ "kid":"😀", "\u0061lg" : "HS256", "typ":"custom", "n":1.20e+99 }"#
        let edit = try #require(JWTEncoderProcessor.algorithmEdit(header: source, algorithm: .hs384))
        #expect((source as NSString).substring(with: edit.0) == #""HS256""#)
        let changed = (source as NSString).replacingCharacters(in: edit.0, with: edit.1)
        #expect(changed == source.replacingOccurrences(of: "HS256", with: "HS384"))
        #expect(JWTEncoderProcessor.headerAlgorithm(changed) == .hs384)
        for malformed in ["{", #"{"alg":false}"#, #"{"alg":"future"}"#, #"{"alg":"HS256","\u0061lg":"HS512"}"#] {
            #expect(JWTEncoderProcessor.headerAlgorithm(malformed) == nil)
        }
        let blank = try #require(JWTEncoderProcessor.algorithmEdit(header: " \n", algorithm: .hs384))
        #expect(JWTEncoderProcessor.headerAlgorithm(blank.1) == .hs384)
        #expect(JWTEncoderProcessor.algorithmEdit(header: String(repeating: " ", count: 262145), algorithm: .hs256) == nil)
    }
    @Test func limitsAndDeadlineAreSeparateStatuses() {
        #expect(JWTEncoderProcessor.process(request(String(repeating: " ", count: 262145))).status == .resourceLimit)
        #expect(JWTEncoderProcessor.process(request("{\"a\":\"" + String(repeating: "😀", count: 50000) + "\"}")).status == .resourceLimit)
        #expect(JWTEncoderProcessor.process(request("{\"a\":" + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "}")).status == .resourceLimit)
        #expect(JWTEncoderProcessor.process(request(), budget: .init(seconds: 0)).status == .resourceLimit)
        var input = request(); input.key = String(repeating: "x", count: 65537)
        #expect(JWTEncoderProcessor.process(input).status == .resourceLimit)
        input.key = String(repeating: "x", count: 8193)
        #expect(JWTEncoderProcessor.process(input).status == .resourceLimit)
    }
    @Test func alreadyCancelledTaskNeverPublishesArtifact() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return JWTEncoderProcessor.process(JWTEncoderRequest(header: "{}", payload: "{}"))
        }
        let result = await task.value
        #expect(result.status == .cancelled && result.artifact == nil && result.issues.isEmpty)
    }
    @Test func explicitAlgorithmEditIsPrecise() throws {
        for header in ["{\"alg\":\"HS256\",\"x\":1}", "{ \n }", "{\"x\":1 \n}"] {
            let edit = try #require(JWTEncoderProcessor.algorithmEdit(header: header, algorithm: .rs256))
            let text = (header as NSString).replacingCharacters(in: edit.0, with: edit.1)
            #expect(JSONProcessor.inspectStructure(text).document != nil)
            #expect(text.contains("RS256"))
        }
        #expect(JWTEncoderProcessor.algorithmEdit(header: "{", algorithm: .rs256) == nil)
        #expect(JWTEncoderProcessor.algorithmEdit(header: #"{"alg":"x","alg":"y"}"#, algorithm: .rs256) == nil)
    }
}
