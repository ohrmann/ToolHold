import Foundation

enum Base64Direction: String, Codable, CaseIterable, Sendable { case decode, encode
    var title: String { self == .decode ? "Decode" : "Encode" }
}
enum Base64Alphabet: String, Codable, CaseIterable, Sendable { case standard, urlSafe
    var title: String { self == .standard ? "Base64" : "Base64URL" }
}
enum Base64DecodeMode: String, Codable, CaseIterable, Sendable { case strict, forgiving
    var title: String { self == .strict ? "Strict" : "Forgiving" }
}
enum Base64TextEncoding: String, Codable, CaseIterable, Sendable {
    case utf8, ascii, latin1, utf16LE, utf16BE
    var title: String { switch self {
    case .utf8: "UTF-8"; case .ascii: "ASCII"; case .latin1: "Latin-1"; case .utf16LE: "UTF-16 LE"; case .utf16BE: "UTF-16 BE"
    } }
}
struct Base64Options: Equatable, Sendable {
    var direction = Base64Direction.decode
    var alphabet = Base64Alphabet.standard
    var encoding = Base64TextEncoding.utf8
    var decodeMode = Base64DecodeMode.strict
    var urlPadding = false
    /// Presentation/hidden controls cannot make an otherwise current artifact stale.
    var effective: Self {
        var value = self
        if direction == .encode { value.decodeMode = .strict }
        if direction == .decode || alphabet == .standard { value.urlPadding = false }
        return value
    }
}
enum Base64Intent: Sendable { case check, convert }
enum Base64Status: Equatable, Sendable {
    case success, bytesOnly, invalidBase64, unrepresentableText, resourceLimit, cancelled, processingFailure
}
struct Base64Issue: Equatable, Sendable {
    enum Severity: Sendable { case error, note }
    enum Code: String, Sendable {
        case invalidSymbol, wrongAlphabet, invalidLength, missingPadding, invalidPadding, nonCanonicalPadBits
        case whitespace, inferredPadding, unrepresentableScalar, invalidTextEncoding, leadingBOM, controls
        case inputLimit, outputLimit, foundationFailure
    }
    let code: Code
    let severity: Severity
    let message: String
    var range: NSRange? = nil
    var line: Int? = nil
    var column: Int? = nil
}
struct Base64Artifact: Sendable {
    let text: String?
    let decodedBytes: Data?
}
struct Base64Result: Sendable {
    var status: Base64Status
    var issues: [Base64Issue] = []
    var byteCount = 0
    var preview = ""
    var artifact: Base64Artifact? = nil
}
struct Base64Limits: Sendable {
    var inputUTF16 = 262_144
    var outputUTF16 = 262_144
    var bytes = 196_608
    static let previewBytes = 64
}
struct Base64Failure: Error {
    let status: Base64Status
    let code: Base64Issue.Code
    let message: String
    var range: NSRange? = nil
}
