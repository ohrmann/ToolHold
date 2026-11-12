import Foundation

/// Explicit persistence allowlist. No values, custom alphabet, exclusion text or visibility state.
struct SecretGeneratorPreferences: Codable, Equatable, Sendable {
    var length = 13
    var passwordCount = 1
    var lowercase = true
    var uppercase = true
    var digits = true
    var symbols = true
    var requireEveryGroup = true
    var excludeSimilar = false
    var wordCount = 6
    var phraseCount = 1
    var separator = PassphraseSeparator.hyphen
    var letterCase = PassphraseCase.lowercase
    var appendDigit = false
    var dictionaryID = PassphraseWordlist.identifier
    init() {}
    enum CodingKeys: String, CodingKey {
        case length, passwordCount, lowercase, uppercase, digits, symbols, requireEveryGroup, excludeSimilar
        case wordCount, phraseCount, separator, letterCase, appendDigit, dictionaryID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            guard let n = try? c.decode(Int.self, forKey: key), range.contains(n) else { return fallback }; return n
        }
        length = number(.length, 13, 8...128); passwordCount = number(.passwordCount, 1, 1...1000)
        wordCount = number(.wordCount, 6, 4...16); phraseCount = number(.phraseCount, 1, 1...1000)
        lowercase = (try? c.decode(Bool.self, forKey: .lowercase)) ?? true
        uppercase = (try? c.decode(Bool.self, forKey: .uppercase)) ?? true
        digits = (try? c.decode(Bool.self, forKey: .digits)) ?? true
        symbols = (try? c.decode(Bool.self, forKey: .symbols)) ?? true
        requireEveryGroup = (try? c.decode(Bool.self, forKey: .requireEveryGroup)) ?? true
        excludeSimilar = (try? c.decode(Bool.self, forKey: .excludeSimilar)) ?? false
        separator = (try? c.decode(PassphraseSeparator.self, forKey: .separator)) ?? .hyphen
        letterCase = (try? c.decode(PassphraseCase.self, forKey: .letterCase)) ?? .lowercase
        appendDigit = (try? c.decode(Bool.self, forKey: .appendDigit)) ?? false
        // Only one approved dictionary; an unknown saved ID safely returns to the bundled default.
        dictionaryID = PassphraseWordlist.identifier
    }
}
struct SecretGeneratorPreferencesRepository {
    let defaults: UserDefaults
    let kind: SecretGeneratorKind
    var key: String { "developerToolbox.\(kind.rawValue)Generator.preferences.v1" }
    init(kind: SecretGeneratorKind, defaults: UserDefaults? = nil) {
        self.kind = kind
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> SecretGeneratorPreferences {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(SecretGeneratorPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: SecretGeneratorPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
}
