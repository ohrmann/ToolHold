import Foundation

enum IdentifierKind: String, CaseIterable, Codable, Sendable {
    case uuidV4, uuidV7, ulid, nanoID
    var title: String { switch self { case .uuidV4: "UUID v4"; case .uuidV7: "UUID v7"; case .ulid: "ULID"; case .nanoID: "NanoID" } }
}
enum IdentifierCase: String, CaseIterable, Codable, Sendable { case lowercase, uppercase }
enum IdentifierAlphabet: String, CaseIterable, Codable, Sendable {
    case urlSafe, alphanumeric, hexadecimal, numeric, custom
    var title: String { switch self { case .urlSafe: "URL-safe"; case .alphanumeric: "Alphanumeric"; case .hexadecimal: "Hexadecimal"; case .numeric: "Numeric"; case .custom: "Custom" } }
    var symbols: String {
        switch self {
        case .urlSafe: "_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        case .alphanumeric: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        case .hexadecimal: "0123456789abcdef"
        case .numeric: "0123456789"
        case .custom: ""
        }
    }
}
struct IdentifierOptions: Equatable, Sendable {
    var kind = IdentifierKind.uuidV4
    var count = 1
    var uuidCase = IdentifierCase.lowercase
    var ulidMonotonic = true
    var nanoLength = 21
    var alphabet = IdentifierAlphabet.urlSafe
    var customAlphabet = ""
    var symbols: String { alphabet == .custom ? customAlphabet : alphabet.symbols }
    // Only effective settings belong to a generated batch or equality check.
    var effective: Self {
        var value = Self(); value.kind = kind; value.count = count
        switch kind {
        case .uuidV4, .uuidV7: value.uuidCase = uuidCase
        case .ulid: value.ulidMonotonic = ulidMonotonic
        case .nanoID: value.nanoLength = nanoLength; value.alphabet = alphabet; if alphabet == .custom { value.customAlphabet = customAlphabet }
        }
        return value
    }
    var issue: IdentifierIssue? {
        guard (1...10_000).contains(count) else { return .init(.invalidOptions, "Count must be between 1 and 10,000.") }
        guard kind == .nanoID else { return nil }
        guard (1...256).contains(nanoLength) else { return .init(.invalidOptions, "Length must be between 1 and 256.") }
        let bytes = Array(symbols.utf8.prefix(95))
        guard (2...94).contains(bytes.count), bytes.allSatisfy({ (33...126).contains($0) }), Set(bytes).count == bytes.count else {
            return .init(.invalidOptions, "Use 2–94 different printable ASCII characters, without spaces or repeated characters.")
        }
        return nil
    }
    var caption: String {
        switch kind {
        case .uuidV4, .uuidV7: return "\(kind.title) · \(count) · \(uuidCase.rawValue)"
        case .ulid: return "ULID · \(count) · \(ulidMonotonic ? "monotonic" : "random")"
        case .nanoID: return "NanoID · \(count) · length \(nanoLength) · \(alphabet.title)"
        }
    }
}
enum IdentifierStatus: String, Sendable {
    case success, cancelled, invalidOptions, resourceLimit, entropyUnavailable, clockUnavailable, sequenceExhausted
}
struct IdentifierIssue: Error, Equatable, Sendable {
    let status: IdentifierStatus
    let message: String
    init(_ status: IdentifierStatus, _ message: String) { self.status = status; self.message = message }
}
struct IdentifierBatch: Sendable, Identifiable {
    let id = UUID()
    let options: IdentifierOptions
    let values: [String]
    let notes: [String]
    let duplicateCount: Int
    let createdAt: Date
}
struct IdentifierResult: Sendable {
    let status: IdentifierStatus
    let batch: IdentifierBatch?
    let issue: IdentifierIssue?
    init(batch: IdentifierBatch) { status = .success; self.batch = batch; issue = nil }
    init(issue: IdentifierIssue) { status = issue.status; batch = nil; self.issue = issue }
}
enum IdentifierCopyFormat: Sendable { case lines, json }
enum IdentifierBudget {
    static let outputBytes = 8 * 1024 * 1024
    static let maxTimestamp: UInt64 = 0xFFFF_FFFF_FFFF
}
