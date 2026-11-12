import Foundation
import Testing
@testable import EncodingCore

@MainActor struct Base64FileWorkspaceTests {
    @Test func pasteCheckArtifactOptionsAndPrivacy() async throws {
        let name = "T013WorkspaceTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let repo = Base64FilePreferencesRepository(defaults: defaults), session = Base64FileWorkspaceSession(repository: .init(defaults: defaults))
        #expect(session.preferences.direction == .encode && session.source == nil)
        session.preferences.direction = .decode; session.input = "YQ=="
        #expect(session.result == nil)
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.artifact == nil)
        await session.run().value
        #expect(session.artifact?.imageBytes == Data([97]))
        await session.run(.check).value
        #expect(session.artifact?.imageBytes == Data([97]))
        let repeatWork = session.run(); session.cancel(); await repeatWork.value
        #expect(session.wasCancelled && session.artifact?.imageBytes == Data([97]))
        session.preferences.wordWrap.toggle(); session.preferences.urlPadding.toggle()
        #expect(session.artifact != nil)
        session.input += "!"; #expect(session.result == nil && session.artifact == nil)
        session.preferences.validateOnPaste = false; #expect(session.didPaste() == nil)
        session.preferences.format = .dataURL
        let loaded = Base64FileWorkspaceSession(repository: repo)
        #expect(loaded.input.isEmpty && loaded.source != nil && loaded.selectedFile == nil && loaded.artifact == nil && loaded.preferences.format == .dataURL)
        let data = try #require(defaults.data(forKey: Base64FilePreferencesRepository.key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String:Any])
        #expect(Set(object.keys) == Set(["direction","format","alphabet","decodeMode","urlPadding","validateOnPaste","wordWrap"]))
        #expect(!String(decoding: data,as: UTF8.self).contains("YQ"))
    }
    @Test func staleWorkerAndExactSourceNeverPublish() async {
        actor Gate {
            var continuation: CheckedContinuation<Void,Never>?
            var started = false
            func pause() async { await withCheckedContinuation { continuation = $0; started = true } }
            func wait() async { while !started { await Task.yield() } }
            func resume() { continuation?.resume(); continuation = nil }
        }
        let gate = Gate(), name = "T013Race." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let session = Base64FileWorkspaceSession(repository: .init(defaults: defaults),worker: { source,opts,intent,destination,digest,operation,progress in
            let result = Base64FileProcessor.run(source: source,options: opts,intent: intent)
            if case .text("YQ==") = source { await gate.pause() }
            return result
        })
        session.preferences.direction = .decode; session.input = "YQ=="
        let old = session.run(); await gate.wait()
        session.input = "Yg=="; await session.run().value
        await gate.resume(); await old.value
        #expect(session.artifact?.imageBytes == Data([98]) && !session.busy)
        session.input = "é"; let revision = session.sourceRevision
        session.input = "e\u{301}"; #expect(session.sourceRevision != revision)
        session.preferences.wordWrap.toggle(); #expect(session.sourceRevision != revision)
        session.clear(); #expect(session.input.isEmpty && session.result == nil)
    }
    @Test func cleanupFailureSurvivesCancelledRequest() async {
        actor Gate {
            var ready = false
            var continuation: CheckedContinuation<Void,Never>?
            func pause() async { await withCheckedContinuation { continuation = $0; ready = true } }
            func wait() async { while !ready { await Task.yield() } }
            func resume() { continuation?.resume(); continuation = nil }
        }
        let gate = Gate(), name = "T013Cleanup." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let session = Base64FileWorkspaceSession(repository: .init(defaults: defaults),worker: { _,_,_,_,_,_,_ in
            await gate.pause()
            var failure = Base64FileFailure(.cancelled,"Export cancelled; partial cleanup failed.")
            failure.cleanupPath = "/synthetic-fixture/.DeveloperToolbox-test.partial"
            return .init(status: .cancelled,failure: failure)
        })
        session.preferences.direction = .decode; session.input = "YQ=="
        let work = session.run(); await gate.wait(); session.cancel()
        await gate.resume(); await work.value
        #expect(session.wasCancelled && session.cleanupWarning?.contains("partial") == true)
        session.input = "Yg=="; #expect(session.cleanupWarning != nil)
        session.dismissCleanupWarning(); #expect(session.cleanupWarning == nil)
    }
    @Test func checkingExternallyChangedFileInvalidatesOldArtifact() async throws {
        let name = "T013ExternalChange." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories:true)
        defer { defaults.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("source.bin")
        try Data("abc".utf8).write(to:url)
        let session = Base64FileWorkspaceSession(repository:.init(defaults:defaults))
        await session.select(url).value; await session.run().value
        #expect(session.artifact?.copyText == "YWJj" && session.canCopy)
        await session.run(.check).value
        #expect(session.artifact?.copyText == "YWJj")
        try Data("xyz".utf8).write(to:url)
        await session.run(.check).value
        #expect(session.result?.status == .success && session.artifact == nil && !session.canCopy)
        await session.run(destination:.init(directory:folder,name:"output.txt")).value
        #expect(session.result?.status == .success && session.artifact?.copyText == "eHl6")
        #expect(try Data(contentsOf:folder.appendingPathComponent("output.txt")) == Data("eHl6".utf8))
    }
    @Test func preferenceCorruptionAndHiddenOptions() throws {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Base64FilePreferences.self,from: Data(#"{"direction":"future","format":"dataURL","wordWrap":false,"urlPadding":"bad"}"#.utf8))
        #expect(value.direction == .encode && value.format == .dataURL && !value.wordWrap && !value.urlPadding)
        var preferences = Base64FilePreferences()
        let before = preferences.options(mime: "image/png")
        preferences.decodeMode = .forgiving
        #expect(preferences.options(mime: "image/png") == before)
        preferences.format = .dataURL; let dataURL = preferences.options(mime: "image/png")
        preferences.alphabet = .urlSafe; preferences.urlPadding = true
        #expect(preferences.options(mime: "image/png") == dataURL)
        #expect(Base64FileDisplay.safeLabel("image\u{202e}gpj\n").contains("\\u{202e}"))
    }
}
