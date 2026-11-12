import Foundation

enum URLPercentDirection: String, Codable, CaseIterable, Sendable {
    case encode, decode
    var title: String { self == .encode ? "Encode" : "Decode" }
}
enum URLPercentProfile: String, Codable, CaseIterable, Sendable {
    case component, formField, uriText
    var title: String { switch self {
    case .component: "Component"
    case .formField: "Form field"
    case .uriText: "URI text · keep delimiters"
    } }
    var help: String { switch self {
    case .component: "One URL value. Delimiters and literal '%' are encoded."
    case .formField: "One name or value, not an entire query. Spaces use '+'."
    case .uriText: "Keeps URL delimiters. Does not validate or normalize a URL."
    } }
}
struct URLPercentOptions: Equatable, Sendable {
    var direction = URLPercentDirection.encode
    var profile = URLPercentProfile.component
    var preserveExistingEscapes = true
    var effective: Self {
        var value = self
        if direction != .encode || profile != .uriText { value.preserveExistingEscapes = false }
        return value
    }
}
enum URLPercentIntent: Sendable { case check, convert }
enum URLPercentStatus: Equatable, Sendable {
    case success, bytesOnly, invalidPercentEncoding, resourceLimit, cancelled, processingFailure
}
struct URLPercentIssue: Sendable, Equatable {
    enum Severity: Sendable { case error, note }
    enum Code: String, Sendable {
        case malformedEscape, incompleteEscape, invalidUTF8, decodedDelimiter, controls, leadingBOM
        case inputLimit, outputLimit, byteLimit
    }
    let code: Code
    let severity: Severity
    let message: String
    var range: NSRange? = nil
    var line: Int? = nil
    var column: Int? = nil
    var context: String? = nil
}
struct URLPercentArtifact: Sendable { let text: String? }
struct URLPercentResult: Sendable {
    var status: URLPercentStatus
    var issues: [URLPercentIssue] = []
    var byteCount = 0
    var preview = ""
    var artifact: URLPercentArtifact? = nil
}
struct URLPercentLimits: Sendable {
    var inputUTF16 = 262_144
    var outputUTF16 = 262_144
    var bytes = 786_432
    static let previewBytes = 64
}
