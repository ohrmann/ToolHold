import Foundation

enum SecretGenerator {
    /// Synchronous pure worker entry point; the workspace always calls it outside MainActor.
    static func generate(_ request: SecretGeneratorRequest, limits: SecretGenerationLimits = .init(),
                         random: @escaping UniformRandomSampler.Provider = { try SecureRandomBytes.read($0) },
                         dictionary: @Sendable () throws -> PassphraseWordlist = { try PassphraseWordlist.bundled() }) -> SecretResult {
        do {
            if let issue = request.issue { throw issue }
            let request = request.effective
            var sampler = UniformRandomSampler(limits: limits, random: random)
            try sampler.check()
            let values: [String], entropy: Double, version: String?
            switch request {
            case .password(let options):
                let groups = try options.groups()
                entropy = try GeneratorEntropy.password(length: options.length, groupSizes: groups.map(\.count), requireEveryGroup: options.mode == .standard && options.requireEveryGroup)
                values = try passwords(options, groups: groups, sampler: &sampler, attempts: limits.candidatesPerPassword)
                version = nil
            case .passphrase(let options):
                let list = try dictionary()
                try sampler.check()
                entropy = GeneratorEntropy.passphrase(words: options.wordCount, dictionarySize: list.words.count, appendDigit: options.appendDigit)
                values = try phrases(options, words: list.words, sampler: &sampler)
                version = list.version
            }
            try sampler.check()
            let duplicates = values.count - Set(values).count
            return .init(batch: .init(options: request, values: values, entropyBits: entropy, duplicateCount: duplicates, dictionaryVersion: version))
        } catch let issue as SecretIssue { return .init(issue: issue) }
        catch is CancellationError { return .init(issue: .init(.cancelled, "Cancelled")) }
        catch { return .init(issue: .init(.entropyUnavailable, "Secure generation is unavailable. Try again.")) }
    }
    private static func passwords(_ options: PasswordOptions, groups: [[UInt8]], sampler: inout UniformRandomSampler, attempts: Int) throws -> [String] {
        let alphabet = groups.flatMap { $0 }
        var masks = [UInt8](repeating: 0, count: 128)
        for (index, bytes) in groups.enumerated() { for byte in bytes { masks[Int(byte)] = 1 << index } }
        let required: UInt8 = options.mode == .standard && options.requireEveryGroup ? UInt8((1 << groups.count) - 1) : 0
        var values = [String](); values.reserveCapacity(options.count)
        for _ in 0..<options.count {
            try sampler.check()
            var accepted: String?
            for _ in 0..<max(0, attempts) {
                var bytes = [UInt8](); bytes.reserveCapacity(options.length)
                var found: UInt8 = 0
                for _ in 0..<options.length {
                    let byte = alphabet[try sampler.index(alphabet.count)]
                    bytes.append(byte); found |= masks[Int(byte)]
                }
                if found & required == required { accepted = String(decoding: bytes, as: UTF8.self); break }
            }
            guard let accepted else { throw SecretIssue(.resourceLimit, "Character policy retry limit reached. Adjust exclusions or disable required groups.") }
            values.append(accepted)
        }
        return values
    }
    private static func phrases(_ options: PassphraseOptions, words: [String], sampler: inout UniformRandomSampler) throws -> [String] {
        var values = [String](); values.reserveCapacity(options.count)
        for _ in 0..<options.count {
            try sampler.check()
            var parts = [String](); parts.reserveCapacity(options.wordCount + 1)
            for _ in 0..<options.wordCount {
                let word = words[try sampler.index(words.count)]
                let rendered = options.letterCase == .lowercase ? word : word.prefix(1).uppercased() + word.dropFirst()
                parts.append(options.separator == .hyphen ? rendered.replacingOccurrences(of: "-", with: "--") : rendered)
            }
            if options.appendDigit { parts.append(String(try sampler.index(10))) }
            values.append(parts.joined(separator: options.separator.text))
        }
        return values
    }
}
enum SecretSerialization {
    static func text(_ batch: SecretBatch, format: SecretCopyFormat) throws -> String {
        var result = format == .json ? "[" : ""
        for (index, value) in batch.values.enumerated() {
            try Task.checkCancellation()
            if index > 0 { result += format == .json ? "," : "\n" }
            if format == .json {
                // The generator produces bounded ASCII. Foundation encodes only an array wrapper, never resamples values.
                let data = try JSONEncoder().encode([value])
                let encoded = String(decoding: data, as: UTF8.self)
                result += encoded.dropFirst().dropLast()
            } else { result += value }
            guard result.utf8.count + 1 <= SecretGenerationLimits.outputBytes else { throw SecretIssue(.resourceLimit, "Copy output limit reached.") }
        }
        if format == .json { result += "]" }
        return result
    }
}
