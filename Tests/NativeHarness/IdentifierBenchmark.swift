import Foundation
import Darwin
// Compile with -O together with IdentifierTypes, SecureRandomBytes and IdentifierGenerator.
@main struct IdentifierBenchmark {
    static func main() async throws {
        setbuf(stdout, nil)
        for kind in IdentifierKind.allCases {
            for count in [1, 1000, 10000] {
                let start = ProcessInfo.processInfo.systemUptime
                let result = await IdentifierGenerator().generate(.init(kind: kind, count: count, nanoLength: 256))
                guard result.batch?.values.count == count else { fatalError("generation failed") }
                print("T022_RELEASE kind=\(kind.rawValue) count=\(count) length=\(kind == .nanoID ? 256 : 0) ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
            }
        }
        for monotonic in [true, false] {
            let start = ProcessInfo.processInfo.systemUptime
            let batch = await IdentifierGenerator(clock: { 1 }).generate(.init(kind: .ulid, count: 10000, ulidMonotonic: monotonic))
            guard batch.batch?.values.count == 10000 else { fatalError("same-ms failed") }
            print("T022_RELEASE sameMsULID monotonic=\(monotonic) ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
        }
        let start = ProcessInfo.processInfo.systemUptime
        let result = await IdentifierGenerator().generate(.init(kind: .nanoID, count: 10000, nanoLength: 256, alphabet: .custom, customAlphabet: IdentifierAlphabet.urlSafe.symbols + "!"))
        let batch = result.batch!
        print("T022_RELEASE custom65 ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
        let copyStart = ProcessInfo.processInfo.systemUptime
        let text = try IdentifierSerialization.text(batch, format: .json)
        print("T022_RELEASE jsonBytes=\(text.utf8.count) ms=\((ProcessInfo.processInfo.systemUptime - copyStart) * 1000)")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage); print("T022_RELEASE peakBytes=\(usage.ru_maxrss)")
    }
}
