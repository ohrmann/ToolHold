import Foundation
import Testing
@testable import EncodingCore

@MainActor struct GZipWorkspaceTests {
    private func repository() -> (GZipPreferencesRepository,String) {
        let name = "GZipTests."+UUID().uuidString; return (.init(defaults:UserDefaults(suiteName:name)!),name)
    }
    private actor Gate {
        private var pending: [CheckedContinuation<Void,Never>] = []
        private var waiting: [(Int,CheckedContinuation<Void,Never>)] = []
        func pause() async {
            await withCheckedContinuation { c in
                pending.append(c)
                let ready = waiting.filter { pending.count >= $0.0 }; waiting.removeAll { pending.count >= $0.0 }
                for (_,w) in ready { w.resume() }
            }
        }
        func wait(_ count:Int = 1) async {
            if pending.count >= count { return }
            await withCheckedContinuation { waiting.append((count,$0)) }
        }
        func release(_ index:Int = 0) { pending[index].resume() }
    }
    @Test func pasteCheckConvertOutputCancelAndEmpty() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = GZipWorkspaceSession(repository:repo)
        #expect(w.source != nil && w.canRun && !w.canExport && w.artifact == nil)
        w.input = "hello\r\n\0"; #expect(w.result == nil && !w.busy)
        await w.didPaste()?.value; #expect(w.result?.status == .success && w.artifact == nil && w.canExport)
        await w.run().value; let id = w.artifact?.id, base64 = w.copyText(.base64)
        #expect(base64 != nil && w.canExport)
        await w.run(.check).value; #expect(w.artifact?.id == id)
        let cancelled = w.run(); w.cancel(); await cancelled.value
        #expect(w.artifact?.id == id && w.wasCancelled && w.canExport)
        w.preferences.wordWrap.toggle(); w.preferences.maxOutput = .large; w.preferences.base64Mode = .forgiving
        #expect(w.artifact?.id == id)
        w.preferences.direction = .decompress; #expect(w.artifact == nil && !w.canExport)
        w.input = base64!; await w.run().value
        #expect(w.copyText(.text) == "hello\r\n\0")
        w.preferences.compressionLevel = .best; #expect(w.artifact != nil)
        w.input = GZipProcessorTests.empty.base64EncodedString(); await w.run().value
        #expect(w.copyText(.text) == "" && w.copyText(.base64) == "" && w.canExport)
        w.clear(); #expect(w.artifact == nil && w.result == nil && !w.canExport)
        w.preferences.validateOnPaste = false; #expect(w.didPaste() == nil)
    }
    @Test func staleSourceOptionsAndNewRequestIgnored() async {
        for scenario in 0..<3 {
            let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
            let gate = Gate()
            let w = GZipWorkspaceSession(repository:repo,worker:{ s,o,i,d,h,g,p in
                let result = GZipFileProcessor.run(source:s,options:o,intent:i)
                await gate.pause(); return result // deliberately ignore cancellation after computation
            })
            w.input = "A"; let old = w.run(); await gate.wait()
            if scenario == 0 { w.input = "B" }
            if scenario == 1 { w.preferences.compressionLevel = .best }
            let fresh = w.run(); await gate.wait(2); await gate.release(1); await fresh.value
            let id = w.artifact?.id
            await gate.release(); await old.value
            #expect(w.artifact?.id == id && !w.busy && w.result?.status == .success)
            let bytes = w.artifact?.bytes
            #expect(bytes != nil && GZipProcessor.process(bytes!,options:.init(direction:.decompress)).artifact?.text == (scenario == 0 ? "B" : "A"))
        }
    }
    @Test func fileCheckInvalidatesOldDigestAndExportReplays() async throws {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
        let file = dir.appendingPathComponent("input"); try Data([65]).write(to:file)
        let w = GZipWorkspaceSession(repository:repo); w.usesFile = true
        await w.select(file).value; await w.run().value
        #expect(w.artifact != nil && w.canExport && w.suggestedName == "input.gz")
        try Data([66]).write(to:file); await w.run(.check).value
        #expect(w.artifact == nil && w.canExport)
        await w.run(.check,destination:.init(directory:dir,name:"result.gz")).value
        #expect(w.exportMessage == "Saved result.gz")
        let result = GZipFileProcessor.run(source:.file(dir.appendingPathComponent("result.gz")),options:.init(direction:.decompress))
        #expect(result.artifact?.bytes == Data([66]))
        try Data([67]).write(to:file)
        await w.run(.check,destination:.init(directory:dir,name:"stale.gz")).value
        #expect(w.result?.status == .sourceChanged && !w.canExport && w.artifact == nil)
    }
    @Test func exactSourceIdentityPreferencesAndRelaunch() async throws {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = GZipWorkspaceSession(repository:repo)
        w.input = "é"; await w.run().value; w.input = "e\u{301}"
        #expect(w.artifact == nil)
        w.preferences.compressionLevel = .best; w.preferences.wordWrap = false; w.preferences.maxOutput = .large
        let data = try #require(repo.defaults.data(forKey:GZipPreferencesRepository.key))
        let values = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        #expect(Set(values.keys) == ["direction","compressionLevel","base64Mode","maxOutput","validateOnPaste","wordWrap"])
        let fresh = GZipWorkspaceSession(repository:repo)
        #expect(fresh.preferences == w.preferences && fresh.input.isEmpty && fresh.selectedFile == nil && fresh.artifact == nil && fresh.result == nil && !fresh.usesFile)
        repo.defaults.set(Data(#"{"direction":"bad","compressionLevel":50,"wordWrap":false,"maxOutput":1000}"#.utf8),forKey:GZipPreferencesRepository.key)
        let fallback = repo.load(); #expect(fallback.direction == .compress && fallback.compressionLevel == .default && fallback.maxOutput == .standard && !fallback.wordWrap)
    }
    @Test func resourceCheckKeepsArtifactAndInvalidCheckRemovesIt() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let w = GZipWorkspaceSession(repository:repo,worker:{ s,o,i,d,h,g,p in
            i == .convert ? GZipFileProcessor.run(source:s,options:o) : .init(status:.resourceLimit)
        })
        await w.run().value; let id = w.artifact?.id; await w.run(.check).value
        #expect(w.result?.status == .resourceLimit && w.artifact?.id == id)
        let invalid = GZipWorkspaceSession(repository:repo,worker:{ s,o,i,d,h,g,p in
            i == .convert ? GZipFileProcessor.run(source:s,options:o) : .init(status:.invalidGZip)
        })
        await invalid.run().value; await invalid.run(.check).value; #expect(invalid.artifact == nil)
    }
    @Test func cancellationAndWindowLifetimeDoNotRetainWorkspaces() async {
        let (repo,name) = repository(); defer { repo.defaults.removePersistentDomain(forName:name) }
        let gate = Gate()
        var workspace:GZipWorkspaceSession? = .init(repository:repo,worker:{ _,_,_,_,_,_,_ in await gate.pause(); return .init(status:.success) })
        weak var reference = workspace
        let work = workspace!.run(); await gate.wait(); workspace = nil
        #expect(reference == nil)
        await gate.release(); await work.value
    }
}
