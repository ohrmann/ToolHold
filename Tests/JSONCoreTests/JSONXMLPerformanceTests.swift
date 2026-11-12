import Foundation
import Testing
@testable import JSONCore

struct JSONXMLPerformanceTests {
    @Test func boundedLargeDocuments() {
        let fixtures: [(String, String, JSONXMLDirection, JSONXMLMapping, JSONXMLStatus)] = [
            ("250k text", "<r>" + String(repeating: "x", count: 250_000) + "</r>", .xmlToJSON, .elements, .success),
            ("10000 repeated elements", "<r>" + String(repeating: "<v>0</v>", count: 10_000) + "</r>", .xmlToJSON, .elements, .success),
            ("30000 repeated elements", "<r>" + String(repeating: "<v>0</v>", count: 30_000) + "</r>", .xmlToJSON, .elements, .resourceLimit),
            ("5000 typed values", "[" + Array(repeating: "9007199254740993", count: 5_000).joined(separator: ",") + "]", .jsonToXML, .typed, .success),
            ("bounded XML expansion", "{\"r\":\"" + String(repeating: "&", count: 60_000) + "\"}", .jsonToXML, .elements, .resourceLimit)
        ]
        for (name,source,direction,mapping,status) in fixtures {
            let start = ContinuousClock.now
            let result = JSONXMLConverter.process(source, direction: direction, mapping: mapping)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("XML_BENCH \(name) input=\(source.utf16.count) output=\(result.output?.utf16.count ?? 0) status=\(result.status) elapsed=\(start.duration(to: .now)) peakRSS=\(usage.ru_maxrss)")
            #expect(result.status == status)
        }
    }
}
