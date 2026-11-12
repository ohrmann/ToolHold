import Foundation
import Testing

@testable import TextCore

@Suite(.serialized) struct TextStressTests {
  @Test func maximumInputsAndCancellation() async throws {
    let clock = ContinuousClock()
    let lines = String(repeating: "x\n", count: 131072)
    var start = clock.now
    let diff = try TextDiffProcessor.process(lines, lines, options: .init())
    print(
      "TEXT_STRESS exact_diff units=262144 rows=131072 duration=\(start.duration(to:clock.now))")
    #expect(diff.diff?.changed.isEmpty == true)
    start = clock.now
    let sorted = try LineSortProcessor.process(lines, options: .init())
    print("TEXT_STRESS sort_dedupe units=262144 duration=\(start.duration(to:clock.now))")
    #expect(sorted.output == "x\n")
    start = clock.now
    let unicode = try TextUnicodeInspector.inspect(String(repeating: "a", count: 262144))
    print(
      "TEXT_STRESS unicode units=262144 rows=\(unicode.rows.count) duration=\(start.duration(to:clock.now))"
    )
    #expect(unicode.rows.count == 262144)
    let work = Task.detached { try LineSortProcessor.process(lines, options: .init()) }
    work.cancel()
    do {
      _ = try await work.value
      Issue.record("Cancelled sort published a result")
    } catch { #expect(error is CancellationError) }
  }
  @Test func generatorReferenceAndMaxDataset() throws {
    var rng = SampleRandom(state: 0)
    #expect(rng.next() == 0xe220_a839_7b1d_cdaf)
    #expect(rng.next() == 0x6e78_9e6a_a1b9_65f4)
    var o = MockOptions()
    o.count = 10000
    o.fields = [.init(name: "id", kind: .sequence)]
    o.seed = "123"
    let clock = ContinuousClock()
    let start = ContinuousClock.now
    let data = try MockDataProcessor.generate(o)
    #expect(data.rows.count == 10000)
    #expect(data.rows.last?.first?.text == "10000")
    #expect(try data.serialize(format: "CSV").hasSuffix("10000\r\n"))
    print("TEXT_STRESS mock rows=10000 fields=1 duration=\(start.duration(to:clock.now))")
  }
}
