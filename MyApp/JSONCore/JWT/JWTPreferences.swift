import Foundation

struct JWTPreferences: Codable, Equatable, Sendable {
    enum Zone: String, Codable, CaseIterable { case utc = "UTC", local = "Local" }
    enum Presentation: String, Codable, CaseIterable { case formatted = "Formatted", raw = "Raw" }
    var decodeOnPaste = true
    var wordWrap = true
    var timeZoneMode = Zone.utc
    var jsonPresentation = Presentation.formatted
    init() {}
    private enum CodingKeys: String, CodingKey { case decodeOnPaste, wordWrap, timeZoneMode, jsonPresentation }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decodeOnPaste = (try? c.decode(Bool.self, forKey: .decodeOnPaste)) ?? true
        wordWrap = (try? c.decode(Bool.self, forKey: .wordWrap)) ?? true
        timeZoneMode = (try? c.decode(Zone.self, forKey: .timeZoneMode)) ?? .utc
        jsonPresentation = (try? c.decode(Presentation.self, forKey: .jsonPresentation)) ?? .formatted
    }
}
struct JWTPreferencesRepository {
    static let key = "developerToolbox.jwtInspector.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> JWTPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(JWTPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: JWTPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
