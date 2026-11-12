import Foundation

enum HTMLEntityDirection: String, Codable, CaseIterable, Sendable {
    case encode, decode
    var title: String { self == .encode ? "Encode" : "Decode" }
}
enum HTMLEntityContext: String, Codable, CaseIterable, Sendable {
    case text, doubleQuoted, singleQuoted
    var title: String { switch self {
    case .text: "HTML text"
    case .doubleQuoted: "Double-quoted attribute"
    case .singleQuoted: "Single-quoted attribute"
    } }
}
enum HTMLEntityScope: String, Codable, CaseIterable, Sendable {
    case required, nonASCII, everyCharacter
    var title: String { switch self {
    case .required: "Required characters"
    case .nonASCII: "Required + non-ASCII"
    case .everyCharacter: "Every character"
    } }
}
enum HTMLEntityNotation: String, Codable, CaseIterable, Sendable {
    case named, decimal, hexadecimal
    var title: String { switch self {
    case .named: "Named when available"
    case .decimal: "Decimal"
    case .hexadecimal: "Hexadecimal"
    } }
}
enum HTMLEntityPolicy: String, Codable, CaseIterable, Sendable {
    case htmlCompatible, strict
    var title: String { self == .htmlCompatible ? "HTML-compatible" : "Strict references" }
}
struct HTMLEntityOptions: Equatable, Sendable {
    var direction = HTMLEntityDirection.encode
    var context = HTMLEntityContext.text
    var scope = HTMLEntityScope.required
    var notation = HTMLEntityNotation.named
    var preserveExistingReferences = false
    var policy = HTMLEntityPolicy.htmlCompatible
    var effective: Self {
        var value = self
        if direction == .encode { value.policy = .htmlCompatible }
        else { value.scope = .required; value.notation = .named; value.preserveExistingReferences = false }
        return value
    }
}
enum HTMLEntityIntent: Sendable { case check, convert }
enum HTMLEntityStatus: Equatable, Sendable {
    case success, successWithWarnings, invalidReferences, resourceLimit, cancelled, processingFailure
}
struct HTMLEntityIssue: Sendable, Equatable {
    enum Severity: Sendable { case warning, error }
    enum Code: String, Sendable {
        case missingSemicolon, unknownName, missingDigits, nullReference, surrogateReference, outsideUnicode
        case remappedControl, controlReference, noncharacterReference, literalControl, unrepresentableScalar
        case inputLimit, outputLimit
    }
    let code: Code
    let severity: Severity
    let message: String
    var range: NSRange?
    var line: Int?
    var column: Int?
    var context: String?
}
struct HTMLEntityArtifact: Sendable { let text: String }
struct HTMLEntityResult: Sendable {
    var status: HTMLEntityStatus
    var issues: [HTMLEntityIssue] = []
    var issueCount = 0
    var inputCount = 0
    var outputCount = 0
    var convertedCount = 0
    var preservedCount = 0
    var artifact: HTMLEntityArtifact?
}
struct HTMLEntityLimits: Sendable {
    var inputUTF16 = 262_144
    var outputUTF16 = 262_144
    static let detailedIssues = 32
}

/// Presentation never changes source or clipboard data. Offsets are always source UTF-16.
enum HTMLEntityPresentation {
    static func context(_ source: String, range: NSRange) -> String {
        let ns = source as NSString, start = max(0, range.location - 36)
        let end = min(ns.length, range.location + max(1, min(range.length, 24)) + 36)
        let safeRange = ns.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: max(0, end - start)))
        guard safeRange.length <= 160 else { return "Long grapheme near source offset \(range.location) · \(safeRange.length) UTF-16 units" }
        let text = ns.substring(with: safeRange)
        var result = safeRange.location > 0 ? "…" : "", spacing = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !spacing { result += " " }; spacing = true
            } else {
                spacing = false
                let n = scalar.value
                if n < 32 || (0x7F...0x9F).contains(n) || (0x202A...0x202E).contains(n) || (0x2066...0x2069).contains(n) || n == 0x061C || n == 0x200E || n == 0x200F {
                    result += "\\u{\(String(n, radix: 16, uppercase: true))}"
                } else { result.unicodeScalars.append(scalar) }
            }
        }
        return result + (NSMaxRange(safeRange) < ns.length ? "…" : "")
    }
}
