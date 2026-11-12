import Foundation

enum Base64FileFormat: String, Codable, CaseIterable, Sendable {
    case raw, dataURL
    var title: String { self == .raw ? "Raw Base64" : "Data URL" }
}
struct Base64FileOptions: Equatable, Sendable {
    var direction = Base64Direction.encode
    var format = Base64FileFormat.raw
    var alphabet = Base64Alphabet.standard
    var decodeMode = Base64DecodeMode.strict
    var urlPadding = false
    var mimeType = "application/octet-stream"
    var effective: Self {
        var result = self
        if format == .dataURL { result.alphabet = .standard; result.urlPadding = true }
        if direction == .encode { result.decodeMode = .strict }
        if direction == .decode || result.alphabet == .standard { result.urlPadding = false }
        if direction == .decode || format == .raw { result.mimeType = "application/octet-stream" }
        return result
    }
}
enum Base64FileSource: Sendable {
    case file(URL), text(String)
}
enum Base64FileStatus: Sendable, Equatable {
    case success, invalidBase64, unsupportedFormat, sourceChanged, resourceLimit, ioFailure, cancelled
}
struct Base64FileFailure: Error, Sendable {
    var status: Base64FileStatus
    var message: String
    var byteOffset: Int64?
    var length: Int = 1
    var context: String = ""
    var textRange: NSRange?
    var line: Int?
    var column: Int?
    var cleanupPath: String?
    init(_ status: Base64FileStatus, _ message: String, byteOffset: Int64? = nil, length: Int = 1) {
        self.status = status; self.message = message; self.byteOffset = byteOffset; self.length = length
    }
}
struct Base64FileResult: Sendable {
    var status = Base64FileStatus.success
    var failure: Base64FileFailure?
    var notes: [String] = []
    var inputBytes: Int64 = 0
    var outputBytes: Int64 = 0
    /// Complete text only if it fits the Copy budget. Never a truncated artifact.
    var copyText: String?
    var textPreview = ""
    var hexPreview = ""
    var imageBytes: Data?
    var mediaType: String?
    var sourceDigest: Data?
    var exportedName: String?
}
struct Base64FileProgress: Sendable {
    var bytes: Int64 = 0
    var total: Int64?
}
enum Base64FileBudget {
    static let chunk = 65_536
    static let textInput = 262_144
    static let copyText = 262_144
    static let previewText = 8_192
    static let imageBytes = 8 * 1_024 * 1_024
    static let header = 4_096
}

/// Synchronizes cancellation with the final no-clobber rename, not just UI publication.
final class Base64FileOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var saved: String?
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        try Task.checkCancellation()
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
    var exportedName: String? { lock.lock(); defer { lock.unlock() }; return saved }
    func commit(name: String, _ action: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled && !Task.isCancelled else { throw CancellationError() }
        try action(); saved = name
    }
}

struct Base64FilePreferences: Codable, Equatable {
    var direction = Base64Direction.encode
    var format = Base64FileFormat.raw
    var alphabet = Base64Alphabet.standard
    var decodeMode = Base64DecodeMode.strict
    var urlPadding = false
    var validateOnPaste = true
    var wordWrap = true
    init() {}
    private enum CodingKeys: String, CodingKey { case direction, format, alphabet, decodeMode, urlPadding, validateOnPaste, wordWrap }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? v.decode(Base64Direction.self, forKey: .direction)) ?? .encode
        format = (try? v.decode(Base64FileFormat.self, forKey: .format)) ?? .raw
        alphabet = (try? v.decode(Base64Alphabet.self, forKey: .alphabet)) ?? .standard
        decodeMode = (try? v.decode(Base64DecodeMode.self, forKey: .decodeMode)) ?? .strict
        urlPadding = (try? v.decode(Bool.self, forKey: .urlPadding)) ?? false
        validateOnPaste = (try? v.decode(Bool.self, forKey: .validateOnPaste)) ?? true
        wordWrap = (try? v.decode(Bool.self, forKey: .wordWrap)) ?? true
    }
    func options(mime: String) -> Base64FileOptions {
        .init(direction: direction, format: format, alphabet: alphabet, decodeMode: decodeMode, urlPadding: urlPadding, mimeType: mime).effective
    }
}
struct Base64FilePreferencesRepository {
    static let key = "developerToolbox.base64Files.preferences.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests")
            ? UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")! : .standard)
    }
    func load() -> Base64FilePreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(Base64FilePreferences.self, from: data) else { return .init() }
        return value
    }
    func save(_ value: Base64FilePreferences) { defaults.set(try? JSONEncoder().encode(value), forKey: Self.key) }
}
