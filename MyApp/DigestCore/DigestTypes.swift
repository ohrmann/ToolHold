import Foundation
#if SWIFT_PACKAGE
import EncodingCore
#endif

enum DigestAlgorithm: String, CaseIterable, Codable, Sendable {
    case sha256, sha384, sha512, md5, sha1, crc32, adler32
    var title: String { switch self { case .sha256: "SHA-256"; case .sha384: "SHA-384"; case .sha512: "SHA-512"; case .md5: "MD5"; case .sha1: "SHA-1"; case .crc32: "CRC-32"; case .adler32: "Adler-32" } }
    var note: String { switch self { case .md5, .sha1: "Legacy · not for security"; case .crc32: "Checksum · CRC-32/ISO-HDLC"; case .adler32: "Checksum · non-cryptographic"; default: "Cryptographic hash" } }
    var count: Int { switch self { case .sha256: 32; case .sha384: 48; case .sha512: 64; case .md5: 16; case .sha1: 20; case .crc32, .adler32: 4 } }
    static let hmac: [Self] = [.sha256, .sha384, .sha512]
}
enum DigestFormat: String, CaseIterable, Codable, Sendable {
    case hex, base64, base64URL
    var title: String { switch self { case .hex: "Hex"; case .base64: "Base64"; case .base64URL: "Base64URL" } }
    func string(_ bytes: Data, uppercase: Bool = false) -> String {
        switch self {
        case .hex:
            let symbols = Array((uppercase ? "0123456789ABCDEF" : "0123456789abcdef").utf8)
            var output = [UInt8](); output.reserveCapacity(bytes.count * 2)
            for byte in bytes { output.append(symbols[Int(byte >> 4)]); output.append(symbols[Int(byte & 15)]) }
            return String(decoding: output, as: UTF8.self)
        case .base64: return bytes.base64EncodedString()
        case .base64URL: return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
    }
}
enum DigestSourceMode: String, CaseIterable, Codable, Sendable {
    case text, hex, base64, base64URL, file
    var title: String { self == .file ? "File" : profile.title }
    var profile: ExactByteProfile { ExactByteProfile(rawValue: rawValue) ?? .text }
}
enum DigestStatus: String, Sendable { case success, invalidInput, resourceLimit, cancelled, sourceChanged, ioFailure, cryptoFailure }
struct DigestIssue: Error, Sendable {
    let status: DigestStatus
    let message: String
    var field = "message"
    var range: NSRange?
}
struct DigestRequest: Sendable {
    var mode = DigestSourceMode.text
    var text = ""
    var file: URL?
    var algorithms: [DigestAlgorithm] = [.sha256]
    var isHMAC = false
    var key = ""
    var keyProfile = ExactByteProfile.text
    var allowEmptyKey = false
}
struct DigestArtifact: Sendable {
    let values: [DigestAlgorithm: Data]
    let bytes: Int64
    let keyBytes: Int?
    let isHMAC: Bool
}
struct DigestResult: Sendable { var artifact: DigestArtifact?; var issue: DigestIssue? }
struct DigestProgress: Sendable { let bytes: Int64; let total: Int64? }
struct DigestFileInfo: Sendable {
    let url: URL; let name: String; let size: Int64?
    static func label(_ text: String) -> String {
        var value = ""
        for scalar in text.unicodeScalars.prefix(160) {
            let n = scalar.value
            if CharacterSet.controlCharacters.contains(scalar) || [0x061c,0x200e,0x200f,0x2028,0x2029].contains(n) || (0x202a...0x202e).contains(n) || (0x2066...0x2069).contains(n) { value += "\\u{\(String(n, radix: 16))}" }
            else { value.unicodeScalars.append(scalar) }
        }
        return value + (text.unicodeScalars.count > 160 ? "…" : "")
    }
}
