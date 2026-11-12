import Foundation

enum StringEscapeLanguage: String, Codable, CaseIterable, Sendable {
    case json, swift, javascript
    var title: String { switch self { case .json: "JSON"; case .swift: "Swift"; case .javascript: "JavaScript" } }
}
enum StringEscapeDirection: String, Codable, CaseIterable, Sendable {
    case escape, unescape
    var title: String { self == .escape ? "Escape" : "Unescape" }
}
enum StringEscapeRepresentation: String, Codable, CaseIterable, Sendable {
    case quoted, contents
    var title: String { self == .quoted ? "Quoted literal" : "String contents" }
}
enum StringEscapeQuote: String, Codable, CaseIterable, Sendable {
    case double, single
    var title: String { self == .double ? "Double quotes" : "Single quotes" }
    var unit: UInt16 { self == .double ? 34 : 39 }
}
struct StringEscapeOptions: Equatable, Sendable {
    var language = StringEscapeLanguage.json
    var direction = StringEscapeDirection.escape
    var representation = StringEscapeRepresentation.quoted
    var quote = StringEscapeQuote.double
    var nonASCII = false
    var effective: Self {
        var value = self
        if language != .javascript { value.quote = .double }
        if direction == .unescape { value.nonASCII = false }
        return value
    }
}
enum StringEscapeIntent: Sendable { case check, convert }
enum StringEscapeStatus: Equatable, Sendable {
    case success, successWithWarnings, invalidSyntax, unsupportedSyntax, notRepresentableAsText
    case resourceLimit, cancelled, processingFailure
}
struct StringEscapeIssue: Equatable, Sendable {
    enum Severity: Sendable { case warning, error }
    enum Code: String, Sendable {
        case openingQuote, closingQuote, unexpectedToken, unescapedQuote, rawControl, rawNewline
        case invalidEscape, incompleteEscape, hexDigit, unicodeDigits, invalidScalar, strictEscape
        case unsupportedLiteral, interpolation, unpairedSurrogate, identityEscape, continuation
        case literalControl, decodedControl, inputLimit, outputLimit
    }
    let code: Code
    let severity: Severity
    let message: String
    var range: NSRange?
    var related: NSRange?
    var line: Int?
    var column: Int?
    var context: String?
    var occurrences = 1
}
struct StringEscapeArtifact: Sendable { let text: String }
struct StringEscapeResult: Sendable {
    var status: StringEscapeStatus
    var issues: [StringEscapeIssue] = []
    var issueCount = 0
    var inputCount = 0
    var outputCount = 0
    var artifact: StringEscapeArtifact?
}
struct StringEscapeLimits: Sendable {
    var inputUTF16 = 262_144
    var outputUTF16 = 262_144
    static let detailedIssues = 32
}

/// Safe display only. Never used as decoded output or to calculate source offsets.
enum StringEscapePresentation {
    static func context(_ source: String, range: NSRange) -> String {
        let ns = source as NSString
        let start = max(0, min(ns.length, range.location) - 36)
        let end = min(ns.length, range.location + min(range.length, 24) + 36)
        let slice = ns.rangeOfComposedCharacterSequences(for: .init(location: start, length: max(0, end - start)))
        guard slice.length <= 160 else { return "Long grapheme near UTF-16 offset \(range.location)" }
        var output = slice.location > 0 ? "…" : "", spacing = false
        for scalar in ns.substring(with: slice).unicodeScalars {
            let n = scalar.value
            if isInvisible(n) {
                output += "\\u{\(String(n, radix: 16, uppercase: true))}"; spacing = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !spacing { output += " " }; spacing = true
            } else { output.unicodeScalars.append(scalar); spacing = false }
        }
        return output + (NSMaxRange(slice) < ns.length ? "…" : "")
    }
    static func isInvisible(_ n: UInt32) -> Bool {
        n < 32 || (0x7F...0x9F).contains(n) || n == 0x061C || n == 0x200E || n == 0x200F
            || (0x2028...0x202E).contains(n) || (0x2066...0x2069).contains(n)
    }
}
