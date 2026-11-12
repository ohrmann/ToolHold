import Foundation
import Testing
@testable import GeneratorCore

@MainActor struct SecretWorkspaceTests {
    private func repository(_ kind: SecretGeneratorKind = .password) -> SecretGeneratorPreferencesRepository {
        let defaults = UserDefaults(suiteName: "secret-test-\(UUID())")!
        return .init(kind: kind, defaults: defaults)
    }
    @Test func preferencesDefaultRecoveryAndExplicitAllowlist() throws {
        let defaults = SecretGeneratorPreferences()
        #expect(defaults.length == 13 && defaults.wordCount == 6 && defaults.separator == .hyphen)
        let recovered = try JSONDecoder().decode(SecretGeneratorPreferences.self, from: Data(#"{"length":900,"passwordCount":-1,"wordCount":0,"separator":"unknown","letterCase":"unknown","dictionaryID":"foreign","values":["must-not-restore"],"customAlphabet":"draft"}"#.utf8))
        #expect(recovered == defaults)
        let keys = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any])
        #expect(Set(keys.keys) == ["length", "passwordCount", "lowercase", "uppercase", "digits", "symbols", "requireEveryGroup", "excludeSimilar", "wordCount", "phraseCount", "separator", "letterCase", "appendDigit", "dictionaryID"])
    }
    @Test func persistenceNeverRestoresResultsOrCustomDraftsAndToolsAreIndependent() async throws {
        let repo = repository(), phraseRepo = SecretGeneratorPreferencesRepository(kind: .passphrase, defaults: repo.defaults)
        defer { repo.defaults.removeObject(forKey: repo.key); repo.defaults.removeObject(forKey: phraseRepo.key) }
        let session = SecretGeneratorWorkspaceSession(kind: .password, repository: repo)
        session.lengthText = "24"; session.countText = "2"; session.mode = .custom; session.customAlphabet = "ab"; session.exclusions = "c"
        await session.run()?.value
        #expect(session.batch?.values.count == 2)
        let fresh = SecretGeneratorWorkspaceSession(kind: .password, repository: repo)
        #expect(fresh.batch == nil && fresh.selection == nil && !fresh.hidden)
        #expect(fresh.lengthText == "24" && fresh.countText == "2" && fresh.mode == .standard)
        #expect(fresh.customAlphabet.isEmpty && fresh.exclusions.isEmpty)
        let phrase = SecretGeneratorWorkspaceSession(kind: .passphrase, repository: phraseRepo)
        #expect(phrase.countText == "1" && phrase.batch == nil)
        #expect(repo.key != phraseRepo.key)
    }
    @Test func settingsChangesKeepActualBatchEntropyAndCancelFailureKeepIt() async throws {
        let session = SecretGeneratorWorkspaceSession(kind: .password, repository: repository(), worker: { request in
            if request.count == 2 { return .init(issue: .init(.entropyUnavailable, "Unavailable")) }
            return SecretGenerator.generate(request)
        })
        await session.run()?.value
        let batch = try #require(session.batch)
        session.lengthText = "64"
        #expect(session.batch?.id == batch.id && session.batch?.entropyBits == batch.entropyBits && session.settingsDiffer && session.canCopy)
        #expect(session.statusText.contains("Settings changed"))
        session.countText = "2"; await session.run()?.value
        #expect(session.batch?.id == batch.id && session.issue?.status == .entropyUnavailable && session.canCopy)
        session.cancel()
        #expect(session.batch?.id == batch.id)
        session.lengthText = ""
        #expect(!session.canGenerate && session.validationIssue != nil && session.canCopy)
    }
    @Test func singleWorkerAndPendingRequestRejectStalePublication() async throws {
        let gate = SecretWorkerGate()
        let session = SecretGeneratorWorkspaceSession(kind: .password, repository: repository(), worker: gate.work)
        let first = session.run(); try await gate.waitFor(1)
        session.lengthText = "14"; session.run()
        session.lengthText = "15"; session.run()
        #expect(await gate.calls == 1)
        await gate.finish(1); try await gate.waitFor(2)
        #expect(session.batch == nil && session.busy)
        await gate.finish(2); await first?.value
        let batch = try #require(session.batch)
        #expect(batch.options == .password(.init(length: 15)))
        #expect(await gate.calls == 2)
    }
    @Test func clearAndCancelIgnoreUncooperativeWorker() async throws {
        for clear in [true, false] {
            let gate = SecretWorkerGate()
            let session = SecretGeneratorWorkspaceSession(kind: .password, repository: repository(), worker: gate.work)
            let job = session.run(); try await gate.waitFor(1)
            if clear { session.clear() } else { session.cancel() }
            await gate.finish(1); await job?.value
            #expect(session.batch == nil && !session.busy)
            if !clear { #expect(session.issue?.status == .cancelled) }
        }
    }
    @Test func hiddenStateIsExplicitAndBackgroundOnlyRetainsBatch() async throws {
        let session = SecretGeneratorWorkspaceSession(kind: .passphrase, repository: repository(.passphrase))
        await session.run()?.value
        let id = try #require(session.batch?.id)
        #expect(!session.hidden)
        session.toggleVisibility(); #expect(session.hidden)
        await session.run()?.value; #expect(session.hidden)
        session.toggleVisibility(); #expect(!session.hidden)
        session.concealSecrets(); #expect(session.hidden && session.batch != nil && session.canCopy)
        #expect(session.batch?.id != id)
    }
    @Test func copyGuardClearSettingsAndBackgroundStopStaleClipboardWrite() async throws {
        for action in 0...2 {
            let gate = SecretCopyGate()
            let session = SecretGeneratorWorkspaceSession(kind: .password, repository: repository(), serializer: { _, _ in await gate.wait() })
            await session.run()?.value
            var published = false
            let job = session.copyAll(.json) { _ in published = true }
            try await gate.waitUntilStarted()
            switch action { case 0: session.clear(); case 1: session.lengthText = "14"; default: session.concealSecrets() }
            await gate.finish(); await job?.value
            #expect(!published && !session.copying)
        }
    }
    @Test func exactCopyAndClearResetCommands() async throws {
        let session = SecretGeneratorWorkspaceSession(kind: .password, repository: repository())
        session.mode = .custom; session.customAlphabet = "ab"; session.exclusions = "c"; session.countText = "2"
        await session.run()?.value
        let batch = try #require(session.batch)
        session.toggleVisibility(); var copied = ""
        await session.copyAll(.lines) { copied = $0 }?.value
        #expect(copied == batch.values.joined(separator: "\n"))
        session.selection = 1
        #expect(session.copyValue(at: 1) == session.selectedValue && session.copyValue(at: 100) == nil)
        session.clear()
        #expect(session.batch == nil && session.rows.isEmpty && session.customAlphabet.isEmpty && session.exclusions.isEmpty && session.mode == .standard)
        #expect(session.countText == "2")
        session.resetSettings()
        #expect(session.lengthText == "13" && session.countText == "1" && session.wordsText == "6" && !session.canCopy)
    }
}
private actor SecretWorkerGate {
    private(set) var calls = 0
    var continuations = [Int: CheckedContinuation<SecretResult, Never>]()
    var requests = [Int: SecretGeneratorRequest]()
    func work(_ request: SecretGeneratorRequest) async -> SecretResult {
        calls += 1; let id = calls; requests[id] = request
        return await withCheckedContinuation { continuations[id] = $0 }
    }
    func waitFor(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while continuations[count] == nil {
            guard ContinuousClock.now < deadline else { throw SecretIssue(.cancelled, "Test gate timed out") }
            await Task.yield()
        }
    }
    func finish(_ id: Int) {
        // Deliberately ignores the cancelled worker's task state.
        let options = requests[id]!
        continuations.removeValue(forKey: id)?.resume(returning: .init(batch: .init(options: options, values: ["synthetic-fixture"], entropyBits: 1, duplicateCount: 0, dictionaryVersion: nil)))
    }
}
private actor SecretCopyGate {
    var continuation: CheckedContinuation<String, Never>?
    func wait() async -> String { await withCheckedContinuation { continuation = $0 } }
    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while continuation == nil { guard ContinuousClock.now < deadline else { throw SecretIssue(.cancelled, "Test gate timed out") }; await Task.yield() }
    }
    func finish() { continuation?.resume(returning: "synthetic-fixture"); continuation = nil }
}
