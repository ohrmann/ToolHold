import Foundation

/// Per-operation bounded execution, including compilation and meta-validation.
/// Lock-protected because TaskLocal values are inherited; no global mutable validator state.
final class SchemaRuntime: Sendable {
    enum Failure: String, Sendable { case cancelled, resourceLimit, unsupportedPattern, unresolvedReference }
    private struct State: Sendable {
        var steps = 0
        var depth = 0
        var active: Set<Data> = []
        var failure: Failure?
    }
    @TaskLocal static var current: SchemaRuntime?
    private let state = LockIsolated(State())
    private let deadline: ContinuousClock.Instant
    let maximumSteps: Int
    init(seconds: Double = 2, maximumSteps: Int = 2_000_000) {
        deadline = .now.advanced(by: .seconds(seconds)); self.maximumSteps = maximumSteps
    }
    var failure: Failure? { state.withLock { $0.failure } }
    func fail(_ reason: Failure) { state.withLock { if $0.failure == nil { $0.failure = reason } } }
    @discardableResult static func check(_ cost: Int = 1) -> Bool {
        guard let run = current else { return !Task.isCancelled }
        return run.state.withLock { s in
            if s.failure != nil { return false }
            s.steps += cost
            if Task.isCancelled { s.failure = .cancelled }
            else if s.steps > run.maximumSteps || ContinuousClock.now >= run.deadline { s.failure = .resourceLimit }
            return s.failure == nil
        }
    }
    static func enter() -> Bool {
        guard check() else { return false }
        guard let run = current else { return true }
        return run.state.withLock { s in
            if s.depth >= 256 { s.failure = .resourceLimit; return false }
            s.depth += 1; return true
        }
    }
    static func beginEvaluation(schema: String, instance: String) -> Bool {
        guard let run = current else { return true }
        let key = Data((schema + "\u{0}" + instance).utf8)
        return run.state.withLock { s in
            if !s.active.insert(key).inserted { s.failure = s.failure ?? .resourceLimit; return false }
            return true
        }
    }
    static func endEvaluation(schema: String, instance: String) {
        let key = Data((schema + "\u{0}" + instance).utf8)
        current?.state.withLock { _ = $0.active.remove(key) }
    }
    static func leave() { current?.state.withLock { $0.depth -= 1 } }
    static func failureResult(at location: JSONPointer, keyword: JSONPointer) -> ValidationResult {
        let error = ValidationError(keyword: "$evaluation", message: "Schema evaluation did not complete",
            keywordLocation: keyword, instanceLocation: location)
        return ValidationResult(valid: false, keywordLocation: keyword, instanceLocation: location,
            errors: [error], evaluationErrors: [error])
    }
}

/// Foundation regex restricted to the interoperable ECMAScript subset. Unlike JSONPath
/// I-Regexp, ^/$ are anchors here. No JSON or pattern is executed as code.
final class SchemaPattern: Sendable {
    private let expression: NSRegularExpression
    init?(_ pattern: String) {
        guard pattern.utf16.count <= 1024 else { SchemaRuntime.current?.fail(.resourceLimit); return nil }
        // Reject unsupported engine-specific constructs instead of silently changing their meaning.
        let unsupported = ["(?P", "(?<", "(?i", "(?m", "(?s", "(?x", "(?>", "\\A", "\\Z", "\\z", "\\R", "\\X", "\\h", "\\Q", "\\E", "&&", "++", "*+", "?+"]
        guard !unsupported.contains(where: { pattern.contains($0) }) else {
            SchemaRuntime.current?.fail(.unsupportedPattern); return nil
        }
        // Bound compile expansion from very large quantifiers before invoking ICU.
        if pattern.range(of: #"\{[0-9]{5,}"#, options: .regularExpression) != nil {
            SchemaRuntime.current?.fail(.resourceLimit); return nil
        }
        guard let mapped = Self.map(pattern), SchemaRuntime.check(), let regex = try? NSRegularExpression(pattern: mapped) else { return nil }
        expression = regex
    }
    private static func map(_ pattern: String) -> String? {
        let chars = Array(pattern.unicodeScalars)
        var result = "", i = 0, inClass = false
        let spaces = "\\u0009-\\u000D\\u0020\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"
        while i < chars.count {
            let c = chars[i]; i += 1
            if c == "\\", i < chars.count {
                let escaped = chars[i]; i += 1
                switch escaped {
                case "d": result += inClass ? "0-9" : "[0-9]"
                case "w": result += inClass ? "A-Za-z0-9_" : "[A-Za-z0-9_]"
                case "s": result += inClass ? spaces : "[" + spaces + "]"
                case "D", "W", "S":
                    guard !inClass else { SchemaRuntime.current?.fail(.unsupportedPattern); return nil }
                    let content = escaped == "D" ? "0-9" : escaped == "W" ? "A-Za-z0-9_" : spaces
                    result += "[^" + content + "]"
                case "c":
                    guard i < chars.count, chars[i].isASCII, (65...90).contains(chars[i].value) || (97...122).contains(chars[i].value) else { return nil }
                    result += String(format: "\\x{%X}", chars[i].value % 32); i += 1
                case "v": result += "\\u000B"
                case "b", "B":
                    if inClass { result += escaped == "b" ? "\\u0008" : "B" }
                    else {
                        let w = "[A-Za-z0-9_]"
                        result += escaped == "b" ? "(?:(?<=\(w))(?!\(w))|(?<!\(w))(?=\(w)))" : "(?:(?<=\(w))(?=\(w))|(?<!\(w))(?!\(w)))"
                    }
                case "u" where i < chars.count && chars[i] == "{": result += "\\x"
                case "x" where i < chars.count && chars[i] == "{": SchemaRuntime.current?.fail(.unsupportedPattern); return nil
                default:
                    let allowed = "fnrtux0123456789pP^$\\.*+?()[]{}|/"
                    guard allowed.unicodeScalars.contains(escaped) else { SchemaRuntime.current?.fail(.unsupportedPattern); return nil }
                    result += "\\" + String(escaped)
                }
            } else if c == "[" { inClass = true; result += "[" }
            else if c == "]" { inClass = false; result += "]" }
            else if c == "$", !inClass { result += "\\z" }
            else if c == ".", !inClass { result += "[^\\n\\r\\u2028\\u2029]" }
            else { result += String(c) }
        }
        return result
    }
    func matches(_ text: String) -> Bool {
        guard SchemaRuntime.check(max(1, text.utf16.count / 32)) else { return false }
        var found = false
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(100))
        expression.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: text.utf16.count)) { match, _, stop in
            if !SchemaRuntime.check() || ContinuousClock.now >= deadline {
                SchemaRuntime.current?.fail(.resourceLimit); stop.pointee = true
            } else if match != nil { found = true; stop.pointee = true }
        }
        return found
    }
}
