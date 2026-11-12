import Foundation
import Testing
@testable import JSONCore

struct JWTNumericDateTests {
    @Test func exactBoundariesAndFractions() {
        let r = JWTProcessor.inspect(JWTFixture.token(#"{"exp":1000,"nbf":1000,"iat":1000.00000000000000001}"#))
        let e = JWTNumericDate.evaluate(r, now: Date(timeIntervalSince1970: 1000))
        #expect(e.values[1]?.status == "Expired"); #expect(e.values[2]?.status == "Not-before time reached")
        #expect(e.values[3]?.status == "Issued in the future"); #expect(e.notes.contains { $0.contains("empty time window") })
        #expect(e.evaluatedAt.contains("millisecond precision"))
        let negative = JWTProcessor.inspect(JWTFixture.token(#"{"exp":-0,"nbf":-1.2e3,"iat":-0.0000001}"#))
        let n = JWTNumericDate.evaluate(negative, now: Date(timeIntervalSince1970: -1))
        #expect(n.values[1]?.status == "Expiration is in the future"); #expect(n.values[3]?.status == "Issued in the future")
    }
    @Test func hugeNumbersAndNoMillisecondGuessing() {
        let r = JWTProcessor.inspect(JWTFixture.token(#"{"exp":1e9999999999999999999,"nbf":1e-9999999999999999999,"iat":1700000000000}"#))
        let e = JWTNumericDate.evaluate(r, now: .init(timeIntervalSince1970: 1000))
        #expect(e.values[1]?.status == "Expiration is in the future"); #expect(e.values[2]?.status == "Not-before time reached")
        #expect(e.values[3]?.status == "Issued in the future"); #expect(e.values[3]?.date.contains("Outside date display range") == true)
    }
    @Test func zonesDSTAndExactLexeme() {
        let r = JWTProcessor.inspect(JWTFixture.token(#"{"exp":1711846800.1234567}"#))
        let e = JWTNumericDate.evaluate(r, now: .init(timeIntervalSince1970: 0), local: true, zone: TimeZone(identifier: "Europe/Prague")!)
        #expect(e.values[1]?.date.contains("Europe/Prague") == true); #expect(e.values[1]?.date.contains("+02:00") == true)
        #expect(r.claims[0].numericDate == "1711846800.1234567")
        #expect(JWTNumericDate.evaluate(r, now: .init(timeIntervalSince1970: 0)).values[1]?.date.contains("GMT") == true)
    }
    @Test func ambiguousAndUnsupportedNeverChooseDate() {
        let r = JWTProcessor.inspect(JWTFixture.token(#"{"exp":0,"exp":9999999999}"#))
        let e = JWTNumericDate.evaluate(r, now: .now)
        #expect(e.values.values.allSatisfy { $0.status == "Ambiguous" }); #expect(e.notes.isEmpty)
        let unsupported = JWTProcessor.inspect(JWTFixture.token(#"{"exp":0}"#, header: #"{"alg":"none","crit":["x"],"x":true}"#))
        #expect(JWTNumericDate.evaluate(unsupported).values[1]?.status == "Interpretation unavailable")
    }
}
