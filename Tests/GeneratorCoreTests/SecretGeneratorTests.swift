import Foundation
import Testing
@testable import GeneratorCore

final class SecretScript: @unchecked Sendable {
    private let lock = NSLock()
    private var position = 0
    private let bytes: [UInt8]
    init(_ words: [UInt32]) { bytes = words.flatMap { word in [UInt8(truncatingIfNeeded: word >> 24), UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)] } }
    func read(_ count: Int) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        let value = (0..<count).map { bytes[(position + $0) % bytes.count] }; position += count; return value
    }
}
struct SecretGeneratorTests {
    @Test func approvedDefaultIsThirteen() throws {
        let o = PasswordOptions()
        #expect(o.length == 13 && o.count == 1 && o.requireEveryGroup)
        #expect(try o.groups().map(\.count) == [26, 26, 10, 32])
        let result = try #require(SecretGenerator.generate(.password(o)).batch)
        #expect(result.values[0].utf8.count == 13)
        let groups = try o.groups()
        for group in groups { #expect(result.values[0].utf8.contains { group.contains($0) }) }
    }
    @Test func samplerBoundaryRejectionAndEndianness() throws {
        for n in [2, 10, 94, 7776] {
            let space: UInt64 = 1 << 32, limit = space - space % UInt64(n)
            var sequence = [UInt32(limit - 1)]
            if limit < space { sequence += [UInt32(limit), .max] }
            sequence += [0, 1]
            let script = SecretScript(sequence)
            var sampler = UniformRandomSampler(random: script.read)
            #expect(try sampler.index(n) == n - 1)
            #expect(try sampler.index(n) == 0)
            #expect(try sampler.index(n) == 1)
        }
    }
    @Test func toyRejectionHasEqualAcceptedCounts() {
        for n in [3, 7, 94] {
            let limit = 256 - 256 % n
            let counts = (0..<limit).reduce(into: [Int](repeating: 0, count: n)) { $0[$1 % n] += 1 }
            #expect(Set(counts).count == 1)
        }
    }
    @Test func samplerFailureShortBufferAndBoundedRejection() throws {
        let failed = SecretGenerator.generate(.password(.init()), random: { _ in throw IdentifierIssue(.entropyUnavailable, "synthetic") })
        #expect(failed.status == .entropyUnavailable && failed.batch == nil)
        #expect(!failed.issue!.message.contains("synthetic"))
        let short = SecretGenerator.generate(.password(.init()), random: { _ in [0] })
        #expect(short.status == .entropyUnavailable && short.batch == nil)
        let script = SecretScript([.max])
        var sampler = UniformRandomSampler(limits: .init(randomBytes: 16), random: script.read)
        #expect(throws: SecretIssue.self) { try sampler.index(94) }
        #expect(sampler.consumed == 16)
    }
    @Test func invalidOptionsDoNotReadEntropy() {
        for o in [PasswordOptions(length: 7), .init(length: 129), .init(count: 0), .init(count: 1001),
                  .init(lowercase: false, uppercase: false, digits: false, symbols: false),
                  .init(mode: .custom, customAlphabet: "aa"), .init(mode: .custom, customAlphabet: "a b"),
                  .init(mode: .custom, customAlphabet: "a😀"), .init(exclusions: "\t"), .init(exclusions: String(repeating: "x", count: 257))] {
            let result = SecretGenerator.generate(.password(o), random: { _ in Issue.record("Invalid options reached RNG"); return [] })
            #expect(result.status == .invalidOptions && result.batch == nil)
        }
    }
    @Test func excludesExactSimilarCharactersAndDoesNotSilentlyDropGroup() throws {
        let o = PasswordOptions(excludeSimilar: true, exclusions: "aa~")
        let alphabet = try o.groups().flatMap { $0 }
        for byte in (PasswordOptions.similar + "a~").utf8 { #expect(!alphabet.contains(byte)) }
        #expect(o.exclusions == "aa~")
        var empty = PasswordOptions(exclusions: "0123456789")
        #expect(SecretGeneratorRequest.password(empty).issue?.message.contains("Digits") == true)
        empty.requireEveryGroup = false
        #expect(try empty.groups().count == 3)
    }
    @Test func wholeCandidateRejectionPreservesDistribution() throws {
        let script = SecretScript(Array(repeating: 0, count: 8) + [0, 26, 0, 26, 0, 26, 0, 26])
        let o = PasswordOptions(length: 8, uppercase: false, symbols: false)
        let batch = try #require(SecretGenerator.generate(.password(o), random: script.read).batch)
        #expect(batch.values == ["a0a0a0a0"])
        let rejected = SecretGenerator.generate(.password(o), limits: .init(candidatesPerPassword: 2), random: SecretScript([0]).read)
        #expect(rejected.status == .resourceLimit && rejected.batch == nil)
    }
    @Test func customExactAlphabetAndRepeatSemantics() throws {
        let o = PasswordOptions(length: 8, count: 3, mode: .custom, customAlphabet: "ab")
        let batch = try #require(SecretGenerator.generate(.password(o), random: SecretScript([0]).read).batch)
        #expect(batch.values == Array(repeating: "aaaaaaaa", count: 3))
        #expect(batch.duplicateCount == 2 && batch.entropyBits == 8)
        #expect(batch.options == .password(o.effective))
    }
    @Test func alphabetGroupsAndBoundaries() throws {
        for i in 0..<4 {
            let o = PasswordOptions(length: 128, count: 20, lowercase: i == 0, uppercase: i == 1, digits: i == 2, symbols: i == 3)
            let group = try #require(o.groups().first)
            let batch = try #require(SecretGenerator.generate(.password(o)).batch)
            #expect(batch.values.count == 20)
            for value in batch.values { #expect(value.utf8.count == 128 && value.utf8.allSatisfy { group.contains($0) }) }
        }
    }
    @Test func entropyDPMatchesIndependentExhaustiveEnumeration() throws {
        for length in 2...6 {
            var allowed = 0
            for number in 0..<Int(pow(3.0, Double(length))) {
                var value = number, a = false, b = false
                for _ in 0..<length { let digit = value % 3; a = a || digit < 2; b = b || digit == 2; value /= 3 }
                if a && b { allowed += 1 }
            }
            let actual = try GeneratorEntropy.password(length: length, groupSizes: [2, 1], requireEveryGroup: true)
            #expect(abs(actual - log2(Double(allowed))) < 1e-10)
        }
        #expect(try GeneratorEntropy.password(length: 13, groupSizes: [94], requireEveryGroup: false) == 13 * log2(94.0))
        #expect(throws: SecretIssue.self) { try GeneratorEntropy.password(length: 2, groupSizes: [1, 1, 1], requireEveryGroup: true) }
    }
    @Test func pinnedWordlistHasAllEntriesAndFailsClosed() throws {
        let list = try PassphraseWordlist.bundled()
        #expect(list.words.count == 7776 && Set(list.words).count == 7776)
        #expect(list.words.first == "abacus" && list.words.last == "zoom")
        #expect(Set(list.words.map { $0.prefix(1).uppercased() + $0.dropFirst() }).count == 7776)
        #expect(list.words.filter { $0.contains("-") }.count == 4)
        #expect(throws: SecretIssue.self) { try PassphraseWordlist(data: Data("bad resource".utf8)) }
        let failed = SecretGenerator.generate(.passphrase(.init()), dictionary: { throw PassphraseWordlist.unavailable })
        #expect(failed.status == .dictionaryUnavailable && failed.batch == nil)
    }
    @Test func phraseWordIndicesRepeatsAndPresentation() throws {
        let list = try PassphraseWordlist.bundled()
        for separator in PassphraseSeparator.allCases {
            for letterCase in PassphraseCase.allCases {
                let options = PassphraseOptions(wordCount: 4, separator: separator, letterCase: letterCase, appendDigit: true)
                let batch = try #require(SecretGenerator.generate(.passphrase(options), random: SecretScript([0, 7775, 0, 7775, 9]).read).batch)
                let words = letterCase == .lowercase ? ["abacus", "zoom", "abacus", "zoom", "9"] : ["Abacus", "Zoom", "Abacus", "Zoom", "9"]
                #expect(batch.values == [words.joined(separator: separator.text)])
                #expect(abs(batch.entropyBits - (4 * log2(7776.0) + log2(10.0))) < 1e-10)
                #expect(batch.dictionaryVersion == list.version)
            }
        }
        let noDigit = try #require(SecretGenerator.generate(.passphrase(.init()), random: SecretScript([0]).read).batch)
        #expect(noDigit.values[0] == Array(repeating: "abacus", count: 6).joined(separator: "-"))
        #expect(abs(noDigit.entropyBits - 6 * log2(7776.0)) < 1e-10)
    }
    @Test func internalHyphensKeepEveryWordAndUnambiguousBoundaries() throws {
        let list = try PassphraseWordlist.bundled()
        let words = ["drop-down", "felt-tip", "t-shirt", "yo-yo"]
        let indices = words.map { UInt32(list.words.firstIndex(of: $0)!) }
        let batch = try #require(SecretGenerator.generate(.passphrase(.init(wordCount: 4)), random: SecretScript(indices).read).batch)
        #expect(batch.values == ["drop--down-felt--tip-t--shirt-yo--yo"])
        let space = try #require(SecretGenerator.generate(.passphrase(.init(wordCount: 4, separator: .space)), random: SecretScript(indices).read).batch)
        #expect(space.values == [words.joined(separator: " ")])
    }
    @Test func phraseInvalidAndMaximumProfiles() throws {
        for options in [PassphraseOptions(wordCount: 3), .init(wordCount: 17), .init(count: 0), .init(count: 1001)] {
            #expect(SecretGenerator.generate(.passphrase(options)).status == .invalidOptions)
        }
        let batch = try #require(SecretGenerator.generate(.passphrase(.init(wordCount: 16, count: 1000, appendDigit: true)), random: SecretScript([0]).read).batch)
        #expect(batch.values.count == 1000 && batch.duplicateCount == 999)
        #expect(batch.values[0].components(separatedBy: "-").count == 17)
    }
    @Test func cancellationAndDeadlinePublishNoPartialBatch() async throws {
        let task = Task.detached { () -> SecretResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return SecretGenerator.generate(.password(.init(count: 1000)))
        }
        let result = await task.value
        #expect(result.status == .cancelled && result.batch == nil)
        let deadline = SecretGenerator.generate(.password(.init()), limits: .init(seconds: 0))
        #expect(deadline.status == .resourceLimit && deadline.batch == nil)
        let limited = SecretGenerator.generate(.password(.init(count: 1000)), limits: .init(randomBytes: 4096))
        #expect(limited.status == .resourceLimit && limited.batch == nil)
    }
    @Test func exactCopyAndSerializationLimits() throws {
        let values = ["a\\b\"c", "[value]", "word word"]
        let batch = SecretBatch(options: .password(.init()), values: values, entropyBits: 1, duplicateCount: 0, dictionaryVersion: nil)
        #expect(try SecretSerialization.text(batch, format: .lines) == values.joined(separator: "\n"))
        let json = try SecretSerialization.text(batch, format: .json)
        #expect(try JSONDecoder().decode([String].self, from: Data(json.utf8)) == values)
        let huge = SecretBatch(options: .password(.init()), values: [String(repeating: "a", count: 1_048_576)], entropyBits: 1, duplicateCount: 0, dictionaryVersion: nil)
        #expect(throws: SecretIssue.self) { try SecretSerialization.text(huge, format: .json) }
    }
}
