import Foundation
import Observation

/// Independent source state; no Codable, SceneStorage or other working-data persistence.
@MainActor @Observable final class JSONDiffInput {
    var source = "" {
        didSet {
            guard !source.utf16.elementsEqual(oldValue.utf16) else { return }
            cancel(); result = nil; document = nil; context = nil; wasCancelled = false
            changed?()
        }
    }
    private(set) var result: JSONResult?
    private(set) var document: JSONStructureDocument?
    private(set) var context: JSONDiagnosticContext?
    private(set) var busy = false
    private(set) var wasCancelled = false
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?

    func cancel() {
        if busy { wasCancelled = true }
        work?.cancel(); work = nil; revision = UUID(); busy = false
    }
    @discardableResult func inspect() -> Task<Void, Never> {
        if result != nil { return Task {} }
        cancel(); wasCancelled = false
        guard !source.isEmpty else { return Task {} }
        let source = source, request = revision
        busy = true
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let capture = JSONProcessor.inspectStructure(source)
                let diagnostic = capture.result.diagnostics.first { $0.severity == .error } ?? capture.result.diagnostics.first
                let context: JSONDiagnosticContext?
                if case .resourceLimit = capture.result.status { context = nil }
                else { context = diagnostic.map { JSONDiagnosticContext.make(source: source, diagnostic: $0) } }
                return (capture, context)
            }
            let response = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.revision == request else { return }
            self.result = response.0.result; self.document = response.0.document; self.context = response.1
            self.busy = false; self.work = nil
        }
        work = task; return task
    }
}

@MainActor @Observable final class JSONDiffWorkspaceSession {
    let before = JSONDiffInput()
    let after = JSONDiffInput()
    var preferences: JSONToolPreferences { didSet { repository.save(preferences) } }
    var inputsCollapsed = false
    var inputFraction = 0.44
    var selection: Int?
    private(set) var result: JSONDiffResult?
    private(set) var rows: [Int] = []
    private(set) var rowNumbers: [Int: Int] = [:]
    private(set) var version = 0
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var scrollRequest = 0
    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?

    init(repository: JSONPreferencesRepository = .init()) {
        self.repository = repository; preferences = repository.load()
        before.changed = { [weak self] in self?.invalidate() }
        after.changed = { [weak self] in self?.invalidate() }
    }
    func input(_ side: JSONDiffSide) -> JSONDiffInput { side == .before ? before : after }
    func refreshPreferences() { preferences = repository.load() }
    private func invalidate() {
        stopComparison(); result = nil; rows = []; rowNumbers = [:]; selection = nil
        wasCancelled = false; version += 1
    }
    private func stopComparison() { work?.cancel(); work = nil; revision = UUID(); busy = false }
    func cancel() {
        wasCancelled = busy || before.busy || after.busy
        stopComparison(); before.cancel(); after.cancel()
    }
    @discardableResult func didPaste(_ side: JSONDiffSide) -> Task<Void, Never>? {
        preferences.validateOnPaste ? input(side).inspect() : nil
    }
    @discardableResult func compare() -> Task<Void, Never> {
        stopComparison(); wasCancelled = false
        guard !before.source.isEmpty, !after.source.isEmpty else { return Task {} }
        // Comparing the same pair preserves selection, native rows and current output.
        if result != nil { return Task {} }
        let request = revision
        busy = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.before.inspect().value
            guard !Task.isCancelled, self.revision == request else { return }
            await self.after.inspect().value
            guard !Task.isCancelled, self.revision == request else { return }
            guard let left = self.before.document, let right = self.after.document else {
                self.busy = false; self.work = nil; return
            }
            let worker = Task.detached(priority: .userInitiated) { () -> (JSONDiffResult, [Int], [Int: Int])? in
                guard let diff = try? JSONStructuralDiff.compare(left, right) else { return nil }
                let rows = Array(diff.changes.indices)
                return (diff, rows, Dictionary(uniqueKeysWithValues: rows.map { ($0, $0 + 1) }))
            }
            let response = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, self.revision == request else { return }
            if let response {
                self.result = response.0; self.rows = response.1; self.rowNumbers = response.2
                self.selection = response.1.first; self.version += 1; self.scrollRequest += 1
            }
            self.busy = false; self.work = nil
        }
        work = task; return task
    }
    func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = min(rows.count - 1, max(0, (selection ?? (delta > 0 ? -1 : rows.count)) + delta))
        scrollRequest += 1
    }
}
