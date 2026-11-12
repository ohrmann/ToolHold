import Foundation
import Testing
import Darwin
@testable import JSONCore

@Suite(.serialized)
struct JSONTreePerformanceTests {
    @Test func maximumDocuments() async throws {
        let fixtures: [(String, String)] = [
            ("array", "[" + Array(repeating: "0", count: 131_070).joined(separator: ",") + ",9]"),
            ("object", "{" + (0..<24_000).map { "\"k\($0)\":0" }.joined(separator: ",") + "}"),
            ("depth64", String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)),
            ("longString", "\"" + String(repeating: "x", count: 262_138) + "end\"")
        ]
        for (name, source) in fixtures {
            guard source.utf16.count <= JSONProcessor.maximumUTF16Length else { continue }
            let measurements = try await Task.detached { () throws -> (Int, Double, Double, Double, Int, Int) in
                let start = ContinuousClock.now
                let parsed = JSONProcessor.inspectStructure(source)
                let parseTime = start.duration(to: .now)
                let doc = try #require(parsed.document)
                let projectStart = ContinuousClock.now
                let expanded = Set(doc.nodes.filter(\.canExpand).map(\.id))
                let projection = try JSONTreeOperations.projection(doc, expanded: expanded)
                let projectionTime = projectStart.duration(to: .now)
                let searchStart = ContinuousClock.now
                let hits = try JSONTreeOperations.search(name == "longString" ? "end" : name == "object" ? "k23999" : "9", in: doc)
                let searchTime = searchStart.duration(to: .now)
                func ms(_ duration: Duration) -> Double { Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15 }
                return (doc.nodes.count, ms(parseTime), ms(projectionTime), ms(searchTime), projection.count, hits.count)
            }.value
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("TREE_BENCH \(name) utf16=\(source.utf16.count) nodes=\(measurements.0) parse_ms=\(measurements.1) projection_ms=\(measurements.2) search_ms=\(measurements.3) rows=\(measurements.4) hits=\(measurements.5) process_peak_bytes=\(usage.ru_maxrss)")
        }
    }
}
