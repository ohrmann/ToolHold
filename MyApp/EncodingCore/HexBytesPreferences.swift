import Foundation

/// Only UI preferences are persisted. Source, artifacts, diagnostics and history remain window-local.
struct HexBytesPreferences: Codable, Equatable {
    var direction = HexBytesDirection.decode
    var inputFormat = HexBytesInputFormat.pairs
    var outputFormat = HexBytesOutputFormat.spaced
    var hexCase = HexBytesCase.uppercase
    var validateOnPaste = true
    var wordWrap = true
    var preferredOutputView = HexBytesOutputView.text
    var options: HexBytesOptions { .init(direction: direction, inputFormat: inputFormat, outputFormat: outputFormat, hexCase: hexCase) }
    private enum CodingKeys: String, CodingKey { case direction, inputFormat, outputFormat, hexCase, validateOnPaste, wordWrap, preferredOutputView }
    init() {}
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? v.decode(HexBytesDirection.self, forKey: .direction)) ?? .decode
        inputFormat = (try? v.decode(HexBytesInputFormat.self, forKey: .inputFormat)) ?? .pairs
        outputFormat = (try? v.decode(HexBytesOutputFormat.self, forKey: .outputFormat)) ?? .spaced
        hexCase = (try? v.decode(HexBytesCase.self, forKey: .hexCase)) ?? .uppercase
        validateOnPaste = (try? v.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? v.decode(Bool.self, forKey: .wordWrap)) ?? true
        preferredOutputView = (try? v.decode(HexBytesOutputView.self, forKey: .preferredOutputView)) ?? .text
    }
}
struct HexBytesPreferencesRepository {
    static let key = "developerToolbox.hexBytes.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> HexBytesPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(HexBytesPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: HexBytesPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
