import Foundation
import Testing
@testable import EncodingCore

@MainActor struct BasicAuthWorkspaceTests {
    func repository() -> (BasicAuthPreferencesRepository, String) {
        let name = "BasicAuthTests." + UUID().uuidString
        return (.init(defaults: UserDefaults(suiteName: name)!), name)
    }
    @Test func lifecycleCopyClearAndExactRevisions() async {
        let (repo, name) = repository(); defer { repo.defaults.removePersistentDomain(forName: name) }
        let w = BasicAuthWorkspaceSession(repository: repo)
        #expect(w.result == nil && w.statusText == "Ready" && !w.canCopy)
        w.username = "Aladdin"; w.password = "open sesame"; #expect(w.result == nil)
        await w.run().value
        #expect(w.copyText(fullHeader: true) == "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
        #expect(w.copyText(fullHeader: false) == "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
        w.showHeader = true; w.showPassword = true; w.hideSensitiveData()
        #expect(!w.showHeader && !w.showPassword && w.canCopy && w.password == "open sesame")
        let running = w.run(); w.cancel(); await running.value
        #expect(w.wasCancelled && w.canCopy)
        w.password = "é"; await w.run().value; let revision = w.sourceRevision
        w.password = "e\u{301}"; #expect(w.sourceRevision != revision && !w.canCopy && w.result == nil)
        w.clear(); #expect(w.username.isEmpty && w.password.isEmpty && !w.canCopy && w.statusText == "Ready")
    }
    private actor Gate {
        var waits: [CheckedContinuation<Void,Never>] = []
        var calls = 0
        func pause() async { calls += 1; await withCheckedContinuation { waits.append($0) } }
        func wait(_ n: Int) async { while calls < n { await Task.yield() } }
        func release(_ index: Int) { waits.remove(at: index).resume() }
    }
    @Test func staleWorkersNeverRestoreOldHeader() async {
        for scenario in 0..<4 {
            let (repo, name) = repository(); defer { repo.defaults.removePersistentDomain(forName: name) }
            let gate = Gate()
            let w = BasicAuthWorkspaceSession(repository: repo, worker: { source in
                let value = BasicAuthProcessor.build(source); await gate.pause(); return value
            })
            w.username = "u"; w.password = "old"; let a = w.run(); await gate.wait(1)
            #expect(w.copyText(fullHeader: true) == nil)
            if scenario == 0 { w.password = "new" }
            if scenario == 1 { w.preferences.encoding = .latin1 }
            if scenario == 2 { w.clear() }
            let b = w.run(); await gate.wait(2); await gate.release(1); await b.value
            let expected = w.copyText(fullHeader: true)
            await gate.release(0); await a.value
            #expect(w.copyText(fullHeader: true) == expected && w.result?.status == .success && !w.busy)
        }
    }
    @Test func rejectedPastePreservesArtifactAndCancelledWorkerIsNotInvalid() async {
        let (repo, name) = repository(); defer { repo.defaults.removePersistentDomain(forName: name) }
        let w = BasicAuthWorkspaceSession(repository: repo); await w.run().value
        let value = w.copyText(fullHeader: true)
        w.reject(.init(code: .control, field: .password, message: "Control characters are not allowed."))
        #expect(w.canCopy && w.copyText(fullHeader: true) == value && w.rejectedInput != nil)
        w.password = "new"; #expect(w.rejectedInput == nil && !w.canCopy)
        let cancelled = BasicAuthWorkspaceSession(repository: repo, worker: { _ in .init(status: .cancelled) })
        await cancelled.run().value
        #expect(cancelled.wasCancelled && cancelled.result == nil && !cancelled.busy)
        #expect(cancelled.statusText == "Cancelled")
    }
    @Test func settingsOnlyAndNewSessionEmpty() async throws {
        let (repo, name) = repository(); defer { repo.defaults.removePersistentDomain(forName: name) }
        let w = BasicAuthWorkspaceSession(repository: repo)
        w.username = "synthetic-username-marker"; w.password = "synthetic-secret-marker"; await w.run().value
        w.preferences.normalizeNFC = true; w.preferences.encoding = .latin1
        let encoded = try #require(repo.defaults.data(forKey: BasicAuthPreferencesRepository.key))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["encoding", "normalizeNFC"])
        #expect(!String(decoding: encoded, as: UTF8.self).contains("marker"))
        let fresh = BasicAuthWorkspaceSession(repository: repo)
        #expect(fresh.username.isEmpty && fresh.password.isEmpty && fresh.result == nil && !fresh.showHeader && !fresh.showPassword)
        #expect(fresh.preferences.encoding == .latin1 && fresh.preferences.normalizeNFC)
        fresh.preferences.normalizeNFC = false; await fresh.run().value
        fresh.preferences.normalizeNFC = true; #expect(fresh.canCopy) // Ineffective in Latin-1.
        repo.defaults.set(Data(#"{"encoding":"future","normalizeNFC":true,"password":"ignored"}"#.utf8), forKey: BasicAuthPreferencesRepository.key)
        #expect(repo.load().encoding == .utf8 && repo.load().normalizeNFC)
        repo.defaults.set(Data("broken".utf8), forKey: BasicAuthPreferencesRepository.key)
        #expect(repo.load() == BasicAuthPreferences())
    }
}
