import Foundation
import Testing
@testable import GeneratorCore

private final class ScriptedBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var offset = 0
    private let bytes: [UInt8]
    private let failAfter: Int?
    init(_ bytes: [UInt8], failAfter: Int? = nil) { self.bytes = bytes; self.failAfter = failAfter }
    func read(_ count: Int) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        if let failAfter, offset >= failAfter { throw IdentifierIssue(.entropyUnavailable, "Test entropy failure") }
        let result = (0..<count).map { bytes[(offset + $0) % bytes.count] }; offset += count; return result
    }
}
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var values: [Double]
    init(_ values: [Double]) { self.values = values }
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return values.count > 1 ? values.removeFirst() : values[0] }
}
struct IdentifierGeneratorTests {
    private func hex(_ text: String) -> [UInt8] { stride(from: 0, to: text.count, by: 2).map { let a = text.index(text.startIndex, offsetBy: $0); return UInt8(text[a..<text.index(a, offsetBy: 2)], radix: 16)! } }
    @Test func uuidRFCVectorsAndMasks() throws {
        let bytes = hex("919108F752D133205BACF847DB4148A8")
        let value = IdentifierGenerator.uuid(bytes, version: 4, letterCase: .lowercase)
        #expect(value == "919108f7-52d1-4320-9bac-f847db4148a8")
        let parsed = try #require(UUID(uuidString: value))
        #expect(parsed.uuidString == value.uppercased())
        let parsedBytes = withUnsafeBytes(of: parsed.uuid) { Array($0) }
        #expect(parsedBytes[6] == 0x43 && parsedBytes[8] == 0x9b)
        #expect(IdentifierGenerator.uuid(Array(repeating: 0, count: 16), version: 4, letterCase: .lowercase) == "00000000-0000-4000-8000-000000000000")
        #expect(IdentifierGenerator.uuid(Array(repeating: 255, count: 16), version: 4, letterCase: .uppercase) == "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")
        #expect(IdentifierGenerator.uuid(hex("0000000000000CC318C4DC0C0C07398F"), version: 7, timestamp: 1645557742000, letterCase: .uppercase) == "017F22E2-79B0-7CC3-98C4-DC0C0C07398F")
    }
    @Test func timestampBoundsAndV7Endianness() throws {
        #expect(try IdentifierGenerator.timestamp(0) == 0)
        #expect(try IdentifierGenerator.timestamp(1645557742) == 1645557742000)
        #expect(try IdentifierGenerator.timestamp(Double(IdentifierBudget.maxTimestamp) / 1000) == IdentifierBudget.maxTimestamp)
        for seconds in [-1.0, -.leastNonzeroMagnitude, .infinity, -.infinity, .nan, Double(IdentifierBudget.maxTimestamp + 1) / 1000] {
            #expect(throws: IdentifierIssue.self) { try IdentifierGenerator.timestamp(seconds) }
        }
        #expect(IdentifierGenerator.uuid(Array(repeating: 0, count: 16), version: 7, timestamp: IdentifierBudget.maxTimestamp, letterCase: .lowercase) == "ffffffff-ffff-7000-8000-000000000000")
    }
    @Test func v7RetainsRandomnessAndActualRollbackTime() async throws {
        let clock = TestClock([2, 2, 1]), bytes = ScriptedBytes(Array(0...255))
        let engine = IdentifierGenerator(random: bytes.read, clock: clock.read)
        let result = await engine.generate(.init(kind: .uuidV7, count: 3))
        let batch = try #require(result.batch)
        #expect(batch.values[0].hasPrefix("00000000-07d0-7"))
        #expect(batch.values[1] != batch.values[0])
        #expect(batch.values[2].hasPrefix("00000000-03e8-7"))
        #expect(batch.notes.contains { $0.contains("observed timestamp") })
        let invalid = await IdentifierGenerator(clock: { -1 }).generate(.init(kind: .uuidV7))
        #expect(invalid.status == .clockUnavailable && invalid.batch == nil)
    }
    @Test func ulidBoundaryVectorsAndIndependentTimestampDecode() throws {
        #expect(IdentifierGenerator.ulid(timestamp: 0, tail: Array(repeating: 0, count: 10)) == String(repeating: "0", count: 26))
        #expect(IdentifierGenerator.ulid(timestamp: IdentifierBudget.maxTimestamp, tail: Array(repeating: 255, count: 10)) == "7" + String(repeating: "Z", count: 25))
        let value = IdentifierGenerator.ulid(timestamp: 1469918176385, tail: Array(repeating: 0, count: 10))
        #expect(value == "01ARYZ6S41" + String(repeating: "0", count: 16))
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let time = value.prefix(10).reduce(UInt64(0)) { $0 * 32 + UInt64(alphabet.firstIndex(of: $1)!) }
        #expect(time == 1469918176385)
    }
    @Test func ulidMonotonicCarryBatchesRollbackAndFreshTime() async throws {
        let bytes = ScriptedBytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 255]), clock = TestClock([2, 2, 1, 3])
        let engine = IdentifierGenerator(random: bytes.read, clock: clock.read)
        let a = try #require(await engine.generate(.init(kind: .ulid, count: 2)).batch)
        let b = try #require(await engine.generate(.init(kind: .ulid)).batch)
        #expect(a.values[0] < a.values[1] && a.values[1] < b.values[0])
        #expect(a.values[0].hasSuffix("7Z") && a.values[1].hasSuffix("80"))
        #expect(b.notes.contains { $0.contains("last timestamp retained") })
        let c = try #require(await engine.generate(.init(kind: .ulid)).batch)
        #expect(c.values[0] > b.values[0])
    }
    @Test func ulidOverflowNeverWrapsAndCanResumeOnNewTime() async throws {
        let clock = TestClock([1, 1, 1, 2])
        let engine = IdentifierGenerator(random: { Array(repeating: 255, count: $0) }, clock: clock.read)
        #expect(await engine.generate(.init(kind: .ulid)).status == .success)
        let failed = await engine.generate(.init(kind: .ulid))
        #expect(failed.status == .sequenceExhausted && failed.batch == nil)
        #expect(await engine.generate(.init(kind: .ulid)).status == .sequenceExhausted)
        #expect(await engine.generate(.init(kind: .ulid)).status == .success)
    }
    @Test func ulidRandomModeAndToggleDoNotResetMonotonicSequence() async throws {
        let engine = IdentifierGenerator(random: { Array(repeating: 0, count: $0) }, clock: { 1 })
        let a = try #require(await engine.generate(.init(kind: .ulid)).batch)
        let random = try #require(await engine.generate(.init(kind: .ulid, count: 2, ulidMonotonic: false)).batch)
        #expect(random.values[0] == random.values[1] && random.duplicateCount == 1)
        let b = try #require(await engine.generate(.init(kind: .ulid)).batch)
        #expect(b.values[0] > a.values[0])
        let fresh = try #require(await IdentifierGenerator(random: { Array(repeating: 0, count: $0) }, clock: { 1 }).generate(.init(kind: .ulid)).batch)
        #expect(fresh.values == a.values)
    }
    @Test func samplingIsUnbiasedAcrossEntireByteDomain() {
        for size in [2, 3, 10, 16, 62, 64, 65, 94] {
            let accepted = (0...255).compactMap { IdentifierGenerator.nanoIndex(UInt8($0), alphabetCount: size) }
            let expected = 256 / size
            #expect(accepted.count == expected * size)
            for i in 0..<size { #expect(accepted.filter { $0 == i }.count == expected) }
        }
    }
    @Test func nanoPresetsBoundsAndDuplicateAccounting() async throws {
        for alphabet in IdentifierAlphabet.allCases where alphabet != .custom {
            for length in [1, 21, 256] {
                let batch = try #require(await IdentifierGenerator().generate(.init(kind: .nanoID, count: 2, nanoLength: length, alphabet: alphabet)).batch)
                #expect(batch.values.allSatisfy { $0.utf8.count == length && Set($0.utf8).isSubset(of: Set(alphabet.symbols.utf8)) })
            }
        }
        let duplicates = try #require(await IdentifierGenerator(random: { Array(repeating: 0, count: $0) }).generate(.init(kind: .nanoID, count: 3, nanoLength: 1, alphabet: .numeric)).batch)
        #expect(duplicates.values == ["0", "0", "0"] && duplicates.duplicateCount == 2)
        #expect(duplicates.notes.count == 1)
        for custom in ["", "a", "aa", " ab", "a\tb", "a\nb", "a😀", "aé", "ae\u{301}", String(repeating: "x", count: 100_000)] {
            #expect(IdentifierOptions(kind: .nanoID, alphabet: .custom, customAlphabet: custom).issue != nil)
        }
        for length in [0, 257, Int.max] { #expect(IdentifierOptions(kind: .nanoID, nanoLength: length).issue != nil) }
        for count in [0, -1, 10_001, Int.max] { #expect(await IdentifierGenerator().generate(.init(count: count)).status == .invalidOptions) }
    }
    @Test func nanoRejectionRefillBudgetAndIncompleteProvider() async throws {
        let bytes = ScriptedBytes([255, 0, 1, 2])
        let batch = try #require(await IdentifierGenerator(random: bytes.read).generate(.init(kind: .nanoID, nanoLength: 3, alphabet: .custom, customAlphabet: "abc")).batch)
        #expect(batch.values == ["abc"])
        let exhausted = await IdentifierGenerator(random: { Array(repeating: 255, count: $0) }).generate(.init(kind: .nanoID, alphabet: .custom, customAlphabet: "abc"))
        #expect(exhausted.status == .resourceLimit && exhausted.batch == nil)
        let incomplete = await IdentifierGenerator(random: { _ in [] }).generate(.init())
        #expect(incomplete.status == .entropyUnavailable && incomplete.batch == nil)
    }
    @Test func entropyFailureAfterPartialWorkPublishesNothing() async {
        let bytes = ScriptedBytes([0], failAfter: 4096)
        let result = await IdentifierGenerator(random: bytes.read).generate(.init(count: 300))
        #expect(result.status == .entropyUnavailable && result.batch == nil)
    }
    @Test func failureConsumesULIDStateAndCancellationIsSeparate() async throws {
        // A sequence overflow discards the partial batch but never rolls back the value it consumed.
        let tail = [UInt8](repeating: 255, count: 9) + [254]
        let engine = IdentifierGenerator(random: ScriptedBytes(tail).read, clock: { 1 })
        let failed = await engine.generate(.init(kind: .ulid, count: 3))
        #expect(failed.status == .sequenceExhausted && failed.batch == nil)
        #expect(await engine.generate(.init(kind: .ulid)).status == .sequenceExhausted)
        let task = Task { () -> IdentifierResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return await IdentifierGenerator().generate(.init(count: 10_000))
        }
        #expect(await task.value.status == .cancelled)
    }
    @Test func cancellationAfterIssuedULIDsDoesNotRollbackSequence() async throws {
        final class Clock: @unchecked Sendable {
            let lock = NSLock(); var calls = 0
            func read() -> Double {
                lock.lock(); calls += 1; let cancel = calls == 2; lock.unlock()
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
                return 1
            }
        }
        let clock = Clock(), engine = IdentifierGenerator(random: { Array(repeating: 0, count: $0) }, clock: clock.read)
        let task = Task { await engine.generate(.init(kind: .ulid, count: 3)) }
        let cancelled = await task.value
        #expect(cancelled.status == .cancelled && cancelled.batch == nil)
        let next = try #require(await engine.generate(.init(kind: .ulid)).batch)
        #expect(next.values[0].hasSuffix("0002"))
    }
    @Test func exactCopyFormsAndOutputBudget() throws {
        let batch = IdentifierBatch(options: .init(kind: .nanoID), values: ["a\"b", "c\\d", "123"], notes: [], duplicateCount: 0, createdAt: .now)
        #expect(try IdentifierSerialization.text(batch, format: .lines) == "a\"b\nc\\d\n123")
        let json = try IdentifierSerialization.text(batch, format: .json)
        #expect(json == "[\n  \"a\\\"b\",\n  \"c\\\\d\",\n  \"123\"\n]")
        #expect(try JSONDecoder().decode([String].self, from: Data(json.utf8)) == batch.values)
        #expect(throws: IdentifierIssue.self) { try IdentifierSerialization.text(batch, format: .json, limit: 8) }
        let worst = IdentifierBatch(options: .init(kind: .nanoID, count: 10_000, nanoLength: 256), values: Array(repeating: String(repeating: "\\", count: 256), count: 10_000), notes: [], duplicateCount: 9999, createdAt: .now)
        let output = try IdentifierSerialization.text(worst, format: .json)
        #expect(output.utf8.count == 5_180_002 && output.utf8.count < IdentifierBudget.outputBytes)
    }
    @Test func systemProviderAndMaximumBatches() async throws {
        #expect(try SecureRandomBytes.read(1).count == 1)
        #expect(try SecureRandomBytes.read(4096).count == 4096)
        #expect(throws: IdentifierIssue.self) { try SecureRandomBytes.read(4097) }
        for kind in IdentifierKind.allCases {
            let batch = try #require(await IdentifierGenerator().generate(.init(kind: kind, count: 10_000, nanoLength: 256)).batch)
            #expect(batch.values.count == 10_000)
            #expect(batch.options.kind == kind)
        }
    }
}
