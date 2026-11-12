import Foundation
import Testing
@testable import EncodingCore

@MainActor struct HTMLEntityWorkspaceTests {
    private func repository() -> (HTMLEntityPreferencesRepository, String) {
        let suite = "HTMLEntityTests." + UUID().uuidString
        return (.init(defaults: UserDefaults(suiteName: suite)!), suite)
    }
    @Test func checkPasteCancelAndCurrentArtifact() async {
        let (repo,suite) = repository(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        let session = HTMLEntityWorkspaceSession(repository:repo)
        session.preferences.direction = .decode; session.input = "&amp;lt;"
        #expect(session.result == nil && !session.busy)
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        await session.run().value
        #expect(session.output == "&lt;" && session.canCopy)
        await session.run(.check).value
        #expect(session.output == "&lt;" && session.canCopy)
        let work = session.run(.check); session.cancel(); await work.value
        #expect(session.wasCancelled && session.output == "&lt;" && session.canCopy)
        session.preferences.wordWrap.toggle(); session.preferences.scope = .everyCharacter; session.preferences.notation = .decimal
        session.preferences.preserveExistingReferences = true
        #expect(session.output == "&lt;")
        session.preferences.validateOnPaste = false; #expect(session.didPaste() == nil)
        session.input = "&bogus;"
        #expect(session.result == nil && session.output == nil && !session.canCopy)
        await session.run().value
        #expect(session.result?.status == .successWithWarnings && session.output == "&bogus;")
        session.preferences.policy = .strict
        #expect(session.result == nil && session.output == nil)
        await session.run().value
        #expect(session.result?.status == .invalidReferences && session.output == nil)
        session.clear()
        #expect(session.input.isEmpty && session.result == nil && !session.canCopy)
    }
    @Test func exactRevisionsAndEncodeEffectiveSettings() async {
        let (repo,suite) = repository(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        let session = HTMLEntityWorkspaceSession(repository:repo)
        session.input = "é"; await session.run().value
        let revision = session.sourceRevision
        session.preferences.policy = .strict
        #expect(session.output == "é")
        session.input = "e\u{301}"
        #expect(session.sourceRevision != revision && session.output == nil)
        await session.run().value
        #expect(session.output?.unicodeScalars.map(\.value) == [101,769])
        session.preferences.scope = .nonASCII
        #expect(session.output == nil)
        await session.run().value
        #expect(session.output?.contains("&#x301;") == true)
        session.preferences.context = .singleQuoted
        #expect(session.output == nil)
    }
    @Test func nonCooperativeWorkerCannotPublishStaleSourceOptionsOrRequest() async {
        actor Gate {
            var continuation: CheckedContinuation<Void,Never>?
            var started = false
            func pause() async { guard !started else { return }; await withCheckedContinuation { continuation = $0; started = true } }
            func wait() async { while !started { await Task.yield() } }
            func resume() { continuation?.resume(); continuation = nil }
        }
        let (repo,suite) = repository(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        for race in 0..<3 {
            let gate = Gate()
            let session = HTMLEntityWorkspaceSession(repository:repo, worker: { source,options,intent in
                let result = HTMLEntityProcessor.process(source,options:options,intent:intent)
                if (race == 2 && intent == .check) || (race < 2 && source == "&amp;") { await gate.pause() }
                return result
            })
            session.preferences.direction = .decode; session.input = "&amp;"
            let old = session.run(race == 2 ? .check : .convert); await gate.wait()
            if race == 0 { session.input = "&lt;" }
            else if race == 1 { session.preferences.direction = .encode }
            await session.run().value
            let publication = session.publicationID, output = session.output
            await gate.resume(); await old.value
            #expect(session.output == output && session.publicationID == publication && !session.busy)
            #expect(output == (race == 0 ? "<" : race == 1 ? "&amp;amp;" : "&"))
        }
    }
    @Test func checkFailureAndWorkerCancellationDoNotDestroyCurrentArtifact() async {
        actor Counter {
            var count = 0
            func next() -> Int { count += 1; return count }
        }
        let counter = Counter(), (repo,suite) = repository()
        defer { repo.defaults.removePersistentDomain(forName:suite) }
        let session = HTMLEntityWorkspaceSession(repository:repo,worker: { source,options,intent in
            switch await counter.next() {
            case 2: return .init(status:.resourceLimit)
            case 3: return .init(status:.cancelled)
            default: return HTMLEntityProcessor.process(source,options:options,intent:intent)
            }
        })
        session.input = "&"; await session.run().value
        await session.run(.check).value
        #expect(session.result?.status == .resourceLimit && session.output == "&amp;" && session.canCopy)
        await session.run().value
        #expect(session.wasCancelled && session.output == "&amp;" && session.canCopy)
    }
    @Test func preferencesAllowlistCorruptionAndSessionPrivacy() async throws {
        let (repo,suite) = repository(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        let session = HTMLEntityWorkspaceSession(repository:repo)
        session.preferences.context = .singleQuoted; session.preferences.wordWrap = false
        session.input = "private synthetic example"; await session.run().value
        let data = try #require(repo.defaults.data(forKey:HTMLEntityPreferencesRepository.key))
        let json = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        #expect(Set(json.keys) == Set(["direction","context","scope","notation","preserveExistingReferences","policy","validateOnPaste","wordWrap"]))
        #expect(!String(decoding:data,as:UTF8.self).contains("private"))
        let fresh = HTMLEntityWorkspaceSession(repository:repo)
        #expect(fresh.input.isEmpty && fresh.result == nil && fresh.artifact == nil)
        #expect(fresh.preferences.context == .singleQuoted && !fresh.preferences.wordWrap)
        repo.defaults.set(Data(#"{"direction":"future","context":"doubleQuoted","scope":99,"notation":"decimal","wordWrap":false,"policy":"strict"}"#.utf8),forKey:HTMLEntityPreferencesRepository.key)
        let partial = repo.load()
        #expect(partial.direction == .encode && partial.context == .doubleQuoted && partial.scope == .required)
        #expect(partial.notation == .decimal && partial.policy == .strict && !partial.wordWrap && partial.validateOnPaste)
        repo.defaults.set(Data("broken".utf8),forKey:HTMLEntityPreferencesRepository.key)
        #expect(repo.load() == .init())
    }
}
