import Foundation
import Testing
@testable import DigestCore
import EncodingCore

struct DigestWorkspaceTests {
    @Test @MainActor func exactSourceRevisionAndComparison() async throws {
        let name = "Digest-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let s = DigestWorkspaceSession(defaults: defaults)
        s.text = "abc"; await s.run()?.value
        #expect(s.current && s.canCopy)
        s.expected = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        #expect(s.comparison == "Match")
        s.expected = String(repeating: "0", count: 64); #expect(s.comparison == "Mismatch")
        s.expected = "0"; #expect(s.comparison.hasPrefix("Invalid expected value"))
        let bytes = s.artifact?.values
        s.preferences.format = .base64; #expect(s.current && s.artifact?.values == bytes)
        s.text = "é"; await s.run()?.value; #expect(s.current)
        s.text = "e\u{301}"; #expect(!s.current && !s.canCopy)
        await s.run()?.value; #expect(s.current && s.artifact?.bytes == 3)
        var copied = ""; s.copyAll { copied = $0 }; #expect(copied.hasPrefix("SHA-256: "))
        let fresh = DigestWorkspaceSession(defaults: defaults)
        #expect(fresh.text.isEmpty && fresh.key.isEmpty && fresh.expected.isEmpty && fresh.file == nil && fresh.artifact == nil)
        #expect(fresh.preferences.format == .base64)
        s.clear(); #expect(s.artifact == nil && s.text.isEmpty && !s.canCopy)
    }
    @Test @MainActor func hmacSeparateStateAndConsent() async throws {
        let name = "Hmac-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let s = DigestWorkspaceSession(isHMAC: true, defaults: defaults)
        await s.run()?.value; #expect(s.issue?.field == "key")
        s.allowEmptyKey = true; await s.run()?.value; #expect(s.current && s.artifact?.keyBytes == 0)
        s.key = "é"; await s.run()?.value; #expect(s.current)
        s.key = "e\u{301}"; #expect(!s.current)
        s.key = "secret"; s.text = "message"; await s.run()?.value
        #expect(s.artifact?.keyBytes == 6 && s.current)
        s.concealSecrets(); #expect(s.keyHidden && s.resultHidden && s.key == "secret")
        let fresh = DigestWorkspaceSession(isHMAC: true, defaults: defaults)
        #expect(!fresh.allowEmptyKey && fresh.key.isEmpty && !fresh.keyHidden)
        let hash = DigestWorkspaceSession(defaults: defaults); #expect(hash.preferences.format == .hex)
        s.clear(); #expect(s.key.isEmpty && !s.allowEmptyKey && s.artifact == nil)
    }
    actor Gate {
        var first: CheckedContinuation<DigestResult, Never>?
        var calls = 0
        func process(_ r: DigestRequest) async -> DigestResult {
            calls += 1
            if calls == 1 { return await withCheckedContinuation { first = $0 } }
            return DigestProcessor.run(r)
        }
        func finish() { first?.resume(returning: DigestProcessor.run(.init(text: "old"))); first = nil }
    }
    @Test @MainActor func revisionRaceAndCancelledRecalculation() async throws {
        let name = "Digest-race-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let gate = Gate(), s = DigestWorkspaceSession(defaults: defaults, worker: { r, _ in await gate.process(r) })
        s.text = "old"; let first = s.run()
        for _ in 0..<100 where await gate.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        s.text = "new"; s.run(); await gate.finish(); await first?.value
        #expect(s.current && s.artifact?.values == DigestProcessor.run(.init(text: "new")).artifact?.values)
        let values = s.artifact?.values
        let second = s.run(); s.cancel(); await second?.value
        #expect(s.current && s.artifact?.values == values && s.issue?.status == .cancelled)
        s.text = "changed"; #expect(!s.current)
        var copied = false; s.copyAll { _ in copied = true }; #expect(!copied)
    }
    @Test @MainActor func fileLifecycleAndPrefs() async throws {
        let name = "Digest-file-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("test".utf8).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let s = DigestWorkspaceSession(defaults: defaults)
        s.preferences.mode = .file; #expect(!s.canRun)
        await s.chooseFile(url).value; #expect(s.file?.size == 4 && s.canRun)
        await s.run()?.value; #expect(s.current && s.artifact?.bytes == 4)
        let fresh = DigestWorkspaceSession(defaults: defaults); #expect(fresh.preferences.mode == .file && fresh.file == nil && !fresh.canRun)
        s.removeFile(); #expect(s.file == nil && !s.current)
        let data = try #require(defaults.data(forKey: s.preferenceKey))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(keys.keys) == ["mode","algorithms","hmac","keyProfile","format","uppercase","expectedProfile"])
        #expect(!String(decoding: data, as: UTF8.self).contains(url.path))
    }
}
