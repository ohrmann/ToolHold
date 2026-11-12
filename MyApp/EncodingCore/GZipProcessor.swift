import Foundation
import CryptoKit

/// Shared byte pipeline used by text, file, Check, Preview and Export.
enum GZipProcessor {
    static func process(_ bytes: Data, options: GZipOptions = .init(), intent: GZipIntent = .convert,
                        limits: GZipLimits = .init(), operation: GZipOperation = .init()) -> GZipResult {
        var offset = 0
        do {
            return try stream(options: options, intent: intent, limits: limits, operation: operation, total: Int64(bytes.count), read: {
                let end = min(bytes.count, offset + max(1, limits.chunk)); defer { offset = end }
                return bytes.subdata(in: offset..<end)
            })
        } catch { return failure(error) }
    }
    static func stream(options: GZipOptions, intent: GZipIntent, limits: GZipLimits, operation: GZipOperation,
                       total: Int64?, read: () throws -> Data, write: ((Data) throws -> Void)? = nil,
                       progress: @Sendable (GZipProgress) -> Void = { _ in }) throws -> GZipResult {
        try operation.check()
        guard limits.chunk > 0 && limits.chunk <= 65_536 && limits.retained >= 0 && limits.preview >= 0 && limits.copyText >= 0 else {
            throw GZipFailure(.resourceLimit, .budget, "Unsupported processing buffer budget.")
        }
        if let total, total > limits.fileInput { throw GZipFailure(.resourceLimit, .budget, "Input exceeds the 256 MiB file processing limit.") }
        let codec = try GZipStreamCodec(options: options, limits: limits, operation: operation)
        let collector = Collector(limits: limits, enabled: intent == .convert)
        var tail = Data(), tailStart: Int64 = 0
        var digest = SHA256(), count: Int64 = 0, lastProgress = ProcessInfo.processInfo.systemUptime
        let emit: (Data) throws -> Void = { data in
            try operation.check(); collector.consume(data); try write?(data)
        }
        while true {
            let more = try autoreleasepool { () throws -> Bool in
                try operation.check()
                let data = try read()
                if data.isEmpty { return false }
                count = try GZipStreamCodec.add(count, Int64(data.count))
                guard count <= limits.fileInput else { throw GZipFailure(.resourceLimit, .budget, "Input exceeds the 256 MiB file processing limit.") }
                digest.update(data: data)
                tail = Data(data.suffix(64)); tailStart = count - Int64(tail.count)
                do { try codec.consume(data, emit: emit) }
                catch var failure as GZipFailure {
                    if let offset = failure.offset { failure.context = byteContext(data, base: count - Int64(data.count), offset: offset) }
                    throw failure
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastProgress >= 0.1 { progress(.init(bytes: count, total: total)); lastProgress = now }
                return true
            }
            if !more { break }
        }
        do { try codec.finish(emit: emit) }
        catch var failure as GZipFailure {
            if let offset = failure.offset { failure.context = byteContext(tail, base: tailStart, offset: offset) }
            throw failure
        }
        try operation.check()
        var result = GZipResult(inputBytes: count, outputBytes: codec.outputBytes, members: codec.members, sourceDigest: Data(digest.finalize()))
        if intent == .convert { result.artifact = try collector.finish(operation: operation) }
        progress(.init(bytes: count, total: count))
        try operation.check()
        return result
    }
    private static func byteContext(_ data: Data, base: Int64, offset: Int64) -> String {
        let point = Int(min(Int64(data.count), max(0, offset - base)))
        let lower = max(0, point - 16), upper = min(data.count, point + 32)
        let bytes = data.subdata(in:lower..<upper).map { String(format:"%02X",$0) }.joined(separator:" ")
        return "Compressed bytes \(base + Int64(lower))–\(base + Int64(upper)): " + bytes + (point == data.count ? " ⟦EOF⟧" : "")
    }
    static func failure(_ error: Error) -> GZipResult {
        if error is CancellationError { return .init(status: .cancelled) }
        if let failure = error as? GZipFailure { return .init(status: failure.status, failure: failure) }
        return .init(status: .ioFailure, failure: .init(.ioFailure, .io, "Reading or writing failed. Check access, available space and the selected file provider."))
    }
    private final class Collector {
        private let limits: GZipLimits
        private let enabled: Bool
        private var complete: Data? = Data()
        private var prefix = Data()
        init(limits: GZipLimits, enabled: Bool) { self.limits = limits; self.enabled = enabled }
        func consume(_ data: Data) {
            guard enabled else { return }
            if prefix.count < limits.preview { prefix.append(data.prefix(limits.preview - prefix.count)) }
            if complete != nil {
                if complete!.count <= limits.retained - data.count { complete?.append(data) }
                else { complete = nil }
            }
        }
        func finish(operation: GZipOperation) throws -> GZipArtifact {
            var artifact = GZipArtifact(bytes: complete)
            artifact.hexPreview = prefix.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
            artifact.base64Preview = String(prefix.base64EncodedString().prefix(limits.preview))
            // A prefix may end inside one UTF-8 scalar; do not repair or call that a file error.
            for trim in 0...min(3, prefix.count) {
                if let text = String(data: prefix.prefix(prefix.count - trim), encoding: .utf8) {
                    artifact.textPreview = safePreview(text, limit: limits.preview); break
                }
            }
            try operation.check()
            if let bytes = complete {
                if let count = try? Base64StreamSize.encoded(Int64(bytes.count), padded: true), count <= limits.copyText {
                    artifact.base64 = bytes.base64EncodedString()
                }
                let decoded = try Base64TextCodec.decode(bytes, encoding: .utf8)
                artifact.binary = decoded == nil
                if let decoded, decoded.utf16.count <= limits.copyText { artifact.text = decoded }
            }
            try operation.check(); return artifact
        }
    }
    static func safePreview(_ text: String, limit: Int = 8_192) -> String {
        var output = "", units = 0
        for character in text {
            var display = ""
            for scalar in character.unicodeScalars {
                let n = scalar.value
                if n < 32 || (0x7F...0x9F).contains(n) || [0x061C,0x200E,0x200F,0x2028,0x2029].contains(n) || (0x202A...0x202E).contains(n) || (0x2066...0x2069).contains(n) {
                    display += "\\u{\(String(n, radix: 16, uppercase: true))}"
                } else { display.unicodeScalars.append(scalar) }
            }
            if units + display.utf16.count > limit { output += "…"; break }
            output += display; units += display.utf16.count
        }
        return output
    }
    static func base64(_ text: String, mode: Base64DecodeMode, limits: GZipLimits, operation: GZipOperation) throws -> (Data, [String]) {
        guard text.utf16.prefix(limits.textInput + 1).count <= limits.textInput else {
            throw GZipFailure(.resourceLimit, .budget, "Text Input exceeds 262,144 UTF-16 units. Choose a gzip file instead.")
        }
        var scanner = Base64PolicyScanner(alphabet: .standard, mode: mode), normalized = Data(), offset = 0
        do {
            for scalar in text.unicodeScalars {
                if offset % 4_096 == 0 { try operation.check(); normalized.append(scanner.drain()) }
                let length = scalar.value > 0xFFFF ? 2 : 1
                try scanner.consume(scalar.value, at: Int64(offset), length: length); offset += length
            }
            let notes = try scanner.finish(at: Int64(offset)); normalized.append(scanner.drain())
            guard let data = Data(base64Encoded: normalized) else { throw GZipFailure(.internalFailure, .engine, "The validated Base64 could not be decoded.") }
            return (data, notes.map(\.message))
        } catch let scan as Base64ScanFailure {
            var failure = GZipFailure(.invalidBase64, .base64, scan.message, offset: scan.offset)
            failure.space = .inputUTF16; failure.length = scan.length; failure.exact = true
            let range = NSRange(location: Int(scan.offset), length: scan.length)
            var line = 1, column = 1, previousCR = false, position = 0
            for unit in text.utf16 {
                if position >= range.location { break }; position += 1
                if unit == 13 { line += 1; column = 1; previousCR = true }
                else if unit == 10 { if !previousCR { line += 1 }; column = 1; previousCR = false }
                else { column += 1; previousCR = false }
            }
            failure.line = line; failure.column = column
            failure.context = safePreview(StringEscapePresentation.context(text, range: range))
            throw failure
        }
    }
}
