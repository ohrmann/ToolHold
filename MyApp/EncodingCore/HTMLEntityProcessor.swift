import Foundation

/// Character references only: no markup interpretation, recursive decode, normalization or I/O.
enum HTMLEntityProcessor {
    private struct Problem { let code: HTMLEntityIssue.Code; let message: String; let range: NSRange }
    private struct Reference {
        let end: Int
        var value: String?
        var problems: [Problem] = []
        var complete = false
    }
    private struct LimitFailure: Error { let code: HTMLEntityIssue.Code }
    private static let remaps: [UInt32: UInt32] = [
        0x80:0x20AC,0x82:0x201A,0x83:0x0192,0x84:0x201E,0x85:0x2026,0x86:0x2020,
        0x87:0x2021,0x88:0x02C6,0x89:0x2030,0x8A:0x0160,0x8B:0x2039,0x8C:0x0152,
        0x8E:0x017D,0x91:0x2018,0x92:0x2019,0x93:0x201C,0x94:0x201D,0x95:0x2022,
        0x96:0x2013,0x97:0x2014,0x98:0x02DC,0x99:0x2122,0x9A:0x0161,0x9B:0x203A,
        0x9C:0x0153,0x9E:0x017E,0x9F:0x0178
    ]
    private static func alphanumeric(_ n: UInt16) -> Bool {
        (48...57).contains(n) || (65...90).contains(n) || (97...122).contains(n)
    }
    private static func digit(_ n: UInt16, base: UInt32) -> UInt32? {
        let value: UInt32
        switch n { case 48...57: value = UInt32(n - 48); case 65...70: value = UInt32(n - 55)
        case 97...102: value = UInt32(n - 87); default: return nil }
        return value < base ? value : nil
    }
    private static func noncharacter(_ n: UInt32) -> Bool { (0xFDD0...0xFDEF).contains(n) || n & 0xFFFF >= 0xFFFE }
    private static func control(_ n: UInt32) -> Bool {
        n == 0x0D || ((n < 0x20 || (0x7F...0x9F).contains(n)) && ![9,10,12].contains(n))
    }
    private static func reference(_ units: [UInt16], at start: Int, context: HTMLEntityContext) throws -> Reference {
        let count = units.count
        guard start + 1 < count else { return .init(end: start + 1) }
        var cursor = start + 1
        if units[cursor] == 35 {
            cursor += 1
            var base: UInt32 = 10
            if cursor < count && (units[cursor] == 120 || units[cursor] == 88) { base = 16; cursor += 1 }
            let digits = cursor
            var value: UInt32 = 0
            while cursor < count, let n = digit(units[cursor], base: base) {
                if cursor & 4095 == 0 { try Task.checkCancellation() }
                value = min(0x110000, value * base + n)
                cursor += 1
            }
            guard cursor > digits else {
                return .init(end: cursor, problems: [.init(code: .missingDigits,
                    message: "Expected \(base == 16 ? "hexadecimal" : "decimal") digits in numeric reference; left unchanged.",
                    range: .init(location: cursor, length: 0))])
            }
            let complete = cursor < count && units[cursor] == 59
            var problems: [Problem] = []
            if complete { cursor += 1 } else {
                problems.append(.init(code: .missingSemicolon, message: "Missing semicolon; decoded using HTML rules.", range: .init(location: cursor, length: 0)))
            }
            let range = NSRange(location: start, length: cursor - start)
            if value == 0 {
                problems.append(.init(code: .nullReference, message: "Null numeric reference replaced with U+FFFD.", range: range)); value = 0xFFFD
            } else if value > 0x10FFFF {
                problems.append(.init(code: .outsideUnicode, message: "Numeric reference outside the Unicode range replaced with U+FFFD.", range: range)); value = 0xFFFD
            } else if (0xD800...0xDFFF).contains(value) {
                problems.append(.init(code: .surrogateReference, message: "Surrogate numeric reference replaced with U+FFFD; references are not UTF-16 code units.", range: range)); value = 0xFFFD
            } else if noncharacter(value) {
                problems.append(.init(code: .noncharacterReference, message: "Reference produces a Unicode noncharacter, which is not conforming HTML.", range: range))
            } else if control(value) {
                if let mapped = remaps[value] {
                    problems.append(.init(code: .remappedControl, message: "HTML rules remap this control reference to U+\(String(mapped, radix: 16, uppercase: true)).", range: range)); value = mapped
                } else {
                    problems.append(.init(code: .controlReference, message: "Reference produces a control character, which is not conforming HTML.", range: range))
                }
            }
            return .init(end: cursor, value: String(Unicode.Scalar(value)!), problems: problems, complete: complete)
        }
        guard alphanumeric(units[cursor]) else { return .init(end: cursor) }
        var name = "", match: (Int, String)?
        while cursor < count && cursor - start - 1 < HTMLEntityTable.maximumNameLength {
            let n = units[cursor]
            guard alphanumeric(n) || n == 59 else { break }
            name.unicodeScalars.append(Unicode.Scalar(n)!)
            cursor += 1
            if let value = HTMLEntityTable.entries[name] { match = (cursor, value) }
            if n == 59 { break }
        }
        if let (end, value) = match {
            let complete = units[end - 1] == 59
            if !complete && context != .text && end < count && (alphanumeric(units[end]) || units[end] == 61) {
                return .init(end: end) // Attribute exception: literal spelling, no parse error.
            }
            return .init(end: end, value: value, problems: complete ? [] : [
                .init(code: .missingSemicolon, message: "Missing semicolon; decoded using HTML rules.", range: .init(location: end, length: 0))
            ], complete: complete)
        }
        // Unknown names may be arbitrarily long. Consume once, with bounded lookup and no suffix rescans.
        cursor = start + 1
        while cursor < count && alphanumeric(units[cursor]) {
            if cursor & 4095 == 0 { try Task.checkCancellation() }
            cursor += 1
        }
        if cursor < count && units[cursor] == 59 {
            cursor += 1
            return .init(end: cursor, problems: [.init(code: .unknownName, message: "Unknown named character reference; left unchanged.", range: .init(location: start, length: cursor - start))])
        }
        return .init(end: cursor)
    }

    static func process(_ source: String, options raw: HTMLEntityOptions = .init(),
                        intent: HTMLEntityIntent = .convert, limits: HTMLEntityLimits = .init()) -> HTMLEntityResult {
        var result = HTMLEntityResult(status: .success)
        let options = raw.effective
        var errors = false
        func issue(_ problem: Problem, error: Bool) {
            result.issueCount += 1; errors = errors || error
            let message = error && options.direction == .decode ? strictMessage(problem) : problem.message
            let detail = HTMLEntityIssue(code: problem.code, severity: error ? .error : .warning, message: message, range: problem.range)
            if result.issues.count < HTMLEntityLimits.detailedIssues { result.issues.append(detail) }
            else if error && !result.issues.contains(where: { $0.severity == .error }) {
                // A presentation cap must never hide the reason conversion was refused.
                result.issues[result.issues.count - 1] = detail
            }
        }
        do {
            try Task.checkCancellation()
            var count = 0
            for _ in source.utf16 {
                if count & 4095 == 0 { try Task.checkCancellation() }
                guard count < limits.inputUTF16 else { throw LimitFailure(code: .inputLimit) }
                count += 1
            }
            result.inputCount = count
            let units = Array(source.utf16)
            var output = "", cursor = 0
            if intent == .convert { output.reserveCapacity(min(count, max(0, limits.outputUTF16))) }
            func append(_ text: String) throws {
                let length = text.utf16.count
                guard length <= limits.outputUTF16 - result.outputCount else { throw LimitFailure(code: .outputLimit) }
                result.outputCount += length
                if intent == .convert { output += text }
            }
            func appendRaw(_ range: Range<Int>) throws {
                guard range.count <= limits.outputUTF16 - result.outputCount else { throw LimitFailure(code: .outputLimit) }
                result.outputCount += range.count
                if intent == .convert { output += String(decoding: units[range], as: UTF16.self) }
            }
            while cursor < count {
                if cursor & 4095 == 0 { try Task.checkCancellation() }
                if units[cursor] == 38 && (options.direction == .decode || options.preserveExistingReferences) {
                    let token = try reference(units, at: cursor, context: options.context)
                    if options.direction == .decode {
                        for problem in token.problems { issue(problem, error: options.policy == .strict) }
                        if let value = token.value { try append(value); result.convertedCount += 1 }
                        else { try appendRaw(cursor..<token.end) }
                        cursor = token.end; continue
                    } else if token.complete && token.value != nil && token.problems.isEmpty {
                        try appendRaw(cursor..<token.end); result.preservedCount += 1
                        cursor = token.end; continue
                    }
                }
                if options.direction == .decode {
                    // Copy the complete literal span, preserving code units and logical newlines.
                    let start = cursor
                    repeat { cursor += 1 } while cursor < count && units[cursor] != 38 && cursor & 4095 != 0
                    try appendRaw(start..<cursor); continue
                }
                let start = cursor, first = units[cursor]
                let value: UInt32
                if (0xD800...0xDBFF).contains(first) && cursor + 1 < count {
                    value = 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(units[cursor + 1] - 0xDC00); cursor += 2
                } else { value = UInt32(first); cursor += 1 }
                let scalar = Unicode.Scalar(value)!
                let required = value == 38 || value == 60 || value == 62 || (options.context == .doubleQuoted && value == 34) || (options.context == .singleQuoted && value == 39)
                let encode = required || options.scope == .everyCharacter || (options.scope == .nonASCII && value > 127)
                let range = NSRange(location: start, length: cursor - start)
                if value == 0 || (encode && remaps[value] != nil) {
                    issue(.init(code: .unrepresentableScalar, message: "U+\(String(value, radix: 16, uppercase: true)) cannot be represented by an HTML character reference without changing its value.", range: range), error: true)
                } else if control(value) || noncharacter(value) {
                    issue(.init(code: .literalControl, message: "Input contains a control or noncharacter; it is preserved, but may not be conforming HTML.", range: range), error: false)
                }
                if encode {
                    let encoded: String
                    switch options.notation {
                    case .named:
                        encoded = HTMLEntityTable.names[value].map { "&" + $0 } ?? "&#x" + String(value, radix: 16, uppercase: true) + ";"
                    case .decimal: encoded = "&#" + String(value) + ";"
                    case .hexadecimal: encoded = "&#x" + String(value, radix: 16, uppercase: true) + ";"
                    }
                    try append(encoded); result.convertedCount += 1
                } else { try append(String(scalar)) }
            }
            try Task.checkCancellation()
            result.status = errors ? .invalidReferences : result.issueCount > 0 ? .successWithWarnings : .success
            if !errors && intent == .convert { result.artifact = .init(text: output) }
            decorate(&result, source: source, units: units)
            return result
        } catch is CancellationError { return .init(status: .cancelled) }
        catch let failure as LimitFailure {
            return .init(status: .resourceLimit, issues: [.init(code: failure.code, severity: .error,
                message: failure.code == .inputLimit ? "Input exceeds the UTF-16 processing limit." : "Result exceeds the UTF-16 processing limit; no partial output was produced.")], issueCount: 1)
        } catch { return .init(status: .processingFailure) }
    }
    private static func strictMessage(_ problem: Problem) -> String {
        let explanation: String
        switch problem.code {
        case .missingSemicolon: explanation = "A semicolon is required after this character reference."
        case .unknownName: explanation = "Unknown named character reference."
        case .missingDigits: explanation = "Expected digits in numeric character reference."
        case .nullReference: explanation = "A null numeric reference would be replaced by HTML rules."
        case .surrogateReference: explanation = "A numeric reference must not name a Unicode surrogate."
        case .outsideUnicode: explanation = "Numeric reference is outside the Unicode range."
        case .remappedControl: explanation = "This numeric control reference would be remapped by HTML rules."
        case .controlReference: explanation = "Control character reference is not accepted in strict mode."
        case .noncharacterReference: explanation = "Unicode noncharacter reference is not accepted in strict mode."
        default: explanation = problem.message
        }
        return "Strict references: " + explanation + " No output was produced."
    }
    private static func decorate(_ result: inout HTMLEntityResult, source: String, units: [UInt16]) {
        var cursor = 0, line = 1, lineStart = 0
        let positions = result.issues.indices.sorted { result.issues[$0].range!.location < result.issues[$1].range!.location }
        for i in positions {
            let range = result.issues[i].range!, target = min(units.count, range.location)
            while cursor < target {
                if units[cursor] == 13 {
                    line += 1; lineStart = cursor + 1
                } else if units[cursor] == 10 {
                    if cursor == 0 || units[cursor - 1] != 13 { line += 1 }
                    lineStart = cursor + 1
                }
                cursor += 1
            }
            result.issues[i].line = line; result.issues[i].column = target - lineStart + 1
            result.issues[i].context = HTMLEntityPresentation.context(source, range: range)
        }
    }
}
