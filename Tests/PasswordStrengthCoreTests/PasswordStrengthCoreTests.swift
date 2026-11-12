import Foundation
import Testing
@testable import PasswordStrengthCore
struct PasswordStrengthCoreTests {
    @Test func actualJavaScriptCoreAndWholeInputBoundary() async throws {
        let worker = PasswordStrengthWorker()
        let weak = await worker.estimate(.init(password:"password"))
        #expect(weak.status == .estimated); #expect(weak.score == 0)
        let stronger = await worker.estimate(.init(password:"8nV!gZ2@rL5#qY9$dX4"))
        #expect(stronger.status == .estimated && stronger.score == 4)
        #expect((await worker.estimate(.init(password:String(repeating:"a",count:256)))).status == .estimated)
        #expect((await worker.estimate(.init(password:String(repeating:"a",count:257)))).status == .resourceLimit)
        #expect((await worker.estimate(.init(password:""))).status == .empty)
        #expect((await worker.estimate(.init(password:"a\nb"))).status == .invalidInput)
    }
    @Test func unicodeSpacesPersonalWordsAndInjectionAreData() async {
        let worker = PasswordStrengthWorker()
        for password in ["пароль", "😀e\u{301}漢字", " leading and trailing ", "'); throw new Error('secret'); //"] {
            let r = await worker.estimate(.init(password:password))
            #expect(r.status == .estimated); #expect(r.characters == password.count); #expect(r.utf8Bytes == password.utf8.count)
        }
        let before = await worker.estimate(.init(password:"XylophonicZebra981"))
        let contextual = await worker.estimate(.init(password:"XylophonicZebra981",personalWords:"XylophonicZebra981"))
        #expect((contextual.guesses ?? .infinity) < (before.guesses ?? 0))
        let after = await worker.estimate(.init(password:"XylophonicZebra981"))
        #expect(after.guesses == before.guesses)
    }
    @Test func boundsAndScenarioFormatting() async {
        let worker = PasswordStrengthWorker()
        #expect((await worker.estimate(.init(password:"hello",personalWords:String(repeating:"a",count:65)))).status == .resourceLimit)
        #expect(PasswordAttackScenario.fast.duration(guesses:1) == "Less than a second")
        #expect(PasswordAttackScenario.slow.duration(guesses:.infinity).contains("100 million"))
    }
}

@MainActor struct PasswordStrengthWorkspaceTests {
    @Test func latestRequestClearAndUIOnlyPersistence() async {
        let name = "test.strength."+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer {defaults.removePersistentDomain(forName:name)}
        let session = PasswordStrengthWorkspaceSession(defaults:defaults);session.autoEstimate = false
        session.password = "password";let first = session.estimate()
        for i in 0..<20 {session.password = "synthetic-change-\(i)";session.estimate()}
        session.password = "correct-horse-synthetic-mango-49";session.estimate()
        await first.value
        #expect(session.result?.status == .estimated && session.result?.characters == session.password.count)
        let job = session.estimate();session.clear();await job.value
        #expect(session.password.isEmpty && session.personalWords.isEmpty && session.result == nil)
        let fresh = PasswordStrengthWorkspaceSession(defaults:defaults)
        #expect(fresh.password.isEmpty && fresh.personalWords.isEmpty && fresh.result == nil && !fresh.revealed && !fresh.autoEstimate)
        #expect(!session.accept("line\nline") && session.password.isEmpty)
        #expect(!session.accept(String(repeating:"a",count:4097)))
    }
}
