import Foundation

struct JWTEncoderPreferences: Codable, Equatable, Sendable {
    var signedAlgorithm = JWTSigningAlgorithm.hs256
    var keyEncoding = JWTSigningKeyEncoding.utf8
    var serialization = JWTEncoderSerialization.compact
    var wordWrap = true
    var checkJSONOnPaste = true
    init() {}
    enum CodingKeys: String, CodingKey { case signedAlgorithm, keyEncoding, serialization, wordWrap, checkJSONOnPaste }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signedAlgorithm = (try? c.decode(JWTSigningAlgorithm.self, forKey: .signedAlgorithm)) ?? .hs256
        if signedAlgorithm == .none { signedAlgorithm = .hs256 }
        keyEncoding = (try? c.decode(JWTSigningKeyEncoding.self, forKey: .keyEncoding)) ?? .utf8
        serialization = (try? c.decode(JWTEncoderSerialization.self, forKey: .serialization)) ?? .compact
        wordWrap = (try? c.decode(Bool.self, forKey: .wordWrap)) ?? true
        checkJSONOnPaste = (try? c.decode(Bool.self, forKey: .checkJSONOnPaste)) ?? true
    }
}
struct JWTEncoderPreferencesRepository {
    static let key = "developerToolbox.jwtEncoder.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) { self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard) }
    func load() -> JWTEncoderPreferences {
        guard let data = defaults.data(forKey: Self.key), let result = try? JSONDecoder().decode(JWTEncoderPreferences.self, from: data) else { return .init() }
        return result
    }
    func save(_ value: JWTEncoderPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
