import Foundation
import Observation

struct JSONPathRowData: Sendable {
    let nodeID: Int
    let path: String
    let preview: String
    let kind: JSONStructureNode.Kind
    static func make(_ id: Int, document: JSONStructureDocument) -> Self {
        let node = document.nodes[id]
        let chain = document.ancestors(of: id) + [id]
        // UI paths are previews; exact external paths are generated only on explicit actions.
        var path = chain.count > 5 ? "$…" : "$"
        for ancestor in chain.suffix(5) {
            let item = document.nodes[ancestor]
            if let key = item.key { path += "['" + JSONTreePreview.make(key, budget: 28).text + "']" }
            else if let index = item.arrayIndex { path += "[\(index)]" }
        }
        let preview = JSONTreePreview.make(node.scalar ?? node.summary, budget: 100).text
        return Self(nodeID: id, path: JSONTreePreview.make(path, budget: 150).text, preview: preview, kind: node.kind)
    }
}

private struct JSONPathPreparedEvaluation: Sendable {
    let result: JSONPathEvaluation
    let presentations: [Int: JSONPathRowData]
    let rows: [Int]
    let rowNumbers: [Int: Int]
}

/// One window's working state. No Codable, persistence or clipboard reads.
@MainActor @Observable final class JSONPathWorkspaceSession {
    enum Status: Equatable { case ready, checking, running, complete, invalidJSON, invalidQuery, blocked, limited, cancelled }
    var input = "" {
        didSet {
            guard !input.utf16.elementsEqual(oldValue.utf16) else { return }
            stop(); document = nil; validation = nil; context = nil; invalidateResults(); status = .ready
        }
    }
    var query = "" {
        didSet {
            guard !query.utf16.elementsEqual(oldValue.utf16) else { return }
            stop(); invalidateResults(); status = .ready
        }
    }
    var preferences: JSONToolPreferences { didSet { repository.save(preferences) } }
    var inputCollapsed = false
    var panelFraction = 0.42
    var selection: Int?
    private(set) var document: JSONStructureDocument?
    private(set) var validation: JSONResult?
    private(set) var context: JSONDiagnosticContext?
    private(set) var result: JSONPathEvaluation?
    private(set) var presentations: [Int: JSONPathRowData] = [:]
    private(set) var rows: [Int] = []
    private(set) var rowNumbers: [Int: Int] = [:]
    private(set) var version = 0
    private(set) var status: Status = .ready
    private(set) var failure: JSONPathFailure?
    private(set) var scrollRequest = 0
    private(set) var scrollTarget: Int?
    var busy: Bool { status == .checking || status == .running }
    var selectedNodeID: Int? {
        guard let selection, let result, result.nodeIDs.indices.contains(selection) else { return nil }
        return result.nodeIDs[selection]
    }
    var resourceLimited: Bool { if case .resourceLimit = validation?.status { return true }; return false }
    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(repository: JSONPreferencesRepository = .init()) { self.repository = repository; preferences = repository.load() }
    func refreshPreferences() { preferences = repository.load() }
    private func stop() { task?.cancel(); task = nil; revision = UUID() }
    private func invalidateResults() {
        result = nil; presentations = [:]; rows = []; rowNumbers = [:]; selection = nil
        failure = nil; scrollTarget = nil; version += 1
    }
    func clear() { input = ""; validation = nil; context = nil; failure = nil; status = .ready }
    func cancel() { let wasBusy = busy; stop(); if wasBusy { status = .cancelled } }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? inspect() : nil }
    @discardableResult func inspect() -> Task<Void, Never> { perform(execute: false) }
    @discardableResult func run() -> Task<Void, Never> {
        if result != nil { return Task {} } // Same exact source/query revision; preserve native viewport/selection.
        return perform(execute: true)
    }
    private func perform(execute: Bool) -> Task<Void, Never> {
        stop(); failure = nil
        guard !input.isEmpty else { status = .ready; return Task {} }
        if execute && query.isEmpty { status = .invalidQuery; failure = .syntax("Enter a JSONPath query beginning with '$'.", NSRange(location: 0, length: 0)); return Task {} }
        let source = input, query = query, request = revision, cached = document, oldValidation = validation
        status = cached == nil ? .checking : .running
        let pending = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> (JSONStructureResult, JSONDiagnosticContext?, JSONPathPreparedEvaluation?, JSONPathFailure?, Bool) in
                let parsed = cached.map { JSONStructureResult(result: oldValidation ?? JSONResult(output: nil, diagnostics: []), document: $0) } ?? JSONProcessor.inspectStructure(source)
                var context: JSONDiagnosticContext?
                if case .resourceLimit = parsed.result.status {} else if let diagnostic = parsed.result.diagnostics.first(where: { $0.severity == .error }) ?? parsed.result.diagnostics.first {
                    context = JSONDiagnosticContext.make(source: source, diagnostic: diagnostic)
                }
                guard execute, let document = parsed.document, !Task.isCancelled else { return (parsed, context, nil, nil, Task.isCancelled) }
                do {
                    let evaluation = try JSONPathOperations.evaluate(query, in: document)
                    var presentations: [Int: JSONPathRowData] = [:]
                    for id in evaluation.nodeIDs {
                        try Task.checkCancellation()
                        if presentations[id] == nil { presentations[id] = .make(id, document: document) }
                    }
                    let rows = Array(evaluation.nodeIDs.indices)
                    let numbers = Dictionary(uniqueKeysWithValues: rows.map { ($0, $0 + 1) })
                    try Task.checkCancellation()
                    return (parsed, context, JSONPathPreparedEvaluation(result: evaluation, presentations: presentations, rows: rows, rowNumbers: numbers), nil, false)
                } catch is CancellationError { return (parsed, context, nil, nil, true) }
                catch let error as JSONPathFailure { return (parsed, context, nil, error, false) }
                catch { return (parsed, context, nil, .evaluation("The query could not be evaluated."), false) }
            }
            let response = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.revision == request else { return }
            self.document = response.0.document; self.validation = response.0.result; self.context = response.1
            self.failure = response.3; self.task = nil
            if response.4 || response.0.result.status == .cancelled { self.status = .cancelled }
            else if case .resourceLimit = response.0.result.status { self.status = .limited }
            else if response.0.result.status == .invalid { self.status = .invalidJSON }
            else if let failure = response.3 {
                switch failure {
                case .limit: self.status = .limited
                case .duplicates: self.status = .blocked
                default: self.status = .invalidQuery
                }
            } else if let result = response.2 {
                self.result = result.result; self.presentations = result.presentations
                self.rows = result.rows; self.rowNumbers = result.rowNumbers
                self.status = .complete; self.version += 1
            } else { self.status = .ready }
        }
        task = pending; return pending
    }
    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = min(rows.count - 1, max(0, (selection ?? (delta > 0 ? -1 : rows.count)) + delta))
        scrollTarget = selection; scrollRequest += 1
    }
}
