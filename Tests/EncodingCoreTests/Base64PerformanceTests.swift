import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif
@testable import EncodingCore

struct Base64PerformanceTests {
    @Test func boundedStress() {
        let cases: [(String,String,Base64Options,Base64Status)] = [
            ("ascii-encode", String(repeating: "a", count: 196_608), .init(direction: .encode), .success),
            ("cjk-encode", String(repeating: "界", count: 65_536), .init(direction: .encode), .success),
            ("decode-long-line", String(repeating: "YWFh", count: 65_536), .init(), .success),
            ("whitespace-heavy", String(repeating: " Y Q ==\r\n", count: 1) + String(repeating: " ", count: 262_135), .init(decodeMode: .forgiving), .success),
            ("invalid-last", String(repeating: "YWFh", count: 65_535) + "YQ=!", .init(), .invalidBase64),
            ("binary", Data(repeating: 255, count: 196_608).base64EncodedString(), .init(), .bytesOnly)
        ]
        for (name,source,options,status) in cases {
            var times: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                let result = Base64Processor.process(source, options: options)
                let duration = start.duration(to: .now).components
                times.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
                #expect(result.status == status)
                #expect((result.artifact?.text?.utf16.count ?? 0) <= 262_144)
            }
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("BASE64_STRESS name=\(name) utf16=\(source.utf16.count) ms=\(times) peakBytes=\(usage.ru_maxrss)")
        }
    }
}
