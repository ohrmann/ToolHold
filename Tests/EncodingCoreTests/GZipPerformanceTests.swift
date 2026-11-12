import Foundation
import Testing
import Darwin
@testable import EncodingCore

struct GZipPerformanceTests {
    @Test func boundedStreamingStress() throws {
        guard ProcessInfo.processInfo.environment["TOOLBOX_T019_STRESS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("T019Stress-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
        let source = dir.appendingPathComponent("source.bin"), gzip = dir.appendingPathComponent("payload.gz")
        for size in [1,16,64,256] {
            FileManager.default.createFile(atPath:source.path,contents:nil)
            let handle = try FileHandle(forWritingTo:source)
            let block = Data(repeating:65,count:65_536)
            for _ in 0..<(size * 16) { try handle.write(contentsOf:block) }; try handle.close()
            let start = ContinuousClock.now
            let compressed = GZipFileProcessor.run(source:.file(source),options:.init(),intent:.check,destination:.init(directory:dir,name:"payload.gz"))
            #expect(compressed.status == .success)
            let compressTime = start.duration(to:.now)
            let decodeStart = ContinuousClock.now
            let options = GZipOptions(direction:.decompress,maxOutput:size > 64 ? .large : .standard)
            let decoded = GZipFileProcessor.run(source:.file(gzip),options:options)
            let decodeTime = decodeStart.duration(to:.now)
            #expect(decoded.status == .success && decoded.outputBytes == Int64(size * 1_024 * 1_024))
            #expect(size <= 8 || decoded.artifact?.bytes == nil)
            let rejected = GZipFileProcessor.run(source:.file(gzip),options:options,intent:.check,limits:.init(decompressedOutput:Int64(size * 1_024 * 1_024 - 1)))
            #expect(rejected.status == .resourceLimit)
            if size == 256 { #expect(GZipFileProcessor.run(source:.file(gzip),options:.init(direction:.decompress),intent:.check).status == .resourceLimit) }
            var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
            print("T019_STRESS inputMiB=\(size) gzipBytes=\(compressed.outputBytes) compress=\(compressTime) decompress=\(decodeTime) peakBytes=\(usage.ru_maxrss)")
            try FileManager.default.removeItem(at:gzip)
        }
        // Deterministic incompressible streams, with no whole-file Data allocation.
        var state:UInt64 = 0x12345678
        for size in [1,16,64,256] {
            FileManager.default.createFile(atPath:source.path,contents:nil)
            let handle = try FileHandle(forWritingTo:source)
            for _ in 0..<(size * 16) {
                var block = Data(count:65_536)
                block.withUnsafeMutableBytes { (raw:UnsafeMutableRawBufferPointer) in
                    for index in raw.indices { state ^= state << 13; state ^= state >> 7; state ^= state << 17; raw[index] = UInt8(truncatingIfNeeded:state) }
                }
                try handle.write(contentsOf:block)
            }; try handle.close()
            let levels:[GZipLevel] = size == 16 ? [.fast,.default,.best,.store] : [.default]
            for level in levels {
                let start = ContinuousClock.now
                let result = GZipFileProcessor.run(source:.file(source),options:.init(level:level),intent:.check)
                #expect(result.status == (size == 256 ? .resourceLimit : .success))
                print("T019_RANDOM inputMiB=\(size) outputBytes=\(result.outputBytes) status=\(result.status) level=\(level.rawValue) elapsed=\(start.duration(to:.now))")
            }
        }
        let oversized = try FileHandle(forWritingTo:source); try oversized.truncate(atOffset:256 * 1_024 * 1_024 + 1); try oversized.close()
        #expect(GZipFileProcessor.run(source:.file(source),options:.init(),intent:.check).status == .resourceLimit)
        let reset = try FileHandle(forWritingTo:source); try reset.truncate(atOffset:16 * 1_024 * 1_024); try reset.close()
        for text in [String(repeating:"a",count:262_144),String(repeating:"😀",count:131_072)] {
            let start = ContinuousClock.now
            let result = GZipFileProcessor.run(source:.text(text),options:.init())
            #expect(result.status == .success)
            print("T019_TEXT inputUTF16=\(text.utf16.count) outputBytes=\(result.outputBytes) elapsed=\(start.duration(to:.now))")
        }
        let op = GZipOperation(), start = ContinuousClock.now
        let cancelled = GZipFileProcessor.run(source:.file(source),options:.init(),operation:op,progress:{ _ in op.cancel() })
        #expect(cancelled.status == .cancelled)
        print("T019_INFLIGHT_CANCEL elapsed=\(start.duration(to:.now))")
    }
}
