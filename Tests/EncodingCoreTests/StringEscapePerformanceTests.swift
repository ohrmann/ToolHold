import Foundation
import Testing
import Darwin
@testable import EncodingCore

struct StringEscapePerformanceTests {
    @Test func boundedStress() async {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T017_STRESS"] == "1" else { return }
        let cases: [(String,String,StringEscapeOptions,StringEscapeStatus)] = [
            ("literal-max-contents",String(repeating:"a",count:262_144),.init(representation:.contents),.success),
            ("escape-dense",String(repeating:"\u{0}\\",count:32_768),.init(),.resourceLimit),
            ("unicode",String(repeating:"é😀e\u{301}",count:40_000),.init(),.success),
            ("json-pairs",String(repeating:#"\uD83D\uDE00"#,count:21_845),.init(direction:.unescape,representation:.contents),.success),
            ("hex-leading-zeros",#"\u{"#+String(repeating:"0",count:262_138)+"41}",.init(language:.javascript,direction:.unescape,representation:.contents),.success),
            ("identity-warning-dense",String(repeating:#"\q"#,count:131_072),.init(language:.javascript,direction:.unescape,representation:.contents),.successWithWarnings),
            ("long-grapheme", "a"+String(repeating:"\u{301}",count:262_136)+#"\uG000"#,.init(direction:.unescape,representation:.contents),.invalidSyntax)
        ]
        for (name,source,options,status) in cases {
            for intent in [StringEscapeIntent.check,.convert] {
                let start = ContinuousClock.now
                let result = StringEscapeProcessor.process(source,options:options,intent:intent)
                var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
                #expect(result.status == status)
                #expect((intent == .check || result.status == .resourceLimit || result.status == .invalidSyntax) ? result.artifact == nil : result.artifact != nil)
                print("T017_STRESS name=\(name) intent=\(intent) inputUTF16=\(source.utf16.count) outputUTF16=\(result.outputCount) elapsed=\(start.duration(to:.now)) peakBytes=\(usage.ru_maxrss)")
            }
        }
        let source = String(repeating:#"\u0041"#,count:43_690)
        let task = Task.detached { StringEscapeProcessor.process(source,options:.init(direction:.unescape,representation:.contents)) }
        let start = ContinuousClock.now; task.cancel()
        #expect(await task.value.status == .cancelled)
        print("T017_CANCEL elapsed=\(start.duration(to:.now))")
        let dense = String(repeating:"\u{0}\\",count:32_768)
        let running = Task.detached { StringEscapeProcessor.process(dense,intent:.check) }
        try? await Task.sleep(for:.milliseconds(1))
        let mid = ContinuousClock.now; running.cancel()
        #expect(await running.value.status == .cancelled)
        print("T017_CANCEL_AFTER_DISPATCH delay=1ms response=\(mid.duration(to:.now))")
    }
}
