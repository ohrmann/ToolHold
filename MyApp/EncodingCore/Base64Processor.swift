import Foundation

/// Policy validation precedes the system codec; the original source is never normalized.
enum Base64Processor {
    static func process(_ source: String, options: Base64Options = .init(), intent: Base64Intent = .convert,
                        limits: Base64Limits = .init()) -> Base64Result {
        do {
            try Task.checkCancellation()
            guard source.utf16.prefix(limits.inputUTF16 + 1).count <= limits.inputUTF16 else {
                throw Base64Failure(status: .resourceLimit, code: .inputLimit, message: "Input exceeds \(limits.inputUTF16) UTF-16 code units.")
            }
            if options.direction == .encode {
                let bytes = try Base64TextCodec.encode(source, encoding: options.encoding, limit: limits.bytes)
                let size = ((bytes.count + 2) / 3) * 4
                let omitted = options.alphabet == .urlSafe && !options.urlPadding ? (3 - bytes.count % 3) % 3 : 0
                guard size - omitted <= limits.outputUTF16 else { throw outputLimit() }
                try Task.checkCancellation()
                var text = bytes.base64EncodedString()
                if options.alphabet == .urlSafe {
                    text = text.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                    if !options.urlPadding { text.removeLast(omitted) }
                }
                let notes = try Base64TextCodec.notes(source)
                try Task.checkCancellation()
                return .init(status: .success, issues: notes, byteCount: bytes.count,
                             artifact: intent == .convert ? .init(text: text, decodedBytes: nil) : nil)
            }
            var (normalized, notes, count) = try validate(source, options: options)
            guard count <= limits.bytes else { throw outputLimit() }
            try Task.checkCancellation()
            // The system receives only canonical, padded standard alphabet, including in Forgiving.
            while !normalized.count.isMultiple(of: 4) { normalized.append(61) }
            guard let bytes = Data(base64Encoded: Data(normalized), options: []) else {
                throw Base64Failure(status: .processingFailure, code: .foundationFailure, message: "The system decoder could not process the validated input.")
            }
            guard bytes.count == count else {
                throw Base64Failure(status: .processingFailure, code: .foundationFailure, message: "The system decoder returned an unexpected byte count.")
            }
            try Task.checkCancellation()
            let text = try Base64TextCodec.decode(bytes, encoding: options.encoding)
            if let text {
                guard text.utf16.prefix(limits.outputUTF16 + 1).count <= limits.outputUTF16 else { throw outputLimit() }
                notes += try Base64TextCodec.notes(text)
            } else {
                notes.append(.init(code: .invalidTextEncoding, severity: .note,
                    message: "Decoded \(count) byte(s), but they are not valid \(options.encoding.title) text. Choose another text encoding explicitly."))
            }
            try Task.checkCancellation()
            let preview = bytes.prefix(Base64Limits.previewBytes).map { String(format: "%02X", $0) }.joined(separator: " ")
            return .init(status: text == nil ? .bytesOnly : .success, issues: notes, byteCount: count, preview: preview,
                         artifact: intent == .convert ? .init(text: text, decodedBytes: bytes) : nil)
        } catch is CancellationError { return .init(status: .cancelled) }
        catch let failure as Base64Failure {
            var issue = Base64Issue(code: failure.code, severity: .error, message: failure.message, range: failure.range)
            if let range = failure.range {
                let location = location(source, at: range.location)
                issue.line = location.0; issue.column = location.1
            }
            return .init(status: failure.status, issues: [issue])
        } catch {
            return .init(status: .processingFailure, issues: [.init(code: .foundationFailure, severity: .error, message: "Processing could not be completed.")])
        }
    }
    private static func outputLimit() -> Base64Failure {
        .init(status: .resourceLimit, code: .outputLimit, message: "Output exceeds the processing limit. Input has been preserved.")
    }
    private static func validate(_ source: String, options: Base64Options) throws -> ([UInt8], [Base64Issue], Int) {
        var scanner = Base64PolicyScanner(alphabet: options.alphabet, mode: options.decodeMode)
        var normalized = Data(), offset = 0
        do {
            for scalar in source.unicodeScalars {
                if offset & 4095 == 0 { try Task.checkCancellation(); normalized.append(scanner.drain()) }
                try scanner.consume(scalar.value, at: Int64(offset), length: scalar.utf16.count)
                offset += scalar.utf16.count
            }
            let notes = try scanner.finish(at: Int64(offset))
            normalized.append(scanner.drain())
            return (Array(normalized), notes, Int(scanner.decodedCount))
        } catch let failure as Base64ScanFailure {
            throw Base64Failure(status: .invalidBase64, code: failure.code, message: failure.message,
                range: NSRange(location: Int(failure.offset), length: failure.length))
        }
    }
    private static func location(_ source: String, at target: Int) -> (Int, Int) {
        var line = 1, column = 1, previousCR = false
        for (offset, unit) in source.utf16.enumerated() {
            if offset >= target { break }
            if unit == 13 { line += 1; column = 1 }
            else if unit == 10 { if !previousCR { line += 1 }; column = 1 }
            else { column += 1 }
            previousCR = unit == 13
        }
        return (line, column)
    }
}
