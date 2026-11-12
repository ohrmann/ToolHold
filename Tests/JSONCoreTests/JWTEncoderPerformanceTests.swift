import Foundation
import Testing
import Darwin
@testable import JSONCore

struct JWTEncoderPerformanceTests {
    @Test func releaseLimitsAndCryptoPhases() throws {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T078_STRESS"] == "1" else { return }
        let vectors = try JWTEncoderVector.all()
        for vector in vectors {
            var request = vector.request
            request.payload = "{\"s\":\"" + String(repeating: "a", count: 195000) + "\"}"
            let started = ContinuousClock.now
            let result = JWTEncoderProcessor.process(request)
            #expect(result.status == .generated)
            let total = started.duration(to: .now)
            let importStart = ContinuousClock.now, key = try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!)
            let imported = importStart.duration(to: .now), signStart = ContinuousClock.now
            _ = try key.sign(Data(repeating: 65, count: 260000))
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("T078_STRESS alg=\(vector.alg) payloadUTF16=\(request.payload.utf16.count) tokenBytes=\(result.artifact!.byteCount) total=\(total) import=\(imported) signAndSelfCheck=\(signStart.duration(to: .now)) peakBytes=\(usage.ru_maxrss)")
        }
        var request = try #require(vectors.first { $0.alg == "RS256" }).request
        for size in [2048,4096,8192] {
            if size > 2048 { request.key = try JWTEncoderVector.rsa(size) }
            let begin = ContinuousClock.now
            #expect(JWTEncoderProcessor.process(request).status == .generated)
            print("T078_STRESS RSA\(size)=\(begin.duration(to: .now))")
        }
        request = vectors[0].request
        for (label, payload) in [("near-token-cap", "{\"s\":\"" + String(repeating: "a", count: 196400) + "\"}"), ("unicode-inflation", "{\"s\":\"" + String(repeating: "😀", count: 50000) + "\"}"), ("many-fields", "{" + (0..<15000).map { "\"k\($0)\":0" }.joined(separator: ",") + "}"), ("depth64", "{\"a\":" + String(repeating: "[", count: 63) + "0" + String(repeating: "]", count: 63) + "}")] {
            request.payload = payload
            let begin = ContinuousClock.now, result = JWTEncoderProcessor.process(request)
            print("T078_STRESS \(label) payloadUTF16=\(payload.utf16.count) tokenBytes=\(result.artifact?.byteCount ?? 0) status=\(result.status) duration=\(begin.duration(to: .now))")
            #expect(result.status == (label == "unicode-inflation" ? .resourceLimit : .generated))
        }
        request.key = "-----BEGIN PRIVATE KEY-----\n" + String(repeating: "A", count: 65000) + "\n-----END PRIVATE KEY-----"
        request.payload = "{}"; request.header = #"{"alg":"RS256"}"#; request.keyEncoding = .pem
        #expect(JWTEncoderProcessor.process(request).status == .resourceLimit)
    }
}
