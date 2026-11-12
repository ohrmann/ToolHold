import Foundation
import Testing

@testable import TextCore

@Suite @MainActor struct TextWorkspaceTests {
  @Test func revisionCancellationAndPrivacy() async throws {
    let suite = "TextTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let w = TextWorkspace(id: "race", options: StatisticsOptions(), defaults: defaults) {
      source, _, _, _, _ in
      if source == "slow" { Thread.sleep(forTimeInterval: 0.08) }
      return TextArtifact(output: source, message: source)
    }
    w.input = "slow"
    w.run()
    try await Task.sleep(for: .milliseconds(10))
    w.input = "current"
    w.run()
    for _ in 0..<100 {
      if !w.busy { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(w.artifact?.output == "current")
    w.wordWrap = false
    #expect(w.artifact?.output == "current")
    w.input = "é"
    w.run()
    try await Task.sleep(for: .milliseconds(30))
    w.input = "e\u{301}"
    #expect(w.artifact == nil)
    #expect(!defaults.dictionaryRepresentation().keys.contains { $0.contains(".input") })
    let fresh = TextWorkspace(id: "race", options: StatisticsOptions(), defaults: defaults) {
      s, _, _, _, _ in .init(output: s)
    }
    #expect(fresh.input.isEmpty && fresh.artifact == nil && !fresh.wordWrap)
  }
  @Test func cancelRetainsCurrentArtifact() async throws {
    let w = TextWorkspaces.casing()
    w.automatic = false
    w.input = "hello world"
    w.run()
    for _ in 0..<100 {
      if !w.busy { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let output = w.artifact?.output
    #expect(output == "helloWorld")
    w.run()
    w.cancel()
    try await Task.sleep(for: .milliseconds(30))
    #expect(w.artifact?.output == output)
    w.input = "changed"
    #expect(w.artifact == nil)
  }
}

@Suite @MainActor struct TextSettingsTests {
  @Test func onlyPresentationSettingsPersist() throws {
    let suite = "TextSettings." + UUID().uuidString
    let d = UserDefaults(suiteName: suite)!
    defer { d.removePersistentDomain(forName: suite) }
    let w = TextWorkspace(id: "regex", options: RegexWorkspaceOptions(), defaults: d) {
      _, _, _, _, _ in .init()
    }
    w.input = "never-store-input"
    w.options.pattern = "never-store-pattern"
    w.options.replacement = "never-store-replacement"
    w.options.regex.ignoreCase = true
    let bytes = try #require(d.data(forKey: w.key + ".options"))
    let text = String(decoding: bytes, as: UTF8.self)
    #expect(!text.contains("never-store"))
    #expect(!text.contains("pattern"))
    #expect(!text.contains("replacement"))
    let restored = TextWorkspace(id: "regex", options: RegexWorkspaceOptions(), defaults: d) {
      _, _, _, _, _ in .init()
    }
    #expect(
      restored.input.isEmpty && restored.options.pattern.isEmpty
        && restored.options.replacement.isEmpty)
    #expect(restored.options.regex.ignoreCase)
  }
}
