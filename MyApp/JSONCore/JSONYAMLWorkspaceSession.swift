import Foundation
import Observation

/// Window-owned conversion state. Working text/results are deliberately not Codable.
@MainActor @Observable final class JSONYAMLWorkspaceSession {
    var input = "" {
        didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } }
    }
    var direction = JSONYAMLDirection.jsonToYAML { didSet { if direction != oldValue { invalidate() } } }
    var preferences: JSONToolPreferences {
        didSet {
            repository.save(preferences)
            if preferences.indentation != oldValue.indentation { invalidate() }
        }
    }
    var fraction = 0.5
    var outputCollapsed = false
    private(set) var result: JSONYAMLResult?
    private(set) var output: String?
    private(set) var context: JSONDiagnosticContext?
    private(set) var busy = false
    private(set) var wasCancelled = false
    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    init(repository: JSONPreferencesRepository = .init()) { self.repository = repository; preferences = repository.load() }
    func refreshPreferences() { preferences = repository.load() }
    private func stop() { work?.cancel(); work = nil; revision = UUID(); busy = false }
    private func invalidate() { stop(); result = nil; output = nil; context = nil; wasCancelled = false }
    func clear() { input = ""; invalidate() }
    func cancel() { if busy { wasCancelled = true }; stop() }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? run(convert: false) : nil }
    @discardableResult func run(convert: Bool = true) -> Task<Void, Never> {
        stop(); wasCancelled = false
        let request = revision, source = input, direction = direction, indentation = preferences.indentation
        busy = true
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let result = JSONYAMLConverter.process(source, direction: direction, indentation: indentation, produceOutput: convert)
                let diagnostic = result.status == .resourceLimit ? nil : result.diagnostics.first
                let context = diagnostic.map { JSONDiagnosticContext.make(source: source, range: $0.range, compactWhitespace: direction == .jsonToYAML) }
                return (result, context)
            }
            let processed = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.revision == request else { return }
            self.result = processed.0; self.context = processed.1
            if convert, processed.0.status == .success { self.output = processed.0.output }
            self.busy = false; self.work = nil
        }
        work = task; return task
    }
}
