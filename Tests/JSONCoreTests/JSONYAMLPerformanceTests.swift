import Foundation
import Testing
@testable import JSONCore

struct JSONYAMLPerformanceTests {
    @Test func boundedLargeConversions() throws {
        let fixtures: [(String,JSONYAMLDirection,String)] = [
            ("array", .jsonToYAML, "[" + Array(repeating: "0", count: 50_000).joined(separator: ",") + "]"),
            ("object", .yamlToJSON, (0..<9_000).map { "key\($0): \($0)" }.joined(separator: "\n")),
            ("long scalar", .yamlToJSON, "key: " + String(repeating: "x", count: 250_000)),
            ("depth64", .yamlToJSON, String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64))]
        for (name,direction,source) in fixtures {
            let start = ContinuousClock.now
            let result = JSONYAMLConverter.process(source, direction: direction)
            let time = start.duration(to: .now)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("YAML_BENCH \(name) input=\(source.utf16.count) output=\(result.output?.utf16.count ?? 0) elapsed=\(time) peakRSS=\(usage.ru_maxrss)")
            #expect(result.status == .success)
        }
    }
}
