import Foundation
#if canImport(CertificateCore)
import CertificateCore
#endif
import CToolboxPKI

public enum PKIStatus: String, Sendable { case ready, processing, completed, completedWithWarnings, invalidInput, unsupported, needsPassword, resourceLimit, cancelled, failed }
public struct PKIFailure: Error, LocalizedError, Sendable {
    public let status: PKIStatus
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String, status: PKIStatus = .invalidInput) { self.message = message; self.status = status }
}
public enum PKILimits {
    public static let file = 4 * 1024 * 1024, object = 262_144, key = 65_536, pfx = 8 * 1024 * 1024
}
public enum PKIAlgorithm: String, CaseIterable, Sendable, Identifiable {
    case p256 = "P-256", p384 = "P-384", p521 = "P-521", ed25519 = "Ed25519", rsa2048 = "RSA 2048", rsa3072 = "RSA 3072", rsa4096 = "RSA 4096"
    public var id: String { rawValue }
    var name: String { rawValue.hasPrefix("RSA") ? "RSA" : rawValue }
    var bits: Int32 { Int32(rawValue.split(separator: " ").last ?? "") ?? 0 }
}
public enum PKIProfile: Int, CaseIterable, Sendable, Identifiable {
    case server, client, root
    public var id: Int { rawValue }
    public var title: String { switch self { case .server: "TLS Server"; case .client: "TLS Client"; case .root: "Development Root CA" } }
}
public struct PKISAN: Sendable, Equatable, Identifiable {
    public enum Kind: Int, CaseIterable, Sendable, Identifiable { case dns = 2, ip = 7, uri = 6, email = 1
        public var id: Int { rawValue }
        public var title: String { switch self { case .dns: "DNS"; case .ip: "IP"; case .uri: "URI"; case .email: "Email" } }
    }
    public var id = UUID(), kind: Kind, value: String
    public init(kind: Kind = .dns, value: String = "") { self.kind = kind; self.value = value }
}
public struct PKIGenerationDraft: Sendable, Equatable {
    public var algorithm: PKIAlgorithm = .p256, profile: PKIProfile = .server
    public var useImportedKey = false, importedKey = "", keyPassword = ""
    public var commonName = "localhost", organization = "", unit = "", locality = "", state = "", country = ""
    public var sans: [PKISAN] = [.init(kind: .dns, value: "localhost"), .init(kind: .ip, value: "127.0.0.1"), .init(kind: .ip, value: "::1")]
    public var pathLength = 0, notBefore = Date().addingTimeInterval(-300), notAfter = Date().addingTimeInterval(365 * 86400)
    public init() {}
    public static func == (a: Self,b: Self) -> Bool {
        guard a.algorithm == b.algorithm, a.profile == b.profile, a.useImportedKey == b.useImportedKey, a.pathLength == b.pathLength, a.notBefore == b.notBefore, a.notAfter == b.notAfter, a.sans.count == b.sans.count else { return false }
        let left = [a.importedKey,a.keyPassword,a.commonName,a.organization,a.unit,a.locality,a.state,a.country]
        let right = [b.importedKey,b.keyPassword,b.commonName,b.organization,b.unit,b.locality,b.state,b.country]
        return zip(left,right).allSatisfy { $0.utf8.elementsEqual($1.utf8) } && zip(a.sans,b.sans).allSatisfy { $0.id == $1.id && $0.kind == $1.kind && $0.value.utf8.elementsEqual($1.value.utf8) }
    }
}
public struct PKIObject: Identifiable, Sendable {
    public let id: Int, label: String, data: Data, sourceRange: NSRange?
    public var sensitive: Bool { label.contains("PRIVATE") }
    public var pem: String { PEMEnvelopeReader.encode(data, label: label) }
    public var fingerprint: String { CertificateDisplay.digest(data) }
}
public struct PKIKeyInfo: Sendable {
    public let handle: Int32, algorithm: String, bits: Int, isPrivate: Bool, spki: Data, consistent: Bool
    public var publicDetails = ""
    public var sourceFingerprint: String? = nil
    public var fingerprint: String { CertificateDisplay.digest(spki) }
    public var publicPEM: String { PEMEnvelopeReader.encode(spki, label: "PUBLIC KEY") }
    public var report: String { (sourceFingerprint.map { "Original DER SHA-256: \($0)\n" } ?? "") + "Type: \(isPrivate ? "Private" : "Public")\nAlgorithm: \(algorithm)\nBits: \(bits)\n\(publicDetails)Consistency: \(consistent ? "Passed" : "Not confirmed")\nSPKI SHA-256: \(fingerprint)\n\n" + publicPEM }
}
public struct PKIGenerated: Sendable {
    public let object: PKIObject, key: PKIKeyInfo
}
public struct PKICSRInfo: Sendable {
    public let object: PKIObject, signatureValid: Bool, summary: String, spki: Data
}
public struct PKIBag: Identifiable, Sendable {
    public let id: Int, key: Int32, certificate: Int32, summary: String, certificateDER: Data?, publicKey: PKIKeyInfo?
    public var matchingCertificates: [Int32] = []
}
public struct PKIPFXInfo: Sendable {
    public let bags: [PKIBag], verified: Bool, rewritable: Bool
    public var protection = ""
    public var report: String { (verified ? "Integrity MAC verified" : "Integrity not authenticated") + "\n" + bags.map(\.summary).joined(separator: "\n\n") }
}
public struct PKIChainResult: Sendable { public let valid: Bool, report: String, chain: [Data] }

/// Never enters Observable/Codable snapshots. Accessed only by PKIEngine's actor.
final class PKIHandle {
    let raw: OpaquePointer
    init() throws { guard let value = tb_pki_new() else { throw PKIFailure("Cryptographic backend unavailable", status: .failed) }; raw = value }
    deinit { tb_pki_free(raw) }
    func error() -> PKIFailure {
        let kind = tb_pki_error_kind(raw)
        let status: PKIStatus = switch kind { case 2: .unsupported; case 3: .resourceLimit; case 4: .needsPassword; case 5: .cancelled; case 6: .failed; default: .invalidInput }
        return .init(String(cString: tb_pki_error(raw)), status: status)
    }
    func bytes(_ action: (UnsafeMutablePointer<TBPKIBuffer>) -> Int32) throws -> Data {
        var buffer = TBPKIBuffer(); defer { tb_pki_buffer_free(buffer) }
        guard action(&buffer) != 0 else { throw error() }
        guard buffer.count <= PKILimits.pfx else { throw PKIFailure("Output exceeds its resource limit", status: .resourceLimit) }
        return buffer.count == 0 ? Data() : Data(bytes: buffer.bytes, count: buffer.count)
    }
}
