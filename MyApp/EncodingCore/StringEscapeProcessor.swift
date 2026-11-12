import Foundation

/// A bounded string-literal codec. No program parsing, execution, normalization or recursive decoding.
enum StringEscapeProcessor {
    static func process(_ source: String, options: StringEscapeOptions = .init(), intent: StringEscapeIntent = .convert,
                        limits: StringEscapeLimits = .init()) -> StringEscapeResult {
        if Task.isCancelled { return .init(status: .cancelled) }
        let count = source.utf16.count
        guard count <= limits.inputUTF16 else {
            return .init(status: .resourceLimit, issues: [.init(code: .inputLimit, severity: .error,
                message: "Input exceeds the \(limits.inputUTF16) UTF-16 unit limit.")], issueCount: 1, inputCount: count)
        }
        var scanner = Scanner(source: source, options: options.effective, intent: intent, limits: limits)
        do {
            if options.direction == .escape { try scanner.encode() } else { try scanner.decode() }
            try Task.checkCancellation()
            if let pending = scanner.pendingHigh { scanner.surrogateIssue(pending.range) }
            let status: StringEscapeStatus = scanner.badUnicode ? .notRepresentableAsText
                : scanner.issues.isEmpty ? .success : .successWithWarnings
            return scanner.result(status, artifact: intent == .convert && !scanner.badUnicode)
        } catch is CancellationError { return .init(status: .cancelled, inputCount: count) }
        catch let failure as Failure {
            // A later grammar violation takes precedence over a provisional Unicode outcome.
            scanner.issueCount -= scanner.issues.filter { $0.code == .unpairedSurrogate }.count
            scanner.issues.removeAll { $0.code == .unpairedSurrogate }
            scanner.add(failure.issue)
            return scanner.result(failure.status, artifact: false)
        } catch { return .init(status: .processingFailure, inputCount: count) }
    }

    private struct Failure: Error { let status: StringEscapeStatus; let issue: StringEscapeIssue }
    private struct Scanner {
        let source: String
        let options: StringEscapeOptions
        let intent: StringEscapeIntent
        let limits: StringEscapeLimits
        let units: [UInt16]
        var cursor = 0
        var output: [UInt16] = []
        var outputCount = 0
        var issues: [StringEscapeIssue] = []
        var issueCount = 0
        var badUnicode = false
        var pendingHigh: (unit: UInt16, range: NSRange)?
        var opening: NSRange?
        init(source: String, options: StringEscapeOptions, intent: StringEscapeIntent, limits: StringEscapeLimits) {
            self.source = source; self.options = options; self.intent = intent; self.limits = limits
            units = Array(source.utf16)
            if intent == .convert { output.reserveCapacity(min(units.count, max(0, limits.outputUTF16))) }
        }
        var current: UInt16? { cursor < units.count ? units[cursor] : nil }
        func range(_ start: Int, _ length: Int = 1) -> NSRange { .init(location: start, length: min(length, max(0, units.count - start))) }
        func failure(_ code: StringEscapeIssue.Code, _ message: String, at: Int? = nil, length: Int = 1,
                     related: NSRange? = nil, status: StringEscapeStatus = .invalidSyntax) -> Failure {
            .init(status: status, issue: .init(code: code, severity: .error, message: message,
                range: range(at ?? cursor, length), related: related ?? opening))
        }
        mutating func add(_ issue: StringEscapeIssue) {
            issueCount += 1
            if issue.severity == .warning, let index = issues.firstIndex(where: { $0.code == issue.code && $0.severity == .warning }) {
                issues[index].occurrences += 1
            } else if issues.count < StringEscapeLimits.detailedIssues { issues.append(issue) }
            else if issue.severity == .error && !issues.contains(where: { $0.severity == .error }) { issues[issues.count - 1] = issue }
        }
        mutating func warn(_ code: StringEscapeIssue.Code, _ message: String, _ sourceRange: NSRange) {
            add(.init(code: code, severity: .warning, message: message, range: sourceRange))
        }
        mutating func append(_ unit: UInt16) throws {
            guard outputCount < limits.outputUTF16 else {
                throw failure(.outputLimit, "Result exceeds the \(limits.outputUTF16) UTF-16 unit limit; no partial output was created.", status: .resourceLimit)
            }
            outputCount += 1
            if intent == .convert { output.append(unit) }
        }
        mutating func append(_ text: String) throws { for unit in text.utf16 { try append(unit) } }
        mutating func checkpoint() throws { if cursor & 4095 < 2 { try Task.checkCancellation() } }
        mutating func encode() throws {
            if options.representation == .quoted { try append(options.quote.unit) }
            for scalar in source.unicodeScalars {
                try checkpoint()
                let n = scalar.value
                let short: String?
                switch n {
                case 92: short = "\\\\"
                case UInt32(options.quote.unit): short = "\\" + String(scalar)
                case 10: short = "\\n"
                case 13: short = "\\r"
                case 9: short = "\\t"
                case 8 where options.language != .swift: short = "\\b"
                case 12 where options.language != .swift: short = "\\f"
                case 11 where options.language == .javascript: short = "\\v"
                case 0 where options.language == .swift: short = "\\0"
                case 0 where options.language == .javascript: short = "\\x00"
                default: short = nil
                }
                if let short { try append(short) }
                else if StringEscapePresentation.isInvisible(n) || (options.nonASCII && n > 127) {
                    if options.language == .swift { try append("\\u{\(String(n, radix: 16, uppercase: true))}") }
                    else {
                        for unit in String(scalar).utf16 { try append(String(format: "\\u%04X", unit)) }
                    }
                } else { try append(String(scalar)) }
                cursor += scalar.utf16.count
            }
            if options.representation == .quoted { try append(options.quote.unit) }
        }
        static func whitespace(_ unit: UInt16) -> Bool { [9,10,13,32].contains(unit) }
        mutating func skipWhitespace() throws {
            while let unit = current, Self.whitespace(unit) { try checkpoint(); cursor += 1 }
        }
        mutating func decode() throws {
            if options.representation == .quoted {
                try skipWhitespace()
                if options.language == .swift && (current == 35 || (current == 34 && units.dropFirst(cursor).starts(with: [34,34,34]))) {
                    throw failure(.unsupportedLiteral, "Swift raw and multiline literals are not supported. Use an ordinary quoted string.", status: .unsupportedSyntax)
                }
                if options.language == .javascript && current == 96 {
                    throw failure(.unsupportedLiteral, "JavaScript template literals are not supported. Use single or double quotes.", status: .unsupportedSyntax)
                }
                guard current == options.quote.unit else { throw failure(.openingQuote, "Expected the selected opening quote.") }
                opening = range(cursor); cursor += 1
            }
            var closed = options.representation == .contents
            while let unit = current {
                try checkpoint()
                if unit == options.quote.unit {
                    guard options.representation == .quoted else { throw failure(.unescapedQuote, "Escape this quote inside string contents.") }
                    cursor += 1; closed = true; break
                }
                if unit == 92 { try escape(); continue }
                if options.language == .json && unit < 32 {
                    throw failure(.rawControl, "Unescaped control character is not allowed in a JSON string.")
                }
                if unit == 10 || unit == 13 { throw failure(.rawNewline, "A literal line break is not allowed here. Use a newline escape.") }
                let r = range(cursor)
                if StringEscapePresentation.isInvisible(UInt32(unit)) {
                    warn(.literalControl, "Literal control or directional character is present in the source.", r)
                }
                try decodedUnit(unit, sourceRange: r); cursor += 1
            }
            guard closed else { throw failure(.closingQuote, "Expected the closing quote before end of input.", length: 0) }
            if options.representation == .quoted {
                try skipWhitespace()
                guard current == nil else { throw failure(.unexpectedToken, "Unexpected text after the string literal.") }
            }
        }
        static func hex(_ unit: UInt16) -> UInt32? {
            switch unit { case 48...57: UInt32(unit - 48); case 65...70: UInt32(unit - 55)
            case 97...102: UInt32(unit - 87); default: nil }
        }
        mutating func fixedHex(_ count: Int, start: Int) throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<count {
                guard let unit = current, let digit = Self.hex(unit) else {
                    throw failure(.hexDigit, "Expected \(count) hexadecimal digits in this escape.", related: range(start))
                }
                value = value * 16 + digit; cursor += 1
            }
            return value
        }
        mutating func braceHex(start: Int) throws -> UInt32 {
            cursor += 1
            let digits = cursor
            var value: UInt32 = 0
            while let unit = current, let digit = Self.hex(unit) {
                try checkpoint()
                if options.language == .swift && cursor - digits == 8 {
                    throw failure(.unicodeDigits, "Swift Unicode escapes allow one to eight hexadecimal digits.", related: range(start))
                }
                value = min(0x110000, value * 16 + digit); cursor += 1
            }
            guard cursor > digits else { throw failure(.unicodeDigits, "Expected hexadecimal digits after '{'.", related: range(start)) }
            guard current == 125 else { throw failure(.unicodeDigits, "Expected '}' after Unicode escape digits.", related: range(start)) }
            cursor += 1
            guard value <= 0x10FFFF, !(options.language == .swift && (0xD800...0xDFFF).contains(value)) else {
                throw failure(.invalidScalar, "Unicode escape is outside the supported Unicode scalar range.", at: start, length: cursor - start)
            }
            return value
        }
        mutating func escape() throws {
            let start = cursor; cursor += 1
            guard let unit = current else { throw failure(.incompleteEscape, "Incomplete escape at end of input.", length: 0, related: range(start)) }
            cursor += 1
            var value: UInt32?
            switch unit {
            case 92,34: value = UInt32(unit)
            case 39 where options.language != .json: value = 39
            case 47 where options.language == .json || options.language == .javascript: value = 47
            case 110: value = 10
            case 114: value = 13
            case 116: value = 9
            case 98 where options.language != .swift: value = 8
            case 102 where options.language != .swift: value = 12
            case 118 where options.language == .javascript: value = 11
            case 48 where options.language != .json:
                if options.language == .javascript, let next = current, (48...57).contains(next) {
                    throw failure(.strictEscape, "Legacy numeric escapes are not allowed in the JavaScript strict profile.", at: start, length: 2)
                }
                value = 0
            case 117:
                if options.language == .swift {
                    guard current == 123 else { throw failure(.invalidEscape, "Swift Unicode escapes use \\u{…}.", related: range(start)) }
                    value = try braceHex(start: start)
                } else if options.language == .javascript && current == 123 { value = try braceHex(start: start) }
                else { value = try fixedHex(4, start: start) }
            case 120 where options.language == .javascript: value = try fixedHex(2, start: start)
            case 40 where options.language == .swift:
                throw failure(.interpolation, "Swift interpolation is not evaluated. Escape its backslash to keep it as text.", at: start, length: 2, status: .unsupportedSyntax)
            case let n where options.language == .javascript && [10,13,0x2028,0x2029].contains(n):
                if unit == 13 && current == 10 { cursor += 1 }
                warn(.continuation, "Line continuation removes this source line break.", range(start, cursor - start)); return
            default:
                if options.language == .javascript {
                    if (49...57).contains(unit) { throw failure(.strictEscape, "Legacy numeric escapes are not allowed in the JavaScript strict profile.", at: start, length: 2) }
                    warn(.identityEscape, "Backslash is ignored by JavaScript for this escape.", range(start, 2))
                    value = UInt32(unit)
                } else { throw failure(.invalidEscape, "This escape is not supported by \(options.language.title).", at: cursor - 1, related: range(start)) }
            }
            let r = range(start, cursor - start)
            if let value {
                if StringEscapePresentation.isInvisible(value) && ![9,10,13].contains(value) {
                    warn(.decodedControl, "Decoded text contains control or directional characters.", r)
                }
                if value > 0xFFFF {
                    let n = value - 0x10000
                    try decodedUnit(UInt16(0xD800 + (n >> 10)), sourceRange: r)
                    try decodedUnit(UInt16(0xDC00 + (n & 1023)), sourceRange: r)
                } else { try decodedUnit(UInt16(value), sourceRange: r) }
            }
        }
        mutating func surrogateIssue(_ r: NSRange) {
            badUnicode = true
            if !issues.contains(where: { $0.code == .unpairedSurrogate }) {
                add(.init(code: .unpairedSurrogate, severity: .error,
                    message: "String syntax accepted; an unpaired UTF-16 surrogate cannot be shown as Unicode text. No output was created.", range: r))
            }
        }
        mutating func decodedUnit(_ unit: UInt16, sourceRange: NSRange) throws {
            if let pending = pendingHigh {
                pendingHigh = nil
                if !(0xDC00...0xDFFF).contains(unit) { surrogateIssue(pending.range) }
                else { try append(unit); return }
            }
            if (0xD800...0xDBFF).contains(unit) { pendingHigh = (unit, sourceRange) }
            else if (0xDC00...0xDFFF).contains(unit) { surrogateIssue(sourceRange) }
            try append(unit)
        }
        mutating func result(_ status: StringEscapeStatus, artifact: Bool) -> StringEscapeResult {
            // At most 32 issue anchors: a single linear source-coordinate pass, independent of wrapping.
            var starts = [0], p = 0
            while p < units.count {
                if units[p] == 13 {
                    if p + 1 < units.count && units[p + 1] == 10 { p += 1 }
                    starts.append(p + 1)
                } else if units[p] == 10 { starts.append(p + 1) }
                p += 1
            }
            for i in issues.indices {
                guard let r = issues[i].range else { continue }
                var low = 0, high = starts.count
                while low < high {
                    let mid = (low + high) / 2
                    if starts[mid] <= r.location { low = mid + 1 } else { high = mid }
                }
                let line = max(0, low - 1)
                issues[i].line = line + 1; issues[i].column = r.location - starts[line] + 1
                issues[i].context = StringEscapePresentation.context(source, range: r)
            }
            return .init(status: status, issues: issues, issueCount: issueCount, inputCount: units.count, outputCount: outputCount,
                         artifact: artifact ? .init(text: String(decoding: output, as: UTF16.self)) : nil)
        }
    }
}
