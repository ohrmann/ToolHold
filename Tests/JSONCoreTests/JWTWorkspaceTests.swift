import Foundation
import Testing
@testable import JSONCore

struct JWTWorkspaceTests {
    @Test @MainActor func currentResultCancelAndInputInvalidation() async {
        let (w, defaults, name) = makeJWTWorkspace(); defer { defaults.removePersistentDomain(forName: name) }
        let token = JWTFixture.token(#"{"sub":"test"}"#); w.input = token; await w.run().value
        let id = w.result?.id; w.cancel(); #expect(w.result?.id == id)
        await w.refreshTime(now: .init(timeIntervalSince1970: 0)).value; #expect(w.result?.id == id)
        w.preferences.wordWrap.toggle(); w.inputCollapsed.toggle(); #expect(w.input == token && w.result?.id == id)
        w.input = token + "x"; #expect(w.result == nil && w.copy(.token) == nil && w.evaluation == nil)
        w.clear(); #expect(w.input.isEmpty)
    }
    @Test @MainActor func staleWorkerIgnoresCancellation() async {
        let (w, defaults, name) = makeJWTWorkspace(worker: { input, budget in
            let result = JWTProcessor.inspect(input, budget: budget)
            if input.contains("Bearer") {
                await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() } }
            }
            return result
        }); defer { defaults.removePersistentDomain(forName: name) }
        w.input = "Bearer " + JWTFixture.token(#"{"sub":"old"}"#)
        let old = w.run(); await Task.yield()
        w.input = JWTFixture.token(#"{"sub":"new"}"#); await w.run().value; await old.value
        #expect(w.result?.claims.first?.preview == "new")
    }
    @Test @MainActor func pasteOnlyAndCancelledRetryRetainsSnapshot() async {
        let (w, defaults, name) = makeJWTWorkspace(); defer { defaults.removePersistentDomain(forName: name) }
        w.input = JWTFixture.token(); #expect(w.result == nil)
        w.preferences.decodeOnPaste = false; w.didPaste(); #expect(!w.busy)
        w.preferences.decodeOnPaste = true; w.didPaste()
        while w.busy { await Task.yield() }
        #expect(w.result != nil)
        let id = w.result?.id; let running = w.run(); w.cancel(); await running.value; #expect(w.result?.id == id)
    }
    @Test @MainActor func preferencesPrivacyAndNewSession() async throws {
        let (w, defaults, name) = makeJWTWorkspace(); defer { defaults.removePersistentDomain(forName: name) }
        w.input = JWTFixture.token(#"{"sub":"private-marker"}"#); await w.run().value; w.setMasked(true)
        w.preferences.wordWrap = false; w.preferences.timeZoneMode = .local
        let data = try #require(defaults.data(forKey: JWTPreferencesRepository.key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set(["wordWrap","decodeOnPaste","timeZoneMode","jsonPresentation"]))
        #expect(!String(decoding: data, as: UTF8.self).contains("private-marker"))
        let next = JWTWorkspaceSession(repository: .init(defaults: defaults))
        #expect(next.input.isEmpty && next.result == nil && !next.masked); #expect(!next.preferences.wordWrap)
        let damaged = Data(#"{"wordWrap":false,"timeZoneMode":"future","decodeOnPaste":"bad"}"#.utf8)
        defaults.set(damaged, forKey: JWTPreferencesRepository.key)
        let restored = JWTPreferencesRepository(defaults: defaults).load()
        #expect(!restored.wordWrap && restored.decodeOnPaste && restored.timeZoneMode == .utc)
    }
}
