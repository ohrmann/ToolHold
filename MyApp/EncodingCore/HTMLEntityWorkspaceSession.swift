import Foundation
import Observation

@MainActor @Observable final class HTMLEntityWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate(sourceChanged: true) } } }
    var preferences: HTMLEntityPreferences {
        didSet {
            if preferences != oldValue { repository.save(preferences) }
            if preferences.options.effective != oldValue.options.effective { invalidate(sourceChanged: false) }
        }
    }
    var fraction = 0.5
    var outputCollapsed = false
    private(set) var sourceRevision = UUID()
    private(set) var result: HTMLEntityResult?
    private(set) var artifact: HTMLEntityArtifact?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var lastIntent = HTMLEntityIntent.check
    private(set) var publicationID = UUID()
    var options: HTMLEntityOptions { preferences.options.effective }
    var output: String? { artifact?.text }
    var canCopy: Bool { !busy && artifactOptions == options && !(output?.isEmpty ?? true) }
    typealias Worker = @Sendable (String, HTMLEntityOptions, HTMLEntityIntent) async -> HTMLEntityResult
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private let repository: HTMLEntityPreferencesRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var artifactOptions: HTMLEntityOptions?

    init(repository: HTMLEntityPreferencesRepository = .init(), worker: @escaping Worker = { source, options, intent in
        HTMLEntityProcessor.process(source, options: options, intent: intent)
    }) { self.repository = repository; preferences = repository.load(); self.worker = worker }
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
    @discardableResult func run(_ intent: HTMLEntityIntent = .convert) -> Task<Void, Never> {
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
