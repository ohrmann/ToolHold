import Foundation
import Testing
@testable import EncodingCore

@MainActor struct StringEscapeWorkspaceTests {
    private func repository() -> (StringEscapePreferencesRepository,String) {
        let name = "StringEscapeTests." + UUID().uuidString
        return (.init(defaults:UserDefaults(suiteName:name)!),name)
    }
    @Test func pasteCheckConvertInvalidateAndEmptyArtifacts() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let workspace = StringEscapeWorkspaceSession(repository:repo)
        #expect(workspace.result == nil && workspace.input.isEmpty && !workspace.canCopy)
        await workspace.run().value
        #expect(workspace.output == "\"\"" && workspace.canCopy)
        workspace.preferences.representation = .contents
        await workspace.run().value
        #expect(workspace.output == "" && workspace.artifact != nil && !workspace.canCopy)
        workspace.preferences.direction = .unescape
        workspace.input = #"\u0041"#
        #expect(workspace.result == nil && workspace.artifact == nil && !workspace.busy)
        await workspace.didPaste()?.value
        #expect(workspace.result?.status == .success && workspace.output == nil)
        await workspace.run().value
        #expect(workspace.output == "A" && workspace.canCopy)
        await workspace.run(.check).value
        #expect(workspace.output == "A" && workspace.canCopy)
        let work = workspace.run(); workspace.cancel(); await work.value
        #expect(workspace.wasCancelled && workspace.output == "A")
        workspace.input += "x"
        #expect(workspace.output == nil && workspace.result == nil && !workspace.canCopy && !workspace.busy)
        workspace.preferences.validateOnPaste = false
        #expect(workspace.didPaste() == nil && !workspace.busy)
        workspace.clear(); #expect(workspace.input.isEmpty && workspace.result == nil)
    }
    @Test func sourceComparisonAndEffectiveOptions() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let workspace = StringEscapeWorkspaceSession(repository:repo)
        workspace.input = "é"; await workspace.run().value
        let revision = workspace.sourceRevision, artifact = workspace.output
        workspace.preferences.quote = .single; workspace.preferences.wordWrap = false
        #expect(workspace.sourceRevision == revision && workspace.output == artifact)
        workspace.input = "e\u{301}"
        #expect(workspace.input == "é") // Swift canonical equality must not suppress the source change.
        #expect(workspace.sourceRevision != revision && workspace.output == nil)
        workspace.preferences.direction = .unescape; workspace.preferences.representation = .contents
        workspace.input = #"\u0041"#; await workspace.run().value
        workspace.preferences.nonASCII = true
        #expect(workspace.output == "A" && workspace.canCopy)
        workspace.preferences.language = .javascript
        #expect(workspace.output == nil)
    }
    @Test func staleSourceOptionsAndRequestCannotPublish() async {
        actor Gate {
            var arrived = false
            var released = false
            var waiter: CheckedContinuation<Void,Never>?
            func pause() async { arrived = true; if !released { await withCheckedContinuation { waiter = $0 } } }
            func wait() async { while !arrived { await Task.yield() } }
            func release() { released = true; waiter?.resume(); waiter = nil }
        }
        for race in 0..<3 {
            let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
            let gate = Gate()
            let workspace = StringEscapeWorkspaceSession(repository:repo,worker: { source,options,intent in
                let result = StringEscapeProcessor.process(source,options:options,intent:intent)
                if (race == 2 && intent == .check) || (race == 0 && source == "old") || (race == 1 && options.representation == .quoted) { await gate.pause() }
                return result
            })
            workspace.input = "old"
            let old = workspace.run(race == 2 ? .check : .convert); await gate.wait()
            if race == 0 { workspace.input = "new" }
            if race == 1 { workspace.preferences.representation = .contents }
            await workspace.run().value
            let publication = workspace.publicationID, output = workspace.output
            await gate.release(); await old.value
            #expect(workspace.publicationID == publication && workspace.output == output && !workspace.busy)
            #expect(output == (race == 1 ? "old" : race == 0 ? "\"new\"" : "\"old\""))
        }
    }
    @Test func checkFailuresAndWorkerCancellationPreserveCurrentArtifact() async {
        actor Counter { var value = 0; func next() -> Int { value += 1; return value } }
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let count = Counter()
        let workspace = StringEscapeWorkspaceSession(repository:repo,worker:{ source,options,intent in
            let n = await count.next()
            if n == 2 { return .init(status:.resourceLimit) }
            if n == 3 { return .init(status:.cancelled) }
            return StringEscapeProcessor.process(source,options:options,intent:intent)
        })
        workspace.input = "a"; await workspace.run().value
        await workspace.run(.check).value
        #expect(workspace.result?.status == .resourceLimit && workspace.output == "\"a\"" && workspace.canCopy)
        await workspace.run(.check).value
        #expect(workspace.wasCancelled && workspace.output == "\"a\"")
        workspace.preferences.direction = .unescape; workspace.input = #""\uD800""#
        await workspace.run().value
        #expect(workspace.result?.status == .notRepresentableAsText && workspace.artifact == nil && !workspace.canCopy)
    }
    @Test func pendingWorkDoesNotRetainClosedWindowSession() async {
        actor Gate {
            var ready = false
            var continuation: CheckedContinuation<Void,Never>?
            func pause() async { ready = true; await withCheckedContinuation { continuation = $0 } }
            func wait() async { while !ready { await Task.yield() } }
            func release() { continuation?.resume(); continuation = nil }
        }
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let gate = Gate()
        var workspace: StringEscapeWorkspaceSession? = .init(repository:repo,worker:{ _,_,_ in
            await gate.pause(); return .init(status:.success)
        })
        weak var reference = workspace
        let task = workspace!.run(); await gate.wait()
        workspace = nil
        #expect(reference == nil)
        await gate.release(); await task.value
    }
    @Test func preferencesAllowlistCorruptionAndNewSessionPrivacy() async throws {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        var value = StringEscapePreferences()
        value.language = .javascript; value.quote = .single; value.direction = .unescape; value.nonASCII = true
        repo.save(value); #expect(repo.load() == value)
        let data = try #require(repo.defaults.data(forKey:StringEscapePreferencesRepository.key))
        let keys = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        #expect(Set(keys.keys) == ["language","direction","representation","quote","nonASCII","validateOnPaste","wordWrap"])
        let current = StringEscapeWorkspaceSession(repository:repo); current.input = "'private'"
        await current.run().value; #expect(current.output == "private")
        let fresh = StringEscapeWorkspaceSession(repository:repo)
        #expect(fresh.input.isEmpty && fresh.artifact == nil && fresh.result == nil && fresh.preferences == value)
        repo.defaults.set(Data(#"{"language":"future","direction":7,"quote":"single","wordWrap":false,"source":"secret"}"#.utf8),forKey:StringEscapePreferencesRepository.key)
        let corrupt = repo.load()
        #expect(corrupt.language == .json && corrupt.direction == .escape && corrupt.quote == .single && !corrupt.wordWrap)
        repo.defaults.set(Data("bad".utf8),forKey:StringEscapePreferencesRepository.key)
        #expect(repo.load() == .init())
    }
}
