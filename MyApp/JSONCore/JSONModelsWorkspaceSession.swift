import Foundation
import Observation

/// Per-window state. Only the selected language and the shared editor UI settings persist.
@MainActor @Observable final class JSONModelsWorkspaceSession {
    var input = "" {
        didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidateSource() } }
    }
    var rootName = "RootModel" {
        didSet { if !rootName.utf16.elementsEqual(oldValue.utf16) { optionsChanged(debounce: true) } }
    }
    var preferences: JSONToolPreferences {
        didSet {
            repository.save(preferences)
            if preferences.modelLanguage != oldValue.modelLanguage || preferences.indentation != oldValue.indentation {
                optionsChanged(debounce: false)
            }
        }
    }
    var language: JSONModelLanguage {
        get { preferences.modelLanguage }
        set { preferences.modelLanguage = newValue }
    }
    var options: JSONModelOptions { .init(language: language, rootName: rootName, indentation: preferences.indentation) }
    var fraction = 0.5
    var outputCollapsed = false
    private(set) var result: JSONModelResult?
    private(set) var artifact: JSONModelArtifact?
    private(set) var context: JSONDiagnosticContext?
    private(set) var sourceLocation: String?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var analysisCount = 0
    private(set) var analysis: JSONModelAnalysis?
    private(set) var hasGenerated = false
    var canCopy: Bool { artifact != nil && artifactOptions == options && !busy }
    var output: String? { artifact?.text }
    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var sourceRevision = UUID()
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var artifactOptions: JSONModelOptions?
    /// Injectable deterministic worker for race tests; production uses the same pure generator.
    typealias Worker = @Sendable (String, JSONModelOptions, JSONModelAnalysis?, Bool) async -> (JSONModelAnalysis, JSONModelResult)
    @ObservationIgnored private let worker: Worker

    init(repository: JSONPreferencesRepository = .init(), worker: @escaping Worker = { source, options, cached, generate in
        await JSONModelsWorkspaceSession.process(source, options, cached, generate)
    }) {
        self.repository = repository; self.preferences = repository.load(); self.worker = worker
    }
    nonisolated static func process(_ source: String, _ options: JSONModelOptions, _ cached: JSONModelAnalysis?, _ generate: Bool) async -> (JSONModelAnalysis, JSONModelResult) {
        let analysis = cached ?? JSONModelGenerator.analyze(source)
        return (analysis, JSONModelGenerator.generate(analysis, options: options, produceArtifact: generate))
    }
    func refreshPreferences() { preferences = repository.load() }
    private func stop() { work?.cancel(); work = nil; requestID = UUID(); busy = false }
    private func invalidateSource() {
        stop(); sourceRevision = UUID(); analysis = nil; result = nil; context = nil; sourceLocation = nil
        artifact = nil; artifactOptions = nil; wasCancelled = false; hasGenerated = false
    }
    private func optionsChanged(debounce: Bool) {
        stop(); result = nil; context = nil; sourceLocation = nil; wasCancelled = false
        guard hasGenerated else { return }
        run(generate: true, debounce: debounce)
    }
    func clear() { input = ""; invalidateSource() }
    func cancel() {
        wasCancelled = busy; stop()
        if artifactOptions != options { artifact = nil; artifactOptions = nil }
    }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? run(generate: false) : nil }
    @discardableResult func run(generate: Bool = true, debounce: Bool = false) -> Task<Void, Never> {
        stop(); wasCancelled = false
        if generate { hasGenerated = true }
        let request = requestID, sourceID = sourceRevision, source = input, options = options, cached = analysis, worker = worker
        busy = true
        let task = Task { [weak self] in
            if debounce {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let detached = Task.detached(priority: .userInitiated) {
                let values = await worker(source, options, cached, generate)
                let range = values.1.status == .resourceLimit ? nil :
                    (values.1.parseResult.diagnostics.first(where: { $0.severity == .error })?.range ?? values.1.issues.first?.range)
                let context = range.map { JSONDiagnosticContext.make(source: source, range: $0) }
                let location = range.map { range in
                    let coordinates = JSONSourceCoordinates(source).location(at: range.location)
                    return "Line \(coordinates.line), column \(coordinates.column) (UTF-16)"
                }
                return (values.0, values.1, context, location)
            }
            let values = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.requestID == request, self.sourceRevision == sourceID, self.options == options else { return }
            if cached == nil { self.analysisCount += 1 }
            if values.0.parseResult.status != .cancelled { self.analysis = values.0 }
            self.result = values.1; self.context = values.2; self.sourceLocation = values.3
            if generate || self.artifactOptions != options {
                self.artifact = values.1.artifact
                self.artifactOptions = values.1.artifact == nil ? nil : options
            }
            self.busy = false; self.work = nil
        }
        work = task; return task
    }
}
