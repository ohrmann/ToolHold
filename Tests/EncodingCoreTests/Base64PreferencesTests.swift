import Foundation
import Testing
@testable import EncodingCore

struct Base64PreferencesTests {
    @Test func allowlistMigrationAndCorruption() throws {
        let suite = "Base64PreferencesTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = Base64PreferencesRepository(defaults: defaults)
        var prefs = Base64Preferences()
        prefs.direction = .encode; prefs.alphabet = .urlSafe; prefs.textEncoding = .utf16BE
        prefs.decodeMode = .forgiving; prefs.urlPadding = true; prefs.validateOnPaste = false; prefs.wordWrap = false
        repository.save(prefs)
        #expect(repository.load() == prefs)
        let object = try #require(JSONSerialization.jsonObject(with: defaults.data(forKey: Base64PreferencesRepository.key)!) as? [String:Any])
        #expect(Set(object.keys) == ["direction","alphabet","textEncoding","decodeMode","urlPadding","validateOnPaste","wordWrap"])
        defaults.set(Data(#"{"alphabet":"future","wordWrap":false,"decodeMode":"forgiving","textEncoding":7}"#.utf8), forKey: Base64PreferencesRepository.key)
        let migrated = repository.load()
        #expect(migrated.alphabet == .standard && !migrated.wordWrap && migrated.decodeMode == .forgiving && migrated.textEncoding == .utf8)
        defaults.set(Data("broken".utf8), forKey: Base64PreferencesRepository.key)
        #expect(repository.load() == Base64Preferences())
    }
}
