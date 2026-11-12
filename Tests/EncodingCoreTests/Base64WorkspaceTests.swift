import Foundation
import Testing
@testable import EncodingCore

@MainActor struct Base64WorkspaceTests {
    private let suite = "Base64Tests." + UUID().uuidString
    private func repository() -> Base64PreferencesRepository {
        .init(defaults: UserDefaults(suiteName: suite)!)
    }
    @Test func checkCancelPasteAndInvalidation() async throws {
        let repo = repository(); defer { repo.defaults.removePersistentDomain(forName: suite) }
        let session = Base64WorkspaceSession(repository: repo)
        session.input = "YQ=="
        #expect(session.result == nil && !session.busy)
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        await session.run().value
        #expect(session.output == "a" && session.canCopy)
        await session.run(.check).value
        #expect(session.output == "a" && session.canCopy)
        let repeatWork = session.run(); session.cancel(); await repeatWork.value
        #expect(session.wasCancelled && session.output == "a" && session.canCopy)
        session.preferences.wordWrap.toggle(); session.preferences.urlPadding.toggle()
        #expect(session.output == "a")
        session.refreshPreferences()
        #expect(session.output == "a")
        session.input = "Yg=="
        #expect(session.result == nil && session.output == nil && !session.canCopy)
        session.preferences.validateOnPaste = false
        #expect(session.didPaste() == nil)
        await session.run().value
        session.preferences.textEncoding = .ascii
        #expect(session.output == nil)
        session.input = "/w=="; await session.run().value
        #expect(session.result?.status == .bytesOnly && !session.canCopy)
        session.clear()
        #expect(session.input.isEmpty && session.result == nil && session.output == nil)
        let fresh = Base64WorkspaceSession(repository: repo)
        #expect(fresh.input.isEmpty && fresh.result == nil && fresh.artifact == nil)
    }
    @Test func effectiveOptionsAndExactSourceRevision() async {
        let repo = repository(); defer { repo.defaults.removePersistentDomain(forName: suite) }
        let session = Base64WorkspaceSession(repository: repo)
        session.preferences.direction = .encode
        session.input = "é"; await session.run().value
        let source = session.sourceRevision, output = session.output
        session.preferences.decodeMode = .forgiving
        #expect(session.output == output)
        session.input = "e\u{301}"
        #expect(session.sourceRevision != source && session.output == nil)
        await session.run().value
        #expect(session.output != output)
        session.preferences.alphabet = .urlSafe
        #expect(session.output == nil)
    }
    @Test func staleNonCooperativeWorkerNeverPublishes() async {
        actor Gate {
            var continuation: CheckedContinuation<Void,Never>?
            var started = false
            func pause() async { await withCheckedContinuation { continuation = $0; started = true } }
            func waitForStart() async { while !started { await Task.yield() } }
            func resume() { continuation?.resume(); continuation = nil }
        }
        let gate = Gate()
        let repo = repository(); defer { repo.defaults.removePersistentDomain(forName: suite) }
        let session = Base64WorkspaceSession(repository: repo, worker: { source,options,intent in
            let value = Base64Processor.process(source, options: options, intent: intent)
            if source == "YQ==" { await gate.pause() }
            return value
        })
        session.input = "YQ=="; let old = session.run()
        await gate.waitForStart()
        session.input = "Yg=="; session.preferences.alphabet = .urlSafe
        await session.run().value
        await gate.resume(); await old.value
        #expect(session.output == "b" && session.result?.status == .success && !session.busy)
    }
}
