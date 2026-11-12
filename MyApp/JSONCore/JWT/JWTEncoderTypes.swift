import Foundation

enum JWTSigningAlgorithm: String, Codable, CaseIterable, Sendable {
    case hs256 = "HS256", hs384 = "HS384", hs512 = "HS512"
    case rs256 = "RS256", rs384 = "RS384", rs512 = "RS512"
    case ps256 = "PS256", ps384 = "PS384", ps512 = "PS512"
    case es256 = "ES256", es384 = "ES384", es512 = "ES512"
    case ed25519 = "Ed25519", edDSA = "EdDSA", none = "none"
    enum Family { case hmac, rsa, ec, ed, unsigned }
    var family: Family {
        switch self {
        case .hs256, .hs384, .hs512: .hmac
        case .rs256, .rs384, .rs512, .ps256, .ps384, .ps512: .rsa
        case .es256, .es384, .es512: .ec
        case .ed25519, .edDSA: .ed
        case .none: .unsigned
        }
    }
    var title: String { self == .edDSA ? "EdDSA (legacy · Ed25519)" : self == .none ? "none · Unsigned test token" : rawValue }
    var signatureBytes: Int {
        switch self {
        case .hs256: 32
        case .hs384: 48
        case .hs512, .es256, .ed25519, .edDSA: 64
        case .es384: 96
        case .es512: 132
        case .none: 0
        default: 1024 // conservative 8192-bit RSA bound; actual size checked before signing
        }
    }
}
enum JWTSigningKeyEncoding: String, Codable, CaseIterable, Sendable {
    case utf8 = "UTF-8", base64 = "Base64", base64URL = "Base64URL", hex = "Hex", pem = "PEM"
}
enum JWTEncoderSerialization: String, Codable, CaseIterable, Sendable {
    case compact = "Compact JSON", preserve = "Preserve JSON text"
}
struct JWTEncoderRequest: Sendable {
    var header: String
    var payload: String
    var key: String = ""
    var keyEncoding: JWTSigningKeyEncoding = .utf8
    var serialization: JWTEncoderSerialization = .compact
    var unsignedConsent = false
    var revision = UUID()
}
struct JWTEncoderIssue: Sendable, Identifiable {
    enum Component: String, Sendable { case header = "Header", payload = "Payload", key = "Signing key", operation = "Operation" }
    let id = UUID()
    let code: String
    let component: Component
    let severity: JSONDiagnostic.Severity
    let message: String
    var diagnostic: JSONDiagnostic?
    var context: JSONDiagnosticContext?
}
struct JWTEncoderArtifact: Sendable {
    let id = UUID()
    let revision: UUID
    let token: String
    let algorithm: JWTSigningAlgorithm
    var byteCount: Int { token.utf8.count }
}
struct JWTEncoderResult: Sendable {
    enum Status: String, Sendable {
        case generated = "JWT generated", checked = "Check complete", invalidInput = "Input needs attention"
        case unsupported = "Unsupported profile", resourceLimit = "Resource limit reached"
        case cancelled = "Cancelled", cryptoFailure = "Signing failed"
    }
    var status: Status = .checked
    var issues: [JWTEncoderIssue] = []
    var issueCount = 0
    var artifact: JWTEncoderArtifact?
    mutating func add(_ issue: JWTEncoderIssue) { issueCount += 1; if issues.count < 100 { issues.append(issue) } }
}
enum JWTEncoderMode: Sendable { case generate, check, jsonOnly }
struct JWTSigningFailure: Error {
    let code: String
    let message: String
    var status: JWTEncoderResult.Status = .invalidInput
}
enum JWTEncoderLimits {
    static let json = 262_144, token = 262_144, keyInput = 65_536, keyBytes = 16_384, hmacBytes = 8192
}
