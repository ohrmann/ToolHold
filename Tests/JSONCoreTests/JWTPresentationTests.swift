import Foundation
import Testing
@testable import JSONCore

struct JWTPresentationTests {
    @Test func exactRenderingAndMaps() throws {
        let raw = #"{"a":1.00,"a":-0,"e":1e3,"s":"\u0061","u":"😀é","o":{"b":[]}}"#
        let part = try #require(JWTProcessor.inspect(JWTFixture.token(raw)).parts[.payload])
        let doc = try #require(part.document), pretty = try #require(part.presentation)
        let expected = "{\n  \"a\": 1.00,\n  \"a\": -0,\n  \"e\": 1e3,\n  \"s\": \"\\u0061\",\n  \"u\": \"😀é\",\n  \"o\": {\n    \"b\": []\n  }\n}"
        #expect(pretty.text == expected)
        for node in doc.nodes {
            if node.scalar != nil { #expect((pretty.text as NSString).substring(with: pretty.nodeRanges[node.id]!) == doc.fragment(node.id)) }
            if let key = node.keyRange { #expect((pretty.text as NSString).substring(with: pretty.keyRanges[node.id]!) == (raw as NSString).substring(with: key)) }
        }
        #expect(try JWTJSONPresentation.make(doc, budget: .init(), limit: 10) == nil)
    }
    @Test func decodedCoordinatesAndEOF() throws {
        let raw = "{\r\n\"😀\":\"é\",\r\n\"broken\": "
        let r = JWTProcessor.inspect(JWTFixture.token(raw))
        let issue = try #require(r.issues.first { $0.severity == .error })
        #expect(issue.anchor?.space == .json(.payload))
        #expect(issue.anchor?.range == NSRange(location: raw.utf16.count, length: 0))
        #expect(issue.diagnostic?.line == 3); #expect(issue.context?.text.contains("EOF") == true)
        #expect(issue.related.contains { $0.space == .input })
    }
    @Test @MainActor func exactCopyAndNavigation() async throws {
        let (w, defaults, name) = makeJWTWorkspace(); defer { defaults.removePersistentDomain(forName: name) }
        let raw = #"{"a":"\u0061\/😀","n":99999999999999999999,"a":1,"o":{}}"#
        let token = JWTFixture.token(raw); w.input = "Bearer " + token; await w.run().value
        #expect(w.copy(.token) == token); #expect(w.copy(.raw(.payload)) == raw)
        #expect(w.copy(.value(1)) == "a/😀"); #expect(w.copy(.fragment(1)) == #""\u0061\/😀""#)
        #expect(w.copy(.value(2)) == "99999999999999999999"); #expect(w.copy(.value(4)) == nil)
        w.showClaim(3); #expect(w.section == .payload)
        #expect(w.payloadTarget == w.result?.parts[.payload]?.presentation?.nodeRanges[3])
        w.show(.init(space: .json(.payload), range: .init(location: raw.utf16.count, length: 0)))
        #expect(w.preferences.jsonPresentation == .raw); #expect(w.payloadTarget?.length == 0)
        w.setMasked(true); #expect(w.copy(.raw(.payload)) == nil); #expect(w.payloadTarget == nil)
        w.showClaim(1); #expect(w.payloadTarget == nil)
    }
}

@MainActor func makeJWTWorkspace(worker: (@Sendable (String, JWTBudget) async -> JWTInspectionResult)? = nil) -> (JWTWorkspaceSession, UserDefaults, String) {
    let name = "JWTTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    let w: JWTWorkspaceSession
    if let worker { w = JWTWorkspaceSession(repository: .init(defaults: defaults), worker: worker) }
    else { w = JWTWorkspaceSession(repository: .init(defaults: defaults)) }
    return (w, defaults, name)
}
