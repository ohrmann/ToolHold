import Foundation
import Observation

/// Only existing editor preferences persist. Table/source/filter/selection are window-memory only.
@MainActor @Observable final class CSVTableWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var format = DelimitedFormat.csv { didSet { if format != oldValue { invalidate() } } }
    var hasHeader = true { didSet { if hasHeader != oldValue { invalidate() } } }
    var query = "" { didSet { if query != oldValue { scheduleProjection(debounce: true) } } }
    var sort: CSVTableSort? { didSet { if sort != oldValue { scheduleProjection() } } }
    var preferences: JSONToolPreferences { didSet { repository.save(preferences) } }
    var selection: CSVTableSelection?
    var inputCollapsed = false
    var fraction = 0.42
    var columnWidth = 180.0
    var scrollRequest = 0
    private(set) var result: CSVTableResult?
    private(set) var projection: CSVTableProjection?
    private(set) var context: JSONDiagnosticContext?
    private(set) var busy = false
    private(set) var filtering = false
    private(set) var wasCancelled = false
    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var filterWork: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var filterRevision = UUID()
    var document: CSVTableDocument? { result?.document }
    init(repository: JSONPreferencesRepository = .init()) { self.repository = repository; preferences = repository.load() }
    func refreshPreferences() { preferences = repository.load() }
    private func stop() {
        work?.cancel(); filterWork?.cancel(); work = nil; filterWork = nil
        revision = UUID(); filterRevision = UUID(); busy = false; filtering = false
    }
    private func invalidate() {
        stop(); result = nil; projection = nil; context = nil; selection = nil; wasCancelled = false
    }
    func clear() { input = ""; invalidate() }
    func cancel() { wasCancelled = busy || filtering; stop() }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? build() : nil }
    @discardableResult func build() -> Task<Void, Never> {
        if document != nil { return Task {} }
        stop(); wasCancelled = false; busy = true
        let source = input, format = format, header = hasHeader, request = revision, query = query, sort = sort
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let result = CSVTableProcessor.build(source, format: format, hasHeader: header)
                let context = result.status != .resourceLimit ? result.diagnostics.first.map { JSONDiagnosticContext.make(source: source, range: $0.range, compactWhitespace: false) } : nil
                let projection = result.document.flatMap { try? CSVTableProcessor.project($0, query: query, sort: sort) }
                return (result, context, projection)
            }
            let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.revision == request else { return }
            self.result = value.0; self.context = value.1; self.projection = value.2; self.busy = false; self.work = nil
            if self.query != query || self.sort != sort { self.scheduleProjection() }
        }
        work = task; return task
    }
    @discardableResult func scheduleProjection(debounce: Bool = false) -> Task<Void, Never>? {
        filterWork?.cancel(); filterRevision = UUID()
        guard let document else { return nil }
        let request = filterRevision, query = query, sort = sort
        filtering = true
        let task = Task { [weak self] in
            if debounce { do { try await Task.sleep(for: .milliseconds(160)) } catch { return } }
            let worker = Task.detached(priority: .userInitiated) { try? CSVTableProcessor.project(document, query: query, sort: sort) }
            let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.filterRevision == request, self.document?.id == document.id, let value else { return }
            self.projection = value; self.filtering = false; self.filterWork = nil
            if let selection = self.selection, value.positions[selection.row] < 0 { self.selection = nil }
        }
        filterWork = task; return task
    }
    func toggleSort(_ column: Int) {
        if sort?.column == column { sort = sort?.ascending == true ? .init(column: column, ascending: false) : nil }
        else { sort = .init(column: column, ascending: true) }
    }
    @discardableResult func go(row: Int, column: Int) -> Bool {
        guard let document, let projection, row >= 0, row < document.rowCount,
              column >= 0, column < document.record(row).cells.count, projection.positions[row] >= 0 else { return false }
        selection = .init(row: row, column: column); scrollRequest += 1; return true
    }
    func move(row delta: Int, column horizontal: Int) {
        guard let document, let projection, !projection.rows.isEmpty else { return }
        let current = selection ?? .init(row: projection.rows[0], column: 0)
        let position = max(0, projection.positions[current.row])
        let row = projection.rows[min(projection.rows.count - 1, max(0, position + delta))]
        let column = min(document.record(row).cells.count - 1, max(0, current.column + horizontal))
        go(row: row, column: column)
    }
}
