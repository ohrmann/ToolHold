import Foundation
import Testing
import Darwin
@testable import JSONCore

struct JWTPerformanceTests {
    @Test func nearLimitDocuments() throws {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T020_STRESS"] == "1" else { return }
        let objects = "{" + (0..<12000).map { "\"k\($0)\":0" }.joined(separator: ",") + "}"
        let cases: [(String, String)] = [
            ("ordinary", "{\"sub\":\"test\",\"exp\":1700000000}"),
            ("12000-claims", objects),
            ("long-string", "{\"s\":\"" + String(repeating: "a", count: 190000) + "\"}"),
            ("depth64", "{\"a\":" + String(repeating: "[", count: 63) + "0" + String(repeating: "]", count: 63) + "}"),
            ("huge-exponent", "{\"exp\":1e" + String(repeating: "9", count: 190000) + "}"),
            ("late-error", "{\"s\":\"" + String(repeating: "a", count: 190000) + "\""),
        ]
        for (name, payload) in cases {
            let source = JWTFixture.token(payload), begin = ContinuousClock.now
            let result = JWTProcessor.inspect(source)
            let inspected = begin.duration(to: .now)
            let timeStart = ContinuousClock.now; _ = JWTNumericDate.evaluate(result)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("T020_STRESS case=\(name) inputUTF16=\(source.utf16.count) claims=\(result.claims.count) inspect=\(inspected) time=\(timeStart.duration(to: .now)) peakBytes=\(usage.ru_maxrss)")
            #expect(source.utf16.count < 262144 && result.processing == .completed)
            if name != "late-error" { #expect(result.parts[.payload]?.document != nil) }
            #expect(inspected < .seconds(3))
        }
    }
}
