import Foundation
import CryptoKit

public enum CertificateLimits {
    public static let file = 4 * 1024 * 1024, editor = 262_144, certificate = 262_144, count = 64
}
public struct CertificateFailure: Error, Sendable, LocalizedError {
    public enum Kind: Sendable { case malformed, unsupported, resource, loading }
    public let kind: Kind
    public let message: String
    public var errorDescription: String? { message }
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
    public init(_ message: String) { self.init(.malformed, message) }
}
public struct CertificateField: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let value: String
    public init(id: Int, name: String, value: String) { self.id = id; self.name = name; self.value = value }
}
public struct CertificateExtension: Identifiable, Sendable {
    public let id: Int, oid: String, critical: Bool, bytes: Data
    public let fields: [CertificateField]
    public let issue: String?
    public var rawHex: String = ""
}
public struct CertificateEntry: Identifiable, Sendable {
    public let id: Int
    public let der: Data
    public let sourceRange: NSRange?
    public var fields: [CertificateField] = []
    public var extensions: [CertificateExtension] = []
    public var issues: [String] = []
    public var subject = "Certificate", issuer = ""
    public var notBefore: Date?, notAfter: Date?
    public var spki: Data?
    public var parsed = false
    public var pem: String { PEMEnvelopeReader.encode(der, label: "CERTIFICATE") }
    public var sha256 = ""
    public var sha1 = ""
    public var spkiDigest: String?
    public func validity(at now: Date) -> String {
        guard let a = notBefore, let b = notAfter else { return "Validity unavailable" }
        if a > b { return "Invalid validity interval" }
        if now < a { return "Not yet valid" }
        if now > b { return "Expired" }
        return "Within validity period"
    }
}
public struct CertificateResult: Sendable {
    public enum Status: String, Sendable { case completed, completedWithIssues, resourceLimit, cancelled, failed }
    public var status: Status
    public var entries: [CertificateEntry]
    public var message: String
    public var evaluatedAt: Date
}
public enum CertificateDisplay {
    public static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02X", $0) }.joined(separator: ":") }
    public static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02X", $0) }.joined() }
    public static func safe(_ text: String, limit: Int = 4096) -> String {
        var s = ""
        for c in text.unicodeScalars.prefix(limit) {
            if c.value < 32 || (0x7f...0x9f).contains(c.value) || (0x202a...0x202e).contains(c.value) || (0x2066...0x2069).contains(c.value) || c.value == 0x200e || c.value == 0x200f || c.value == 0x061c {
                s += String(format: "\\u{%04X}", c.value)
            } else { s.unicodeScalars.append(c) }
        }
        if text.unicodeScalars.count > limit { s += "…" }
        return s
    }
    public static func date(_ date: Date, local: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = local ? .current : TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss XXXXX"; return f.string(from: date)
    }
}
