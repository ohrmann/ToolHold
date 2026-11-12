import Foundation
import Observation

/// Window-owned conversion state. Working text/results are deliberately not Codable.
@MainActor @Observable final class JSONCSVWorkspaceSession {
    var input = "" {
        didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } }
    }
    var direction = JSONCSVDirection.toDelimited { didSet { if direction != oldValue { invalidate() } } }
    var options = JSONCSVOptions() { didSet { if options != oldValue { invalidate() } } }
    var inputName: String { direction == .toDelimited ? "JSON" : options.format.rawValue }
    var outputName: String { direction == .toJSON ? "JSON" : options.format.rawValue }
    var preferences: JSONToolPreferences {
        didSet {
            repository.save(preferences)
            if preferences.indentation != oldValue.indentation { invalidate() }
        }
    }
    var fraction = 0.5
    var outputCollapsed = false
    private(set) var result: JSONCSVResult?
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
        let request = revision, source = input, direction = direction, options = options, indentation = preferences.indentation
        busy = true
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let result = JSONCSVConverter.process(source, direction: direction, options: options, indentation: indentation, produceOutput: convert)
                let diagnostic = result.status == .resourceLimit || result.diagnostics.first?.code == "TABLE-OPTIONS" ? nil : result.diagnostics.first
                let context = diagnostic.map { JSONDiagnosticContext.make(source: source, range: $0.range, compactWhitespace: direction == .toDelimited) }
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
