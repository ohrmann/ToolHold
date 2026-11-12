import Foundation
import Testing
import CryptoKit
@testable import JSONCore

struct JWTEncoderVector: Decodable {
    let alg: String, header: String, payload: String, key: String, encoding: String, message: String, signature: String, token: String
    var publicKey: String?
    var alternateKey: String?
    var request: JWTEncoderRequest { .init(header: header, payload: payload, key: key, keyEncoding: .init(rawValue: encoding)!) }
    static func all() throws -> [Self] {
        let path = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/JWTEncoder/vectors.json")
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: path))
    }
    static func rsa(_ size: Int) throws -> String { try String(contentsOf: Bundle.module.resourceURL!.appendingPathComponent("Fixtures/JWTEncoder/rsa-\(size).pem"), encoding: .utf8) }
}
struct JWTEncoderCryptoTests {
    @Test func independentVectorsAndAllKeyRepresentations() throws {
        let vectors = try JWTEncoderVector.all()
        #expect(vectors.count == 14)
        for vector in vectors {
            let key = try JWTSigningProvider.prepare(vector.request, algorithm: .init(rawValue: vector.alg)!)
            let signature = try key.sign(Data(vector.message.utf8))
            #expect(signature.count == key.signatureBytes)
            if vector.alg.hasPrefix("HS") || vector.alg.hasPrefix("RS") { #expect(signature.base64EncodedString() == vector.signature) }
            if case .ed(let edKey) = key { #expect(edKey.publicKey.isValidSignature(Data(base64Encoded: vector.signature)!, for: Data(vector.message.utf8))) }
            if let alternate = vector.alternateKey {
                var request = vector.request; request.key = alternate
                let second = try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!)
                #expect(try second.sign(Data(vector.message.utf8)).count == key.signatureBytes)
            }
            let result = JWTEncoderProcessor.process(vector.request)
            #expect(result.status == .generated)
            #expect(result.artifact?.token.hasPrefix(vector.message + ".") == true)
            let inspected = JWTProcessor.inspect(try #require(result.artifact?.token))
            #expect(inspected.algorithm == vector.alg && inspected.profile == .decoded)
        }
    }
    @Test func hmacEncodingByteCountsAndRejection() throws {
        let vector = try #require(JWTEncoderVector.all().first)
        for encoding in [JWTSigningKeyEncoding.utf8, .base64, .base64URL, .hex] {
            var request = vector.request; request.keyEncoding = encoding
            let bytes = Data(vector.key.utf8)
            switch encoding {
            case .base64: request.key = bytes.base64EncodedString()
            case .base64URL: request.key = JWTSigningProvider.base64URL(bytes)
            case .hex: request.key = bytes.map { String(format: "%02x", $0) }.joined()
            default: break
            }
            #expect(try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!).sign(Data(vector.message.utf8)).base64EncodedString() == vector.signature)
        }
        var request = vector.request; request.key = String(repeating: "😀", count: 8)
        #expect(JWTEncoderProcessor.process(request).status == .generated) //32 bytes,16 UTF16
        request.key = String(repeating: "a", count: 31)
        #expect(JWTEncoderProcessor.process(request).issues.contains { $0.code == "KEY-HMAC-SHORT" })
        for (encoding, text) in [(JWTSigningKeyEncoding.hex, "0"), (.hex, "ff gg"), (.base64, "YQ"), (.base64, "YR=="), (.base64, " YQ=="), (.base64URL, "YQ=="), (.base64URL, "YR")] {
            #expect(throws: (any Error).self) { try JWTSigningProvider.decodedSecret(text, encoding: encoding) }
        }
    }
    @Test func edSeedAndWrongCurveKeyFamilies() throws {
        let vectors = try JWTEncoderVector.all()
        let ed = try #require(vectors.first { $0.alg == "Ed25519" })
        let seed = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
        var request = ed.request; request.keyEncoding = .hex; request.key = seed
        #expect(JWTEncoderProcessor.process(request).artifact?.token.hasPrefix(ed.message + ".") == true)
        if case .ed(let key) = try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!) {
            #expect(key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined() == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
            #expect(key.publicKey.isValidSignature(Data(base64Encoded: ed.signature)!, for: Data(ed.message.utf8)))
        }
        request.key += seed
        #expect(JWTEncoderProcessor.process(request).status == .invalidInput)
        let ec = try #require(vectors.first { $0.alg == "ES256" })
        request = ec.request; request.header = #"{"alg":"ES384"}"#
        #expect(throws: (any Error).self) { try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!) }
        request = ec.request; request.key = ed.key
        #expect(throws: (any Error).self) { try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!) }
        request = ed.request; request.key = ec.key
        #expect(throws: (any Error).self) { try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!) }
    }
    @Test func rsaBoundariesAndPemFailures() throws {
        var request = try #require(JWTEncoderVector.all().first { $0.alg == "RS256" }).request
        for size in [1024,4096,8192] {
            request.key = try JWTEncoderVector.rsa(size)
            if size == 1024 { #expect(throws: (any Error).self) { try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!) } }
            else { let key = try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!); #expect(key.signatureBytes == size / 8); #expect(try key.sign(Data("probe".utf8)).count == size / 8) }
        }
        request.key = try #require(JWTEncoderVector.all().first { $0.alg == "RS256" }).key.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(try JWTSigningProvider.prepare(request, algorithm: JWTEncoderProcessor.headerAlgorithm(request.header)!).signatureBytes == 256)
        for text in [request.key + request.key, "unexpected" + request.key, request.key + "trailing", "-----BEGIN PUBLIC KEY-----\nAA==\n-----END PUBLIC KEY-----", "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAA==\n-----END ENCRYPTED PRIVATE KEY-----"] {
            #expect(throws: (any Error).self) { try JWTPrivateKeyImporter.pem(text) }
        }
    }
    @Test func derBoundsAndUnsupportedContainers() throws {
        for bytes: [UInt8] in [[0x30,0x80], [0x30,0x81,1,0], [0x30,0x82,0,0x80], [0x30,0x84,0xff,0xff,0xff,0xff], [0x30,2,0], [0x30,0,0]] {
            var reader = JWTDERReader(Data(bytes))
            if bytes == [0x30,0,0] { _ = try reader.read(0x30); #expect(!reader.finished) }
            else { #expect(throws: (any Error).self) { try reader.read(0x30) } }
        }
        var integer = JWTDERReader(Data([2,2,0,1])); #expect(throws: (any Error).self) { try integer.integer() }
        let vector = try #require(JWTEncoderVector.all().first { $0.alg == "Ed25519" })
        let pem = try JWTPrivateKeyImporter.pem(vector.key)
        for byte in 0..<pem.der.count { #expect(throws: (any Error).self) { try JWTPrivateKeyImporter.unwrapPKCS8(pem.der.prefix(byte), oid: JWTPrivateKeyImporter.edOID) } }
        var der = pem.der; der[4] = 1 //version0 ->1
        #expect(throws: (any Error).self) { try JWTPrivateKeyImporter.unwrapPKCS8(der, oid: JWTPrivateKeyImporter.edOID) }
    }
    #if os(macOS)
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/openssl"), "Independent verification requires the local OpenSSL test tool; no app dependency."))
    func independentlyVerifyGeneratedSignaturesAndTampering() throws {
        let ssl = "/opt/homebrew/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: ssl) else { throw TestFailure.missingIndependentVerifier }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jwt-encoder-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for vector in try JWTEncoderVector.all() where !vector.alg.hasPrefix("HS") {
            let key = try JWTSigningProvider.prepare(vector.request, algorithm: .init(rawValue: vector.alg)!)
            let message = Data(vector.message.utf8), raw = try key.sign(message)
            func integer(_ bytes: Data) -> Data {
                var value = Data(bytes.drop(while: { $0 == 0 })); if value.first.map({ $0 & 128 != 0 }) == true { value.insert(0, at: 0) }
                return Data([2,UInt8(value.count)]) + value
            }
            var signature = raw
            if vector.alg.hasPrefix("ES") {
                let part = raw.count / 2, body = integer(raw.prefix(part)) + integer(raw.suffix(part))
                signature = Data([0x30]) + (body.count >= 128 ? Data([0x81,UInt8(body.count)]) : Data([UInt8(body.count)])) + body
            }
            try Data(try #require(vector.publicKey).utf8).write(to: dir.appendingPathComponent("public.pem"))
            try signature.write(to: dir.appendingPathComponent("signature"))
            for variant in 0..<4 {
                var checkedMessage = message, checkedSignature = signature
                if variant == 1 { checkedMessage[checkedMessage.startIndex] ^= 1 }
                if variant == 2 { checkedMessage.append(0x20) }
                if variant == 3 { checkedSignature[checkedSignature.startIndex] ^= 1 }
                try checkedMessage.write(to: dir.appendingPathComponent("message"))
                try checkedSignature.write(to: dir.appendingPathComponent("signature"))
                let process = Process(); process.executableURL = URL(fileURLWithPath: ssl)
                if vector.alg.hasPrefix("Ed") { process.arguments = ["pkeyutl","-verify","-pubin","-rawin","-inkey",dir.appendingPathComponent("public.pem").path,"-sigfile",dir.appendingPathComponent("signature").path,"-in",dir.appendingPathComponent("message").path] }
                else {
                    process.arguments = ["dgst","-sha" + vector.alg.dropFirst(2),"-verify",dir.appendingPathComponent("public.pem").path,"-signature",dir.appendingPathComponent("signature").path]
                    if vector.alg.hasPrefix("PS") { process.arguments! += ["-sigopt","rsa_padding_mode:pss","-sigopt","rsa_pss_saltlen:digest","-sigopt","rsa_mgf1_md:sha" + vector.alg.dropFirst(2)] }
                    process.arguments!.append(dir.appendingPathComponent("message").path)
                }
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit()
                #expect((process.terminationStatus == 0) == (variant == 0))
            }
        }
    }
    enum TestFailure: Error { case missingIndependentVerifier }
    #endif
}
