import Foundation
import Testing
import CryptoKit
import Darwin
@testable import EncodingCore

struct Base64FileTests {
    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T013Tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func output(_ text: String, options: Base64FileOptions = .init(direction: .decode), chunk: Int = 65_536) -> Base64FileResult {
        Base64FileProcessor.run(source: .text(text), options: options, chunkSize: chunk)
    }
    @Test func chunkBoundariesAndRawParity() throws {
        for count in [0,1,2,3,4,5,63,64,65,127,256,1023] {
            let bytes = Data((0..<count).map { UInt8(truncatingIfNeeded: $0 * 73 + 19) })
            let directory = try temp(); defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("source.bin"); try bytes.write(to: file)
            for size in [1,2,3,4,5,63,64,65,65_535,65_536] {
                for alphabet in Base64Alphabet.allCases {
                    for padded in [false,true] {
                        let encode = Base64FileOptions(alphabet: alphabet, urlPadding: padded)
                        let encoded = Base64FileProcessor.run(source: .file(file), options: encode, chunkSize: size)
                        let expected = bytes.base64EncodedString().replacingOccurrences(of: "+", with: alphabet == .urlSafe ? "-" : "+").replacingOccurrences(of: "/", with: alphabet == .urlSafe ? "_" : "/")
                        let text = alphabet == .urlSafe && !padded ? expected.replacingOccurrences(of: "=", with: "") : expected
                        #expect(encoded.status == .success && encoded.copyText == text, "\(encoded.status) \(encoded.failure?.message ?? "")")
                        let decoded = output(text, options: .init(direction: .decode, alphabet: alphabet), chunk: size)
                        #expect(decoded.status == .success && decoded.outputBytes == count && decoded.imageBytes == bytes)
                    }
                }
            }
        }
        for source in ["YQ=", "YQ===", "Y===", "YW=Jj", "AAAA====", "A", "YQ==YQ==", "YQ==😀", "YQ%3D%3D", "YQ.Yg", "YQ\u{b}==", "\u{feff}YQ==", "YQ", "Zh==", "Zm9=", "\r\n Z\th==", "YQ==\n", "+_8="] {
            for alphabet in Base64Alphabet.allCases {
                for mode in Base64DecodeMode.allCases {
                    let text = Base64Processor.process(source, options: .init(alphabet: alphabet, decodeMode: mode))
                    for chunk in [1,2,3,4,5,64] {
                        let file = output(source, options: .init(direction: .decode, alphabet: alphabet, decodeMode: mode), chunk: chunk)
                        if text.status == .success || text.status == .bytesOnly {
                            #expect(file.status == .success && file.imageBytes == text.artifact?.decodedBytes)
                            #expect(file.notes == text.issues.filter { $0.code != .invalidTextEncoding && $0.code != .controls && $0.code != .leadingBOM }.map(\.message))
                        } else {
                            #expect(file.status == .invalidBase64)
                            #expect(file.failure?.textRange == text.issues.first?.range, "\(source.debugDescription) / \(chunk)")
                        }
                    }
                }
            }
        }
    }
    @Test func dataURLProfilesAndOriginalAnchors() {
        for chunk in [1,2,3,4,5,64] {
            let opts = Base64FileOptions(direction: .decode, format: .dataURL)
            for text in ["data:;base64,YQ==", "DATA:text/plain;charset=UTF-8;BASE64,YQ==", "data:image/png;base64,YQ=="] {
                let value = output(text, options: opts, chunk: chunk)
                #expect(value.status == .success && value.imageBytes == Data([97]))
            }
            #expect(output("data:;base64,", options: opts, chunk: chunk).outputBytes == 0)
            for text in ["data:text/plain,hello", "data:text/plain;base64=,YQ==", "data:text/plain;base64;base64,YQ==", "data:text/plain;a=b;A=c;base64,YQ==", "data:text/plain;a=\"b\";base64,YQ==", "data:text/plain;a=%20;base64,YQ==", "data:text/plain;base64,YQ%3D%3D", "data:text/plain;base64"] {
                #expect(output(text, options: opts, chunk: chunk).status == .unsupportedFormat, "\(text)")
            }
            let invalid = output("data:;base64,A", options: opts, chunk: chunk)
            #expect(invalid.failure?.byteOffset == 14 && invalid.failure?.textRange == .init(location: 14,length: 0))
        }
        #expect(output("data:" + String(repeating: "x",count: 4097), options: .init(direction: .decode,format: .dataURL)).status == .resourceLimit)
        let percent = output("data:;x=%20;base64,YQ==", options: .init(direction: .decode,format: .dataURL))
        #expect(percent.failure?.textRange == .init(location: 8,length: 1))
        let nonASCII = output("data:😀;base64,YQ==", options: .init(direction: .decode,format: .dataURL),chunk: 1)
        #expect(nonASCII.failure?.textRange == .init(location: 5,length: 2))
        #expect((try? Base64DataURL.header(mime: "image/png")) == Data("data:image/png;base64,".utf8))
        #expect(throws: Base64FileFailure.self) { try Base64DataURL.header(mime: "image/png\r\nX: hi") }
        let unicode = output("\r\n YQ==😀", options: .init(direction: .decode,decodeMode: .forgiving))
        #expect(unicode.failure?.textRange == .init(location: 7,length: 2))
        #expect(unicode.failure?.line == 2 && unicode.failure?.column == 6)
        #expect(unicode.failure?.context.contains("\\xF0") == true)
    }
    @Test func safeExportCollisionSourceConsistencyAndCleanup() throws {
        let directory = try temp(); defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("original.bin")
        let bytes = Data((0..<100_003).map { UInt8(truncatingIfNeeded: $0) }); try bytes.write(to: input)
        let opts = Base64FileOptions()
        let checked = Base64FileProcessor.run(source: .file(input), options: opts, intent: .check)
        #expect(checked.status == .success && checked.copyText == nil && checked.imageBytes == nil)
        let encoded = Base64FileProcessor.run(source: .file(input), options: opts, destination: .init(directory: directory,name: "encoded.txt"), expectedDigest: checked.sourceDigest)
        #expect(encoded.status == .success && encoded.exportedName == "encoded.txt")
        #expect(try Data(contentsOf: directory.appendingPathComponent("encoded.txt")) == bytes.base64EncodedData())
        let decoded = Base64FileProcessor.run(source: .file(directory.appendingPathComponent("encoded.txt")), options: .init(direction: .decode), destination: .init(directory: directory,name: "decoded.bin"))
        #expect(decoded.status == .success)
        #expect(try Data(contentsOf: directory.appendingPathComponent("decoded.bin")) == bytes)
        let collision = Base64FileProcessor.run(source: .file(input), options: opts, destination: .init(directory: directory,name: "decoded.bin"))
        #expect(collision.status == .ioFailure)
        #expect(try Data(contentsOf: directory.appendingPathComponent("decoded.bin")) == bytes)
        #expect(Base64FileProcessor.run(source: .file(input), options: opts, destination: .init(directory: directory,name: "original.bin")).status == .ioFailure)
        try Data([42]).write(to: input)
        let changed = Base64FileProcessor.run(source: .file(input), options: opts, destination: .init(directory: directory,name: "stale.txt"), expectedDigest: checked.sourceDigest)
        #expect(changed.status == .sourceChanged && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("stale.txt").path))
        let invalid = Base64FileProcessor.run(source: .text("YQ==!"), options: .init(direction: .decode), destination: .init(directory: directory,name: "invalid.bin"))
        #expect(invalid.status == .invalidBase64 && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("invalid.bin").path))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".partial") })
        #expect(try Data(contentsOf: input) == Data([42]))
    }
    @Test func budgetsPositionsAndCancellation() throws {
        #expect(throws: Base64FileFailure.self) { try Base64StreamSize.encoded(Int64.max,padded: true) }
        #expect(try Base64StreamSize.encoded(3,padded: true) == 4)
        #expect(try Base64StreamSize.encoded(1,padded: false,header: 9) == 11)
        #expect(output(String(repeating: "A",count: Base64FileBudget.textInput + 1)).status == .resourceLimit)
        for name in ["", ".", "..", "../out", "a/b", "a\\b", "a:b", "bad\0name", "bad\u{202e}name", "bad\u{85}name", "bad\u{2028}name"] { #expect(!Base64FileProcessor.validFilename(name)) }
        #expect(Base64FileProcessor.validFilename("hello 世界.png"))
        #expect(Base64FileProcessor.run(source: .file(URL(string: "https://example.invalid/data")!),options: .init()).status == .unsupportedFormat)
        let directory = try temp(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("long.txt")
        let bytes = Data(repeating: 65,count: 65_537) + Data([33]); try bytes.write(to: file)
        let invalid = Base64FileProcessor.run(source: .file(file), options: .init(direction: .decode))
        #expect(invalid.failure?.byteOffset == 65_537 && invalid.failure?.textRange == nil)
        #expect(invalid.failure?.context.contains("⟦!⟧") == true)
        let gate = Base64FileOperation(); gate.cancel()
        #expect(Base64FileProcessor.run(source: .file(file), options: .init(), operation: gate).status == .cancelled)
        let previewFile = directory.appendingPathComponent("preview.bin"); try Data(repeating: 1,count: 200_000).write(to: previewFile)
        let large = Base64FileProcessor.run(source: .file(previewFile), options: .init())
        #expect(large.status == .success && large.copyText == nil && large.textPreview.count == 8192 && large.outputBytes == 266_668)
        let zero = directory.appendingPathComponent("empty.bin"); try Data().write(to: zero)
        #expect(Base64FileProcessor.run(source: .file(zero), options: .init()).copyText == "")
        let cancelled = Base64FileProcessor.run(source: .file(previewFile), options: .init(), destination: .init(directory: directory,name: "cancelled.txt"), operation: gate)
        #expect(cancelled.status == .cancelled && gate.exportedName == nil)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".partial") })
    }
    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var used = false
        func run(_ body: () -> Void) { lock.lock(); defer { lock.unlock() }; if !used { used = true; body() } }
    }
    @Test func sourceMutationCollisionRaceAndCleanupFailure() throws {
        let directory = try temp(); defer { chmod(directory.path, 0o700); try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        try Data(repeating: 7,count: 1_000_000).write(to: source)
        let mutate = Once()
        let changed = Base64FileProcessor.run(source: .file(source),options: .init(),destination: .init(directory: directory,name: "changed.txt"),chunkSize: 5,progress: { _ in
            mutate.run { try? Data([42]).write(to: source) }
        })
        #expect(changed.status == .sourceChanged)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("changed.txt").path))
        try Data(repeating: 7,count: 1_000_000).write(to: source)
        let collide = Once(), target = directory.appendingPathComponent("race.txt")
        let collision = Base64FileProcessor.run(source: .file(source),options: .init(),destination: .init(directory: directory,name: "race.txt"),chunkSize: 5,progress: { _ in
            collide.run { try? Data([99]).write(to: target) }
        })
        #expect(collision.status == .ioFailure && (try? Data(contentsOf: target)) == Data([99]))
        let restrict = Once(), operation = Base64FileOperation()
        let restricted = Base64FileProcessor.run(source: .file(source),options: .init(),destination: .init(directory: directory,name: "restricted.txt"),operation: operation,chunkSize: 5,progress: { _ in
            restrict.run { chmod(directory.path,0o500); operation.cancel() }
        })
        #expect(restricted.status == .cancelled && restricted.failure?.cleanupPath != nil)
        chmod(directory.path,0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".partial") }.count == 1)
    }
    @Test func realInFlightCancellationNeverPublishes() async throws {
        let directory = try temp(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        try Data(repeating: 7,count: 2_000_000).write(to: source)
        let gate = Base64FileOperation()
        let task = Task.detached {
            Base64FileProcessor.run(source: .file(source), options: .init(), destination: .init(directory: directory,name: "output.txt"),operation: gate,chunkSize: 5,
                progress: { _ in gate.cancel() })
        }
        let result = await task.value
        #expect(result.status == .cancelled && gate.exportedName == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("output.txt").path))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".partial") })
    }
}
