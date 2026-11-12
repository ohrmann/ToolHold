import Foundation

/// UI-only allowlist. Working strings, bytes and diagnostics never enter this model.
struct Base64Preferences: Codable, Equatable {
    var direction = Base64Direction.decode
    var alphabet = Base64Alphabet.standard
    var textEncoding = Base64TextEncoding.utf8
    var decodeMode = Base64DecodeMode.strict
    var urlPadding = false
    var validateOnPaste = true
    var wordWrap = true
    var options: Base64Options { .init(direction: direction, alphabet: alphabet, encoding: textEncoding, decodeMode: decodeMode, urlPadding: urlPadding) }
    private enum CodingKeys: String, CodingKey { case direction, alphabet, textEncoding, decodeMode, urlPadding, validateOnPaste, wordWrap }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? values.decode(Base64Direction.self, forKey: .direction)) ?? .decode
        alphabet = (try? values.decode(Base64Alphabet.self, forKey: .alphabet)) ?? .standard
        textEncoding = (try? values.decode(Base64TextEncoding.self, forKey: .textEncoding)) ?? .utf8
        decodeMode = (try? values.decode(Base64DecodeMode.self, forKey: .decodeMode)) ?? .strict
        urlPadding = (try? values.decode(Bool.self, forKey: .urlPadding)) ?? false
        validateOnPaste = (try? values.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? values.decode(Bool.self, forKey: .wordWrap)) ?? true
    }
}
struct Base64PreferencesRepository {
    static let key = "developerToolbox.base64.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> Base64Preferences {
        guard let data = defaults.data(forKey: Self.key), let settings = try? JSONDecoder().decode(Base64Preferences.self, from: data) else { return .init() }
        return settings
    }
    func save(_ settings: Base64Preferences) { defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key) }
}
