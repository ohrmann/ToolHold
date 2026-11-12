import Foundation
import Testing
import Darwin
@testable import EncodingCore

struct URLQueryPerformanceTests {
    @Test func permittedDocumentStress() throws {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T015_STRESS"] == "1" else { return }
        let cases: [(String,String)] = [
            ("empty-segments","?"+String(repeating:"&",count:262_143)),
            ("short-parameters","?"+String(repeating:"a=1&",count:65_535)+"a=1"),
            ("long-value","?q="+String(repeating:"a",count:262_141)),
            ("percent-dense","?q="+String(repeating:"%41",count:87_380)),
            ("unicode-limit","/"+String(repeating:"界",count:262_143))
        ]
        for (name,source) in cases {
            let start = ContinuousClock.now
            let inspection = URLQueryProcessor.inspect(source)
            let parseTime = start.duration(to:.now)
            #expect(inspection.status == .parsed)
            let snapshot = try #require(inspection.snapshot)
            var draft = URLQueryDraft(snapshot)
            let reorderStart = ContinuousClock.now
            if draft.rows.count > 1 { let last = draft.rows.removeLast(); draft.rows.insert(last,at:0) }
            let reorderTime = reorderStart.duration(to:.now)
            let buildStart = ContinuousClock.now
            let result = URLQueryProcessor.build(snapshot,draft:draft)
            let buildTime = buildStart.duration(to:.now)
            #expect(result.status == .parsed)
            var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
            print("T015_STRESS name=\(name) input=\(source.utf16.count) rows=\(snapshot.rows.count) inspect=\(parseTime) reorder=\(reorderTime) build=\(buildTime) preserve=\(result.artifact?.preserve.utf16.count ?? 0) ascii=\(result.artifact?.ascii?.utf16.count ?? 0) peakBytes=\(usage.ru_maxrss)")
        }
    }
}
