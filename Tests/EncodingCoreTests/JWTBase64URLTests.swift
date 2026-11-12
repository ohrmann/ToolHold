import Foundation
import Testing
@testable import EncodingCore

struct JWTBase64URLTests {
    @Test func independentVectors() throws {
        for (text, expected) in [("", ""), ("Zg", "f"), ("Zm8", "fo"), ("Zm9v", "foo"), ("eyJhbGciOiJub25lIn0", "{\"alg\":\"none\"}")] {
            #expect(try JWTBase64URLDecoder.decode(text) == Data(expected.utf8))
        }
        #expect(try JWTBase64URLDecoder.decode("-_8") == Data([251,255]))
    }
    @Test(arguments: ["Zg==", "Zm8=", "Z", "Zh", "Zm9", "+w", "/w", " Zg", "Zg\n", "Zg😀", "Zg\u{200B}"])
    func strictRejects(_ text: String) { #expect(throws: JWTBase64URLDecoder.Failure.self) { try JWTBase64URLDecoder.decode(text) } }
    @Test func exactOffsetsAndLimits() {
        do { _ = try JWTBase64URLDecoder.decode("Zg😀"); Issue.record("accepted emoji") }
        catch let error as JWTBase64URLDecoder.Failure { #expect(error.offset == 2); #expect(error.length == 2) } catch { Issue.record("unexpected failure") }
        #expect(throws: JWTBase64URLDecoder.Failure.self) { try JWTBase64URLDecoder.decode("Zg", maximumLength: 1) }
        let base64 = Base64Processor.process("Zg==", options: .init(direction: .decode, alphabet: .urlSafe))
        #expect(base64.artifact?.text == "f") // Existing general policy still accepts padding.
    }
}
