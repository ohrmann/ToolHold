import Foundation
import Darwin
import Testing
@testable import DigestCore
import EncodingCore

struct DigestProcessorTests {
    func request(_ text: String = "", _ algorithms: [DigestAlgorithm] = DigestAlgorithm.allCases) -> DigestRequest { .init(text: text, algorithms: algorithms) }
    @Test func knownHashes() throws {
        let expected = ["e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b", "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", "d41d8cd98f00b204e9800998ecf8427e", "da39a3ee5e6b4b0d3255bfef95601890afd80709", "00000000", "00000001"]
        let result = try #require(DigestProcessor.run(request()).artifact)
        for (algorithm, expected) in zip(DigestAlgorithm.allCases, expected) { #expect(DigestFormat.hex.string(try #require(result.values[algorithm])) == expected) }
        let abc = try #require(DigestProcessor.run(request("abc")).artifact)
        #expect(DigestFormat.hex.string(abc.values[.sha256]!) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(DigestFormat.hex.string(abc.values[.md5]!) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(DigestFormat.hex.string(abc.values[.sha1]!) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        let checksums = try #require(DigestProcessor.run(request("123456789")).artifact)
        #expect(DigestFormat.hex.string(checksums.values[.crc32]!) == "cbf43926")
        #expect(DigestFormat.hex.string(checksums.values[.adler32]!) == "091e01de")
    }
    @Test func rfc4231() throws {
        let expected = ["b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6", "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854".replacingOccurrences(of: " ", with: "")]
        for (algorithm, expected) in zip(DigestAlgorithm.hmac, expected) {
            let r = DigestRequest(text: "Hi There", algorithms: [algorithm], isHMAC: true, key: String(repeating: "0b", count: 20), keyProfile: .hex)
            #expect(DigestFormat.hex.string(try #require(DigestProcessor.run(r).artifact?.values[algorithm])) == expected)
        }
        let expectedLong = ["60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", "4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952", "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598"]
        for (algorithm, expected) in zip(DigestAlgorithm.hmac, expectedLong) {
            let r = DigestRequest(text: "Test Using Larger Than Block-Size Key - Hash Key First", algorithms: [algorithm], isHMAC: true, key: String(repeating: "aa", count: 131), keyProfile: .hex)
            #expect(DigestFormat.hex.string(try #require(DigestProcessor.run(r).artifact?.values[algorithm])) == expected)
        }
    }
    // RFC4231 cases 2,3,4,7; captured with Python hashlib/hmac as an independent implementation.
    @Test func additionalRFC4231AndBinaryChunkBoundaries() throws {
        let fixtures: [(String, String, [String])] = [
            ("4a656665", "7768617420646f2079612077616e7420666f72206e6f7468696e673f", ["5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", "af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649", "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"]),
            ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", ["773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe", "88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b2a5ab39dc13814b94e3ab6e101a34f27", "fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb"]),
            ("0102030405060708090a0b0c0d0e0f10111213141516171819", "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd", ["82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b", "3e8a69b7783c25851933ab6290af6ca77a9981480850009cc5577c6e1f573b4e6801dd23c4a7d679ccf8a386c674cffb", "b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3dba91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd"]),
            ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "5468697320697320612074657374207573696e672061206c6172676572207468616e20626c6f636b2d73697a65206b657920616e642061206c6172676572207468616e20626c6f636b2d73697a6520646174612e20546865206b6579206e6565647320746f20626520686173686564206265666f7265206265696e6720757365642062792074686520484d414320616c676f726974686d2e", ["9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2", "6617178e941f020d351e2f254e8fd32c602420feb0b8fb9adccebb82461e99c5a678cc31e799176d3860e6110c46523e", "e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58"]),
        ]
        for (key, message, values) in fixtures {
            for (algorithm, expected) in zip(DigestAlgorithm.hmac, values) {
                let request = DigestRequest(mode: .hex, text: message, algorithms: [algorithm], isHMAC: true, key: key, keyProfile: .hex)
                for chunk in [1,63,64,65,127,128,129,65536] {
                    #expect(DigestFormat.hex.string(try #require(DigestProcessor.run(request, chunkSize: chunk).artifact?.values[algorithm])) == expected)
                }
            }
        }
    }
    @Test func strictProfilesAndRanges() throws {
        for profile in ExactByteProfile.allCases {
            let input: String = switch profile { case .text: "hi"; case .hex: "6869"; case .base64: "aGk="; case .base64URL: "aGk" }
            #expect(try ExactByteInputDecoder.decode(input, profile: profile) == Data("hi".utf8))
            #expect(try ExactByteInputDecoder.decode("", profile: profile).isEmpty)
        }
        for (profile, samples) in [(ExactByteProfile.hex, ["0x00","ab cd","0","🧑‍💻"]), (.base64,["Zg","Zh==","Zg==\n","_w==","Zg==="]), (.base64URL,["Zg==","Zh","Z","/w"])] {
            for sample in samples { #expect(throws: ExactByteFailure.self) { try ExactByteInputDecoder.decode(sample, profile: profile) } }
        }
        do { _ = try ExactByteInputDecoder.decode("00😀", profile: .hex); Issue.record("accepted emoji") }
        catch let f as ExactByteFailure { #expect(f.range == NSRange(location: 2, length: 2)) }
        #expect(throws: ExactByteFailure.self) { try ExactByteInputDecoder.decode("a", profile: .text, byteLimit: 0) }
    }
    @Test func unicodeAndChunkParity() throws {
        let samples = ["é", "e\u{301}", "👩‍💻\r\n\u{feff}\u{0}", "abc\n", "abc"]
        var values = [Data]()
        for text in samples {
            let reference = try #require(DigestProcessor.run(request(text)).artifact)
            values.append(reference.values[.sha256]!)
            for chunk in [1,63,64,65,127,128,129,65536] {
                #expect(DigestProcessor.run(request(text), chunkSize: chunk).artifact?.values == reference.values)
            }
        }
        #expect(values[0] != values[1]); #expect(values[3] != values[4])
    }
    @Test func streamedBinaryFileAndReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("input")
        let data = Data((0..<4096).map { UInt8($0 & 255) }); try data.write(to: url)
        let encoded = DigestRequest(mode: .base64, text: data.base64EncodedString(), algorithms: DigestAlgorithm.allCases)
        let reference = try #require(DigestProcessor.run(encoded).artifact)
        let file = DigestRequest(mode: .file, file: url, algorithms: DigestAlgorithm.allCases)
        for chunk in [1,63,64,65,127,128,129,65536] { #expect(DigestProcessor.run(file, chunkSize: chunk).artifact?.values == reference.values) }
        var once = false
        #expect(throws: DigestIssue.self) {
            try DigestFileReader.read(url, chunkSize: 100) { _ in
                if !once { once = true; try Data([2]).write(to: url, options: .atomic) }
            }
        }
        #expect(DigestProcessor.run(.init(mode: .file, file: directory)).issue?.status == .ioFailure)
        #expect(DigestProcessor.run(.init(mode: .file, file: directory.appendingPathComponent("missing"))).issue?.status == .ioFailure)
        try Data().write(to: url)
        #expect(DigestProcessor.run(.init(mode: .file, file: url)).artifact?.bytes == 0)
    }
    @Test func invalidKeyBeforeFileAndLimits() {
        var r = DigestRequest(mode: .file, file: URL(fileURLWithPath: "/missing"), isHMAC: true)
        #expect(DigestProcessor.run(r).issue?.field == "key")
        r.key = "z"; r.keyProfile = .hex
        #expect(DigestProcessor.run(r).issue?.field == "key")
        r.keyProfile = .text; r.key = String(repeating: "a", count: 16_385)
        #expect(DigestProcessor.run(r).issue?.status == .resourceLimit)
        #expect(DigestProcessor.run(.init(text: String(repeating: "a", count: 262_145))).issue?.status == .resourceLimit)
        r = .init(isHMAC: true, allowEmptyKey: true)
        #expect(DigestProcessor.run(r).artifact?.keyBytes == 0)
        r.algorithms = [.md5]; #expect(DigestProcessor.run(r).issue?.status == .invalidInput)
    }
    @Test func filePermissionsSpecialFilesAndInPlaceMutation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source"), fifo = folder.appendingPathComponent("fifo")
        try Data(repeating: 1, count: 4096).write(to: source)
        #expect(chmod(source.path, 0) == 0)
        #expect(DigestProcessor.run(.init(mode: .file, file: source)).issue?.status == .ioFailure)
        #expect(chmod(source.path, 0o600) == 0)
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(DigestProcessor.run(.init(mode: .file, file: fifo)).issue?.status == .ioFailure)
        var changed = false
        do {
            _ = try DigestFileReader.read(source, chunkSize: 64) { _ in
                if !changed {
                    changed = true; let handle = try FileHandle(forWritingTo: source)
                    try handle.write(contentsOf: Data([2])); try handle.close()
                }
            }
            Issue.record("accepted mutation")
        } catch let issue as DigestIssue { #expect(issue.status == .sourceChanged) }
        let remote = DigestProcessor.run(.init(mode: .file, file: URL(string: "https://example.invalid/data")!))
        #expect(remote.issue?.status == .ioFailure)
        #expect(DigestFileInfo.label("abc\u{202e}\n").contains("\\u{202e}"))
        let bytes = Data([0xcb,0xf4,0x39,0x26])
        #expect(DigestFormat.base64.string(bytes) == "y/Q5Jg==")
        #expect(DigestFormat.base64URL.string(bytes) == "y_Q5Jg")
    }
    @Test func cancellation() async {
        let child = Task { () -> DigestResult in
            withUnsafeCurrentTask { $0?.cancel() }; return DigestProcessor.run(.init(text: "abc"))
        }
        #expect(await child.value.issue?.status == .cancelled)
    }
}
