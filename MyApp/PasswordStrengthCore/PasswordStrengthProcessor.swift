import Foundation
import JavaScriptCore

struct PasswordStrengthRequest: Sendable {
    let password: String
    var personalWords: String = ""
    var revision = UUID()
}
struct PasswordStrengthResult: Sendable {
    enum Status: String, Sendable { case estimated, empty, resourceLimit, unavailable, cancelled, invalidInput }
    var status: Status
    var message: String
    var score: Int?
    var guesses: Double?
    var warning = ""
    var suggestions: [String] = []
    var patterns: [String] = []
    var characters = 0
    var utf8Bytes = 0
    var limitedLanguageCoverage = false
    static let levels = ["Very guessable", "Guessable", "Moderate", "Stronger", "Much stronger"]
}

/// JS values and context are confined to this serial queue. Only typed scalar results escape.
final class PasswordStrengthWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "developerToolbox.passwordStrength", qos: .userInitiated)
    private var context: JSContext?
    private var function: JSValue?
    func reset() { queue.async { self.function = nil; self.context = nil } }
    func estimate(_ request: PasswordStrengthRequest) async -> PasswordStrengthResult {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.process(request)) }
        }
    }
    private func load() throws {
        if function != nil { return }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "password-estimator", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8), let c = JSContext() else { throw Failure.unavailable }
        c.exceptionHandler = { context, _ in context?.exception = nil }
        c.evaluateScript(source)
        guard let function = c.objectForKeyedSubscript("ToolboxPasswordEstimator")?.objectForKeyedSubscript("estimate"), !function.isUndefined else { throw Failure.unavailable }
        self.context = c; self.function = function
    }
    private enum Failure: Error { case unavailable }
    private func process(_ request: PasswordStrengthRequest) -> PasswordStrengthResult {
        let password = request.password
        if password.isEmpty { return .init(status: .empty, message: "Enter a password to estimate.") }
        guard password.utf16.prefix(257).count <= 256 else { return .init(status: .resourceLimit, message: "Analysis limit reached · maximum 256 UTF-16 units. No prefix was scored.") }
        guard !password.unicodeScalars.contains(where: { [0,9,10,13].contains($0.value) }) else { return .init(status: .invalidInput, message: "Use a single-line password without tabs or NUL. Input was not normalized.") }
        let words = request.personalWords.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard request.personalWords.utf16.prefix(513).count <= 512, words.count <= 10, words.allSatisfy({ $0.utf16.count <= 64 }) else { return .init(status: .resourceLimit, message: "Use at most 10 personal words, 64 UTF-16 units each, 512 in total.") }
        do {
            let started = ContinuousClock.now
            try load()
            // User input is a function argument, never executable source or a global.
            guard let raw = function?.call(withArguments: [password, words]), !raw.isUndefined,
                  let score = raw.objectForKeyedSubscript("score")?.toInt32(), (0...4).contains(score),
                  let guesses = raw.objectForKeyedSubscript("guesses")?.toDouble(), guesses > 0, !guesses.isNaN else { throw Failure.unavailable }
            guard ContinuousClock.now-started < .seconds(10) else { return .init(status:.resourceLimit,message:"Analysis time limit reached. No score was published.") }
            let feedback = raw.objectForKeyedSubscript("feedback")
            let warning = feedback?.objectForKeyedSubscript("warning")?.toString() ?? ""
            let suggestions = feedback?.objectForKeyedSubscript("suggestions")?.toArray() as? [String] ?? []
            let patterns = raw.objectForKeyedSubscript("patterns")?.toArray() as? [String] ?? []
            return .init(status: .estimated, message: PasswordStrengthResult.levels[Int(score)], score: Int(score), guesses: guesses,
                         warning: warning, suggestions: suggestions, patterns: patterns, characters: password.count, utf8Bytes: password.utf8.count,
                         limitedLanguageCoverage: password.unicodeScalars.contains { $0.value > 127 })
        } catch { return .init(status: .unavailable, message: "The local estimator is unavailable. No strength rating was produced.") }
    }
}

enum PasswordAttackScenario: String, CaseIterable {
    case throttled = "Online · 100 guesses/hour", online = "Online · 10 guesses/second"
    case slow = "Offline slow hash · 10⁴/second", fast = "Offline fast hash · 10¹⁰/second"
    var rate: Double { switch self { case .throttled: 100/3600; case .online: 10; case .slow: 1e4; case .fast: 1e10 } }
    func duration(guesses: Double) -> String {
        let seconds = guesses / rate
        if !seconds.isFinite || seconds > 3.15576e15 { return "More than 100 million years under this assumption" }
        if seconds < 1 { return "Less than a second" }
        for (scale, label) in [(31557600.0,"years"),(86400.0,"days"),(3600.0,"hours"),(60.0,"minutes")] where seconds >= scale { return "≈ \(Int(seconds/scale)) \(label)" }
        return "≈ \(Int(seconds)) seconds"
    }
}
