import Foundation
import Testing
@testable import JSONCore

private actor JWTEncoderGate {
    var arrived = 0
    var active = 0
    var peak = 0
    var continuation: CheckedContinuation<Void, Never>?
    func enter() async {
        arrived += 1; active += 1; peak = max(peak, active)
        if arrived == 1 { await withCheckedContinuation { continuation = $0 } }
        active -= 1
    }
    func release() { continuation?.resume(); continuation = nil }
}
struct JWTEncoderWorkspaceTests {
    @MainActor func make(worker: (@Sendable (JWTEncoderRequest, JWTEncoderMode, JWTBudget) async -> JWTEncoderResult)? = nil) -> (JWTEncoderWorkspaceSession, UserDefaults, String) {
        let name = "jwt-encoder-test-" + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        let repository = JWTEncoderPreferencesRepository(defaults: defaults)
        let session = worker.map { JWTEncoderWorkspaceSession(repository: repository, worker: $0) } ?? JWTEncoderWorkspaceSession(repository: repository)
        return (session, defaults, name)
    }
    @Test @MainActor func outputValidityCheckAndCopyContracts() async throws {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        w.key = String(repeating: "x", count: 32); await w.run().value
        let id = try #require(w.artifact?.id), token = try #require(w.copy())
        #expect(w.copy(bearer: true) == "Bearer " + token)
        await w.run(.check).value; #expect(w.artifact?.id == id)
        w.preferences.wordWrap.toggle(); w.fraction = 0.65
        #expect(w.copy() == token)
        w.hide(); #expect(w.copy() == nil && w.artifact?.id == id)
        w.reveal(); #expect(w.copy() == token)
        w.payload = #"{"sub":"new"}"#; #expect(w.artifact == nil && w.copy() == nil && w.result == nil)
        await w.run().value; #expect(w.artifact != nil)
        w.key += "x"; #expect(w.artifact == nil)
    }
    @Test @MainActor func pasteChecksJSONWithoutSigningOrKey() async {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        w.payload = #"{"a":1}"#; #expect(w.result == nil)
        w.didPaste(); await w.run(.jsonOnly).value
        #expect(w.result?.status == .checked && w.artifact == nil)
        w.preferences.checkJSONOnPaste = false; w.payload = "{"
        w.didPaste(); #expect(!w.busy && w.result == nil)
        w.preferences.checkJSONOnPaste = true; w.didPaste()
        while w.busy { await Task.yield() }
        #expect(w.result?.status == .invalidInput)
    }
    @Test @MainActor func boundedQueueIgnoresOldWorkerAndOnlyKeepsLatestPending() async throws {
        let gate = JWTEncoderGate()
        let (w,d,n) = make(worker: { request,mode,budget in
            let response = JWTEncoderProcessor.process(request, mode: mode, budget: budget)
            await gate.enter() // intentionally ignores cancellation
            return response
        }); defer { d.removePersistentDomain(forName: n) }
        w.key = String(repeating: "x", count: 32)
        let task = w.run()
        while await gate.arrived == 0 { await Task.yield() }
        for i in 0..<100 { w.payload = "{\"i\":\(i)}"; w.run() }
        await gate.release(); await task.value
        let arrived = await gate.arrived, peak = await gate.peak
        #expect(arrived == 2 && peak == 1)
        let token = try #require(w.artifact?.token)
        #expect(JWTProcessor.inspect(token).parts[.payload]?.text == #"{"i":99}"#)
        #expect(w.artifact?.revision == w.revision && !w.busy)
    }
    @Test @MainActor func cancelAndClearCannotRepublishOrEraseCurrentArtifact() async throws {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        w.key = String(repeating: "x", count: 32); await w.run().value
        let id = try #require(w.artifact?.id)
        let task = w.run(); w.cancel(); await task.value
        #expect(w.artifact?.id == id && w.result?.status == .cancelled)
        let epoch = w.editorEpoch
        let clearing = w.run(); w.clear(); await clearing.value
        #expect(w.artifact == nil && w.result == nil && w.key.isEmpty && w.payload == "{}" && w.editorEpoch != epoch)
        #expect(!w.unsignedConsent && w.keyRevealed && w.tokenRevealed)
    }
    @Test @MainActor func failureForSameSnapshotRetainsArtifact() async throws {
        actor Attempt { var count = 0; func next() -> Int { count += 1; return count } }
        let attempts = Attempt()
        let (w,d,n) = make(worker: { request, mode, budget in
            if await attempts.next() == 1 { return JWTEncoderProcessor.process(request, mode: mode, budget: budget) }
            return .init(status: .cryptoFailure)
        }); defer { d.removePersistentDomain(forName: n) }
        w.key = String(repeating: "x", count: 32); await w.run().value
        let id = try #require(w.artifact?.id)
        await w.run().value
        #expect(w.artifact?.id == id && w.result?.status == .cryptoFailure)
    }
    @Test @MainActor func preferencesAllowlistUnknownValuesAndNewSession() async throws {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        w.payload = #"{"sub":"private-draft"}"#; w.key = String(repeating: "x", count: 32); await w.run().value
        w.preferences.serialization = .preserve; w.preferences.wordWrap = false
        w.unsignedConsent = true; w.header = #"{"alg":"none"}"#; w.keyRevealed = true
        let data = try #require(d.data(forKey: JWTEncoderPreferencesRepository.key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String:Any])
        #expect(Set(object.keys) == Set(["signedAlgorithm","keyEncoding","serialization","wordWrap","checkJSONOnPaste"]))
        #expect(!String(decoding: data, as: UTF8.self).contains("private-draft"))
        let next = JWTEncoderWorkspaceSession(repository: .init(defaults: d))
        #expect(next.key.isEmpty && next.payload == "{}" && next.artifact == nil && !next.unsignedConsent && next.keyRevealed && next.tokenRevealed)
        #expect(next.algorithm == .hs256 && next.preferences.serialization == .preserve && !next.preferences.wordWrap)
        d.set(Data(#"{"signedAlgorithm":"none","keyEncoding":"future","serialization":"bad","wordWrap":false}"#.utf8), forKey: JWTEncoderPreferencesRepository.key)
        let recovered = JWTEncoderPreferencesRepository(defaults: d).load()
        #expect(recovered.signedAlgorithm == .hs256 && recovered.keyEncoding == .utf8 && recovered.serialization == .compact && !recovered.wordWrap)
    }
    @Test @MainActor func exactScalarChangesInvalidateAndShowCorrectEditor() async throws {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        w.key = String(repeating: "x", count: 32); w.payload = "{\"s\":\"é\"}"; await w.run().value
        w.payload = "{\"s\":\"e\u{301}\"}"; #expect(w.artifact == nil)
        w.payload = "{\"a\":"; await w.run(.jsonOnly).value
        let issue = try #require(w.result?.issues.first)
        w.show(issue)
        #expect(w.payloadTarget == issue.diagnostic?.range)
        w.payload = "{}"; w.show(issue); #expect(w.payloadTarget == nil)
    }
    @Test @MainActor func visibilityOnlyChangesOnExplicitActionOrRealBackground() async throws {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        #expect(!w.masked && w.keyRevealed && w.tokenRevealed)
        w.key = String(repeating: "k", count: 32); await w.run().value
        let token = try #require(w.artifact?.token)
        await w.run(.jsonOnly).value; w.disappear()
        #expect(!w.masked && w.keyRevealed && w.tokenRevealed && w.copy() == token)
        w.keyRevealed = false; w.tokenRevealed = false
        w.payload = #"{"sub":"changed"}"#; await w.run().value; w.disappear()
        #expect(!w.keyRevealed && !w.tokenRevealed && !w.masked)
        w.reveal(); let artifact = w.artifact?.id, header = w.header, payload = w.payload
        w.concealSecrets()
        #expect(!w.masked && !w.keyRevealed && !w.tokenRevealed)
        #expect(w.header == header && w.payload == payload && w.artifact?.id == artifact)
        w.hide(); #expect(w.masked && w.copy() == nil)
        w.reveal(); #expect(!w.masked && w.keyRevealed && w.tokenRevealed && w.copy() != nil)
    }

    @Test @MainActor func manualHeaderAlgorithmTracksEditsUndoAndRejectsStaleProjection() async throws {
        let (w,d,n) = make(); defer { d.removePersistentDomain(forName: n) }
        w.key = String(repeating: "k", count: 64)
        let original = w.header
        w.header = #"{"alg":"HS512","kid":"keep"}"#
        // Signing must read its snapshot even before the debounced UI projection completes.
        await w.run().value
        #expect(w.artifact?.algorithm == .hs512)
        await w.algorithmTask?.value
        #expect(w.algorithm == .hs512 && w.preferences.signedAlgorithm == .hs512)
        w.header = original; await w.algorithmTask?.value
        #expect(w.algorithm == .hs256 && w.artifact == nil)
        for source in [#"{"alg":"future"}"#, "{", #"{"alg":false}"#, #"{"alg":"HS256","alg":"HS512"}"#] {
            w.header = source; await w.algorithmTask?.value
            #expect(w.algorithm == nil && w.header == source)
            #expect(w.preferences.signedAlgorithm == .hs256)
        }
        w.header = #"{"alg":"HS384"}"#
        let outdated = w.algorithmTask
        w.header = #"{"alg":"HS512"}"#
        await outdated?.value; await w.algorithmTask?.value
        #expect(w.algorithm == .hs512)
        w.header = #"{"alg":"none"}"#; await w.algorithmTask?.value
        #expect(w.algorithm == JWTSigningAlgorithm.none && w.preferences.signedAlgorithm == .hs512)
        await w.run().value
        #expect(w.result?.issues.contains { $0.code == "UNSIGNED-CONSENT" } == true && w.artifact == nil)
        w.unsignedConsent = true; await w.run().value
        #expect(w.artifact?.algorithm == JWTSigningAlgorithm.none)
        w.unsignedConsent = false; await w.run().value
        #expect(w.artifact == nil && w.header == #"{"alg":"none"}"#)
    }

}
