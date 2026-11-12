import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif
@testable import JSONCore

struct JSONModelsPerformanceTests {
    @Test func boundedStressSnapshots() throws {
        let cases: [(String, String)] = [
            ("array", "[" + Array(repeating: #"{"id":1,"name":"x"}"#, count: 13_100).joined(separator: ",") + "]"),
            ("wide", "{" + (0..<12_000).map { "\"p\($0)\":0" }.joined(separator: ",") + "}"),
            ("models", "{" + (0..<2_500).map { "\"p\($0)\":{}" }.joined(separator: ",") + "}"),
            ("deep", String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)),
            ("key", "{\"" + String(repeating: "\\n", count: 70_000) + "\":0}")
        ]
        for (name, source) in cases {
            #expect(source.utf16.count <= JSONProcessor.maximumUTF16Length)
            let start = Date.timeIntervalSinceReferenceDate
            let analysis = JSONModelGenerator.analyze(source)
            #expect(analysis.graph != nil)
            let parsed = Date.timeIntervalSinceReferenceDate
            var results: [String] = []
            for language in JSONModelLanguage.allCases {
                let result = JSONModelGenerator.generate(analysis, options: .init(language: language))
                #expect(result.status == .success || result.status == .resourceLimit || result.status == .unsupported)
                #expect((result.artifact?.text.utf16.count ?? 0) <= JSONModelGenerator.maximumOutputLength)
                if result.status != .success { #expect(result.artifact == nil) }
                results.append("\(language.rawValue):\(result.status)")
            }
            var peak: Int64 = 0
            #if canImport(Darwin)
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage); peak = Int64(usage.ru_maxrss)
            #endif
            print("MODELS_STRESS \(name) utf16=\(source.utf16.count) nodes=\(analysis.graph?.document.nodes.count ?? 0) parseInfer=\(parsed-start) render5=\(Date.timeIntervalSinceReferenceDate-parsed) peakBytes=\(peak) \(results.joined(separator: " "))")
        }
    }
}
