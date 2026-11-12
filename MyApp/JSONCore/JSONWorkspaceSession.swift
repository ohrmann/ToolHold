import Foundation
import Observation

/// Window-owned, memory only. Neither this object nor its working data is Codable.
@MainActor @Observable
final class JSONWorkspaceSession {
    var input = "" {
        didSet {
            // Canonical String equality can hide a change to the exact JSON source.
            guard !input.utf16.elementsEqual(oldValue.utf16) else { return }
            cancel()
            output = nil
            result = nil
            context = nil
            wasCancelled = false
        }
    }
    private(set) var output: String?
    private(set) var result: JSONResult?
    private(set) var busy = false
    private(set) var context: JSONDiagnosticContext?
    private(set) var wasCancelled = false
    var preferences: JSONToolPreferences { didSet { repository.save(preferences) } }
    var panelFraction = 0.5
    var outputCollapsed = false

    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    init(repository: JSONPreferencesRepository = .init()) {
        self.repository = repository
        preferences = repository.load()
    }

    func refreshPreferences() { preferences = repository.load() }

    var resourceLimited: Bool {
        if case .resourceLimit = result?.status { return true }
        return false
    }

    /// Called only by the native paste completion hook, after updating input.
    @discardableResult
    func didPaste() -> Task<Void, Never>? {
        preferences.validateOnPaste ? run(.validate) : nil
    }

    func clear() {
        input = ""
        cancel()
        output = nil
        result = nil
        context = nil
        wasCancelled = false
    }

    func cancel() {
        if busy { wasCancelled = true }
        stopWork()
    }

    private func stopWork() {
        work?.cancel()
        work = nil
        revision = UUID()
        busy = false
    }

    @discardableResult
    func run(_ operation: JSONProcessor.Operation) -> Task<Void, Never> {
        stopWork()
        wasCancelled = false
        let request = revision
        let source = input
        let indentation = preferences.indentation
        busy = true
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let result = JSONProcessor.process(source, operation: operation, indentation: indentation)
                let diagnostic = result.diagnostics.first { $0.severity == .error } ?? result.diagnostics.first
                let context: JSONDiagnosticContext?
                if case .resourceLimit = result.status { context = nil }
                else { context = diagnostic.map { JSONDiagnosticContext.make(source: source, diagnostic: $0) } }
                return (result, context)
            }
            let processed = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.revision == request else { return }
            self.result = processed.0
            self.context = processed.1
            // Validation and cancellation never discard a current successful transformation.
            if operation != .validate, processed.0.isValid, let output = processed.0.output {
                self.output = output
            }
            self.busy = false
            self.work = nil
        }
        work = task
        return task
    }
}
