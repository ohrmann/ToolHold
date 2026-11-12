import Foundation

/// Operation-local buffered system entropy. Rejection avoids modulo bias for any supported alphabet.
struct UniformRandomSampler {
    typealias Provider = @Sendable (Int) throws -> [UInt8]
    private let provider: Provider
    private let limits: SecretGenerationLimits
    private let deadline: ContinuousClock.Instant
    private var buffer: [UInt8] = []
    private var position = 0
    private(set) var consumed = 0
    init(limits: SecretGenerationLimits = .init(), random: @escaping Provider = { try SecureRandomBytes.read($0) }) {
        self.limits = limits; provider = random
        deadline = ContinuousClock.now.advanced(by: .seconds(max(0, limits.seconds)))
    }
    func check() throws {
        guard !Task.isCancelled else { throw SecretIssue(.cancelled, "Cancelled") }
        guard ContinuousClock.now < deadline else { throw SecretIssue(.resourceLimit, "Generation time limit reached. Adjust the character policy or reduce the count.") }
    }
    mutating func index(_ count: Int) throws -> Int {
        guard count > 0, UInt64(count) <= UInt64(UInt32.max) else { throw SecretIssue(.invalidOptions, "Invalid alphabet size.") }
        let space: UInt64 = 1 << 32, limit = space - space % UInt64(count)
        while true {
            let x = UInt64(try word())
            if x < limit { return Int(x % UInt64(count)) }
        }
    }
    private mutating func word() throws -> UInt32 {
        if consumed % 256 == 0 { try check() }
        guard consumed <= limits.randomBytes - 4 else { throw SecretIssue(.resourceLimit, "Randomness consumption limit reached. Adjust the character policy or reduce the count.") }
        if position + 4 > buffer.count {
            try check()
            let size = min(4096, limits.randomBytes - consumed)
            do { buffer = try provider(size) }
            catch let error as SecretIssue { throw error }
            catch is CancellationError { throw SecretIssue(.cancelled, "Cancelled") }
            catch { throw SecretIssue(.entropyUnavailable, "Secure randomness is unavailable. Try again.") }
            guard buffer.count == size else { throw SecretIssue(.entropyUnavailable, "Secure randomness returned an incomplete buffer.") }
            position = 0
        }
        let x = buffer[position..<position + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        position += 4; consumed += 4
        return x
    }
}
