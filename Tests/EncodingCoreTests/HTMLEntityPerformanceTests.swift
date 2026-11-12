import Foundation
import Testing
import Darwin
@testable import EncodingCore

struct HTMLEntityPerformanceTests {
    @Test func boundedStress() async {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T016_STRESS"] == "1" else { return }
        let cold = ContinuousClock.now
        _ = HTMLEntityTable.entries.count; _ = HTMLEntityTable.names.count
        print("T016_TABLE_INIT duration=\(cold.duration(to:.now))")
        let cases: [(String,String,HTMLEntityOptions,HTMLEntityStatus)] = [
            ("literal",String(repeating:"a",count:262_144),.init(),.success),
            ("entity-dense",String(repeating:"&amp;",count:52_428),.init(direction:.decode),.success),
            ("unknown-name","&"+String(repeating:"z",count:262_142)+";",.init(direction:.decode),.successWithWarnings),
            ("numeric-run","&#"+String(repeating:"9",count:262_141)+";",.init(direction:.decode),.successWithWarnings),
            ("mixed-unicode",String(repeating:"é😀e\u{301}",count:43_690),.init(),.success),
            ("expansion-refusal",String(repeating:"😀",count:131_072),.init(scope:.nonASCII,notation:.hexadecimal),.resourceLimit)
        ]
        for (name,source,options,status) in cases {
            let start = ContinuousClock.now
            let result = HTMLEntityProcessor.process(source,options:options)
            var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
            #expect(result.status == status)
            print("T016_STRESS name=\(name) inputUTF16=\(source.utf16.count) outputUTF16=\(result.outputCount) elapsed=\(start.duration(to:.now)) peakBytes=\(usage.ru_maxrss)")
        }
        let task = Task.detached { HTMLEntityProcessor.process("&#"+String(repeating:"9",count:262_141)+";",options:.init(direction:.decode)) }
        let start = ContinuousClock.now; task.cancel()
        #expect(await task.value.status == .cancelled)
        print("T016_CANCEL elapsed=\(start.duration(to:.now))")
    }
}
