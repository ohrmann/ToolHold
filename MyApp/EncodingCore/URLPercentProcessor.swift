import Foundation

/// A bounded byte transform, not a URL parser. No normalization, URL construction or recursive decoding.
enum URLPercentProcessor {
    private static let reserved = Set(":/?#[]@!$&'()*+,;=".utf8)
    private static let hex = Array("0123456789ABCDEF".utf8)
    private struct Failure: Error { let issue: URLPercentIssue; let status: URLPercentStatus }

    static func process(_ source: String, options raw: URLPercentOptions = .init(),
                        intent: URLPercentIntent = .convert, limits: URLPercentLimits = .init()) -> URLPercentResult {
        do {
            try Task.checkCancellation()
            // Bounded preflight avoids counting an arbitrarily large pasted document in full.
            var inputCount = 0
            for _ in source.utf16 {
                if inputCount & 4095 == 0 { try Task.checkCancellation() }
                guard inputCount < limits.inputUTF16 else {
                    throw failure(.inputLimit, "Input exceeds the UTF-16 processing limit.", .resourceLimit)
                }
                inputCount += 1
            }
            let options = raw.effective
            let scalars = source.unicodeScalars
            var cursor = scalars.startIndex, offset = 0, processed = 0
            var bytes = Data(), decodedDelimiter = false
            func append(_ byte: UInt8) throws {
                guard bytes.count < (options.direction == .encode ? limits.outputUTF16 : limits.bytes) else {
                    throw failure(options.direction == .encode ? .outputLimit : .byteLimit,
                                  "Result exceeds the processing limit.", .resourceLimit)
                }
                bytes.append(byte)
            }
            while cursor < scalars.endIndex {
                if processed & 4095 == 0 { try Task.checkCancellation() }
                processed += 1
                let scalar = scalars[cursor]
                let next = scalars.index(after: cursor)
                let preserve = options.direction == .encode && options.preserveExistingEscapes
                if scalar == "%" && (options.direction == .decode || preserve) {
                    let first = next
                    let second = first < scalars.endIndex ? scalars.index(after: first) : scalars.endIndex
                    let end = second < scalars.endIndex ? scalars.index(after: second) : scalars.endIndex
                    if (first < scalars.endIndex && digit(scalars[first]) == nil) ||
                       (second < scalars.endIndex && digit(scalars[second]) == nil) {
                        let length = 1 + (first < scalars.endIndex ? scalars[first].utf16.count : 0) +
                            (second < scalars.endIndex ? scalars[second].utf16.count : 0)
                        throw failure(.malformedEscape, "Expected two hexadecimal digits after '%'.", .invalidPercentEncoding,
                                      range: .init(location: offset, length: length))
                    }
                    guard second < scalars.endIndex else {
                        throw failure(.incompleteEscape, "Incomplete percent escape at end of input.", .invalidPercentEncoding,
                                      range: .init(location: inputCount, length: 0))
                    }
                    let byte = digit(scalars[first])! * 16 + digit(scalars[second])!
                    if preserve {
                        try append(37); try append(UInt8(scalars[first].value)); try append(UInt8(scalars[second].value))
                    } else {
                        try append(byte)
                        if options.profile == .uriText && reserved.contains(byte) { decodedDelimiter = true }
                    }
                    cursor = end; offset += 3; continue
                }
                if options.direction == .decode {
                    if options.profile == .formField && scalar == "+" { try append(32) }
                    else { for byte in String(scalar).utf8 { try append(byte) } }
                } else {
                    for byte in String(scalar).utf8 {
                        if options.profile == .formField && byte == 32 { try append(43) }
                        else if allowed(byte, profile: options.profile) { try append(byte) }
                        else { try append(37); try append(hex[Int(byte >> 4)]); try append(hex[Int(byte & 15)]) }
                    }
                }
                offset += scalar.utf16.count; cursor = next
            }
            try Task.checkCancellation()
            var issues: [URLPercentIssue] = []
            if decodedDelimiter {
                issues.append(.init(code: .decodedDelimiter, severity: .note,
                    message: "Decoded delimiters can change URL structure. This is text, not a validated URL."))
            }
            // Foundation validates the completed byte sequence. The backport never publishes repaired text.
            let text: String?
            if #available(macOS 15, iOS 18, *) { text = String(validating: bytes, as: UTF8.self) }
            else {
                let candidate = String(decoding: bytes, as: UTF8.self)
                text = candidate.utf8.elementsEqual(bytes) ? candidate : nil
            }
            let preview = bytes.prefix(URLPercentLimits.previewBytes).map { String(format: "%02X", $0) }.joined(separator: " ")
            guard let text else {
                issues.insert(.init(code: .invalidUTF8, severity: .note,
                    message: "Percent escapes decoded to bytes that are not valid UTF-8. No replacement text was created."), at: 0)
                return .init(status: .bytesOnly, issues: issues, byteCount: bytes.count, preview: preview,
                             artifact: intent == .convert ? .init(text: nil) : nil)
            }
            guard text.utf16.count <= limits.outputUTF16 else {
                throw failure(.outputLimit, "Text result exceeds the UTF-16 processing limit.", .resourceLimit)
            }
            if text.unicodeScalars.first?.value == 0xFEFF {
                issues.append(.init(code: .leadingBOM, severity: .note, message: "Leading U+FEFF preserved."))
            }
            var controls = 0
            for (index, scalar) in text.unicodeScalars.enumerated() {
                if index & 4095 == 0 { try Task.checkCancellation() }
                if isControl(scalar.value) { controls += 1 }
            }
            if controls > 0 {
                issues.append(.init(code: .controls, severity: .note,
                    message: "Contains \(controls) control or directional character(s). Text and copied data are preserved."))
            }
            try Task.checkCancellation()
            return .init(status: .success, issues: issues, byteCount: bytes.count, preview: preview,
                         artifact: intent == .convert ? .init(text: text) : nil)
        } catch is CancellationError { return .init(status: .cancelled) }
        catch let error as Failure {
            var issue = error.issue
            if let range = issue.range {
                let position = coordinates(source, at: range.location)
                issue.line = position.0; issue.column = position.1
                issue.context = context(source, range: range)
            }
            return .init(status: error.status, issues: [issue])
        } catch { return .init(status: .processingFailure) }
    }
    private static func failure(_ code: URLPercentIssue.Code, _ message: String, _ status: URLPercentStatus,
                                range: NSRange? = nil) -> Failure {
        .init(issue: .init(code: code, severity: .error, message: message, range: range), status: status)
    }
    private static func digit(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 48...57: UInt8(scalar.value - 48)
        case 65...70: UInt8(scalar.value - 55)
        case 97...102: UInt8(scalar.value - 87)
        default: nil
        }
    }
    private static func allowed(_ byte: UInt8, profile: URLPercentProfile) -> Bool {
        if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95].contains(byte) { return true }
        switch profile {
        case .component: return byte == 126
        case .formField: return byte == 42
        case .uriText: return byte == 126 || reserved.contains(byte)
        }
    }
    private static func isControl(_ value: UInt32) -> Bool {
        value < 32 || (127...159).contains(value) || [0x061C,0x200E,0x200F].contains(value) ||
            (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value)
    }
    private static func coordinates(_ source: String, at target: Int) -> (Int, Int) {
        var offset = 0, line = 1, column = 1, wasCR = false
        for scalar in source.unicodeScalars {
            if offset >= target { break }
            if scalar == "\r" { line += 1; column = 1 }
            else if scalar == "\n" { if !wasCR { line += 1 }; column = 1 }
            else { column += scalar.utf16.count }
            wasCR = scalar == "\r"; offset += scalar.utf16.count
        }
        return (line, column)
    }
    /// Grapheme-bounded presentation only; the diagnostic retains its original source range.
    private static func context(_ source: String, range: NSRange) -> String {
        var before: [String] = [], token = "", after: [String] = [], offset = 0, trimmed = false
        for character in source {
            let count = character.utf16.count
            let shown: String
            if count > 64 { shown = "[long grapheme · \(count) UTF-16]" }
            else {
                shown = character.unicodeScalars.map { scalar in
                    isControl(scalar.value) ? "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}" : String(scalar)
                }.joined()
            }
            if offset + count <= range.location {
                before.append(shown)
                if before.count > 24 { before.removeFirst(); trimmed = true }
            } else if offset < range.location + range.length { token += shown }
            else {
                after.append(shown)
                if after.count == 25 { break }
            }
            offset += count
        }
        return (trimmed ? "…" : "") + before.joined() + "⟦" + (token.isEmpty ? "│ EOF" : token) + "⟧" +
            after.prefix(24).joined() + (after.count > 24 ? "…" : "")
    }
}
