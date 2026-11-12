import Foundation
import Testing
import CryptoKit
import Darwin
@testable import EncodingCore

struct GZipFileTests {
    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T019-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url
    }
    @Test func fullFileRoundtripCheckDigestAndNoImplicitDiskWrites() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at:dir) }
        let bytes = Data((0..<400_003).map { UInt8(truncatingIfNeeded:$0 * 17) })
        let source = dir.appendingPathComponent("source.bin"); try bytes.write(to:source)
        let snapshot = try FileManager.default.contentsOfDirectory(atPath:dir.path)
        let meta = try GZipFileMetadata.load(source); #expect(meta.size == bytes.count)
        let check = GZipFileProcessor.run(source:.file(source),options:.init(),intent:.check)
        #expect(check.status == .success && check.artifact == nil && check.sourceDigest == Data(SHA256.hash(data:bytes)))
        let preview = GZipFileProcessor.run(source:.file(source),options:.init())
        #expect(preview.status == .success)
        #expect(try FileManager.default.contentsOfDirectory(atPath:dir.path) == snapshot)
        let gzip = dir.appendingPathComponent("source.bin.gz")
        let exported = GZipFileProcessor.run(source:.file(source),options:.init(),intent:.check,destination:.init(directory:dir,name:gzip.lastPathComponent),expectedDigest:check.sourceDigest)
        #expect(exported.status == .success && exported.exportedName == gzip.lastPathComponent)
        let decoded = GZipFileProcessor.run(source:.file(gzip),options:.init(direction:.decompress),intent:.check,destination:.init(directory:dir,name:"restored.bin"))
        #expect(decoded.status == .success)
        #expect(try Data(contentsOf:dir.appendingPathComponent("restored.bin")) == bytes)
        #expect(try Data(contentsOf:source) == bytes)
        #expect(try !FileManager.default.contentsOfDirectory(atPath:dir.path).contains { $0.hasSuffix(".partial") })
    }
    @Test func noOverwriteSymlinkSameFileAndInvalidSecondMember() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at:dir) }
        let source = dir.appendingPathComponent("source"); try Data("hello".utf8).write(to:source)
        let target = dir.appendingPathComponent("target"); try Data([42]).write(to:target)
        for name in ["source","target"] {
            #expect(GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:name)).status == .ioFailure)
        }
        let link = dir.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        #expect(GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:"link")).status == .ioFailure)
        #expect(try Data(contentsOf:target) == Data([42]))
        let invalid = GZipProcessorTests.hello + GZipProcessorTests.hello.dropLast()
        let bad = dir.appendingPathComponent("bad.gz"); try invalid.write(to:bad)
        let result = GZipFileProcessor.run(source:.file(bad),options:.init(direction:.decompress),destination:.init(directory:dir,name:"invalid.bin"))
        #expect(result.status == .invalidGZip && !FileManager.default.fileExists(atPath:dir.appendingPathComponent("invalid.bin").path))
        #expect(try !FileManager.default.contentsOfDirectory(atPath:dir.path).contains { $0.hasSuffix(".partial") })
    }
    @Test func sourceMutationDigestReplayCollisionAndCancellation() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at:dir) }
        let source = dir.appendingPathComponent("source"); try Data(repeating:65,count:80_000).write(to:source)
        let receipt = GZipFileProcessor.run(source:.file(source),options:.init(),intent:.check)
        try Data(repeating:66,count:80_000).write(to:source)
        let stale = GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:"stale.gz"),expectedDigest:receipt.sourceDigest)
        #expect(stale.status == .sourceChanged)
        let changed = GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:"changed.gz"),progress:{ _ in try? Data([7]).write(to:source) })
        #expect(changed.status == .sourceChanged)
        try Data(repeating:65,count:80_000).write(to:source)
        let collision = dir.appendingPathComponent("race.gz")
        let raced = GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:"race.gz"),progress:{ _ in try? Data([99]).write(to:collision) })
        #expect(raced.status == .ioFailure && (try? Data(contentsOf:collision)) == Data([99]))
        let op = GZipOperation()
        let cancelled = GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:"cancelled.gz"),operation:op,progress:{ _ in op.cancel() })
        #expect(cancelled.status == .cancelled && op.exportedName == nil)
        for name in ["stale.gz","changed.gz","cancelled.gz"] { #expect(!FileManager.default.fileExists(atPath:dir.appendingPathComponent(name).path)) }
        #expect(try !FileManager.default.contentsOfDirectory(atPath:dir.path).contains { $0.hasSuffix(".partial") })
    }
    @Test func fileBudgetsAndLargeRecipeExport() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at:dir) }
        let bytes = Data(repeating:65,count:10_000)
        let gzip = try #require(GZipProcessor.process(bytes).artifact?.bytes)
        let source = dir.appendingPathComponent("data.gz"); try gzip.write(to:source)
        let options = GZipOptions(direction:.decompress)
        let result = GZipFileProcessor.run(source:.file(source),options:options,limits:.init(retained:10))
        #expect(result.status == .success && result.artifact?.bytes == nil && result.outputBytes == bytes.count)
        let saved = GZipFileProcessor.run(source:.file(source),options:options,intent:.check,destination:.init(directory:dir,name:"all.bin"),expectedDigest:result.sourceDigest,limits:.init(retained:10))
        #expect(saved.status == .success)
        #expect(try Data(contentsOf:dir.appendingPathComponent("all.bin")) == bytes)
        let limited = GZipFileProcessor.run(source:.file(source),options:options,destination:.init(directory:dir,name:"bomb.bin"),limits:.init(decompressedOutput:9_999))
        #expect(limited.status == .resourceLimit && !FileManager.default.fileExists(atPath:dir.appendingPathComponent("bomb.bin").path))
        #expect(GZipFileProcessor.run(source:.file(source),options:options,limits:.init(fileInput:Int64(gzip.count-1))).status == .resourceLimit)
    }
    @Test func cleanupDenialVisibleAndOnlyOurPartialIsTouched() throws {
        let dir = try temp(); defer { chmod(dir.path,0o700); try? FileManager.default.removeItem(at:dir) }
        let source = dir.appendingPathComponent("source"); try Data(repeating:65,count:1000).write(to:source)
        let unrelated = dir.appendingPathComponent("unrelated.partial"); try Data([42]).write(to:unrelated)
        let op = GZipOperation()
        let result = GZipFileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:dir,name:"denied.gz"),operation:op,progress:{ _ in chmod(dir.path,0o500); op.cancel() })
        chmod(dir.path,0o700)
        #expect(result.status == .cancelled && result.failure?.cleanupPath != nil)
        #expect(try Data(contentsOf:unrelated) == Data([42]))
        #expect(!FileManager.default.fileExists(atPath:dir.appendingPathComponent("denied.gz").path))
    }
    @Test func sourceKindsFilenameAndCommitBoundary() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at:dir) }
        #expect(GZipFileProcessor.run(source:.file(dir),options:.init()).status == .unsupportedFormat)
        #expect(GZipFileProcessor.run(source:.file(URL(string:"https://example.invalid/x")!),options:.init()).status == .unsupportedFormat)
        for name in ["../a","", ".", "..", "a/b", "a\\b", "x\0y", "a\u{202e}b"] { #expect(!GZipFileProcessor.validFilename(name)) }
        let cancelled = GZipOperation(); cancelled.cancel()
        #expect(throws:CancellationError.self) { try cancelled.commit(name:"absent") { Issue.record("Commit after cancellation") } }
        let finalCallback = GZipOperation()
        let stopped = GZipFileProcessor.run(source:.text("small"),options:.init(),operation:finalCallback,progress:{ _ in finalCallback.cancel() })
        #expect(stopped.status == .cancelled && stopped.artifact == nil)
        let saved = GZipOperation(); try saved.commit(name:"done") {}; saved.cancel()
        #expect(saved.exportedName == "done")
        #expect(GZipFileProcessor.run(source:.text(""),options:.init(),destination:.init(directory:dir,name:"empty.gz")).status == .success)
        let empty = GZipFileProcessor.run(source:.file(dir.appendingPathComponent("empty.gz")),options:.init(direction:.decompress))
        #expect(empty.artifact?.bytes == Data() && empty.artifact?.text == "")
    }
}
