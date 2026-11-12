import Foundation
import Testing
import Darwin
@testable import JSONCore

@Suite(.serialized) struct JSONDiffPerformanceTests {
    @Test func maximumPairs() async throws {
        let arrayA = "[" + Array(repeating: "0", count: 131_071).joined(separator: ",") + "]"
        let arrayB = "[" + Array(repeating: "1", count: 131_071).joined(separator: ",") + "]"
        let fields = (0..<24_000).map { "\"k\($0)\":0" }
        let object = "{" + fields.joined(separator: ",") + "}"
        let reordered = "{" + fields.reversed().joined(separator: ",") + "}"
        let deep = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        let long = "\"" + String(repeating: "x", count: 262_140) + "a\""
        for (name, left, right, expected) in [
            ("all-array-values", arrayA, arrayB, 131_071),
            ("identical-array", arrayA, arrayA, 0),
            ("reordered-object", object, reordered, 0),
            ("all-object-values", object, object.replacingOccurrences(of: ":0", with: ":1"), 24_000),
            ("depth64", deep, deep.replacingOccurrences(of: "0", with: "1"), 1),
            ("long-string", long, String(long.dropLast(2)) + "b\"", 1)
        ] {
            #expect(left.utf16.count <= JSONProcessor.maximumUTF16Length && right.utf16.count <= JSONProcessor.maximumUTF16Length)
            let count = try await Task.detached { () throws -> Int in
                let start = ContinuousClock.now
                let a = try #require(JSONProcessor.inspectStructure(left).document)
                let b = try #require(JSONProcessor.inspectStructure(right).document)
                let parsed = ContinuousClock.now
                let result = try JSONStructuralDiff.compare(a,b)
                let finished = ContinuousClock.now
                var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                func ms(_ duration: Duration) -> Double { Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15 }
                print("DIFF_BENCH \(name) left_utf16=\(left.utf16.count) right_utf16=\(right.utf16.count) left_nodes=\(a.nodes.count) right_nodes=\(b.nodes.count) changes=\(result.changes.count) parse_pair_ms=\(ms(start.duration(to: parsed))) diff_ms=\(ms(parsed.duration(to: finished))) process_peak_bytes=\(usage.ru_maxrss)")
                return result.changes.count
            }.value
            #expect(count == expected)
        }
    }
}
