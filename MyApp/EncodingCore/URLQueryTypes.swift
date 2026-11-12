import Foundation

enum URLQueryProfile: String, Codable, CaseIterable, Sendable {
    case percent, form
    var title: String { self == .percent ? "Percent · literal +" : "Form · + means space" }
    var codec: URLPercentProfile { self == .percent ? .component : .formField }
}
enum URLQueryOutputForm: String, CaseIterable, Sendable {
    case preserve, ascii
    var title: String { self == .preserve ? "Preserve source" : "ASCII URI" }
}
enum URLQueryStatus: Equatable, Sendable { case ready, parsed, invalidSyntax, resourceLimit, cancelled, processingFailure }
struct URLQueryIssue: Equatable, Sendable {
    enum Severity: Sendable { case error, note }
    let code: String
    let message: String
    var severity: Severity = .error
    var range: NSRange? = nil
    var region = false
}
struct URLQueryLimits: Sendable {
    var input = 262_144
    var output = 262_144
    var bytes = 786_432
    var validation = 2_359_296
}
struct URLQueryComponents: Sendable {
    var scheme: NSRange?
    var authority: NSRange?
    var userinfo: NSRange?
    var host: NSRange?
    var port: NSRange?
    var path = NSRange(location: 0, length: 0)
    var query: NSRange?
    var fragment: NSRange?
    var dnsHost = false
    var asciiHost: String?
    var unicodeHost: String?
    var kind = "Relative reference"
}
struct URLQueryRow: Identifiable, Sendable {
    let id: Int
    var sourceRange: NSRange?
    var nameRange: NSRange?
    var valueRange: NSRange?
    var rawName: String
    var rawValue: String?
    var name: String?
    var value: String?
    var changedName: String?
    var changedValue: String?
    var hasValue: Bool { rawValue != nil }
    var displayName: String { changedName ?? name ?? rawName }
    var displayValue: String? { rawValue == nil ? nil : changedValue ?? value ?? rawValue }
    var rawOnlyName: Bool { name == nil && changedName == nil }
    var rawOnlyValue: Bool { rawValue != nil && value == nil && changedValue == nil }
}
struct URLQuerySnapshot: Sendable {
    let source: String
    let profile: URLQueryProfile
    let components: URLQueryComponents
    let rows: [URLQueryRow]
    let issues: [URLQueryIssue]
    var queryPresent: Bool { components.query != nil }
    func slice(_ range: NSRange?) -> String? { range.map { (source as NSString).substring(with: $0) } }
}
enum URLQueryListChange: Sendable {
    case reload, update(Int), insert(Int), remove(Int), move(Int,Int)
}
struct URLQueryDraft: Sendable {
    var rows: [URLQueryRow]
    var queryPresent: Bool
    var nextID: Int
    init(_ snapshot: URLQuerySnapshot) { rows = snapshot.rows; queryPresent = snapshot.queryPresent; nextID = rows.count }
}
struct URLQuerySourceMap: Sendable {
    let source: NSRange
    var derived: NSRange
    let exact: Bool
}
struct URLQueryReference: Sendable {
    let ascii: String
    let mapping: [URLQuerySourceMap]
    let components: URLQueryComponents
    let issues: [URLQueryIssue]
    func sourceRegion(for range: NSRange) -> NSRange? {
        var regions: [NSRange] = []
        for segment in mapping {
            let overlap = NSIntersectionRange(segment.derived,range)
            if overlap.length > 0 {
                regions.append(segment.exact ? NSRange(location:segment.source.location+overlap.location-segment.derived.location,length:overlap.length) : segment.source)
            } else if range.length == 0 && segment.derived.location <= range.location && NSMaxRange(segment.derived) >= range.location {
                regions.append(segment.exact ? NSRange(location:segment.source.location+range.location-segment.derived.location,length:0) : segment.source)
                break
            }
        }
        guard let first = regions.first, let last = regions.last else { return nil }
        return .init(location:first.location,length:NSMaxRange(last)-first.location)
    }
}
struct URLQueryInspection: Sendable {
    let status: URLQueryStatus
    var snapshot: URLQuerySnapshot? = nil
    var issues: [URLQueryIssue] = []
}
struct URLQueryArtifact: Sendable {
    let preserve: String
    let ascii: String?
    let asciiIssue: URLQueryIssue?
}
struct URLQueryBuildResult: Sendable {
    let status: URLQueryStatus
    var artifact: URLQueryArtifact? = nil
    var issues: [URLQueryIssue] = []
}
struct URLQueryFailure: Error {
    let status: URLQueryStatus
    let issue: URLQueryIssue
    init(_ code: String, _ message: String, range: NSRange? = nil, region: Bool = false, resource: Bool = false) {
        status = resource ? .resourceLimit : .invalidSyntax
        issue = .init(code: code, message: message, range: range, region: region)
    }
}
/// Presentation is bounded and escapes controls/bidi; copied/model text is never modified.
enum URLQueryPresentation {
    static func safe(_ text: String, limit: Int = 100) -> String {
        var result = "", count = 0
        for scalar in text.unicodeScalars {
            guard count < limit else { return result + "…" }; count += 1
            let n = scalar.value
            if n < 32 || (127...159).contains(n) || [0x061C,0x200E,0x200F].contains(n) ||
                (0x202A...0x202E).contains(n) || (0x2066...0x2069).contains(n) {
                result += "\\u{" + String(n, radix: 16, uppercase: true) + "}"
            } else { result.unicodeScalars.append(scalar) }
        }
        return result
    }
    static func coordinates(_ text: String, offset: Int) -> (Int,Int) {
        var line = 1, column = 1, position = 0, cr = false
        for scalar in text.unicodeScalars {
            if position >= offset { break }
            if scalar == "\r" { line += 1; column = 1 }
            else if scalar == "\n" { if !cr { line += 1 }; column = 1 }
            else { column += scalar.utf16.count }
            cr = scalar == "\r"; position += scalar.utf16.count
        }
        return (line,column)
    }
    static func context(_ text: String, range: NSRange) -> String {
        let source = text as NSString, length = source.length
        let location = min(range.location,length), start = max(0,location - 40), end = min(length,location + max(1,range.length) + 40)
        let bounded = source.rangeOfComposedCharacterSequences(for: NSRange(location:start,length:end-start))
        return (bounded.location > 0 ? "…" : "") + safe(source.substring(with:bounded),limit:120) + (NSMaxRange(bounded) < length ? "…" : "")
    }
}
