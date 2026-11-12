import Foundation
import Observation

@MainActor @Observable final class StringEscapeWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate(sourceChanged: true) } } }
    var preferences: StringEscapePreferences {
        didSet {
            if preferences != oldValue { repository.save(preferences) }
            if preferences.options.effective != oldValue.options.effective { invalidate(sourceChanged: false) }
        }
    }
    var fraction = 0.5
    var outputCollapsed = false
    private(set) var sourceRevision = UUID()
    private(set) var result: StringEscapeResult?
    private(set) var artifact: StringEscapeArtifact?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var lastIntent = StringEscapeIntent.check
    private(set) var publicationID = UUID()
    var options: StringEscapeOptions { preferences.options.effective }
    var output: String? { artifact?.text }
    var canCopy: Bool { !busy && artifactOptions == options && !(output?.isEmpty ?? true) }
    typealias Worker = @Sendable (String, StringEscapeOptions, StringEscapeIntent) async -> StringEscapeResult
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private let repository: StringEscapePreferencesRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var artifactOptions: StringEscapeOptions?

    init(repository: StringEscapePreferencesRepository = .init(), worker: @escaping Worker = { source, options, intent in
        StringEscapeProcessor.process(source, options: options, intent: intent)
    }) { self.repository = repository; preferences = repository.load(); self.worker = worker }
    deinit { task?.cancel() }
    func refreshPreferences() { preferences = repository.load() }
    private func stop() { task?.cancel(); task = nil; requestID = UUID(); busy = false }
    private func invalidate(sourceChanged: Bool) {
        stop(); result = nil; artifact = nil; artifactOptions = nil; wasCancelled = false
        if sourceChanged { sourceRevision = UUID() }
        publicationID = UUID()
    }
    func clear() { if input.isEmpty { invalidate(sourceChanged: true) } else { input = "" } }
    func cancel() { let running = busy; stop(); if running { wasCancelled = true } }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? run(.check) : nil }
    @discardableResult func run(_ intent: StringEscapeIntent = .convert) -> Task<Void, Never> {
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
