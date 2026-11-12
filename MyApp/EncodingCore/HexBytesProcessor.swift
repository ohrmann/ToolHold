import Foundation

/// Bounded text/bytes transform. No guessing, normalization, recursive decoding or I/O.
enum HexBytesProcessor {
    private struct Failure: Error { let status: HexBytesStatus; let issue: HexBytesIssue }
    static func process(_ source: String, options raw: HexBytesOptions = .init(),
                        intent: HexBytesIntent = .convert, limits: HexBytesLimits = .init()) -> HexBytesResult {
        var units = [UInt16]()
        do {
            try Task.checkCancellation()
            for unit in source.utf16 {
                if units.count & 4095 == 0 { try Task.checkCancellation() }
                guard units.count < limits.inputUTF16 else { throw resource(.inputLimit, "Input exceeds the UTF-16 processing limit.") }
                units.append(unit)
            }
            let options = raw.effective
            let bytes: Data, map: HexBytesSourceMap?
            if options.direction == .decode {
                var scanner = Scanner(units: units, format: options.inputFormat, limit: limits.bytes)
                try scanner.scan(); bytes = scanner.bytes; map = .init(digitStarts: scanner.starts)
            } else {
                bytes = try Base64TextCodec.encode(source, encoding: .utf8, limit: limits.bytes); map = nil
            }
            var issues: [HexBytesIssue] = [], text: String?, hex: String?, outputCount = 0
            if let failure = try HexUTF8Validator.firstFailure(bytes) {
                issues.append(.init(code: failure.code, severity: .note, domain: .utf8, message: failure.message,
                    range: map?.range(for: failure.offset) ?? .init(location: units.count, length: 0),
                    related: failure.lead.flatMap { map?.range(for: $0) }, byteOffset: failure.offset))
            } else {
                if options.direction == .encode { text = source }
                else { text = try Base64TextCodec.decode(bytes, encoding: .utf8) }
                guard text != nil else { return .init(status: .processingFailure, inputCount: units.count) }
                issues += try notes(text!)
            }
            if options.direction == .encode {
                guard let count = options.outputFormat.length(for: bytes.count), count <= limits.outputUTF16 else {
                    throw resource(.outputLimit, "Hex output exceeds the UTF-16 limit. Choose Compact or reduce Input.")
                }
                outputCount = count
                if intent == .convert { hex = try format(bytes, format: options.outputFormat, hexCase: options.hexCase, limit: limits.outputUTF16) }
            } else {
                outputCount = text?.utf16.count ?? 0
                guard outputCount <= limits.outputUTF16 else { throw resource(.outputLimit, "Text output exceeds the UTF-16 processing limit.") }
            }
            try Task.checkCancellation()
            issues = enrich(issues, source: source, units: units)
            let status: HexBytesStatus = text == nil ? .bytesOnly : issues.isEmpty ? .success : .successWithNotes
            return .init(status: status, issues: Array(issues.prefix(HexBytesLimits.detailedIssues)),
                issueCount: issues.reduce(0) { $0 + $1.occurrences }, inputCount: units.count, byteCount: bytes.count, outputCount: outputCount,
                artifact: intent == .convert ? .init(bytes: bytes, text: text, hex: hex, sourceMap: map) : nil)
        } catch is CancellationError { return .init(status: .cancelled, inputCount: units.count) }
        catch let failure as Failure {
            return .init(status: failure.status, issues: enrich([failure.issue], source: source, units: units), issueCount: 1, inputCount: units.count)
        } catch let failure as Base64Failure {
            return .init(status: failure.status == .resourceLimit ? .resourceLimit : .processingFailure,
                issues: [.init(code: .byteLimit, severity: .error, domain: .resource, message: "Encoded bytes exceed the processing limit.")], issueCount: 1, inputCount: units.count)
        } catch { return .init(status: .processingFailure, inputCount: units.count) }
    }
    static func format(_ bytes: Data, format: HexBytesOutputFormat, hexCase: HexBytesCase, limit: Int = 262_144) throws -> String {
        try Task.checkCancellation()
        guard let count = format.length(for: bytes.count), count <= limit else { throw resource(.outputLimit, "Copy format exceeds limit; choose Compact.") }
        var result = [UInt8](); result.reserveCapacity(count)
        let digits = Array((hexCase == .uppercase ? "0123456789ABCDEF" : "0123456789abcdef").utf8)
        for (index, b) in bytes.enumerated() {
            if index & 4095 == 0 { try Task.checkCancellation() }
            if index > 0 {
                if format == .spaced { result.append(32) }
                else if format == .prefixed { result.append(contentsOf: [44, 32]) }
            }
            if format == .prefixed { result.append(contentsOf: [48, 120]) }
            else if format == .escaped { result.append(contentsOf: [92, 120]) }
            result.append(digits[Int(b >> 4)]); result.append(digits[Int(b & 15)])
        }
        try Task.checkCancellation(); return String(decoding: result, as: UTF8.self)
    }
    private static func resource(_ code: HexBytesIssue.Code, _ message: String) -> Failure {
        .init(status: .resourceLimit, issue: .init(code: code, severity: .error, domain: .resource, message: message))
    }
    private static func notes(_ text: String) throws -> [HexBytesIssue] {
        var nul = 0, controls = 0
        for (index, s) in text.unicodeScalars.enumerated() {
            if index & 4095 == 0 { try Task.checkCancellation() }
            if s.value == 0 { nul += 1 }
            else if StringEscapePresentation.isInvisible(s.value) && ![9,10,13].contains(s.value) { controls += 1 }
        }
        var result: [HexBytesIssue] = []
        if text.unicodeScalars.first?.value == 0xFEFF { result.append(.init(code: .leadingBOM, severity: .note, domain: .utf8, message: "Leading BOM (U+FEFF) preserved.")) }
        if nul > 0 { result.append(.init(code: .nul, severity: .note, domain: .utf8, message: "Text contains NUL bytes. Text and copied data are preserved.", occurrences: nul)) }
        if controls > 0 { result.append(.init(code: .controls, severity: .note, domain: .utf8, message: "Text contains control or directional characters. Use Bytes for safe inspection.", occurrences: controls)) }
        return result
    }
    private static func enrich(_ issues: [HexBytesIssue], source: String, units: [UInt16]) -> [HexBytesIssue] {
        issues.map { item in
            var issue = item
            guard let range = issue.range else { return issue }
            var p = 0, line = 1, start = 0
            while p < min(range.location, units.count) {
                if units[p] == 13 {
                    if p + 1 < units.count && units[p + 1] == 10 { p += 1 }
                    line += 1; start = p + 1
                } else if units[p] == 10 { line += 1; start = p + 1 }
                p += 1
            }
            issue.line = line; issue.column = max(1, range.location - start + 1)
            issue.context = StringEscapePresentation.context(source, range: range); return issue
        }
    }
    private struct Scanner {
        let units: [UInt16]
        let format: HexBytesInputFormat
        let limit: Int
        var p = 0
        var bytes = Data()
        var starts = [UInt32]()
        var current: UInt16? { p < units.count ? units[p] : nil }
        func digit(_ n: UInt16) -> UInt8? {
            switch n { case 48...57: UInt8(n - 48); case 65...70: UInt8(n - 55); case 97...102: UInt8(n - 87); default: nil }
        }
        func whitespace(_ n: UInt16) -> Bool { [9,10,13,32].contains(n) }
        func fail(_ code: HexBytesIssue.Code, _ message: String, related: NSRange? = nil) -> Failure {
            let length = p < units.count ? ((0xD800...0xDBFF).contains(units[p]) && p + 1 < units.count && (0xDC00...0xDFFF).contains(units[p + 1]) ? 2 : 1) : 0
            return .init(status: .invalidHex, issue: .init(code: code, severity: .error, domain: .hex, message: message,
                range: .init(location: p, length: length), related: related))
        }
        mutating func skipWhitespace() throws -> Bool {
            let start = p
            while let n = current, whitespace(n) { if p & 4095 == 0 { try Task.checkCancellation() }; p += 1 }
            return p != start
        }
        mutating func pair() throws {
            let start = p
            guard let n = current, let high = digit(n) else { throw fail(.digit, "Expected an ASCII hexadecimal digit.") }
            p += 1
            guard let n = current, let low = digit(n) else { throw fail(.incompleteByte, "Expected a second hexadecimal digit in this byte.", related: .init(location: start, length: 1)) }
            guard bytes.count < limit else { throw HexBytesProcessor.resource(.byteLimit, "Bytes exceed the processing limit.") }
            p += 1; bytes.append(high * 16 + low); starts.append(UInt32(start))
        }
        mutating func scan() throws {
            _ = try skipWhitespace()
            while p < units.count {
                if bytes.count & 4095 == 0 { try Task.checkCancellation() }
                if format != .pairs {
                    let prefix = p
                    guard current == (format == .prefixed ? 48 : 92) else { throw fail(.prefix, "Expected \(format == .prefixed ? "0xHH" : "\\xHH") byte token.") }
                    p += 1
                    guard current == 120 || (format == .prefixed && current == 88) else {
                        throw fail(.prefix, "Expected '\(format == .prefixed ? "x or X" : "x")' in byte prefix.", related: .init(location: prefix, length: 1))
                    }
                    p += 1; try pair()
                } else {
                    try pair()
                    // Even contiguous runs are allowed. No nibble may cross a separator.
                    if let n = current, digit(n) != nil { continue }
                }
                let spaced = try skipWhitespace()
                guard p < units.count else { break }
                let punct: Bool = format == .pairs ? current == 58 || current == 45 : format == .prefixed ? current == 44 : false
                if punct {
                    let separator = p; p += 1; _ = try skipWhitespace()
                    guard p < units.count else { throw fail(.separator, "Expected a byte after the separator.", related: .init(location: separator, length: 1)) }
                } else if !spaced && format != .escaped {
                    throw fail(.separator, "Expected a permitted separator between byte tokens.")
                }
            }
        }
    }
}
