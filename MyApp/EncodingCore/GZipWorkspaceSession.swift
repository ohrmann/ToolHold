import Foundation
import Observation

@MainActor @Observable final class GZipWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var preferences: GZipPreferences {
        didSet {
            if preferences != oldValue { repository.save(preferences) }
            if preferences.options.effective(file:usesFile) != oldValue.options.effective(file:usesFile) { invalidate() }
        }
    }
    var usesFile = false { didSet { if usesFile != oldValue { invalidate(); cancelImport() } } }
    var fraction = 0.5
    var outputCollapsed = false
    enum OutputView: String, CaseIterable { case base64 = "Base64", text = "Text", hex = "Hex preview" }
    var outputView = OutputView.base64
    private(set) var selectedFile: GZipFileMetadata?
    private(set) var result: GZipResult?
    private(set) var artifact: GZipArtifact?
    private(set) var busy = false
    private(set) var importing = false
    private(set) var importFailure: String?
    private(set) var cleanupWarning: String?
    private(set) var exportMessage: String?
    private(set) var progress = GZipProgress()
    private(set) var wasCancelled = false
    private(set) var sourceRevision = UUID()
    private(set) var publicationID = UUID()
    private(set) var lastIntent = GZipIntent.check
    @ObservationIgnored private let repository: GZipPreferencesRepository
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var importTask: Task<Void,Never>?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var importRequest = UUID()
    @ObservationIgnored private var operation = GZipOperation()
    @ObservationIgnored private let worker: Worker
    typealias Worker = @Sendable (GZipSource, GZipOptions, GZipIntent, GZipDestination?, Data?, GZipOperation, @escaping @Sendable (GZipProgress) -> Void) async -> GZipResult
    init(repository: GZipPreferencesRepository = .init(), worker: @escaping Worker = { source, options, intent, destination, digest, operation, progress in
        GZipFileProcessor.run(source:source,options:options,intent:intent,destination:destination,expectedDigest:digest,operation:operation,progress:progress)
    }) { self.repository = repository; preferences = repository.load(); self.worker = worker }
    deinit { operation.cancel(); task?.cancel(); importTask?.cancel() }
    var options: GZipOptions { preferences.options.effective(file:usesFile) }
    var source: GZipSource? { usesFile ? selectedFile.map { .file($0.url) } : .text(input) }
    var canRun: Bool { source != nil && !busy && !importing }
    var canExport: Bool { canRun && result?.status == .success && result?.sourceDigest != nil }
    var outputText: String {
        guard let artifact else { return "" }
        switch outputView {
        case .base64: return artifact.base64 ?? artifact.base64Preview
        case .text: return artifact.text ?? artifact.textPreview
        case .hex: return artifact.hexPreview
        }
    }
    var outputCaption: String {
        guard let artifact else { return "" }
        switch outputView {
        case .base64: return artifact.base64 != nil ? "Complete Base64 · exact output bytes" : "Base64 prefix preview · Export for the complete result"
        case .text:
            if artifact.text != nil { return "Complete UTF-8 text · exact output bytes" }
            if artifact.binary { return "Binary result · no complete valid UTF-8 text" }
            return "UTF-8 prefix preview · full text validity not established · Export for the complete result"
        case .hex: return "Hex preview · first \(min(64,result?.outputBytes ?? 0)) bytes · Export for the complete result"
        }
    }
    var suggestedName: String {
        let original = selectedFile?.url.lastPathComponent
        let proposed: String
        if options.direction == .compress { proposed = original.map { $0 + ".gz" } ?? "compressed.gz" }
        else if let original, original.lowercased().hasSuffix(".gz") { proposed = String(original.dropLast(3)) }
        else { proposed = "decompressed.bin" }
        return GZipFileProcessor.validFilename(proposed) ? proposed : (options.direction == .compress ? "compressed.gz" : "decompressed.bin")
    }
    func refreshPreferences() { preferences = repository.load() }
    func dismissCleanupWarning() { cleanupWarning = nil }
    func copyText(_ kind: OutputView) -> String? {
        guard !busy && !importing, let artifact else { return nil }
        return kind == .text ? artifact.text : kind == .base64 ? artifact.base64 : nil
    }
    private func stop() { operation.cancel(); task?.cancel(); task = nil; request = UUID(); busy = false }
    private func cancelImport() { importTask?.cancel(); importTask = nil; importRequest = UUID(); importing = false }
    private func invalidate() {
        stop(); result = nil; artifact = nil; importFailure = nil; exportMessage = nil; wasCancelled = false
        sourceRevision = UUID(); publicationID = UUID(); progress = .init()
    }
    func cancel() {
        let running = busy, gate = operation; stop()
        if let saved = gate.exportedName { exportMessage = "Saved \(Base64FileDisplay.safeLabel(saved))"; wasCancelled = false }
        else if running { wasCancelled = true }
    }
    func disappear() { cancel(); cancelImport() }
    func clear() {
        cancelImport()
        if usesFile { selectedFile = nil; invalidate() }
        else if input.isEmpty { invalidate() }
        else { input = "" }
    }
    @discardableResult func select(_ url: URL) -> Task<Void,Never> {
        cancelImport(); invalidate(); importing = true
        let id = importRequest, direction = preferences.direction
        let work = Task { [weak self] in
            let detached = Task.detached(priority:.userInitiated) { () -> Result<GZipFileMetadata,Error> in
                do { try Task.checkCancellation(); return .success(try GZipFileMetadata.load(url)) }
                catch { return .failure(error) }
            }
            let loaded = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.importRequest == id else { return }
            self.importing = false; self.importTask = nil
            guard self.usesFile && self.preferences.direction == direction else { return }
            switch loaded {
            case .success(let metadata): self.selectedFile = metadata
            case .failure: self.importFailure = "Choose a readable regular file available locally."
            }
        }
        importTask = work; return work
    }
    @discardableResult func didPaste() -> Task<Void,Never>? {
        !usesFile && preferences.validateOnPaste ? run(.check) : nil
    }
    @discardableResult func run(_ intent: GZipIntent = .convert, destination: GZipDestination? = nil) -> Task<Void,Never> {
        guard let source, !importing, destination == nil || canExport else { return Task {} }
        let expected = destination == nil ? nil : result?.sourceDigest
        stop(); busy = true; wasCancelled = false; importFailure = nil; exportMessage = nil; lastIntent = intent
        progress = .init(total:usesFile ? selectedFile?.size : nil)
        let id = request, revision = sourceRevision, options = options, worker = worker
        let gate = GZipOperation(); operation = gate
        let report: @Sendable (GZipProgress) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.request == id, self.sourceRevision == revision, self.busy else { return }
                self.progress = value
            }
        }
        let work = Task { [weak self] in
            let detached = Task.detached(priority:.userInitiated) { await worker(source,options,intent,destination,expected,gate,report) }
            let value = await withTaskCancellationHandler { await detached.value } onCancel: { gate.cancel(); detached.cancel() }
            guard let self else { return }
            if let path = value.failure?.cleanupPath { self.cleanupWarning = "A partial export could not be removed: " + Base64FileDisplay.safeLabel(path,limit:500) }
            if let saved = value.exportedName { self.exportMessage = "Saved \(Base64FileDisplay.safeLabel(saved))" }
            guard !Task.isCancelled, self.request == id, self.sourceRevision == revision, self.options == options else { return }
            self.busy = false; self.task = nil
            if value.status == .cancelled {
                self.wasCancelled = true
                if value.failure?.cleanupPath != nil { self.result = value }
            } else {
                let previousDigest = self.result?.sourceDigest
                self.result = value
                if value.status == .success {
                    if intent == .check, previousDigest != value.sourceDigest { self.artifact = nil }
                    if intent == .convert && destination == nil {
                        self.artifact = value.artifact
                        self.outputView = options.direction == .compress ? .base64 : value.artifact?.text != nil ? .text : .hex
                    }
                } else if intent == .convert || [.sourceChanged,.invalidGZip,.invalidBase64,.ioFailure].contains(value.status) { self.artifact = nil }
            }
            self.publicationID = UUID()
        }
        task = work; return work
    }
}
