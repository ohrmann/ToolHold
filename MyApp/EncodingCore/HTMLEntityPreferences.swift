import Foundation

/// UI-only allowlist. Working text, results, diagnostics, paths and history are never persisted.
struct HTMLEntityPreferences: Codable, Equatable {
    var direction = HTMLEntityDirection.encode
    var context = HTMLEntityContext.text
    var scope = HTMLEntityScope.required
    var notation = HTMLEntityNotation.named
    var preserveExistingReferences = false
    var policy = HTMLEntityPolicy.htmlCompatible
    var validateOnPaste = true
    var wordWrap = true
    var options: HTMLEntityOptions { .init(direction: direction, context: context, scope: scope, notation: notation, preserveExistingReferences: preserveExistingReferences, policy: policy) }
    private enum CodingKeys: String, CodingKey { case direction, context, scope, notation, preserveExistingReferences, policy, validateOnPaste, wordWrap }
    init() {}
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? v.decode(HTMLEntityDirection.self, forKey: .direction)) ?? .encode
        context = (try? v.decode(HTMLEntityContext.self, forKey: .context)) ?? .text
        scope = (try? v.decode(HTMLEntityScope.self, forKey: .scope)) ?? .required
        notation = (try? v.decode(HTMLEntityNotation.self, forKey: .notation)) ?? .named
        preserveExistingReferences = (try? v.decode(Bool.self, forKey: .preserveExistingReferences)) ?? false
        policy = (try? v.decode(HTMLEntityPolicy.self, forKey: .policy)) ?? .htmlCompatible
        validateOnPaste = (try? v.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? v.decode(Bool.self, forKey: .wordWrap)) ?? true
    }
}
struct HTMLEntityPreferencesRepository {
    static let key = "developerToolbox.htmlEntity.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> HTMLEntityPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(HTMLEntityPreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: HTMLEntityPreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
