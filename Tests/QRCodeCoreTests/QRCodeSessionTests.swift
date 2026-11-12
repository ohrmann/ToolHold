import Testing
import Foundation
@testable import QRCodeCore

@MainActor struct QRCodeSessionTests {
    func wait(_ session: QRCodeWorkspaceSession) async throws {
        for _ in 0..<400 { if !session.busy { return }; try await Task.sleep(for:.milliseconds(10)) }
        Issue.record("QR worker timed out")
    }
    @Test func statePrivacyCopyAndReuse() async throws {
        let name = "qr-test-"+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let s = QRCodeWorkspaceSession(defaults:defaults)
        #expect(s.input.isEmpty && s.artifact == nil && !s.canOutput)
        s.input = "first 🌍"; s.generate(); try await wait(s)
        #expect(s.canOutput)
        let first = try #require(s.artifact)
        s.preferences.style = .rounded; try await wait(s)
        #expect(s.canOutput && s.artifact?.matrix.payload == first.matrix.payload)
        var copied: QRExport?
        await s.prepare(.png) { copied = $0 }?.value
        #expect(copied?.format == .png)
        s.input = "different"; #expect(!s.isCurrent && !s.canOutput)
        s.generate(); try await wait(s)
        s.preferences.format = .svg; #expect(s.canOutput) // UI format alone does not regenerate.
        s.cancel(); #expect(s.canOutput)
        s.setLogo(try QRCodeTests.logo()); try await wait(s); #expect(s.artifact?.matrix.correction == .h)
        let fresh = QRCodeWorkspaceSession(defaults:defaults)
        #expect(fresh.input.isEmpty && fresh.logo == nil && fresh.artifact == nil)
        #expect(fresh.preferences.style == .rounded && fresh.preferences.format == .svg)
        let stored = String(decoding:defaults.data(forKey:QRCodeWorkspaceSession.key)!,as:UTF8.self)
        #expect(!stored.contains("different") && !stored.contains("payload") && !stored.contains("png"))
        s.resetAppearance(); try await wait(s)
        #expect(s.input == "different" && s.logo == nil && s.preferences == QRPreferences())
        s.clear(); #expect(s.input.isEmpty && s.artifact == nil && !s.canOutput)
        defaults.set(Data("broken".utf8),forKey:QRCodeWorkspaceSession.key)
        #expect(QRCodeWorkspaceSession(defaults:defaults).preferences == QRPreferences())
    }
    @Test func staleUncooperativeWorkerAndCopy() async throws {
        let name = "qr-race-"+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let a = try QRCodeProcessor.generate(source:"old",preferences:.init(),logo:nil)
        let b = try QRCodeProcessor.generate(source:"new",preferences:.init(),logo:nil)
        let s = QRCodeWorkspaceSession(defaults:defaults) { source,_,_,_ in
            // Deliberately ignore cancellation, as a system call may do.
            await withCheckedContinuation { c in DispatchQueue.global().asyncAfter(deadline:.now()+0.1) { c.resume() } }
            return source == "old" ? a : b
        }
        s.input = "old"; s.generate()
        try await Task.sleep(for:.milliseconds(20))
        s.input = "new"; s.generate(); try await wait(s)
        #expect(s.artifact?.matrix.payload == Data("new".utf8))
        var didCopy = false
        let task = s.prepare(.png) { _ in didCopy = true }
        s.clear(); await task?.value
        #expect(!didCopy && s.artifact == nil)
        s.input = "old"; s.generate(); try await Task.sleep(for:.milliseconds(10)); s.clear()
        try await Task.sleep(for:.milliseconds(150)); #expect(s.artifact == nil && !s.busy)
    }
}
