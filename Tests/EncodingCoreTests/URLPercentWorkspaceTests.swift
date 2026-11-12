import Foundation
import Testing
@testable import EncodingCore

@MainActor struct URLPercentWorkspaceTests {
    private let suite = "URLPercentTests." + UUID().uuidString
    private func repository() -> URLPercentPreferencesRepository {
        .init(defaults: UserDefaults(suiteName: suite)!)
    }
    @Test func checkCancelPasteAndInvalidation() async throws {
        let repo = repository(); defer { repo.defaults.removePersistentDomain(forName: suite) }
        let session = URLPercentWorkspaceSession(repository: repo)
        session.preferences.direction = .decode
        session.input = "%61"
        #expect(session.result == nil && !session.busy)
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        await session.run().value
        #expect(session.output == "a" && session.canCopy)
        await session.run(.check).value
        #expect(session.output == "a" && session.canCopy)
        let repeatWork = session.run(); session.cancel(); await repeatWork.value
        #expect(session.wasCancelled && session.output == "a" && session.canCopy)
        session.preferences.wordWrap.toggle(); session.preferences.preserveExistingEscapes.toggle()
        #expect(session.output == "a")
        session.refreshPreferences()
        #expect(session.output == "a")
        session.input = "%62"
        #expect(session.result == nil && session.output == nil && !session.canCopy)
        session.preferences.validateOnPaste = false
        #expect(session.didPaste() == nil)
        await session.run().value
        session.preferences.profile = .formField
        #expect(session.output == nil)
        session.input = "%FF"; await session.run().value
        #expect(session.result?.status == .bytesOnly && !session.canCopy)
        session.clear()
        #expect(session.input.isEmpty && session.result == nil && session.output == nil)
        let fresh = URLPercentWorkspaceSession(repository: repo)
        #expect(fresh.input.isEmpty && fresh.result == nil && fresh.artifact == nil)
    }
    @Test func effectiveOptionsAndExactSourceRevision() async {
        let repo = repository(); defer { repo.defaults.removePersistentDomain(forName: suite) }
        let session = URLPercentWorkspaceSession(repository: repo)
        session.preferences.direction = .encode
        session.input = "é"; await session.run().value
        let source = session.sourceRevision, output = session.output
        session.preferences.preserveExistingEscapes.toggle()
        #expect(session.output == output)
        session.input = "e\u{301}"
        #expect(session.sourceRevision != source && session.output == nil)
        await session.run().value
        #expect(session.output != output)
        session.preferences.profile = .uriText
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
        let session = URLPercentWorkspaceSession(repository: repo, worker: { source,options,intent in
            let value = URLPercentProcessor.process(source, options: options, intent: intent)
            if source == "%61" { await gate.pause() }
            return value
        })
        session.preferences.direction = .decode
        session.input = "%61"; let old = session.run()
        await gate.waitForStart()
        session.input = "%62"; session.preferences.profile = .uriText
        await session.run().value
        await gate.resume(); await old.value
        #expect(session.output == "b" && session.result?.status == .success && !session.busy)
    }
}
