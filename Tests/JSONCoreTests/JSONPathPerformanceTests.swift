import Foundation
import Testing
import Darwin
@testable import JSONCore

@Suite(.serialized) struct JSONPathPerformanceTests {
    @Test func maximumDocuments() async throws {
        let array = "[" + Array(repeating: "0", count: 131_071).joined(separator: ",") + "]"
        let object = "{" + (0..<24_000).map { "\"k\($0)\":0" }.joined(separator: ",") + "}"
        let deep = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        let long = "[\"" + String(repeating: "x", count: 262_134) + "needle\"]"
        for (name, source, query, count) in [("array-wildcard", array, "$[*]", 131_071),
                                           ("array-filter", array, "$[?@ == 0]", 131_071),
                                           ("object-descendants", object, "$..*", 24_000),
                                           ("depth64", deep, "$..*", 64),
                                           ("long-string", long, "$[?search(@, 'needle')]", 1),
                                           ("array-last", array, "$[-1]", 1)] {
            try await Task.detached {
                #expect(source.utf16.count <= JSONProcessor.maximumUTF16Length)
                let start = ContinuousClock.now
                let document = try #require(JSONProcessor.inspectStructure(source).document)
                let parsed = ContinuousClock.now
                let result = try JSONPathOperations.evaluate(query, in: document)
                let evaluated = ContinuousClock.now
                var presentations: [Int: JSONPathRowData] = [:]
                for id in result.nodeIDs { if presentations[id] == nil { presentations[id] = .make(id, document: document) } }
                let finished = ContinuousClock.now
                #expect(result.nodeIDs.count == count && presentations.count == count)
                var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                print("JSONPATH_BENCH \(name) utf16=\(source.utf16.count) nodes=\(document.nodes.count) results=\(count) parse=\(start.duration(to: parsed)) query=\(parsed.duration(to: evaluated)) previews=\(evaluated.duration(to: finished)) peak=\(usage.ru_maxrss)")
            }.value
        }
    }
}
