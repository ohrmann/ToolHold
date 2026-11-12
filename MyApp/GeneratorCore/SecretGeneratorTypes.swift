import Foundation

enum SecretGeneratorKind: String, Codable, Sendable { case password, passphrase }
enum PasswordAlphabetMode: String, Codable, CaseIterable, Sendable { case standard, custom }
enum PassphraseSeparator: String, Codable, CaseIterable, Sendable {
    case space, hyphen, underscore, period
    var title: String { rawValue.capitalized }
    var text: String { switch self { case .space: " "; case .hyphen: "-"; case .underscore: "_"; case .period: "." } }
}
enum PassphraseCase: String, Codable, CaseIterable, Sendable {
    case lowercase, titleCase
    var title: String { self == .lowercase ? "Lowercase" : "Title Case" }
}
struct PasswordOptions: Equatable, Sendable {
    var length = 13
    var count = 1
    var mode = PasswordAlphabetMode.standard
    var lowercase = true
    var uppercase = true
    var digits = true
    var symbols = true
    var requireEveryGroup = true
    var excludeSimilar = false
    var exclusions = ""
    var customAlphabet = ""
    static let similar = "0O1Il|"
    static let punctuation = String(bytes: (UInt8(33)...126).filter { !(48...57).contains($0) && !(65...90).contains($0) && !(97...122).contains($0) }, encoding: .ascii)!
    var effective: Self {
        var value = self
        if mode == .standard { value.customAlphabet = "" }
        else { value.lowercase = false; value.uppercase = false; value.digits = false; value.symbols = false; value.requireEveryGroup = false }
        return value
    }
    func groups() throws -> [[UInt8]] {
        guard (8...128).contains(length), (1...1000).contains(count) else { throw SecretIssue(.invalidOptions, "Length must be 8–128 and count must be 1–1,000.") }
        guard exclusions.utf16.count <= 256, exclusions.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw SecretIssue(.invalidOptions, "Excluded characters must be printable ASCII without spaces (up to 256 characters).")
        }
        let excluded = Set(exclusions.utf8).union(excludeSimilar ? Set(Self.similar.utf8) : [])
        let groups: [(String, String)]
        if mode == .custom {
            let bytes = Array(customAlphabet.utf8.prefix(95))
            guard (2...94).contains(bytes.count), bytes.allSatisfy({ (33...126).contains($0) }), Set(bytes).count == bytes.count else {
                throw SecretIssue(.invalidOptions, "Use 2–94 different printable ASCII characters, without spaces or duplicates.")
            }
            groups = [("Custom alphabet", customAlphabet)]
        } else {
            groups = [(lowercase, "Lowercase", "abcdefghijklmnopqrstuvwxyz"), (uppercase, "Uppercase", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
                      (digits, "Digits", "0123456789"), (symbols, "Symbols", Self.punctuation)].compactMap { $0.0 ? ($0.1, $0.2) : nil }
        }
        let filtered = groups.map { Array($0.1.utf8).filter { !excluded.contains($0) } }
        if mode == .standard && requireEveryGroup {
            let empty = zip(groups, filtered).filter { $0.1.isEmpty }.map { $0.0.0 }
            guard empty.isEmpty else { throw SecretIssue(.invalidOptions, "Exclusions leave these required groups empty: " + empty.joined(separator: ", ") + ".") }
        }
        guard filtered.reduce(0, { $0 + $1.count }) >= 2 else { throw SecretIssue(.invalidOptions, "Select an alphabet with at least two available characters.") }
        return filtered.filter { !$0.isEmpty }
    }
}
struct PassphraseOptions: Equatable, Sendable {
    var wordCount = 6
    var count = 1
    var separator = PassphraseSeparator.hyphen
    var letterCase = PassphraseCase.lowercase
    var appendDigit = false
    var issue: SecretIssue? {
        guard (4...16).contains(wordCount), (1...1000).contains(count) else { return .init(.invalidOptions, "Words must be 4–16 and count must be 1–1,000.") }
        return nil
    }
}
enum SecretGeneratorRequest: Equatable, Sendable {
    case password(PasswordOptions), passphrase(PassphraseOptions)
    var effective: Self { switch self { case .password(let o): .password(o.effective); case .passphrase: self } }
    var count: Int { switch self { case .password(let o): o.count; case .passphrase(let o): o.count } }
    var kind: SecretGeneratorKind { switch self { case .password: .password; case .passphrase: .passphrase } }
    var caption: String {
        switch self {
        case .password(let o): "\(o.count) password\(o.count == 1 ? "" : "s") · \(o.length) characters · \(o.mode.rawValue)"
        case .passphrase(let o): "\(o.count) phrase\(o.count == 1 ? "" : "s") · \(o.wordCount) words · English"
        }
    }
    var issue: SecretIssue? {
        switch self { case .password(let o): do { _ = try o.groups(); return nil } catch { return error as? SecretIssue }; case .passphrase(let o): return o.issue }
    }
}
enum SecretStatus: String, Sendable { case success, invalidOptions, entropyUnavailable, dictionaryUnavailable, resourceLimit, cancelled }
struct SecretIssue: Error, Equatable, Sendable {
    let status: SecretStatus
    let message: String
    init(_ status: SecretStatus, _ message: String) { self.status = status; self.message = message }
}
struct SecretBatch: Sendable, Identifiable {
    let id = UUID()
    let options: SecretGeneratorRequest
    let values: [String]
    let entropyBits: Double
    let duplicateCount: Int
    let dictionaryVersion: String?
}
struct SecretResult: Sendable {
    let status: SecretStatus
    let batch: SecretBatch?
    let issue: SecretIssue?
    init(batch: SecretBatch) { status = .success; self.batch = batch; issue = nil }
    init(issue: SecretIssue) { status = issue.status; batch = nil; self.issue = issue }
}
enum SecretCopyFormat: Sendable { case lines, json }
struct SecretGenerationLimits: Sendable {
    var randomBytes = 16 * 1024 * 1024
    var candidatesPerPassword = 4096
    var seconds: Double = 5
    static let outputBytes = 1024 * 1024
}
