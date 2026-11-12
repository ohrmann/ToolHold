import Foundation

enum GZipDirection: String, Codable, CaseIterable, Sendable {
    case compress, decompress
    var title: String { self == .compress ? "Compress" : "Decompress" }
}
enum GZipLevel: Int, Codable, CaseIterable, Sendable {
    case `default` = -1, fast = 1, balanced = 6, best = 9, store = 0
    var title: String {
        switch self { case .default: "Default"; case .fast: "Fast (1)"; case .balanced: "Balanced (6)"; case .best: "Best (9)"; case .store: "Store (0)" }
    }
}
enum GZipOutputLimit: Int, Codable, CaseIterable, Sendable {
    case small = 16, standard = 64, large = 256
    var title: String { "\(rawValue) MiB" }
    var bytes: Int64 { Int64(rawValue) * 1_024 * 1_024 }
}
struct GZipOptions: Equatable, Sendable {
    var direction = GZipDirection.compress
    var level = GZipLevel.default
    var base64Mode = Base64DecodeMode.strict
    var maxOutput = GZipOutputLimit.standard
    func effective(file: Bool) -> Self {
        var value = self
        if direction == .compress { value.base64Mode = .strict; value.maxOutput = .standard }
        else { value.level = .default; if file { value.base64Mode = .strict } }
        return value
    }
}
struct GZipLimits: Sendable {
    var textInput = 262_144
    var fileInput: Int64 = 256 * 1_024 * 1_024
    var decompressedOutput: Int64 = 256 * 1_024 * 1_024
    var compressedOutput: Int64 = 256 * 1_024 * 1_024
    var retained = 8 * 1_024 * 1_024
    var copyText = 262_144
    var preview = 8_192
    var chunk = 65_536
}
enum GZipSource: Sendable { case text(String), file(URL) }
enum GZipIntent: Sendable { case check, convert }
enum GZipStatus: Sendable, Equatable {
    case success, invalidBase64, invalidGZip, unsupportedFormat, resourceLimit, sourceChanged, ioFailure, cancelled, internalFailure
}
struct GZipFailure: Error, Sendable {
    enum Code: String, Sendable { case base64, invalidData, truncated, trailingData, empty, budget, deadline, sourceChanged, io, unsupported, engine, cancelled }
    enum Space: Sendable { case inputUTF16, compressedBytes }
    var status: GZipStatus
    var code: Code
    var message: String
    var space = Space.compressedBytes
    var offset: Int64?
    var length = 0
    var member: Int?
    var exact = false
    var line: Int?
    var column: Int?
    var context = ""
    var cleanupPath: String?
    var textRange: NSRange? {
        guard space == .inputUTF16, let offset, offset >= 0, offset <= Int64(Int.max) else { return nil }
        return NSRange(location: Int(offset), length: length)
    }
    init(_ status: GZipStatus, _ code: Code, _ message: String, offset: Int64? = nil) {
        self.status = status; self.code = code; self.message = message; self.offset = offset
    }
}
struct GZipArtifact: Sendable {
    let id = UUID()
    var bytes: Data?
    var text: String?
    var base64: String?
    var textPreview = ""
    var base64Preview = ""
    var hexPreview = ""
    var binary = false
}
struct GZipResult: Sendable {
    var status = GZipStatus.success
    var failure: GZipFailure?
    var notes: [String] = []
    var inputBytes: Int64 = 0
    var outputBytes: Int64 = 0
    var members = 0
    var sourceDigest: Data?
    var artifact: GZipArtifact?
    var exportedName: String?
}
struct GZipProgress: Sendable { var bytes: Int64 = 0; var total: Int64? }
struct GZipDestination: Sendable { let directory: URL; let name: String }

/// The lock also defines the boundary between cancellation and successful publication on disk.
final class GZipOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var saved: String?
    private let start: TimeInterval
    private let timeout: TimeInterval
    private let clock: @Sendable () -> TimeInterval
    init(timeout: TimeInterval = 60, clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock; self.start = clock(); self.timeout = timeout
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        try Task.checkCancellation()
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        if clock() - start >= timeout { throw GZipFailure(.resourceLimit, .deadline, "Processing time limit reached. Try a smaller file or a faster compression level.") }
    }
    var exportedName: String? { lock.lock(); defer { lock.unlock() }; return saved }
    func commit(name: String, _ action: () throws -> Void) throws {
        try check()
        lock.lock(); defer { lock.unlock() }
        guard !cancelled && !Task.isCancelled else { throw CancellationError() }
        guard clock() - start < timeout else { throw GZipFailure(.resourceLimit, .deadline, "Processing time limit reached before export could be published.") }
        try action(); saved = name
    }
}
