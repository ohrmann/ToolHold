import Foundation
import Observation

@MainActor @Observable final class HexBytesWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate(sourceChanged: true) } } }
    var preferences: HexBytesPreferences {
        didSet {
            if preferences != oldValue { repository.save(preferences) }
            if preferences.outputFormat != oldValue.outputFormat || preferences.hexCase != oldValue.hexCase { cancelCopy() }
            if preferences.options.effective != oldValue.options.effective { invalidate(sourceChanged: false) }
        }
    }
    var fraction = 0.5
    var outputCollapsed = false
    private(set) var sourceRevision = UUID()
    private(set) var result: HexBytesResult?
    private(set) var artifact: HexBytesArtifact?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var lastIntent = HexBytesIntent.check
    private(set) var publicationID = UUID()
    var options: HexBytesOptions { preferences.options.effective }
    var output: String? { options.direction == .encode ? artifact?.hex : artifact?.text }
    var canCopyText: Bool { !busy && !copyBusy && artifactOptions == options && !(artifact?.text?.isEmpty ?? true) }
    var canCopyHex: Bool {
        !busy && !copyBusy && artifactOptions == options && (artifact?.bytes.count ?? 0) > 0 && copyHexFits
    }
    var copyHexFits: Bool {
        guard let count = preferences.outputFormat.length(for: artifact?.bytes.count ?? 0) else { return false }
        return count <= HexBytesLimits().outputUTF16
    }
    var showingBytes: Bool { artifact != nil && (artifact?.text == nil || preferences.preferredOutputView == .bytes) }
    private(set) var copyBusy = false
    enum CopyKind: Sendable { case text, hex }
    struct PreparedCopy: Sendable {
        let text: String
        let artifactID: UUID
        let requestID: UUID
        let format: HexBytesOutputFormat
        let hexCase: HexBytesCase
        let kind: CopyKind
    }
    typealias CopyWorker = @Sendable (Data, HexBytesOutputFormat, HexBytesCase) async -> String?
    @ObservationIgnored private let copyWorker: CopyWorker
    @ObservationIgnored private var copyTask: Task<PreparedCopy?, Never>?
    @ObservationIgnored private var copyRequestID = UUID()
    typealias Worker = @Sendable (String, HexBytesOptions, HexBytesIntent) async -> HexBytesResult
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private let repository: HexBytesPreferencesRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var artifactOptions: HexBytesOptions?

    init(repository: HexBytesPreferencesRepository = .init(), copyWorker: @escaping CopyWorker = { data, format, hexCase in
        try? HexBytesProcessor.format(data, format: format, hexCase: hexCase)
    }, worker: @escaping Worker = { source, options, intent in
        HexBytesProcessor.process(source, options: options, intent: intent)
    }) { self.repository = repository; preferences = repository.load(); self.worker = worker; self.copyWorker = copyWorker }
    deinit { task?.cancel(); copyTask?.cancel() }
    func refreshPreferences() { preferences = repository.load() }
    private func stop() { task?.cancel(); task = nil; requestID = UUID(); busy = false; cancelCopy() }
    private func invalidate(sourceChanged: Bool) {
        stop(); result = nil; artifact = nil; artifactOptions = nil; wasCancelled = false
        if sourceChanged { sourceRevision = UUID() }
        publicationID = UUID()
    }
    func clear() { if input.isEmpty { invalidate(sourceChanged: true) } else { input = "" } }
    func cancel() { let running = busy; stop(); if running { wasCancelled = true } }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? run(.check) : nil }
    @discardableResult func run(_ intent: HexBytesIntent = .convert) -> Task<Void, Never> {
        stop(); busy = true; wasCancelled = false; lastIntent = intent
        let request = requestID, revision = sourceRevision, options = options, source = input, worker = worker
        let work = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let detached = Task.detached(priority: .userInitiated) { await worker(source, options, intent) }
            let processed = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.requestID == request, self.sourceRevision == revision, self.options == options else { return }
            if processed.status == .cancelled {
                self.wasCancelled = true
            } else {
                self.result = processed
                if intent == .convert {
                    self.artifact = processed.artifact
                    self.artifactOptions = processed.artifact == nil ? nil : options
                }
                self.publicationID = UUID()
            }
            self.busy = false; self.task = nil
        }
        task = work; return work
    }
}


extension HexBytesWorkspaceSession {
    func cancelCopy() { copyTask?.cancel(); copyTask = nil; copyRequestID = UUID(); copyBusy = false }
    func isCurrent(_ copy: PreparedCopy) -> Bool {
        !busy && copy.artifactID == artifact?.id && copy.requestID == copyRequestID &&
            (copy.kind == .text || (copy.format == preferences.outputFormat && copy.hexCase == preferences.hexCase))
    }
    @discardableResult func prepareCopy(_ kind: CopyKind) -> Task<PreparedCopy?, Never> {
        let allowed = kind == .text ? canCopyText : canCopyHex
        guard allowed, let artifact else { return Task { nil } }
        cancelCopy(); copyBusy = true
        let request = copyRequestID, format = preferences.outputFormat, hexCase = preferences.hexCase, worker = copyWorker
        let work = Task { [weak self] () -> PreparedCopy? in
            let detached = Task.detached(priority: .userInitiated) {
                if kind == .text { return artifact.text }
                return await worker(artifact.bytes, format, hexCase)
            }
            let text = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.copyRequestID == request, self.artifact?.id == artifact.id else { return nil }
            self.copyBusy = false; self.copyTask = nil
            guard let text else { return nil }
            return .init(text: text, artifactID: artifact.id, requestID: request, format: format, hexCase: hexCase, kind: kind)
        }
        copyTask = work; return work
    }
}
