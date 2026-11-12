import Foundation
import Testing
import Darwin
@testable import EncodingCore

struct HexBytesPerformanceTests {
    @Test func boundedStress() async {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T018_STRESS"] == "1" else { return }
        let cases: [(String,String,HexBytesOptions,HexBytesStatus)] = [
            ("compact-max",String(repeating:"41",count:131_072),.init(),.success),
            ("whitespace-max",String(repeating:" \t\r\n",count:65_536),.init(),.success),
            ("nul-dense",String(repeating:"00",count:131_072),.init(),.successWithNotes),
            ("invalid-utf8-end",String(repeating:"41",count:131_071)+"FF",.init(),.bytesOnly),
            ("text-max-ascii",String(repeating:"a",count:262_144),.init(direction:.encode),.resourceLimit),
            ("text-max-three-byte",String(repeating:"\u{4e00}",count:262_144),.init(direction:.encode),.resourceLimit),
            ("compact-output-boundary",String(repeating:"a",count:131_072),.init(direction:.encode,outputFormat:.compact),.success),
            ("spaced-output-boundary",String(repeating:"a",count:87_381),.init(direction:.encode),.success),
            ("bidi-dense",String(repeating:"E280AE",count:43_690),.init(),.successWithNotes)
        ]
        for (name,source,options,status) in cases {
            for intent in [HexBytesIntent.check,.convert] {
                let start = ContinuousClock.now
                let result = HexBytesProcessor.process(source,options:options,intent:intent)
                var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
                #expect(result.status == status)
                #expect(intent != .check || result.artifact == nil)
                print("T018_STRESS name=\(name) intent=\(intent) inputUTF16=\(source.utf16.count) bytes=\(result.byteCount) outputUTF16=\(result.outputCount) elapsed=\(start.duration(to:.now)) peakBytes=\(usage.ru_maxrss)")
            }
        }
        let task = Task.detached { HexBytesProcessor.process(String(repeating:"41",count:131_072)) }
        let start = ContinuousClock.now; task.cancel()
        #expect(await task.value.status == .cancelled)
        print("T018_CANCEL elapsed=\(start.duration(to:.now))")
    }
}
