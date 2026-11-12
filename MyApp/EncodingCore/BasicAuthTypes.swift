import Foundation

enum BasicAuthEncoding: String, Codable, CaseIterable, Sendable {
    case utf8, latin1
    var title: String { self == .utf8 ? "UTF-8" : "ISO-8859-1 (Latin-1)" }
}
struct BasicAuthOptions: Equatable, Sendable {
    var encoding = BasicAuthEncoding.utf8
    var normalizeNFC = false
    var effective: Self { .init(encoding: encoding, normalizeNFC: encoding == .utf8 && normalizeNFC) }
}
struct BasicAuthRequest: Sendable { let username: String; let password: String; var options = BasicAuthOptions() }
enum BasicAuthField: String, Sendable { case username, password, options }
struct BasicAuthIssue: Equatable, Sendable {
    enum Code: String, Sendable { case colon, control, unrepresentable, boundarySpaces, invisible, normalized, empty, inputLimit, byteLimit, outputLimit, failure }
    let code: Code
    let field: BasicAuthField
    let message: String
    var isError = true
    var originalUTF16Range: NSRange? = nil
}
enum BasicAuthStatus: Sendable { case success, invalidCredentials, unrepresentableText, resourceLimit, cancelled, processingFailure }
struct BasicAuthArtifact: Sendable {
    let headerValue: String
    var fullHeader: String { "Authorization: " + headerValue }
}
struct BasicAuthResult: Sendable {
    var status: BasicAuthStatus
    var issues: [BasicAuthIssue] = []
    var artifact: BasicAuthArtifact?
    var credentialByteCount = 0
}
struct BasicAuthLimits: Sendable {
    var inputUTF16 = 262_144
    var bytes = 196_608
    var fullHeaderUTF16 = 262_144
}
