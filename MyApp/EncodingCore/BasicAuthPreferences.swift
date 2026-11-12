import Foundation

struct BasicAuthPreferences: Codable, Equatable, Sendable {
    var encoding = BasicAuthEncoding.utf8
    var normalizeNFC = false
    var options: BasicAuthOptions { .init(encoding: encoding, normalizeNFC: normalizeNFC).effective }
    enum CodingKeys: String, CodingKey { case encoding, normalizeNFC }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        encoding = (try? c.decode(BasicAuthEncoding.self, forKey: .encoding)) ?? .utf8
        normalizeNFC = (try? c.decode(Bool.self, forKey: .normalizeNFC)) ?? false
    }
}
struct BasicAuthPreferencesRepository {
    static let key = "developerToolbox.basicAuth.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> BasicAuthPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(BasicAuthPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: BasicAuthPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
