import Foundation
import CryptoKit
import Darwin
import Testing
@testable import EncodingCore

struct Base64FilePerformanceTests {
    /// Explicit opt-in: large fixtures are streamed to a private temporary test directory.
    @Test func streamingStress() throws {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T013_STRESS"] == "1" else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T013Stress-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let block = Data((0..<65_536).map { UInt8(truncatingIfNeeded: $0 * 61 + 9) })
        let isolated = ProcessInfo.processInfo.environment["TOOLBOX_T013_STRESS_SIZE"].flatMap(Int.init)
        for size in isolated.map({ [$0] }) ?? [0,1,1_048_576,67_108_864,268_435_456] {
            let source = directory.appendingPathComponent("source.bin")
            _ = FileManager.default.createFile(atPath: source.path, contents: nil)
            let writer = try FileHandle(forWritingTo: source)
            var remaining = size, hash = SHA256()
            while remaining > 0 {
                try autoreleasepool {
                    let piece = Data(block.prefix(min(remaining,block.count)))
                    try writer.write(contentsOf: piece); hash.update(data: piece); remaining -= piece.count
                }
            }
            try writer.close()
            let expected = Data(hash.finalize())
            for direction in Base64Direction.allCases.reversed() {
                let input = direction == .encode ? source : directory.appendingPathComponent("encoded.txt")
                let name = direction == .encode ? "encoded.txt" : "decoded.bin"
                let start = ContinuousClock.now
                let value = Base64FileProcessor.run(source: .file(input),options: .init(direction: direction),destination: .init(directory: directory,name: name))
                let elapsed = start.duration(to: .now).components
                #expect(value.status == .success)
                var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
                print("T013_STRESS direction=\(direction.rawValue) sourceBytes=\(value.inputBytes) outputBytes=\(value.outputBytes) seconds=\(Double(elapsed.seconds) + Double(elapsed.attoseconds)/1e18) peakRSS=\(usage.ru_maxrss)")
                #expect(value.copyText == nil || size <= 196_608)
                if direction == .decode {
                    let verify = Base64FileProcessor.run(source: .file(directory.appendingPathComponent(name)),options: .init(),intent: .check)
                    #expect(verify.sourceDigest == expected && verify.inputBytes == size)
                }
            }
            for name in ["source.bin","encoded.txt","decoded.bin"] { try FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
        }
    }
}
