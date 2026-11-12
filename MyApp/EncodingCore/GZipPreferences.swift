import Foundation

/// Explicit UI-only allowlist. URLs, names, digests, text and results are never serialized.
struct GZipPreferences: Codable, Equatable {
    var direction = GZipDirection.compress
    var compressionLevel = GZipLevel.default
    var base64Mode = Base64DecodeMode.strict
    var maxOutput = GZipOutputLimit.standard
    var validateOnPaste = true
    var wordWrap = true
    var options: GZipOptions { .init(direction: direction, level: compressionLevel, base64Mode: base64Mode, maxOutput: maxOutput) }
    init() {}
    private enum CodingKeys: String, CodingKey { case direction, compressionLevel, base64Mode, maxOutput, validateOnPaste, wordWrap }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? v.decode(GZipDirection.self, forKey: .direction)) ?? .compress
        compressionLevel = (try? v.decode(GZipLevel.self, forKey: .compressionLevel)) ?? .default
        base64Mode = (try? v.decode(Base64DecodeMode.self, forKey: .base64Mode)) ?? .strict
        maxOutput = (try? v.decode(GZipOutputLimit.self, forKey: .maxOutput)) ?? .standard
        validateOnPaste = (try? v.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? v.decode(Bool.self, forKey: .wordWrap)) ?? true
    }
}
struct GZipPreferencesRepository {
    static let key = "developerToolbox.gzip.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName:"developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> GZipPreferences {
        guard let data = defaults.data(forKey:Self.key), let value = try? JSONDecoder().decode(GZipPreferences.self,from:data) else { return .init() }
        return value
    }
    func save(_ value: GZipPreferences) { defaults.set(try? JSONEncoder().encode(value),forKey:Self.key) }
}
