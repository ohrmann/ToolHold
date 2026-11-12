import Foundation
import Observation

@MainActor @Observable final class Base64FileWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var preferences: Base64FilePreferences {
        didSet {
            if preferences != oldValue { repository.save(preferences) }
            if preferences.options(mime: effectiveMIME) != oldValue.options(mime: effectiveMIME) { invalidate() }
        }
    }
    var decodeFromFile = false { didSet { if decodeFromFile != oldValue { invalidate() } } }
    var mimeOverride = "" { didSet { if !mimeOverride.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var inputCollapsed = false
    var outputCollapsed = false
    var fraction = 0.5
    private(set) var encodeFile: Base64FileMetadata?
    private(set) var decodeFile: Base64FileMetadata?
    private(set) var result: Base64FileResult?
    private(set) var artifact: Base64FileResult?
    private(set) var busy = false
    private(set) var progress = Base64FileProgress()
    private(set) var wasCancelled = false
    private(set) var sourceRevision = UUID()
    private(set) var publicationID = UUID()
    private(set) var importing = false
    private(set) var importFailure: String?
    private(set) var exportMessage: String?
    private(set) var cleanupWarning: String?
    private(set) var lastIntent = Base64Intent.check
    @ObservationIgnored private let repository: Base64FilePreferencesRepository
    @ObservationIgnored private var work: Task<Void,Never>?
    @ObservationIgnored private var importWork: Task<Void,Never>?
    @ObservationIgnored private var operation = Base64FileOperation()
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var importRequest = UUID()
    @ObservationIgnored private let worker: Worker
    typealias Worker = @Sendable (Base64FileSource, Base64FileOptions, Base64Intent, Base64FileDestination?, Data?, Base64FileOperation, @escaping @Sendable (Base64FileProgress) -> Void) async -> Base64FileResult
    init(repository: Base64FilePreferencesRepository = .init(), worker: @escaping Worker = { source, options, intent, destination, digest, operation, progress in
        Base64FileProcessor.run(source: source, options: options, intent: intent, destination: destination, expectedDigest: digest, operation: operation, progress: progress)
    }) { self.repository = repository; preferences = repository.load(); self.worker = worker }

    var selectedFile: Base64FileMetadata? { preferences.direction == .encode ? encodeFile : decodeFile }
    var usesFile: Bool { preferences.direction == .encode || decodeFromFile }
    var effectiveMIME: String { mimeOverride.isEmpty ? (encodeFile?.mime ?? "application/octet-stream") : mimeOverride }
    var options: Base64FileOptions { preferences.options(mime: effectiveMIME) }
    var source: Base64FileSource? {
        if usesFile { return selectedFile.map { .file($0.url) } }
        return .text(input)
    }
    var canRun: Bool { source != nil && !busy && !importing }
    var canCopy: Bool { !busy && !(artifact?.copyText?.isEmpty ?? true) }
    var canExport: Bool { canRun }
    var suggestedName: String { preferences.direction == .encode ? "encoded.txt" : "decoded.bin" }
    var outputText: String {
        guard let artifact else { return "" }
        if preferences.direction == .encode {
            if let full = artifact.copyText { return full }
            return "Preview · first \(artifact.textPreview.count) of \(artifact.outputBytes) characters\nUse Export for the complete result.\n\n" + artifact.textPreview
        }
        return "Decoded \(Base64FileDisplay.bytes(artifact.outputBytes))\n\nHex preview · first \(min(64, artifact.outputBytes)) bytes\n" + artifact.hexPreview
    }
    func refreshPreferences() { preferences = repository.load() }
    func dismissCleanupWarning() { cleanupWarning = nil }
    private func stop() {
        operation.cancel(); work?.cancel(); work = nil; request = UUID(); busy = false
    }
    private func invalidate() {
        stop(); result = nil; artifact = nil; wasCancelled = false; exportMessage = nil
        sourceRevision = UUID(); publicationID = UUID(); progress = .init()
    }
    func cancel() {
        let active = busy; stop()
        if let saved = operation.exportedName { exportMessage = "Saved \(Base64FileDisplay.safeLabel(saved))"; wasCancelled = false }
        else if active { wasCancelled = true }
    }
    func disappear() { cancel(); importWork?.cancel(); importRequest = UUID(); importing = false }
    func clear() {
        importWork?.cancel(); importRequest = UUID(); importing = false; importFailure = nil
        if usesFile {
            if preferences.direction == .encode { encodeFile = nil } else { decodeFile = nil }
            invalidate()
        } else { if input.isEmpty { invalidate() } else { input = "" } }
    }
    @discardableResult func select(_ url: URL) -> Task<Void,Never> {
        importWork?.cancel(); let id = UUID(); importRequest = id; importing = true; importFailure = nil
        let direction = preferences.direction
        let task = Task { [weak self] in
            let detached = Task.detached(priority: .userInitiated) { () -> Result<Base64FileMetadata, Error> in
                do { try Task.checkCancellation(); return .success(try Base64FileMetadata.load(url)) } catch { return .failure(error) }
            }
            let loaded = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.importRequest == id else { return }
            self.importing = false
            guard self.preferences.direction == direction && self.usesFile else { return }
            switch loaded {
            case .success(let file):
                if direction == .encode { self.encodeFile = file } else { self.decodeFile = file }
                self.invalidate()
            case .failure: self.importFailure = "The file is unavailable. Choose a regular file stored locally with readable access."
            }
        }
        importWork = task; return task
    }
    @discardableResult func didPaste() -> Task<Void,Never>? {
        !usesFile && preferences.validateOnPaste ? run(.check) : nil
    }
    @discardableResult func run(_ intent: Base64Intent = .convert, destination: Base64FileDestination? = nil) -> Task<Void,Never> {
        guard let source else { return Task {} }
        stop(); busy = true; wasCancelled = false; exportMessage = nil; importFailure = nil; lastIntent = intent
        progress = .init(total: usesFile ? selectedFile?.size : Int64(input.utf8.count))
        let id = request, revision = sourceRevision, opts = options, worker = worker
        let gate = Base64FileOperation(); operation = gate
        let digest = destination == nil ? nil : (artifact?.sourceDigest ?? (result?.status == .success ? result?.sourceDigest : nil))
        let report: @Sendable (Base64FileProgress) -> Void = { [weak self] progress in
            guard let owner = self else { return }
            Task { @MainActor in
                guard owner.request == id && owner.sourceRevision == revision && owner.busy else { return }
                owner.progress = progress
            }
        }
        let task = Task { [weak self] in
            let detached = Task.detached(priority: .userInitiated) {
                await worker(source, opts, intent, destination, digest, gate, report)
            }
            let value = await withTaskCancellationHandler { await detached.value } onCancel: { gate.cancel(); detached.cancel() }
            guard let self else { return }
            if let path = value.failure?.cleanupPath {
                self.cleanupWarning = "A partial export could not be removed: " + Base64FileDisplay.safeLabel(path, limit: 500)
            }
            guard self.request == id && self.sourceRevision == revision && self.options == opts else { return }
            self.busy = false; self.work = nil
            if value.status == .cancelled {
                self.wasCancelled = true
                // Cleanup failure must remain visible even for cancellation.
                if value.failure?.cleanupPath != nil { self.result = value }
            } else {
                self.result = value
                if value.status == .success {
                    // A file URL can keep its identity while its bytes change externally.
                    // A fresh Check must not bless the previous snapshot's preview/Copy.
                    if intent == .check, let previous = self.artifact?.sourceDigest,
                       previous != value.sourceDigest { self.artifact = nil }
                    if intent == .convert { self.artifact = value }
                    if let saved = value.exportedName { self.exportMessage = "Saved \(Base64FileDisplay.safeLabel(saved))" }
                } else { self.artifact = nil }
            }
            self.publicationID = UUID()
        }
        work = task; return task
    }
}
