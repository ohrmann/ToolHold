import Foundation

enum JWTComponent: String, Sendable, CaseIterable { case input = "Input", header = "Header", payload = "Payload", signature = "Signature" }
struct JWTAnchor: Sendable, Equatable {
    enum Space: Sendable, Equatable { case input, json(JWTComponent), bytes(JWTComponent) }
    let space: Space
    let range: NSRange
}
struct JWTIssue: Sendable, Identifiable {
    enum Severity: Sendable { case error, warning, note }
    let id = UUID()
    let code: String
    let component: JWTComponent
    let severity: Severity
    let message: String
    var anchor: JWTAnchor?
    var related: [JWTAnchor] = []
    var diagnostic: JSONDiagnostic?
    var context: JSONDiagnosticContext?
    var location: String?
}
struct JWTPart: Sendable {
    let component: JWTComponent
    let encoded: String
    let inputRange: NSRange
    var bytes: Data?
    var text: String?
    var document: JSONStructureDocument?
    var presentation: JWTJSONPresentation?
}
struct JWTClaim: Sendable, Identifiable {
    let id: Int
    let name: String
    let namePreview: String
    let kind: JSONStructureNode.Kind
    let preview: String
    let explanation: String
    let ambiguous: Bool
    let numericDate: String?
    let range: NSRange
}
struct JWTInspectionResult: Sendable {
    enum Processing: Sendable, Equatable { case completed, resourceLimit, cancelled, failure }
    enum Representation: Sendable { case compact, jweCandidate, unsupported, malformed }
    enum Profile: Sendable { case decoded, issues, unsupported }
    let id = UUID()
    var processing: Processing = .completed
    var representation: Representation = .compact
    var profile: Profile = .decoded
    var token: String?
    var parts: [JWTComponent: JWTPart] = [:]
    var claims: [JWTClaim] = []
    var claimRows: [Int] = []
    var claimRowNumbers: [Int: Int] = [:]
    var issues: [JWTIssue] = []
    var issueCount = 0
    var unsigned = false
    var algorithm: String?
    var interpretationAvailable = true
    var nestedContent = false
    var hasRootDuplicates = false
    var missingTimeClaims: [String] = []
    mutating func add(_ issue: JWTIssue) {
        issueCount += 1
        if issues.count < 100 { issues.append(issue) }
        if issue.severity == .error && profile != .unsupported { profile = .issues }
    }
    var trust: String { unsigned ? "Unsigned token" : "Signature not verified" }
    var title: String {
        switch processing {
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        case .failure: return "Processing failed"
        case .completed:
            if representation == .jweCandidate { return "JWE-style token · not supported" }
            if profile == .unsupported { return "Unsupported token semantics" }
            if profile == .issues { return parts.values.contains(where: { $0.document != nil }) ? "Partially decoded · issues found" : "Unable to decode token" }
            return issueCount > 0 ? "Decoded with notes" : "Decoded"
        }
    }
}
struct JWTBudget: Sendable {
    let deadline: ContinuousClock.Instant
    init(seconds: Double = 10) { deadline = .now.advanced(by: .milliseconds(Int64(max(0, seconds) * 1000))) }
    func check() throws {
        if ContinuousClock.now >= deadline { throw Limit.deadline }
        try Task.checkCancellation()
    }
    enum Limit: Error { case deadline }
}
