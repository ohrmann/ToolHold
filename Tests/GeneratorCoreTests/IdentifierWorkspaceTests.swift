import Foundation
import Testing
@testable import GeneratorCore

private actor DelayedIdentifierWorker {
    private var pending: [Int: CheckedContinuation<IdentifierResult, Never>] = [:]
    func run(_ options: IdentifierOptions) async -> IdentifierResult { await withCheckedContinuation { pending[options.count] = $0 } }
    func wait(_ count: Int) async { while pending[count] == nil { await Task.yield() } }
    func finish(_ count: Int) { pending.removeValue(forKey: count)?.resume(returning: .init(batch: .init(options: .init(count: count), values: Array(repeating: "fixture", count: count), notes: [], duplicateCount: max(0, count - 1), createdAt: .now))) }
}
@MainActor struct IdentifierWorkspaceTests {
    private func repository() -> IdentifierPreferencesRepository { .init(defaults: UserDefaults(suiteName: "T022-\(UUID())")!) }
    @Test func previousBatchSurvivesOptionsCancelAndFailure() async throws {
        let session = IdentifierWorkspaceSession(repository: repository())
        await session.run()?.value
        let first = try #require(session.batch?.id)
        session.countText = "2"
        #expect(session.batch?.id == first && session.settingsDiffer && session.canCopy)
        session.countText = "1"
        #expect(!session.settingsDiffer)
        session.preferences.kind = .nanoID; session.preferences.nanoAlphabetPreset = .custom; session.customAlphabet = "aa"
        #expect(!session.canGenerate && session.batch?.id == first && session.canCopy)
        session.selection = 0; #expect(session.selectedValue == session.batch?.values[0])
        session.clear()
        #expect(session.batch == nil && session.customAlphabet.isEmpty && session.selection == nil && session.rows.isEmpty)
        #expect(session.preferences.nanoAlphabetPreset == .urlSafe && !session.canCopy)
    }
    @Test func staleGenerationNeverOverwritesNewBatch() async {
        let worker = DelayedIdentifierWorker()
        let session = IdentifierWorkspaceSession(repository: repository(), worker: { _, options in await worker.run(options) })
        let a = session.run(); await worker.wait(1)
        session.countText = "2"
        let b = session.run(); await worker.wait(2)
        await worker.finish(2); await b?.value
        #expect(session.batch?.values.count == 2)
        await worker.finish(1); await a?.value
        #expect(session.batch?.values.count == 2 && !session.busy)
    }
    @Test func cancelAndClearIgnoreWorkersThatIgnoreCancellation() async {
        let worker = DelayedIdentifierWorker()
        let session = IdentifierWorkspaceSession(repository: repository(), worker: { _, options in await worker.run(options) })
        let a = session.run(); await worker.wait(1); session.cancel()
        #expect(session.statusText == "Cancelled")
        await worker.finish(1); await a?.value
        #expect(session.batch == nil && session.statusText == "Cancelled")
        let b = session.run(); await worker.wait(1); session.clear()
        await worker.finish(1); await b?.value
        #expect(session.batch == nil && session.statusText == "Ready")
    }
    @Test func oldBatchPreservedWhileGeneratingThenCancelled() async throws {
        let worker = DelayedIdentifierWorker()
        let session = IdentifierWorkspaceSession(repository: repository(), worker: { _, options in await worker.run(options) })
        let a = session.run(); await worker.wait(1); await worker.finish(1); await a?.value
        let first = try #require(session.batch?.id)
        session.countText = "2"; let b = session.run(); await worker.wait(2)
        #expect(session.batch?.id == first && !session.canCopy && session.statusText.contains("Previous batch"))
        session.cancel(); await worker.finish(2); await b?.value
        #expect(session.batch?.id == first && session.canCopy)
    }
    @Test func entropyFailureDoesNotDestroyPreviousBatch() async throws {
        let session = IdentifierWorkspaceSession(repository: repository(), worker: { engine, options in
            if options.count == 2 { return .init(issue: .init(.entropyUnavailable, "Unavailable")) }
            return await engine.generate(options)
        })
        await session.run()?.value; let id = try #require(session.batch?.id)
        session.countText = "2"; await session.run()?.value
        #expect(session.batch?.id == id && session.canCopy && session.issue?.status == .entropyUnavailable)
    }
    @Test func staleCopyCannotWriteClipboardAfterClearOrOptionChange() async {
        actor Gate {
            var continuation: CheckedContinuation<String, Never>?
            func serialize() async -> String { await withCheckedContinuation { continuation = $0 } }
            func wait() async { while continuation == nil { await Task.yield() } }
            func finish() { continuation?.resume(returning: "synthetic"); continuation = nil }
        }
        let gate = Gate()
        let session = IdentifierWorkspaceSession(repository: repository(), serializer: { _, _ in await gate.serialize() })
        await session.run()?.value
        var published = [String]()
        let a = session.copyAll(.lines) { published.append($0) }; await gate.wait()
        session.countText = "2"; await gate.finish(); await a?.value
        #expect(published.isEmpty)
        let b = session.copyAll(.json) { published.append($0) }; await gate.wait()
        session.clear(); await gate.finish(); await b?.value
        #expect(published.isEmpty && !session.copying)
    }
    @Test func copyRowsAndULIDSequenceAcrossBatchesAndClear() async throws {
        let session = IdentifierWorkspaceSession(repository: repository(), makeEngine: { IdentifierGenerator(random: { Array(repeating: 0, count: $0) }, clock: { 1 }) })
        session.preferences.kind = .ulid
        await session.run()?.value; let first = try #require(session.copyValue(at: 0))
        await session.run()?.value; #expect(try #require(session.copyValue(at: 0)) > first)
        var output: String?
        await session.copyAll(.json) { output = $0 }?.value
        #expect(try JSONDecoder().decode([String].self, from: Data(try #require(output).utf8)) == session.batch?.values)
        session.clear(); await session.run()?.value
        #expect(session.copyValue(at: 0) == first)
    }
    @Test func transientNumericDraftsDoNotGenerateOrChangeSavedDefaults() {
        let session = IdentifierWorkspaceSession(repository: repository())
        for text in ["", "-1", "+1", " 1", "1.0", "😀", "10001", "999999999999999999"] {
            session.countText = text; #expect(!session.canGenerate && session.run() == nil)
        }
        #expect(session.preferences.count == 1)
        session.countText = "000010"; #expect(session.canGenerate && session.options.count == 10)
        session.preferences.kind = .nanoID; session.lengthText = "257"; #expect(!session.canGenerate)
        session.preferences.kind = .uuidV4; #expect(session.canGenerate)
    }
}
