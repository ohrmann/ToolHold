import Foundation

enum JWTVerificationKeyFormat: String, CaseIterable, Codable, Sendable {
    case publicPEM = "Public Key PEM", certificate = "Certificate PEM", jwk = "Local JWK / JWKS"
    case secretUTF8 = "Secret · UTF-8", secretBase64 = "Secret · Base64", secretBase64URL = "Secret · Base64URL", secretHex = "Secret · Hex"
    case edHex = "Ed25519 public · Hex", edBase64 = "Ed25519 public · Base64"
    var secret: Bool { [.secretUTF8,.secretBase64,.secretBase64URL,.secretHex].contains(self) }
}
struct JWTClaimsPolicy: Equatable, Sendable {
    var checkTime = true, requireExp = false, requireNbf = false, requireIat = false, checkFutureIat = false
    var issuerEnabled = false, audienceEnabled = false, subjectEnabled = false
    var issuer = "", audience = "", subject = ""
    var skew = 0
    var customTime = false, reference = Date.now
}
struct JWTVerifierRequest: Sendable {
    var token = "", key = ""
    var algorithm: JWTSigningAlgorithm?
    var format = JWTVerificationKeyFormat.publicPEM
    var keyIndex: Int? = nil
    var policy = JWTClaimsPolicy()
    var revision = UUID()
}
struct JWTVerificationCheck: Identifiable, Sendable {
    enum State: String, Sendable { case passed, failed, notPresent, notConfigured }
    let id: String, state: State, message: String
}
struct JWTVerifierResult: Sendable {
    enum Processing: String, Sendable { case completed, resourceLimit, cancelled, failed }
    enum Signature: String, Sendable { case notChecked = "Signature not checked", matches = "Signature matches supplied key", doesNotMatch = "Signature does not match" }
    enum Profile: String, Sendable { case notEvaluated, supported, malformed, ambiguous, unsupported }
    var profile = Profile.notEvaluated
    var processing = Processing.completed
    var signature = Signature.notChecked
    var message = "Choose an expected algorithm and provide a verification key."
    var inspection: JWTInspectionResult?
    var checks: [JWTVerificationCheck] = []
    var keyIdentity = "", algorithm = ""
    var keyNotes: [String] = []
    var evaluatedAt = Date.now
    var referenceTime = Date.now
    var policySummary = ""
    var expiresAt: Date?
    var claimsEvaluated = false
    var revision = UUID()
    var claimsPassed: Bool { claimsEvaluated && !checks.contains { $0.state == .failed } }
    var summary: String {
        // No token, key, actual or expected claim values are included.
        "\(signature.rawValue)\nProfile: \(profile.rawValue)\nAlgorithm: \(algorithm)\nClaims: \(claimsEvaluated ? (claimsPassed ? "Configured checks passed" : "Checks failed") : "Not authenticated / not evaluated")\n\(checks.map { "\($0.id): \($0.state.rawValue)" }.joined(separator: "\n"))\nEvaluated: \(ISO8601DateFormatter().string(from: evaluatedAt))\nReference time: \(ISO8601DateFormatter().string(from:referenceTime))\n\(policySummary)\nKey provenance and issuer trust are the caller's responsibility."
    }
}
struct JWTKeyChoice: Identifiable, Sendable {
    let id: Int, title: String, supported: Bool
}
struct JWTVerificationFailure: Error, Sendable {
    let message: String
    var resource = false
    init(_ message: String, resource: Bool = false) { self.message = message; self.resource = resource }
}
