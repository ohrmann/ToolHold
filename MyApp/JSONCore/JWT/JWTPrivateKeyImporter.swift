import Foundation
import Security

/// Only the small DER envelopes we explicitly support. No key arithmetic or BER recovery.
struct JWTDERReader {
    private let bytes: [UInt8]
    private(set) var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    var finished: Bool { offset == bytes.count }
    mutating func read(_ tag: UInt8) throws -> Data {
        guard offset + 2 <= bytes.count, bytes[offset] == tag else { throw Self.invalid }
        offset += 1
        var length = Int(bytes[offset]); offset += 1
        if length & 0x80 != 0 {
            let n = length & 0x7f
            guard n > 0, n <= 4, offset + n <= bytes.count, bytes[offset] != 0 else { throw Self.invalid }
            length = 0
            for _ in 0..<n { length = length * 256 + Int(bytes[offset]); offset += 1 }
            guard length >= 128 else { throw Self.invalid }
        }
        guard length <= bytes.count - offset else { throw Self.invalid }
        let data = Data(bytes[offset..<offset+length]); offset += length
        return data
    }
    mutating func integer() throws -> Data {
        let data = try read(2)
        guard let first = data.first, first & 0x80 == 0,
              data.count < 2 || first != 0 || data[data.startIndex + 1] & 0x80 != 0 else { throw Self.invalid }
        return data
    }
    static var invalid: JWTSigningFailure { .init(code: "KEY-DER", message: "Invalid or unsupported private-key DER container.") }
}
struct JWTPEMBlock {
    let label: String
    let der: Data
    var canonical: String { "-----BEGIN \(label)-----\n" + der.base64EncodedString(options: .lineLength64Characters) + "\n-----END \(label)-----" }
}
enum JWTPrivateKeyImporter {
    static let rsaOID = Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01])
    static let edOID = Data([0x2b,0x65,0x70])
    static let ecOID = Data([0x2a,0x86,0x48,0xce,0x3d,0x02,0x01])
    static func pem(_ text: String) throws -> JWTPEMBlock {
        guard text.utf16.prefix(JWTEncoderLimits.keyInput + 1).count <= JWTEncoderLimits.keyInput else {
            throw JWTSigningFailure(code: "KEY-SIZE", message: "Key input exceeds 65,536 UTF-16 code units.", status: .resourceLimit)
        }
        let white = CharacterSet(charactersIn: " \t\r\n")
        let text = text.trimmingCharacters(in: white)
        guard text.hasPrefix("-----BEGIN "), let end = text.range(of: "-----", range: text.index(text.startIndex, offsetBy: 11)..<text.endIndex) else { throw JWTDERReader.invalid }
        let label = String(text[text.index(text.startIndex, offsetBy: 11)..<end.lowerBound])
        guard ["PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY"].contains(label) else {
            throw JWTSigningFailure(code: "KEY-PEM-PROFILE", message: "Use one unencrypted private-key PEM block. Public keys, certificates and encrypted keys are not supported.", status: .unsupported)
        }
        let footer = "-----END \(label)-----"
        guard text.hasSuffix(footer) else { throw JWTDERReader.invalid }
        let body = text[end.upperBound..<text.index(text.endIndex, offsetBy: -footer.count)]
        guard body.unicodeScalars.allSatisfy({ $0.value < 128 }) else { throw JWTDERReader.invalid }
        let encoded = String(body.unicodeScalars.filter { !white.contains($0) })
        guard let der = Data(base64Encoded: encoded), der.base64EncodedString() == encoded else { throw JWTDERReader.invalid }
        guard der.count <= JWTEncoderLimits.keyBytes else { throw JWTSigningFailure(code: "KEY-SIZE", message: "Decoded key exceeds 16,384 bytes.", status: .resourceLimit) }
        return .init(label: label, der: der)
    }
    static func unwrapPKCS8(_ der: Data, oid: Data, rsa: Bool = false) throws -> Data {
        var outer = JWTDERReader(der), seq = JWTDERReader(try outer.read(0x30))
        guard outer.finished else { throw JWTDERReader.invalid }
        guard try seq.integer() == Data([0]) else { throw JWTSigningFailure(code: "KEY-PKCS8-VERSION", message: "Only PKCS#8 version 0 is supported.", status: .unsupported) }
        var algorithm = JWTDERReader(try seq.read(0x30))
        guard try algorithm.read(6) == oid else { throw JWTSigningFailure(code: "KEY-TYPE", message: "The private-key algorithm does not match the selected signing algorithm.") }
        if rsa && !algorithm.finished { guard try algorithm.read(5).isEmpty else { throw JWTDERReader.invalid } }
        guard algorithm.finished else { throw JWTDERReader.invalid }
        let key = try seq.read(4)
        guard seq.finished else { throw JWTSigningFailure(code: "KEY-PKCS8", message: "Only PKCS#8 version 0 without attributes is supported.", status: .unsupported) }
        return key
    }
    static func rsa(_ pem: JWTPEMBlock) throws -> SecKey {
        let der: Data
        switch pem.label {
        case "PRIVATE KEY": der = try unwrapPKCS8(pem.der, oid: rsaOID, rsa: true)
        case "RSA PRIVATE KEY": der = pem.der
        default: throw JWTSigningFailure(code: "KEY-TYPE", message: "An RSA private key is required.")
        }
        var outer = JWTDERReader(der), fields = JWTDERReader(try outer.read(0x30))
        guard outer.finished, try fields.integer() == Data([0]) else { throw JWTSigningFailure(code: "KEY-RSA-VERSION", message: "Only two-prime RSA private keys are supported.", status: .unsupported) }
        let modulus = try fields.integer()
        for _ in 0..<7 { let field = try fields.integer(); guard field.contains(where: { $0 != 0 }) else { throw JWTDERReader.invalid } }
        guard fields.finished else { throw JWTDERReader.invalid }
        let significant = modulus.drop(while: { $0 == 0 })
        let bits = significant.count * 8 - (significant.first?.leadingZeroBitCount ?? 0)
        guard bits >= 2048, bits <= 8192 else { throw JWTSigningFailure(code: "KEY-RSA-SIZE", message: "RSA keys must contain 2,048–8,192 bits.") }
        var error: Unmanaged<CFError>?
        let imported = SecKeyCreateWithData(der as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, &error)
        if let error { _ = error.takeRetainedValue() }
        guard let imported else { throw JWTDERReader.invalid }
        return imported
    }
    static func edSeed(_ pem: JWTPEMBlock) throws -> Data {
        guard pem.label == "PRIVATE KEY" else { throw JWTSigningFailure(code: "KEY-TYPE", message: "Use an Ed25519 PKCS#8 private key or a 32-byte seed.") }
        let wrapped = try unwrapPKCS8(pem.der, oid: edOID)
        var reader = JWTDERReader(wrapped)
        let seed = try reader.read(4)
        guard reader.finished, seed.count == 32 else { throw JWTDERReader.invalid }
        return seed
    }
}
