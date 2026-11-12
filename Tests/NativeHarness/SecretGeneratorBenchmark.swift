import Foundation
import Darwin

/// Compile with -O plus SecretGeneratorTypes, UniformRandomSampler, GeneratorEntropy,
/// SecretGenerator, PassphraseWordlist, SecureRandomBytes and IdentifierTypes.
@main struct SecretGeneratorBenchmark {
    static func main() async throws {
        setbuf(stdout, nil)
        let excluded = "bcdefghijklmnopqrstuvwxyzBCDEFGHIJKLMNOPQRSTUVWXYZ123456789"
        let profiles: [(String, SecretGeneratorRequest)] = [
            ("password-default13", .password(.init(count: 1000))),
            ("password-max128", .password(.init(length: 128, count: 1000))),
            ("password-exclusions128", .password(.init(length: 128, count: 1000, exclusions: excluded))),
            ("password-exclusions8", .password(.init(length: 8, count: 1000, exclusions: excluded))),
            ("phrase-max16", .passphrase(.init(wordCount: 16, count: 1000, appendDigit: true)))
        ]
        for (label, options) in profiles {
            let start = ProcessInfo.processInfo.systemUptime
            let result = SecretGenerator.generate(options)
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            print("SECRET_RELEASE profile=\(label) count=1000 ms=\(ms) status=\(result.status.rawValue)")
            guard let batch = result.batch, batch.values.count == 1000 else { throw result.issue ?? SecretIssue(.resourceLimit, "Benchmark failed") }
            let copyStart = ProcessInfo.processInfo.systemUptime, text = try SecretSerialization.text(batch, format: .json)
            print("SECRET_RELEASE_COPY profile=\(label) bytes=\(text.utf8.count) ms=\((ProcessInfo.processInfo.systemUptime - copyStart) * 1000)")
        }
        let task = Task.detached {
            SecretGenerator.generate(.password(.init(length: 128, count: 1000)), random: { count in
                Thread.sleep(forTimeInterval: 0.001); return try SecureRandomBytes.read(count)
            })
        }
        try await Task.sleep(for: .milliseconds(10))
        let cancelStart = ProcessInfo.processInfo.systemUptime; task.cancel()
        let cancelled = await task.value
        guard cancelled.status == .cancelled && cancelled.batch == nil else { throw SecretIssue(.cancelled, "Cancel benchmark failed") }
        print("SECRET_RELEASE_CANCEL ms=\((ProcessInfo.processInfo.systemUptime - cancelStart) * 1000)")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage); print("SECRET_RELEASE_PEAK_BYTES \(usage.ru_maxrss)")
    }
}
