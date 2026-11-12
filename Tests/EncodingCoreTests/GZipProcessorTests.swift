import Foundation
import Testing
import zlib
@testable import EncodingCore

struct GZipProcessorTests {
    // Python stdlib gzip.compress(..., mtime=0), independent fixture, Python is not an app dependency.
    static let empty = hex("1f8b08000000000002ff03000000000000000000")
    static let hello = hex("1f8b08000000000002ffcb48cdc9c9e7020020303a3606000000")
    static func hex(_ string: String) -> Data {
        let a = Array(string); return Data(stride(from: 0, to: a.count, by: 2).map { UInt8(String(a[$0...$0+1]),radix:16)! })
    }
    private func decode(_ bytes: Data, chunk: Int = 65_536, limit: Int64 = 256 * 1_024 * 1_024, retained: Int = 8 * 1_024 * 1_024) -> GZipResult {
        GZipProcessor.process(bytes, options: .init(direction: .decompress), limits: .init(decompressedOutput: limit, retained: retained, chunk: chunk))
    }
    @Test func independentFixturesChunksEmptyAndAllLevels() throws {
        for chunk in [1,2,3,7,31,65_536] {
            #expect(decode(Self.hello, chunk: chunk).artifact?.bytes == Data("hello\n".utf8))
            #expect(decode(Self.empty, chunk: chunk).artifact?.bytes == Data())
            let data = Data((0..<(chunk < 31 ? 1_027 : 100_003)).map { UInt8(truncatingIfNeeded: $0 * 73 + 19) })
            for level in GZipLevel.allCases {
                let encoded = GZipProcessor.process(data, options: .init(level: level), limits: .init(chunk: chunk))
                #expect(encoded.status == .success && encoded.members == 1)
                let gzip = try #require(encoded.artifact?.bytes)
                #expect(Array(gzip.prefix(10))[3...7] == [0,0,0,0,0])
                #expect(gzip[9] == 255)
                #expect(decode(gzip, chunk: chunk).artifact?.bytes == data)
                #expect(GZipProcessor.process(data, options: .init(level: level), limits: .init(chunk: chunk)).artifact?.bytes == gzip)
            }
        }
    }
    @Test func unicodeBinaryAndExactText() throws {
        let texts = ["", "\0\u{feff}\r\n", "é e\u{301} 👩🏽‍💻", "\u{202e}abc", "a\t\\n"]
        for text in texts {
            let gzip = try #require(GZipProcessor.process(Data(text.utf8)).artifact?.bytes)
            let result = decode(gzip)
            #expect(result.status == .success && result.artifact?.text?.utf8.elementsEqual(text.utf8) == true)
        }
        for bytes in [Data(0...255),Data([0xFF]),Data([0xED,0xA0,0x80]),Data([0xC0,0xAF])] {
            let gzip = try #require(GZipProcessor.process(bytes).artifact?.bytes)
            let result = decode(gzip)
            #expect(result.status == .success && result.artifact?.binary == true && result.artifact?.bytes == bytes && result.artifact?.text == nil)
        }
    }
    @Test func multipleMembersTrailingAndBrokenSecond() {
        for chunk in [1,2,7,65_536] {
            let stream = Self.empty + Self.hello + Self.empty + Self.hello
            let result = decode(stream, chunk:chunk)
            #expect(result.members == 4 && result.artifact?.text == "hello\nhello\n")
            for tail in [Data([0]),Data([32,10]),Data([1,2]),Data("junk".utf8)] {
                let bad = decode(stream + tail, chunk:chunk)
                #expect(bad.status == .invalidGZip && bad.artifact == nil)
            }
            let truncated = decode(stream + Data([0x1f]), chunk:chunk)
            #expect(truncated.failure?.code == .truncated && truncated.failure?.length == 0 && truncated.failure?.offset == Int64(stream.count + 1) && truncated.failure?.member == 5)
            var badSecond = Self.hello; badSecond[badSecond.count - 8] ^= 1
            #expect(decode(Self.hello + badSecond, chunk:chunk).artifact == nil)
        }
    }
    @Test func truncationCorruptionHeadersAndNoPartialResults() {
        for length in 0..<Self.hello.count {
            let result = decode(Self.hello.prefix(length), chunk:1)
            #expect(result.status == .invalidGZip && result.artifact == nil)
            #expect(result.failure?.offset == Int64(length) && result.failure?.exact == true && result.failure?.length == 0)
        }
        for index in [0,1,2,3,10,Self.hello.count - 8,Self.hello.count - 1] {
            var bytes = Self.hello; bytes[index] ^= index == 3 ? 32 : 255
            let bad = decode(bytes)
            #expect(bad.status == .invalidGZip && bad.artifact == nil)
        }
        for bytes in [Data([0x78,0x9C,3,0,0,0,0,1]),Data([0x50,0x4b,3,4]),Data([3,0])] { #expect(decode(bytes).status == .invalidGZip) }
    }
    @Test func optionalHeadersCRCAndLongHeader() {
        var header = Data([0x1f,0x8b,8,0x1f,0,0,0,0,0,255]) // text + header CRC + extra + name + comment
        header += Data([3,0,1,2,3]); header += Data("name\0comment\0".utf8)
        let crc = header.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(header.count)) }
        header += Data([UInt8(truncatingIfNeeded:crc),UInt8(truncatingIfNeeded:crc >> 8)])
        let bytes = header + Self.hello.dropFirst(10)
        for chunk in [1,3,65_536] { #expect(decode(bytes,chunk:chunk).artifact?.text == "hello\n") }
        var bad = bytes; bad[header.count - 1] ^= 1; #expect(decode(bad).status == .invalidGZip)
        let longHeader = Data([0x1f,0x8b,8,8,0,0,0,0,0,255]) + Data(repeating:65,count:70_000) + Data([0]) + Self.empty.dropFirst(10)
        #expect(decode(longHeader).artifact?.bytes == Data())
    }
    @Test func budgetsCountingCollectorAndCancellation() throws {
        let data = Data(repeating:65,count:100_000)
        let gzip = try #require(GZipProcessor.process(data).artifact?.bytes)
        #expect(decode(gzip,limit:100_000).outputBytes == 100_000)
        #expect(decode(gzip,limit:99_999).status == .resourceLimit)
        #expect(decode(gzip + gzip,limit:150_000).status == .resourceLimit)
        let large = decode(gzip,retained:10)
        #expect(large.status == .success && large.artifact?.bytes == nil && large.artifact?.base64 == nil && large.artifact?.text == nil)
        #expect(large.artifact?.textPreview.count == 8_192)
        let check = GZipProcessor.process(gzip,options:.init(direction:.decompress),intent:.check)
        #expect(check.status == .success && check.artifact == nil && check.outputBytes == 100_000)
        #expect(GZipProcessor.process(data,limits:.init(fileInput:99_999)).status == .resourceLimit)
        #expect(GZipProcessor.process(data,limits:.init(compressedOutput:1)).status == .resourceLimit)
        let op = GZipOperation(); op.cancel()
        #expect(GZipProcessor.process(data,operation:op).status == .cancelled)
        #expect(GZipProcessor.process(data,operation:.init(timeout:0)).failure?.code == .deadline)
        #expect(GZipProcessor.process(data,limits:.init(chunk:0)).status == .resourceLimit)
        #expect(throws:GZipFailure.self) { try GZipStreamCodec.add(Int64.max,1) }
    }
    private final class Clock: @unchecked Sendable {
        let lock = NSLock(); var value:TimeInterval = 0
        func next() -> TimeInterval { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }
    @Test func emptyMemberStormChecksDeadlineBetweenMembers() {
        var bytes = Data(); for _ in 0..<10_000 { bytes += Self.empty }
        let result = decode(bytes)
        #expect(result.status == .success && result.members == 10_000 && result.outputBytes == 0)
        let clock = Clock(), gate = GZipOperation(timeout:20,clock:{ clock.next() })
        let timed = GZipProcessor.process(bytes,options:.init(direction:.decompress),operation:gate)
        #expect(timed.status == .resourceLimit && timed.failure?.code == .deadline && timed.artifact == nil)
        let truncated = decode(Self.hello.dropLast())
        #expect(truncated.failure?.context.contains("⟦EOF⟧") == true)
    }
    @Test func base64PolicyPriorityAndAnchors() {
        let base64 = Self.hello.base64EncodedString()
        let options = GZipOptions(direction:.decompress)
        #expect(GZipFileProcessor.run(source:.text(base64),options:options).artifact?.text == "hello\n")
        #expect(GZipFileProcessor.run(source:.text("\r\n " + base64),options:options).status == .invalidBase64)
        let forgiving = GZipOptions(direction:.decompress,base64Mode:.forgiving)
        #expect(GZipFileProcessor.run(source:.text("\r\n " + base64),options:forgiving).artifact?.text == "hello\n")
        let invalid = GZipFileProcessor.run(source:.text("AAAA😀"),options:options)
        #expect(invalid.status == .invalidBase64 && invalid.failure?.textRange == NSRange(location:4,length:2))
        let eof = GZipFileProcessor.run(source:.text("YQ="),options:options)
        #expect(eof.failure?.textRange == NSRange(location:3,length:0))
        #expect(GZipFileProcessor.run(source:.text(""),options:options).failure?.code == .empty)
        #expect(GZipFileProcessor.run(source:.text("hello"),options:.init()).status == .success)
        #expect(GZipFileProcessor.run(source:.text(String(repeating:"a",count:262_145)),options:.init()).status == .resourceLimit)
    }
    @Test func previewEscapesControlsAndCopiesRemainExact() throws {
        let text = "A\0\r\n\u{202e}👩🏽‍💻e\u{301}"
        let gzip = try #require(GZipProcessor.process(Data(text.utf8)).artifact?.bytes)
        let result = decode(gzip)
        #expect(result.artifact?.text?.utf8.elementsEqual(text.utf8) == true)
        #expect(result.artifact?.textPreview.contains("\\u{0}") == true && result.artifact?.textPreview.contains("\\u{202E}") == true)
        #expect(!GZipProcessor.safePreview(text).contains("\u{202e}"))
        #expect(GZipProcessor.safePreview("👩🏽‍💻hello",limit:2) == "…")
    }
    #if os(macOS)
    @Test func outputAcceptedByIndependentSystemGunzip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
        let bytes = Data(0...255) + Data("👩🏽‍💻\r\n\0".utf8)
        let gzip = try #require(GZipProcessor.process(bytes).artifact?.bytes)
        let file = dir.appendingPathComponent("fixture.gz"); try gzip.write(to:file)
        let process = Process(), output = Pipe(); process.executableURL = URL(fileURLWithPath:"/usr/bin/gzip")
        process.arguments = ["-dc",file.path]; process.standardOutput = output
        try process.run(); let decoded = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        #expect(process.terminationStatus == 0 && decoded == bytes)
    }
    #endif
}
