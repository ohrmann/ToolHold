import Foundation
import Testing
@testable import EncodingCore

struct URLPercentPreferencesTests {
    @Test func allowlistAndIndependentCorruptionFallbacks() throws {
        let suite = "URLPercentPreferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let repo = URLPercentPreferencesRepository(defaults:defaults)
        #expect(repo.load() == URLPercentPreferences())
        var prefs = URLPercentPreferences()
        prefs.direction = .decode; prefs.profile = .uriText; prefs.preserveExistingEscapes = false
        prefs.validateOnPaste = false; prefs.wordWrap = false
        repo.save(prefs)
        #expect(repo.load() == prefs)
        let object = try #require(JSONSerialization.jsonObject(with:defaults.data(forKey:URLPercentPreferencesRepository.key)!) as? [String:Any])
        #expect(Set(object.keys) == ["direction","profile","preserveExistingEscapes","validateOnPaste","wordWrap"])
        defaults.set(Data(#"{"profile":"future","wordWrap":false,"direction":"decode","preserveExistingEscapes":7}"#.utf8),forKey:URLPercentPreferencesRepository.key)
        let fallback = repo.load()
        #expect(fallback.profile == .component && fallback.direction == .decode && !fallback.wordWrap && fallback.preserveExistingEscapes)
        defaults.set(Data("broken".utf8),forKey:URLPercentPreferencesRepository.key)
        #expect(repo.load() == .init())
        #expect(defaults.data(forKey:Base64PreferencesRepository.key) == nil)
        #expect(defaults.data(forKey:Base64FilePreferencesRepository.key) == nil)
    }
}
