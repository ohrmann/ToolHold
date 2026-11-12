import Foundation

/// Only UI choices are persisted. No source, result, diagnostic, URL or history fields.
struct URLPercentPreferences: Codable, Equatable {
    var direction = URLPercentDirection.encode
    var profile = URLPercentProfile.component
    var preserveExistingEscapes = true
    var validateOnPaste = true
    var wordWrap = true
    var options: URLPercentOptions { .init(direction: direction, profile: profile, preserveExistingEscapes: preserveExistingEscapes) }
    private enum CodingKeys: String, CodingKey { case direction, profile, preserveExistingEscapes, validateOnPaste, wordWrap }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? values.decode(URLPercentDirection.self, forKey: .direction)) ?? .encode
        profile = (try? values.decode(URLPercentProfile.self, forKey: .profile)) ?? .component
        preserveExistingEscapes = (try? values.decode(Bool.self, forKey: .preserveExistingEscapes)) ?? true
        validateOnPaste = (try? values.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? values.decode(Bool.self, forKey: .wordWrap)) ?? true
    }
}
struct URLPercentPreferencesRepository {
    static let key = "developerToolbox.urlPercent.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> URLPercentPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(URLPercentPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: URLPercentPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
