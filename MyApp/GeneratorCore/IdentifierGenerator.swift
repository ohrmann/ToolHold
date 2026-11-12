import Foundation

/// Serial, memory-only sequence state. No await inside generation: a batch is never interleaved.
actor IdentifierGenerator {
    typealias RandomBytes = @Sendable (Int) throws -> [UInt8]
    typealias Clock = @Sendable () -> Double
    private let random: RandomBytes
    private let clock: Clock
    private var lastULIDTime: UInt64?
    private var lastULIDTail = [UInt8]()
    private var lastV7Time: UInt64?
    init(random: @escaping RandomBytes = SecureRandomBytes.read, clock: @escaping Clock = { Date().timeIntervalSince1970 }) {
        self.random = random; self.clock = clock
    }
    static func timestamp(_ seconds: Double) throws -> UInt64 {
        let ms = floor(seconds * 1000)
        guard seconds.isFinite, seconds >= 0, ms.isFinite, ms >= 0, ms <= Double(IdentifierBudget.maxTimestamp) else {
            throw IdentifierIssue(.clockUnavailable, "Clock unavailable. Time must fit a 48-bit Unix millisecond timestamp.")
        }
        return UInt64(ms)
    }
    static func uuid(_ bytes: [UInt8], version: UInt8, timestamp: UInt64? = nil, letterCase: IdentifierCase) -> String {
        precondition(bytes.count == 16)
        var bytes = bytes
        if let timestamp { for i in 0..<6 { bytes[i] = UInt8(truncatingIfNeeded: timestamp >> (8 * (5 - i))) } }
        bytes[6] = (bytes[6] & 15) | (version << 4); bytes[8] = (bytes[8] & 63) | 128
        let hex = Array((letterCase == .lowercase ? "0123456789abcdef" : "0123456789ABCDEF").utf8)
        var result = [UInt8](); result.reserveCapacity(36)
        for i in bytes.indices {
            if [4, 6, 8, 10].contains(i) { result.append(45) }
            result.append(hex[Int(bytes[i] >> 4)]); result.append(hex[Int(bytes[i] & 15)])
        }
        return String(decoding: result, as: UTF8.self)
    }
    static func ulid(timestamp: UInt64, tail: [UInt8]) -> String {
        precondition(timestamp <= IdentifierBudget.maxTimestamp && tail.count == 10)
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<6 { bytes[i] = UInt8(truncatingIfNeeded: timestamp >> (8 * (5 - i))) }
        bytes.replaceSubrange(6..<16, with: tail)
        var output = [UInt8](); output.reserveCapacity(26)
        // A conceptual 130-bit stream begins with two zero bits; no 128-bit numeric conversion.
        for group in 0..<26 {
            var value = 0
            for bit in 0..<5 {
                let sourceBit = group * 5 + bit - 2
                value <<= 1
                if sourceBit >= 0 { value |= Int((bytes[sourceBit / 8] >> (7 - sourceBit % 8)) & 1) }
            }
            output.append(alphabet[value])
        }
        return String(decoding: output, as: UTF8.self)
    }
    static func nanoIndex(_ byte: UInt8, alphabetCount: Int) -> Int? {
        let limit = 256 - 256 % alphabetCount
        return Int(byte) < limit ? Int(byte) % alphabetCount : nil
    }
    func generate(_ original: IdentifierOptions) -> IdentifierResult {
        let options = original.effective
        if let issue = options.issue { return .init(issue: issue) }
        do {
            try Task.checkCancellation()
            var stream = RandomStream(provider: random, budget: max(4096, options.count * (options.kind == .nanoID ? options.nanoLength : 16) * 8))
            var values = [String](); values.reserveCapacity(options.count)
            var rollback = false
            let symbols = options.kind == .nanoID ? Array(options.symbols.utf8) : []
            for _ in 0..<options.count {
                try Task.checkCancellation()
                switch options.kind {
                case .uuidV4:
                    values.append(Self.uuid(try stream.read(16), version: 4, letterCase: options.uuidCase))
                case .uuidV7:
                    let now = try Self.timestamp(clock())
                    if let previous = lastV7Time, now < previous { rollback = true }
                    lastV7Time = now
                    values.append(Self.uuid(try stream.read(16), version: 7, timestamp: now, letterCase: options.uuidCase))
                case .ulid:
                    let now = try Self.timestamp(clock())
                    if options.ulidMonotonic {
                        if let previous = lastULIDTime, now <= previous {
                            rollback = rollback || now < previous
                            // Checked increment: overflow leaves the exhausted state intact, never wraps.
                            guard let index = lastULIDTail.lastIndex(where: { $0 != 255 }) else {
                                throw IdentifierIssue(.sequenceExhausted, "ULID sequence exhausted. Try again after the clock advances.")
                            }
                            lastULIDTail[index] += 1
                            if index < 9 { for i in (index + 1)..<10 { lastULIDTail[i] = 0 } }
                        } else {
                            let tail = try stream.read(10)
                            lastULIDTail = tail; lastULIDTime = now
                        }
                        values.append(Self.ulid(timestamp: lastULIDTime!, tail: lastULIDTail))
                    } else { values.append(Self.ulid(timestamp: now, tail: try stream.read(10))) }
                case .nanoID:
                    var value = [UInt8](); value.reserveCapacity(options.nanoLength)
                    while value.count < options.nanoLength {
                        let byte = try stream.next()
                        if let index = Self.nanoIndex(byte, alphabetCount: symbols.count) { value.append(symbols[index]) }
                    }
                    values.append(String(decoding: value, as: UTF8.self))
                }
            }
            try Task.checkCancellation()
            let duplicates = values.count - Set(values).count
            try Task.checkCancellation()
            var notes = [String]()
            if rollback { notes.append(options.kind == .ulid ? "Clock moved backwards; last timestamp retained." : "Clock moved backwards; IDs use the observed timestamp.") }
            if duplicates > 0 { notes.append("\(duplicates) duplicate occurrence\(duplicates == 1 ? "" : "s") in this batch. Values have not been changed.") }
            return .init(batch: .init(options: options, values: values, notes: notes, duplicateCount: duplicates, createdAt: Date()))
        } catch is CancellationError { return .init(issue: .init(.cancelled, "Cancelled")) }
        catch let issue as IdentifierIssue { return .init(issue: issue) }
        catch { return .init(issue: .init(.entropyUnavailable, "Secure randomness is unavailable. Try again.")) }
    }
}
private struct RandomStream {
    let provider: IdentifierGenerator.RandomBytes
    let budget: Int
    private var buffer = [UInt8]()
    private var position = 0
    private var consumed = 0
    init(provider: @escaping IdentifierGenerator.RandomBytes, budget: Int) { self.provider = provider; self.budget = budget }
    mutating func next() throws -> UInt8 {
        if consumed % 256 == 0 { try Task.checkCancellation() }
        guard consumed < budget else { throw IdentifierIssue(.resourceLimit, "Random sampling budget reached. Try again.") }
        if position == buffer.count {
            let count = min(4096, budget - consumed)
            buffer = try provider(count); position = 0
            guard buffer.count == count else { throw IdentifierIssue(.entropyUnavailable, "Secure randomness returned an incomplete buffer.") }
        }
        consumed += 1; defer { position += 1 }; return buffer[position]
    }
    mutating func read(_ count: Int) throws -> [UInt8] { try (0..<count).map { _ in try next() } }
}

enum IdentifierSerialization {
    static func text(_ batch: IdentifierBatch, format: IdentifierCopyFormat, limit: Int = IdentifierBudget.outputBytes) throws -> String {
        // Build only the requested representation; bounded, cancellable, not on MainActor.
        var bytes = [UInt8](); bytes.reserveCapacity(min(limit, batch.values.count * 40))
        func append(_ byte: UInt8) throws {
            guard bytes.count < limit else { throw IdentifierIssue(.resourceLimit, "Copy output limit reached.") }; bytes.append(byte)
        }
        if format == .json { try append(91); try append(10) }
        for (index, value) in batch.values.enumerated() {
            try Task.checkCancellation()
            if index > 0 { if format == .json { try append(44) }; try append(10) }
            if format == .json { try append(32); try append(32); try append(34) }
            for byte in value.utf8 {
                if format == .json && (byte == 34 || byte == 92) { try append(92) }
                try append(byte)
            }
            if format == .json { try append(34) }
        }
        if format == .json { try append(10); try append(93) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
