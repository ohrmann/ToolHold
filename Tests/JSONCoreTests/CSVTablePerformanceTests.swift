import Foundation
import Testing
@testable import JSONCore

struct CSVTablePerformanceTests {
    @Test func maximumTallWideAndRaggedSnapshots() throws {
        let fixtures = [
            ("262144 blank records", String(repeating: "\n", count: 262144), 262144, 1),
            ("131073 columns", String(repeating: "x,", count: 131072), 1, 131073),
            ("12000 ten-column records", Array(repeating: "1,2,3,4,5,6,7,8,9,10", count: 12000).joined(separator: "\n"), 12000, 10),
            ("ragged avoids Cartesian matrix", String(repeating: ",", count: 10000) + String(repeating: "\nx", count: 10000), 10001, 10001)
        ]
        for (name, source, rows, columns) in fixtures {
            let start = ContinuousClock.now
            let result = CSVTableProcessor.build(source, hasHeader: false)
            let document = try #require(result.document)
            let built = ContinuousClock.now
            let projection = try CSVTableProcessor.project(document, query: "x", sort: .init(column: 0, ascending: true))
            let finished = ContinuousClock.now
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("TABLE_BENCH \(name) utf16=\(source.utf16.count) rows=\(document.rowCount) columns=\(document.columnCount) cells=\(document.table.cells.count) matchedRows=\(projection.rows.count) build=\(start.duration(to: built)) filterSort=\(built.duration(to: finished)) peakRSS=\(usage.ru_maxrss)")
            #expect(result.status == .success && document.rowCount == rows && document.columnCount == columns)
        }
    }
}
