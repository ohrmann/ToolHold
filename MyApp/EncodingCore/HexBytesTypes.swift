import Foundation

enum HexBytesDirection: String, Codable, CaseIterable, Sendable {
    case decode, encode
    var title: String { self == .decode ? "Hex → UTF-8 / Bytes" : "Text → Hex" }
}
enum HexBytesInputFormat: String, Codable, CaseIterable, Sendable {
    case pairs, prefixed, escaped
    var title: String { switch self { case .pairs: "Hex pairs"; case .prefixed: "0x bytes"; case .escaped: "\\x bytes" } }
}
enum HexBytesOutputFormat: String, Codable, CaseIterable, Sendable {
    case spaced, compact, prefixed, escaped
    var title: String { switch self { case .spaced: "Spaced"; case .compact: "Compact"; case .prefixed: "0x bytes"; case .escaped: "\\x bytes" } }
    var inputFormat: HexBytesInputFormat { switch self { case .spaced, .compact: .pairs; case .prefixed: .prefixed; case .escaped: .escaped } }
    /// Checked arithmetic, including callers outside the normal bounded workspace.
    func length(for count: Int) -> Int? {
        guard count >= 0 else { return nil }; if count == 0 { return 0 }
        let factor = self == .prefixed ? 6 : self == .escaped ? 4 : self == .spaced ? 3 : 2
        let (n, overflow) = count.multipliedReportingOverflow(by: factor)
        guard !overflow else { return nil }
        return n - (self == .spaced ? 1 : self == .prefixed ? 2 : 0)
    }
}
enum HexBytesCase: String, Codable, CaseIterable, Sendable {
    case uppercase, lowercase
    var title: String { self == .uppercase ? "Uppercase" : "Lowercase" }
}
enum HexBytesOutputView: String, Codable, CaseIterable, Sendable { case text, bytes }
struct HexBytesOptions: Equatable, Sendable {
    var direction = HexBytesDirection.decode
    var inputFormat = HexBytesInputFormat.pairs
    var outputFormat = HexBytesOutputFormat.spaced
    var hexCase = HexBytesCase.uppercase
    var effective: Self {
        var v = self
        if direction == .encode { v.inputFormat = .pairs }
        else { v.outputFormat = .spaced; v.hexCase = .uppercase }
        return v
    }
}
enum HexBytesIntent: Sendable { case check, convert }
enum HexBytesStatus: Equatable, Sendable {
    case success, successWithNotes, bytesOnly, invalidHex, resourceLimit, cancelled, processingFailure
}
struct HexBytesIssue: Equatable, Sendable {
    enum Severity: Sendable { case note, error }
    enum Domain: Sendable { case hex, utf8, resource }
    enum Code: String, Sendable {
        case digit, incompleteByte, prefix, separator, invalidLead, continuation, restrictedSecond, truncatedUTF8
        case nul, controls, leadingBOM, inputLimit, outputLimit, byteLimit
    }
    let code: Code
    let severity: Severity
    let domain: Domain
    let message: String
    var range: NSRange?
    var related: NSRange?
    var byteOffset: Int?
    var line: Int?
    var column: Int?
    var context: String?
    var occurrences = 1
}
struct HexBytesSourceMap: Sendable {
    let digitStarts: [UInt32]
    func range(for byte: Int) -> NSRange? {
        guard digitStarts.indices.contains(byte) else { return nil }
        return .init(location: Int(digitStarts[byte]), length: 2)
    }
}
struct HexBytesArtifact: Sendable {
    let id = UUID()
    let bytes: Data
    let text: String?
    let hex: String?
    let sourceMap: HexBytesSourceMap?
}
struct HexBytesResult: Sendable {
    var status: HexBytesStatus
    var issues: [HexBytesIssue] = []
    var issueCount = 0
    var inputCount = 0
    var byteCount = 0
    var outputCount = 0
    var artifact: HexBytesArtifact?
}
struct HexBytesLimits: Sendable {
    var inputUTF16 = 262_144
    var outputUTF16 = 262_144
    var bytes = 786_432
    static let detailedIssues = 32
}

/// Bounded, safe row presentation. No decoding, Data copies or document-wide formatting.
struct HexBytesRow: Equatable, Sendable {
    let offset: String
    let hex: String
    let ascii: String
    init(bytes: Data, start: Int, count: Int, hexCase: HexBytesCase = .uppercase) {
        offset = String(format: "%08X", max(0, start))
        let digits = Array((hexCase == .uppercase ? "0123456789ABCDEF" : "0123456789abcdef").utf8)
        var h = [UInt8](), a = String()
        let end = min(bytes.count, max(0, start) + max(0, min(16, count)))
        if start >= 0 && start < end {
            for i in start..<end {
                let b = bytes[bytes.startIndex + i]
                if !h.isEmpty { h.append(32) }; h.append(digits[Int(b >> 4)]); h.append(digits[Int(b & 15)])
                a.append((32...126).contains(b) ? Character(UnicodeScalar(b)) : "·")
            }
        }
        hex = String(decoding: h, as: UTF8.self); ascii = a
    }
}
