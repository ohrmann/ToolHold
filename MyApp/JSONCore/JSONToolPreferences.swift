import Foundation

/// Only interface preferences. No working text is encoded by this type.
struct JSONToolPreferences: Codable, Equatable {
    var indentation: JSONIndentation = .two
    var validateOnPaste = true
    var syntaxHighlighting = true
    var rainbowBrackets = true
    var matchingBrackets = true
    var wordWrap = true
    var schemaValidateFormats = false
    var schemaAssumedDialect = Dialect.draft2020_12.rawValue
    var modelLanguage = JSONModelLanguage.swift

    private enum CodingKeys: String, CodingKey {
        case indentation, validateOnPaste, syntaxHighlighting, rainbowBrackets, matchingBrackets, wordWrap, schemaValidateFormats, schemaAssumedDialect, modelLanguage
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        indentation = (try? values.decode(JSONIndentation.self, forKey: .indentation)) ?? .two
        validateOnPaste = (try? values.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        syntaxHighlighting = (try? values.decode(Bool.self, forKey: .syntaxHighlighting)) ?? true
        rainbowBrackets = (try? values.decode(Bool.self, forKey: .rainbowBrackets)) ?? true
        matchingBrackets = (try? values.decode(Bool.self, forKey: .matchingBrackets)) ?? true
        wordWrap = (try? values.decode(Bool.self, forKey: .wordWrap)) ?? true
        schemaValidateFormats = (try? values.decode(Bool.self, forKey: .schemaValidateFormats)) ?? false
        schemaAssumedDialect = (try? values.decode(String.self, forKey: .schemaAssumedDialect)) ?? Dialect.draft2020_12.rawValue
        modelLanguage = (try? values.decode(JSONModelLanguage.self, forKey: .modelLanguage)) ?? .swift
    }
}

struct JSONPreferencesRepository {
    static let key = "developerToolbox.json.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> JSONToolPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(JSONToolPreferences.self, from: data) else {
            return JSONToolPreferences()
        }
        return settings
    }
    func save(_ settings: JSONToolPreferences) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }
}
