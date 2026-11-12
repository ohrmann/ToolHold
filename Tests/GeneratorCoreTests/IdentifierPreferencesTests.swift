import Foundation
import Testing
@testable import GeneratorCore

struct IdentifierPreferencesTests {
    @Test func preferencesAllowlistAndSafeFallbacks() throws {
        var prefs = IdentifierPreferences(); prefs.kind = .nanoID; prefs.nanoAlphabetPreset = .custom; prefs.count = 100; prefs.nanoLength = 256
        let data = try JSONEncoder().encode(prefs)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == ["count", "kind", "nanoAlphabetPreset", "nanoLength", "ulidMonotonic", "uuidCase"])
        let restored = try JSONDecoder().decode(IdentifierPreferences.self, from: data)
        #expect(restored.nanoAlphabetPreset == .urlSafe && restored.count == 100 && restored.nanoLength == 256)
        let corrupt = Data(#"{"kind":"future","count":999999,"nanoLength":0,"uuidCase":null,"ulidMonotonic":"yes","nanoAlphabetPreset":"custom","values":["private"]}"#.utf8)
        #expect(try JSONDecoder().decode(IdentifierPreferences.self, from: corrupt) == IdentifierPreferences())
        #expect(try JSONDecoder().decode(IdentifierPreferences.self, from: Data("{}".utf8)) == IdentifierPreferences())
    }
    @Test @MainActor func newSessionRestoresOnlyUIChoices() async throws {
        let name = "T022-prefs-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = IdentifierPreferencesRepository(defaults: defaults)
        defaults.set(Data("broken".utf8), forKey: IdentifierPreferencesRepository.key)
        #expect(repository.load() == IdentifierPreferences())
        let a = IdentifierWorkspaceSession(repository: repository)
        a.preferences.kind = .nanoID; a.countText = "5"; a.lengthText = "12"
        a.preferences.nanoAlphabetPreset = .custom; a.customAlphabet = "ab"
        await a.run()?.value
        #expect(a.batch?.values.count == 5)
        let b = IdentifierWorkspaceSession(repository: repository)
        #expect(b.batch == nil && b.customAlphabet.isEmpty && b.selection == nil)
        #expect(b.preferences.kind == .nanoID && b.countText == "5" && b.lengthText == "12")
        #expect(b.preferences.nanoAlphabetPreset == .urlSafe && b.statusText == "Ready")
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox.identifierGenerator") } == [IdentifierPreferencesRepository.key])
        let saved = try #require(defaults.data(forKey: IdentifierPreferencesRepository.key))
        #expect(!String(decoding: saved, as: UTF8.self).contains("customAlphabet"))
    }
}
