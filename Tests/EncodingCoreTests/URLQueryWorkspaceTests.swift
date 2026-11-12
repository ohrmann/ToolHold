import Foundation
import Testing
@testable import EncodingCore

@MainActor struct URLQueryWorkspaceTests {
    private func session(_ suffix: String = UUID().uuidString) -> (URLQueryWorkspaceSession,URLQueryPreferencesRepository,String) {
        let suite = "URLQueryTests." + suffix, repo = URLQueryPreferencesRepository(defaults:UserDefaults(suiteName:"URLQueryTests."+suffix)!)
        return (.init(repository:repo),repo,suite)
    }
    @Test func pasteBuildCancelExactInvalidationAndPrivacy() async {
        let (s,repo,suite) = session(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        s.input = "https://例え.テスト/?q=😀"
        #expect(s.snapshot == nil && !s.busy)
        let beforeParse = s.draftRevision
        await s.didPaste()?.value
        #expect(s.draftRevision != beforeParse) // Native lists reload on publication, not just source invalidation.
        #expect(s.snapshot?.rows.count == 1 && s.artifact == nil)
        await s.build()?.value
        #expect(s.output == s.input && s.canCopy)
        let artifact = s.output
        await s.parse().value
        #expect(s.output == artifact)
        let work = s.build(); s.cancel(); await work?.value
        #expect(s.wasCancelled && s.output == artifact && s.canCopy)
        s.setWordWrap(false); s.setParseOnPaste(false)
        #expect(s.output == artifact && s.didPaste() == nil)
        s.outputForm = .ascii
        #expect(s.output?.contains("xn--") == true)
        s.input = "/é"; await s.parse().value
        let source = s.sourceRevision
        s.input = "/e\u{301}"
        #expect(s.sourceRevision != source && s.artifact == nil && s.snapshot == nil && s.selectedID == nil)
        let fresh = URLQueryWorkspaceSession(repository:repo)
        #expect(fresh.input.isEmpty && fresh.draft == nil && fresh.output == nil && !fresh.preferences.wordWrap)
        let data = repo.defaults.data(forKey:URLQueryPreferencesRepository.key)!
        let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any]
        #expect(Set(json?.keys.map{$0} ?? []) == ["profile","parseOnPaste","wordWrap"])
        s.clear(); #expect(s.input.isEmpty && s.result == nil)
    }
    @Test func editReorderUndoResetAndProfileTransactions() async throws {
        let (s,repo,suite) = session(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        s.input = "?%61=%2f&flag&x=a+b"; await s.parse().value
        s.beginEdit(0); s.editValue = "😀 +"; #expect(s.hasPendingEdit)
        #expect(!s.changeProfile(.form))
        #expect(s.applyEdit() && s.canUndo)
        s.move(0,to:2); await s.build()?.value
        #expect(s.output == "?flag&x=a+b&%61=%F0%9F%98%80%20%2B")
        s.undo(); s.undo(); await s.build()?.value
        #expect(s.output == s.input)
        s.redo(); s.redo(); #expect(s.rows.last?.id == 0)
        s.beginEdit(1); s.editHasValue = true; s.editValue = ""; #expect(s.applyEdit())
        await s.build()?.value; #expect(s.output?.hasPrefix("?flag=&") == true)
        s.remove(1); #expect(s.rows.count == 2); s.undo(); #expect(s.rows.count == 3)
        s.reset(); #expect(!s.dirty && !s.canUndo && s.rows[0].id == 0)
        s.add(); let added = try #require(s.editingID); s.editName = "é"; s.editValue = "e\u{301}"
        #expect(s.applyEdit()); #expect(s.rows.last?.id == added)
        #expect(!s.changeProfile(.form)); let oldRevision = s.draftRevision
        #expect(s.changeProfile(.form,discard:true)); #expect(s.draftRevision != oldRevision && s.rows.isEmpty)
        await s.parse().value
        #expect(s.preferences.profile == .form && s.rows[2].value == "a b" && !s.dirty)
    }
    @Test func rawOnlyReplacementAndMissingVsEmpty() async {
        let (s,repo,suite) = session(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        s.input = "?%FF=%FF"; await s.parse().value
        s.beginEdit(0); #expect(s.editName.isEmpty && s.editValue.isEmpty)
        s.editHasValue = false; #expect(s.applyEdit())
        await s.build()?.value; #expect(s.output == "?%FF")
        s.beginEdit(0); s.replaceName = true; s.editName = ""; s.editHasValue = true; s.editValue = "test"
        #expect(s.applyEdit()); s.beginEdit(0); #expect(!s.hasPendingEdit); s.cancelEdit()
        await s.build()?.value; #expect(s.output == "?=test")
        s.remove(0); await s.build()?.value; #expect(s.output == "?")
        s.setQueryPresent(false); await s.build()?.value; #expect(s.output == "")
        #expect(s.canCopy) // Empty reference is still an explicit valid artifact.
    }
    @Test func staleParseAndBuildCannotOverwriteSourceOrDraft() async {
        actor Gate {
            var paused = false
            var continuation: CheckedContinuation<Void,Never>?
            func wait() async { await withCheckedContinuation { continuation = $0; paused = true } }
            func started() async { while !paused { await Task.yield() } }
            func resume() { continuation?.resume(); continuation = nil }
        }
        let gate = Gate(), buildGate = Gate()
        let (_,repo,suite) = session(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        let s = URLQueryWorkspaceSession(repository:repo,inspector:{ source,profile in
            let value = URLQueryProcessor.inspect(source,profile:profile)
            if source == "?old=1" { await gate.wait() }; return value
        },builder:{ snapshot,draft in
            let value = URLQueryProcessor.build(snapshot,draft:draft)
            await buildGate.wait(); return value
        })
        s.input = "?old=1"; let old = s.parse(); await gate.started()
        s.input = "?new=2"; await s.parse().value
        await gate.resume(); await old.value
        #expect(s.rows[0].name == "new")
        let build = s.build(); await buildGate.started()
        s.input = "?latest=3"; await s.parse().value
        await buildGate.resume(); await build?.value
        #expect(s.rows[0].name == "latest" && s.artifact == nil && !s.busy)
    }
    @Test func preferencesCorruptionFallback() {
        let (_,repo,suite) = session(); defer { repo.defaults.removePersistentDomain(forName:suite) }
        repo.defaults.set(Data("{\"profile\":\"bad\",\"parseOnPaste\":false,\"wordWrap\":1,\"source\":\"ignored\"}".utf8),forKey:URLQueryPreferencesRepository.key)
        let value = repo.load(); #expect(value.profile == .percent && !value.parseOnPaste && value.wordWrap)
        repo.save(value)
        let text = String(decoding:repo.defaults.data(forKey:URLQueryPreferencesRepository.key)!,as:UTF8.self)
        #expect(!text.contains("ignored") && !text.contains("source"))
    }
}
