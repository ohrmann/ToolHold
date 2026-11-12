import Foundation

/// One strict/forgiving grammar for the text adapter and chunked file decoder.
/// Positions belong to the caller: UTF-16 for T-012, byte offsets for files.
struct Base64ScanFailure: Error, Sendable {
    let code: Base64Issue.Code
    let message: String
    let offset: Int64
    let length: Int
}
struct Base64PolicyScanner {
    let alphabet: Base64Alphabet
    let mode: Base64DecodeMode
    private var pending: [UInt8] = []
    private var lastOffset: Int64 = 0
    private var padding = 0
    private var whitespace: Int64 = 0
    private(set) var decodedCount: Int64 = 0
    private var normalized = Data()
    private static let symbols = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    init(alphabet: Base64Alphabet, mode: Base64DecodeMode) { self.alphabet = alphabet; self.mode = mode }
    mutating func consume(_ value: UInt32, at offset: Int64, length: Int = 1) throws {
        if [9,10,12,13,32].contains(value), mode == .forgiving { whitespace += 1; return }
        if value == 61 {
            guard pending.count == 2 || pending.count == 3, padding < (pending.count == 2 ? 2 : 1) else {
                throw failure(.invalidPadding, "Padding is not allowed at this position.", offset, length)
            }
            padding += 1; return
        }
        let number: UInt8
        switch value {
        case 65...90: number = UInt8(value - 65)
        case 97...122: number = UInt8(value - 97 + 26)
        case 48...57: number = UInt8(value - 48 + 52)
        case 43 where alphabet == .standard, 47 where alphabet == .standard: number = value == 43 ? 62 : 63
        case 45 where alphabet == .urlSafe, 95 where alphabet == .urlSafe: number = value == 45 ? 62 : 63
        default:
            let wrong = [43,47,45,95].contains(value)
            throw failure(wrong ? .wrongAlphabet : .invalidSymbol, wrong ?
                "This symbol does not belong to the selected \(alphabet.title) alphabet." :
                "U+\(String(format: "%04X", value)) is not allowed in \(alphabet.title)\(mode == .strict ? " Strict mode" : "").", offset, length)
        }
        guard padding == 0 else { throw failure(.invalidPadding, "Data is not allowed after padding.", offset, length) }
        pending.append(number); lastOffset = offset
        if pending.count == 4 {
            normalized.append(contentsOf: pending.map { Self.symbols[Int($0)] })
            pending.removeAll(keepingCapacity: true)
            decodedCount = try Base64StreamSize.add(decodedCount, 3)
        }
    }
    /// Drain after each bounded input block; carries only the unfinished quartet.
    mutating func drain() -> Data { let value = normalized; normalized = Data(); return value }
    mutating func finish(at eof: Int64) throws -> [Base64Issue] {
        let remainder = pending.count
        if remainder == 1 { throw failure(.invalidLength, "The final Base64 group needs at least two data symbols.", eof, 0) }
        if padding > 0 && remainder + padding != 4 { throw failure(.invalidPadding, "Incomplete padding at end of input.", eof, 0) }
        var notes: [Base64Issue] = []
        if whitespace > 0 { notes.append(.init(code: .whitespace, severity: .note, message: "Ignored \(whitespace) ASCII whitespace character(s) for decoding. Input is unchanged.")) }
        if padding == 0 && remainder > 0 && alphabet == .standard {
            if mode == .strict { throw failure(.missingPadding, "Expected '\(remainder == 2 ? "==" : "=")' padding before end of input.", eof, 0) }
            notes.append(.init(code: .inferredPadding, severity: .note, message: "Missing terminal padding was interpreted for decoding. Input is unchanged."))
        }
        if let last = pending.last, remainder == 2 || remainder == 3 {
            let mask: UInt8 = remainder == 2 ? 15 : 3
            if last & mask != 0 {
                if mode == .strict { throw failure(.nonCanonicalPadBits, "Non-zero pad bits are not allowed in Strict mode.", lastOffset, 1) }
                notes.append(.init(code: .nonCanonicalPadBits, severity: .note, message: "Non-canonical pad bits were ignored. Input is unchanged."))
                pending[remainder - 1] = last & ~mask
            }
            normalized.append(contentsOf: pending.map { Self.symbols[Int($0)] })
            normalized.append(contentsOf: repeatElement(UInt8(61), count: 4 - remainder))
            decodedCount = try Base64StreamSize.add(decodedCount, Int64(remainder - 1))
        }
        pending.removeAll(); return notes
    }
    private func failure(_ code: Base64Issue.Code, _ message: String, _ offset: Int64, _ length: Int) -> Base64ScanFailure {
        .init(code: code, message: message, offset: offset, length: length)
    }
}

enum Base64StreamSize {
    static func add(_ first: Int64, _ second: Int64) throws -> Int64 {
        let result = first.addingReportingOverflow(second)
        guard !result.overflow && result.partialValue >= 0 else { throw Base64FileFailure(.resourceLimit, "The byte count exceeds the supported range.") }
        return result.partialValue
    }
    static func encoded(_ bytes: Int64, padded: Bool, header: Int64 = 0) throws -> Int64 {
        guard bytes >= 0 else { throw Base64FileFailure(.resourceLimit, "Invalid byte count.") }
        let groups = bytes / 3, remainder = bytes % 3
        let full = groups.multipliedReportingOverflow(by: 4)
        guard !full.overflow else { throw Base64FileFailure(.resourceLimit, "The output size exceeds the supported range.") }
        return try add(add(full.partialValue, remainder == 0 ? 0 : padded ? 4 : remainder + 1), header)
    }
}

struct Base64StreamEncoder {
    let alphabet: Base64Alphabet
    let padded: Bool
    private var carry = Data()
    init(alphabet: Base64Alphabet, padded: Bool) { self.alphabet = alphabet; self.padded = padded }
    mutating func consume(_ data: Data) -> Data {
        var block = carry; block.append(data)
        let complete = block.count - block.count % 3
        carry = Data(block.suffix(block.count - complete))
        return translate(Data(block.prefix(complete)).base64EncodedData())
    }
    mutating func finish() -> Data {
        var encoded = carry.base64EncodedData(); carry.removeAll()
        if !padded { while encoded.last == 61 { encoded.removeLast() } }
        return translate(encoded)
    }
    private func translate(_ data: Data) -> Data {
        guard alphabet == .urlSafe else { return data }
        return Data(data.map { $0 == 43 ? 45 : $0 == 47 ? 95 : $0 })
    }
}
