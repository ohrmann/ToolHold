import Foundation
import Testing
@testable import JSONCore

struct JSONTOMLPerformanceTests {
    @Test func boundedLargeConfigurations() {
        let fixtures: [(String, String, JSONTOMLDirection, JSONTOMLStatus)] = [
            ("250k string", "text='" + String(repeating: "x", count: 250_000) + "'", .tomlToJSON, .success),
            ("10000 fields", (0..<10_000).map { "k\($0)=\($0)" }.joined(separator: "\n"), .tomlToJSON, .success),
            ("30000 array values", "values=[" + Array(repeating: "0", count: 30_000).joined(separator: ",") + "]", .tomlToJSON, .success),
            ("40000 expanded values", "values=[" + Array(repeating: "0", count: 40_000).joined(separator: ",") + "]", .tomlToJSON, .resourceLimit),
            ("10000 JSON fields", "{" + (0..<10_000).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}", .jsonToTOML, .success)
        ]
        for (name,source,direction,status) in fixtures {
            let start = ContinuousClock.now
            let result = JSONTOMLConverter.process(source, direction: direction)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("TOML_BENCH \(name) input=\(source.utf16.count) output=\(result.output?.utf16.count ?? 0) status=\(result.status) elapsed=\(start.duration(to: .now)) peakRSS=\(usage.ru_maxrss)")
            #expect(result.status == status)
        }
    }
}
