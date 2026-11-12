import Foundation
import Darwin
@testable import Developer_Toolbox

/// Run against the Debug app module; timings explicitly describe Debug core.
@main struct TokenDigestBenchmark {
    @MainActor final class Pulse { var times = [Double](); var running = true }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-digest-stress-\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let mib = 1_048_576
        let sizes = [100, 1024]
        for size in sizes {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            let block = Data((0..<mib).map { UInt8($0 & 255) })
            for _ in 0..<size { try handle.write(contentsOf: block) }; try handle.close()
            let cases: [(String, DigestRequest)] = [
                ("SHA256", .init(mode: .file, file: url)),
                ("all-seven", .init(mode: .file, file: url, algorithms: DigestAlgorithm.allCases)),
                ("HMAC-SHA256", .init(mode: .file, file: url, isHMAC: true, key: "synthetic-benchmark-key"))
            ]
            for (name, request) in cases {
                let start = ProcessInfo.processInfo.systemUptime
                let pulse = Pulse()
                let heartbeat = Task { @MainActor in
                    while pulse.running { pulse.times.append(ProcessInfo.processInfo.systemUptime); try? await Task.sleep(for: .milliseconds(5)) }
                }
                let result = await Task.detached { DigestProcessor.run(request) }.value
                pulse.running = false; await heartbeat.value
                let gap = zip(pulse.times.dropFirst(), pulse.times).map { ($0 - $1) * 1000 }.max() ?? 0
                print("DIGEST_MAIN_HEARTBEAT maxGapMs=\(gap)")
                guard result.artifact?.bytes == Int64(size * mib) else { fatalError("benchmark-processing-failed") }
                var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                print("DIGEST_STRESS core=Debug fileMiB=\(size) profile=\(name) ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) peakRSS=\(usage.ru_maxrss)")
            }
        }
        let request = DigestRequest(mode: .file, file: url, algorithms: DigestAlgorithm.allCases)
        let task = Task.detached { DigestProcessor.run(request) }
        try await Task.sleep(for: .milliseconds(15)); let start = ProcessInfo.processInfo.systemUptime; task.cancel()
        let cancelled = await task.value
        guard cancelled.issue?.status == .cancelled && cancelled.artifact == nil else { fatalError("cancel-failed") }
        print("DIGEST_CANCEL_MS \((ProcessInfo.processInfo.systemUptime-start)*1000)")
        let tokenStart = ProcessInfo.processInfo.systemUptime
        let token = await Task.detached { TokenGenerator.generate(.init(bytes: 1024, count: 1000)) }.value
        guard let batch = token.batch else { fatalError("token-failed") }
        let presentation = try TokenGenerator.present(batch, encoding: .hex, uppercase: false)
        let json = try TokenGenerator.serialize(presentation, json: true)
        print("TOKEN_STRESS bytes=1024000 count=1000 jsonBytes=\(json.utf8.count) ms=\((ProcessInfo.processInfo.systemUptime-tokenStart)*1000)")
    }
}
