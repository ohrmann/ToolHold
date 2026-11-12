import Foundation
import Testing
@testable import EncodingCore

@MainActor struct HexBytesWorkspaceTests {
    private func repository() -> (HexBytesPreferencesRepository,String) {
        let name = "HexBytesTests."+UUID().uuidString; return (.init(defaults:UserDefaults(suiteName:name)!),name)
    }
    @Test func pasteCheckConvertCancelAndInputRevisions() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = HexBytesWorkspaceSession(repository:repo)
        #expect(w.artifact == nil && w.result == nil && !w.canCopyText && !w.canCopyHex)
        await w.run().value
        #expect(w.artifact?.text == "" && w.artifact?.bytes.isEmpty == true && !w.canCopyHex)
        w.input = "4142"; #expect(w.result == nil && !w.busy)
        await w.didPaste()?.value; #expect(w.result?.status == .success && w.artifact == nil)
        await w.run().value; let id = w.artifact?.id
        #expect(w.output == "AB" && w.canCopyHex && w.canCopyText)
        await w.run(.check).value; #expect(w.artifact?.id == id && w.output == "AB")
        let task = w.run(); w.cancel(); await task.value
        #expect(w.wasCancelled && w.artifact?.id == id)
        w.preferences.wordWrap.toggle(); w.preferences.preferredOutputView = .bytes
        #expect(w.artifact?.id == id && w.showingBytes)
        w.input = "FF"; #expect(w.artifact == nil && w.result == nil)
        await w.run().value; #expect(w.showingBytes && !w.canCopyText && w.canCopyHex)
        w.preferences.validateOnPaste = false
        w.input = "4142"; #expect(w.didPaste() == nil && w.result == nil)
        w.clear(); #expect(w.artifact == nil && w.result == nil)
    }
    @Test func effectiveOptionsAndExactCanonicalSourceIdentity() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = HexBytesWorkspaceSession(repository:repo); w.input = "4142"; await w.run().value
        let id = w.artifact?.id
        w.preferences.outputFormat = .compact; w.preferences.hexCase = .lowercase
        #expect(w.artifact?.id == id && w.canCopyHex)
        w.preferences.inputFormat = .prefixed; #expect(w.artifact == nil)
        w.preferences.direction = .encode; w.input = "é"; await w.run().value
        let revision = w.sourceRevision
        w.preferences.inputFormat = .escaped; #expect(w.artifact != nil)
        w.input = "e\u{301}"
        #expect(w.sourceRevision != revision && w.artifact == nil)
        await w.run().value; #expect(w.output == "65cc81")
        w.preferences.outputFormat = .spaced; #expect(w.artifact == nil)
    }
    @Test func copyExactBytesAndFormatBudgets() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = HexBytesWorkspaceSession(repository:repo); w.input = "00 41 00 EF BB BF"; await w.run().value
        let text = await w.prepareCopy(.text).value
        #expect(text?.text.utf8.elementsEqual([0,65,0,0xEF,0xBB,0xBF]) == true && w.isCurrent(text!))
        w.preferences.outputFormat = .escaped
        let copy = await w.prepareCopy(.hex).value
        #expect(copy?.text == #"\x00\x41\x00\xEF\xBB\xBF"# && w.isCurrent(copy!))
        w.input = String(repeating:"41",count:131_072); await w.run().value
        #expect(!w.canCopyHex && !w.copyHexFits && w.canCopyText)
        w.preferences.outputFormat = .compact
        #expect(w.canCopyHex)
        #expect(await w.prepareCopy(.hex).value?.text.utf16.count == 262_144)
    }
    private actor Gate {
        var continuations: [CheckedContinuation<Void,Never>] = []
        var calls = 0
        func pause() async { calls += 1; await withCheckedContinuation { continuations.append($0) } }
        func wait(_ count: Int = 1) async { while calls < count { await Task.yield() } }
        func release(_ index: Int = 0) { continuations.remove(at:index).resume() }
    }
    @Test func staleSourceOptionsAndRequestResultsAreIgnored() async {
        for scenario in 0..<3 {
            let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
            let gate = Gate()
            let w = HexBytesWorkspaceSession(repository:repo,worker:{ s,o,i in
                let result = HexBytesProcessor.process(s,options:o,intent:i); await gate.pause(); return result
            })
            w.input = "4142"; let old = w.run(); await gate.wait()
            if scenario == 0 { w.input = "4344" }
            if scenario == 1 { w.preferences.inputFormat = .prefixed }
            let new = w.run(); await gate.wait(2)
            await gate.release(1); await new.value; let id = w.artifact?.id, result = w.result?.status
            await gate.release(); await old.value
            #expect(w.artifact?.id == id && w.result?.status == result && !w.busy)
            #expect(scenario == 0 ? w.output == "CD" : scenario == 1 ? w.result?.status == .invalidHex : w.output == "AB")
        }
    }
    @Test func cancelledAndResourceChecksPreserveCurrentArtifact() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = HexBytesWorkspaceSession(repository:repo,worker:{ s,o,i in
            i == .convert ? HexBytesProcessor.process(s,options:o) : .init(status:.resourceLimit)
        })
        w.input = "4142"; await w.run().value; let id = w.artifact?.id
        await w.run(.check).value
        #expect(w.result?.status == .resourceLimit && w.artifact?.id == id)
        let cancelled = HexBytesWorkspaceSession(repository:repo,worker:{ _,_,_ in .init(status:.cancelled) })
        await cancelled.run().value; #expect(cancelled.wasCancelled && cancelled.result == nil && !cancelled.busy)
    }
    @Test func lateCopyNeverPublishesAfterSourceFormatOrNewRequest() async {
        for scenario in 0..<3 {
            let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
            let gate = Gate()
            let w = HexBytesWorkspaceSession(repository:repo,copyWorker:{ data,format,hexCase in
                let result = try? HexBytesProcessor.format(data,format:format,hexCase:hexCase); await gate.pause(); return result
            })
            w.input = "4142"; await w.run().value
            let copy = w.prepareCopy(.hex); await gate.wait()
            if scenario == 0 { w.input = "4344" }
            if scenario == 1 { w.preferences.outputFormat = .compact }
            if scenario == 2 { await w.run(.check).value }
            await gate.release(); #expect(await copy.value == nil && !w.copyBusy)
        }
    }
    @Test func preferencesAllowlistCorruptionAndRelaunchPrivacy() async throws {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = HexBytesWorkspaceSession(repository:repo); w.input = "sensitive"; w.preferences.direction = .encode; await w.run().value
        w.preferences.outputFormat = .escaped; w.preferences.hexCase = .lowercase; w.preferences.wordWrap = false; w.preferences.preferredOutputView = .bytes
        let json = try JSONSerialization.jsonObject(with:repo.defaults.data(forKey:HexBytesPreferencesRepository.key)!) as! [String:Any]
        #expect(Set(json.keys) == ["direction","inputFormat","outputFormat","hexCase","validateOnPaste","wordWrap","preferredOutputView"])
        #expect(!String(decoding:repo.defaults.data(forKey:HexBytesPreferencesRepository.key)!,as:UTF8.self).contains("sensitive"))
        let fresh = HexBytesWorkspaceSession(repository:repo)
        #expect(fresh.input.isEmpty && fresh.artifact == nil && fresh.result == nil && fresh.preferences == w.preferences)
        repo.defaults.set(Data(#"{"direction":"invalid","wordWrap":false,"inputFormat":7}"#.utf8),forKey:HexBytesPreferencesRepository.key)
        let fallback = repo.load(); #expect(fallback.direction == .decode && fallback.inputFormat == .pairs && !fallback.wordWrap)
        repo.defaults.set(Data([0]),forKey:HexBytesPreferencesRepository.key); #expect(repo.load() == HexBytesPreferences())
    }
    @Test func closedWindowDoesNotRetainSessionDuringWork() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let gate = Gate()
        var w: HexBytesWorkspaceSession? = .init(repository:repo,worker:{ _,_,_ in await gate.pause(); return .init(status:.success) })
        weak var reference = w
        let task = w!.run(); await gate.wait(); w = nil
        #expect(reference == nil)
        await gate.release(); await task.value
    }
}
