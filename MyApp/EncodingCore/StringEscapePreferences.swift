import Foundation

/// Only UI preferences are persisted. Source, artifacts, diagnostics and history remain window-local.
struct StringEscapePreferences: Codable, Equatable {
    var language = StringEscapeLanguage.json
    var direction = StringEscapeDirection.escape
    var representation = StringEscapeRepresentation.quoted
    var quote = StringEscapeQuote.double
    var nonASCII = false
    var validateOnPaste = true
    var wordWrap = true
    var options: StringEscapeOptions { .init(language: language, direction: direction, representation: representation, quote: quote, nonASCII: nonASCII) }
    private enum CodingKeys: String, CodingKey { case language, direction, representation, quote, nonASCII, validateOnPaste, wordWrap }
    init() {}
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        language = (try? v.decode(StringEscapeLanguage.self, forKey: .language)) ?? .json
        direction = (try? v.decode(StringEscapeDirection.self, forKey: .direction)) ?? .escape
        representation = (try? v.decode(StringEscapeRepresentation.self, forKey: .representation)) ?? .quoted
        quote = (try? v.decode(StringEscapeQuote.self, forKey: .quote)) ?? .double
        nonASCII = (try? v.decode(Bool.self, forKey: .nonASCII)) ?? false
        validateOnPaste = (try? v.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? v.decode(Bool.self, forKey: .wordWrap)) ?? true
    }
}
struct StringEscapePreferencesRepository {
    static let key = "developerToolbox.stringEscape.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> StringEscapePreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(StringEscapePreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: StringEscapePreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
