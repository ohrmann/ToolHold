import Foundation

/// An explicit allowlist: no URL, source, output, row IDs, credentials or history.
struct URLQueryPreferences: Codable, Equatable {
    var profile = URLQueryProfile.percent
    var parseOnPaste = true
    var wordWrap = true
    private enum CodingKeys: String, CodingKey { case profile, parseOnPaste, wordWrap }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        profile = (try? values.decode(URLQueryProfile.self,forKey:.profile)) ?? .percent
        parseOnPaste = (try? values.decode(Bool.self,forKey:.parseOnPaste)) ?? true
        wordWrap = (try? values.decode(Bool.self,forKey:.wordWrap)) ?? true
    }
}
struct URLQueryPreferencesRepository {
    static let key = "developerToolbox.urlQuery.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName:"developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> URLQueryPreferences {
        guard let data = defaults.data(forKey:Self.key), let value = try? JSONDecoder().decode(URLQueryPreferences.self,from:data) else { return .init() }
        return value
    }
    func save(_ value: URLQueryPreferences) { defaults.set(try? JSONEncoder().encode(value),forKey:Self.key) }
}
