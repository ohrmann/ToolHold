import Foundation
import Testing
@testable import JSONCore

struct JSONCSVPerformanceTests {
    @Test func boundedLargeTables() {
        var typed = JSONCSVOptions(); typed.cells = .json
        let fixtures: [(String,String,JSONCSVDirection,JSONCSVOptions)] = [
            ("4000 CSV rows", "id,value\n" + (0..<4_000).map { "\($0),v\($0)" }.joined(separator: "\n"), .toJSON, .init()),
            ("5000 JSON rows", "[" + (0..<5_000).map { "{\"id\":\($0),\"v\":\"text\"}" }.joined(separator: ",") + "]", .toDelimited, typed),
            ("long quoted field", "value\n\"" + String(repeating: "x", count: 250_000) + "\"", .toJSON, .init()),
            ("20000 short records", Array(repeating: "x", count: 20_000).joined(separator: "\n"), .toJSON, { var o = JSONCSVOptions(); o.shape = .arrays; o.hasHeader = false; return o }())]
        for (name,source,direction,options) in fixtures {
            let start = ContinuousClock.now
            let result = JSONCSVConverter.process(source, direction: direction, options: options)
            let elapsed = start.duration(to: .now)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("CSV_BENCH \(name) input=\(source.utf16.count) output=\(result.output?.utf16.count ?? 0) rows=\(result.rowCount) columns=\(result.columnCount) status=\(result.status) elapsed=\(elapsed) peakRSS=\(usage.ru_maxrss)")
            // The last fixture intentionally exceeds the bounded pretty JSON output.
            #expect(name == "20000 short records" ? result.status == .resourceLimit : result.status == .success)
        }
    }
}
