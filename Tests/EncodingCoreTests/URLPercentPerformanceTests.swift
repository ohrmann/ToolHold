import Foundation
import Testing
import Darwin
@testable import EncodingCore

struct URLPercentPerformanceTests {
    @Test func boundedStress() async {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T014_STRESS"] == "1" else { return }
        let cases: [(String,String,URLPercentDirection,URLPercentStatus)] = [
            ("ascii",String(repeating:"a",count:262_144),.encode,.success),
            ("spaces-max",String(repeating:" ",count:87_381),.encode,.success),
            ("spaces-over",String(repeating:" ",count:87_382),.encode,.resourceLimit),
            ("unicode",String(repeating:"界",count:29_127),.encode,.success),
            ("percent-dense",String(repeating:"%F0%9F%98%80",count:21_845),.decode,.success),
            ("late-error",String(repeating:"a",count:262_141)+"%G1",.decode,.invalidPercentEncoding)
        ]
        for (name,source,direction,status) in cases {
            let start = ContinuousClock.now
            let result = URLPercentProcessor.process(source,options:.init(direction:direction))
            let time = start.duration(to:.now).components
            var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
            #expect(result.status == status)
            print("T014_STRESS name=\(name) inputUTF16=\(source.utf16.count) outputUTF16=\(result.artifact?.text?.utf16.count ?? 0) ms=\(Double(time.seconds)*1000+Double(time.attoseconds)/1e15) peakBytes=\(usage.ru_maxrss)")
        }
        let work = Task.detached { URLPercentProcessor.process(String(repeating:"界",count:262_144),limits:.init(outputUTF16:3_000_000)) }
        let start = ContinuousClock.now; work.cancel()
        let result = await work.value
        #expect(result.status == .cancelled)
        print("T014_CANCEL elapsed=\(start.duration(to:.now))")
    }
}
