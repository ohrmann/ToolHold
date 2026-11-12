import Foundation

struct IdentifierPreferences: Codable, Equatable, Sendable {
    var kind = IdentifierKind.uuidV4
    var count = 1
    var uuidCase = IdentifierCase.lowercase
    var ulidMonotonic = true
    var nanoLength = 21
    var nanoAlphabetPreset = IdentifierAlphabet.urlSafe
    enum CodingKeys: String, CodingKey { case kind, count, uuidCase, ulidMonotonic, nanoLength, nanoAlphabetPreset }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(IdentifierKind.self, forKey: .kind)) ?? .uuidV4
        if let count = try? c.decode(Int.self, forKey: .count), (1...10_000).contains(count) { self.count = count }
        uuidCase = (try? c.decode(IdentifierCase.self, forKey: .uuidCase)) ?? .lowercase
        ulidMonotonic = (try? c.decode(Bool.self, forKey: .ulidMonotonic)) ?? true
        if let length = try? c.decode(Int.self, forKey: .nanoLength), (1...256).contains(length) { nanoLength = length }
        nanoAlphabetPreset = (try? c.decode(IdentifierAlphabet.self, forKey: .nanoAlphabetPreset)) ?? .urlSafe
        if nanoAlphabetPreset == .custom { nanoAlphabetPreset = .urlSafe }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(count, forKey: .count)
        try c.encode(uuidCase, forKey: .uuidCase); try c.encode(ulidMonotonic, forKey: .ulidMonotonic)
        try c.encode(nanoLength, forKey: .nanoLength)
        try c.encode(nanoAlphabetPreset == .custom ? .urlSafe : nanoAlphabetPreset, forKey: .nanoAlphabetPreset)
    }
}
struct IdentifierPreferencesRepository {
    static let key = "developerToolbox.identifierGenerator.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> IdentifierPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(IdentifierPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: IdentifierPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
