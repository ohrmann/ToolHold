import Foundation
import Observation

/// One window, memory only. Source-scoped work is never encoded or restored.
@MainActor @Observable
final class JSONTreeWorkspaceSession {
    var input = "" {
        didSet {
            guard !input.utf16.elementsEqual(oldValue.utf16) else { return }
            cancelAll(); document = nil; result = nil; context = nil
            visible = []; rowNumbers = [:]; manualExpanded = []; searchExpanded = []; selection = nil
            matches = []; matchesByNode = [:]; activeMatch = nil; wasCancelled = false
            scrollTarget = nil; renderVersion += 1
            rowsVersion += 1; rowChanges = nil
        }
    }
    var query = "" { didSet { if !query.utf16.elementsEqual(oldValue.utf16) { scheduleSearch() } } }
    var preferences: JSONToolPreferences { didSet { repository.save(preferences) } }
    var inputCollapsed = false
    var panelFraction = 0.4
    var selection: Int?
    private(set) var document: JSONStructureDocument?
    private(set) var result: JSONResult?
    private(set) var context: JSONDiagnosticContext?
    private(set) var busy = false
    private(set) var searching = false
    private(set) var projecting = false
    private(set) var wasCancelled = false
    private(set) var renderVersion = 0
    private(set) var rowsVersion = 0
    private(set) var rowChanges: JSONTreeRowChanges?
    private(set) var visible: [Int] = []
    private(set) var rowNumbers: [Int: Int] = [:]
    private(set) var manualExpanded: Set<Int> = []
    private(set) var searchExpanded: Set<Int> = []
    private(set) var matches: [JSONTreeMatch] = []
    private(set) var matchesByNode: [Int: JSONTreeNodeMatches] = [:]
    private(set) var activeMatch: Int?
    private(set) var scrollTarget: Int?
    private(set) var scrollRequest = 0
    @ObservationIgnored private let repository: JSONPreferencesRepository
    @ObservationIgnored private var parseTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var projectionTask: Task<Void, Never>?
    @ObservationIgnored private var searchRevealAllowed = true
    @ObservationIgnored private var sourceRevision = UUID()
    @ObservationIgnored private var queryRevision = UUID()
    @ObservationIgnored private var projectionRevision = UUID()

    init(repository: JSONPreferencesRepository = .init()) { self.repository = repository; preferences = repository.load() }
    var resourceLimited: Bool { if case .resourceLimit = result?.status { return true }; return false }
    var activeHidden: Bool { activeMatch.map { rowNumbers[matches[$0].nodeID] == nil } ?? false }
    func expanded(_ id: Int) -> Bool { manualExpanded.contains(id) || searchExpanded.contains(id) }
    func refreshPreferences() { preferences = repository.load() }
    @discardableResult func didPaste() -> Task<Void, Never>? { preferences.validateOnPaste ? build() : nil }
    func clear() { input = ""; result = nil; context = nil; wasCancelled = false }
    func cancel() {
        wasCancelled = busy || projecting || searching
        cancelAll()
    }
    private func cancelAll() {
        parseTask?.cancel(); searchTask?.cancel(); projectionTask?.cancel()
        sourceRevision = UUID(); queryRevision = UUID(); projectionRevision = UUID()
        busy = false; searching = false; projecting = false
    }
    @discardableResult func build() -> Task<Void, Never> {
        if document != nil { return Task {} } // Current source already has a valid immutable snapshot.
        cancelAll(); wasCancelled = false; busy = true
        let source = input, revision = sourceRevision
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let parsed = JSONProcessor.inspectStructure(source)
                let diagnostic = parsed.result.diagnostics.first { $0.severity == .error } ?? parsed.result.diagnostics.first
                let context: JSONDiagnosticContext?
                if case .resourceLimit = parsed.result.status { context = nil }
                else { context = diagnostic.map { JSONDiagnosticContext.make(source: source, diagnostic: $0) } }
                let expanded: Set<Int> = parsed.document?.nodes[0].canExpand == true ? [0] : []
                let visible = parsed.document.flatMap { try? JSONTreeOperations.projection($0, expanded: expanded) } ?? []
                return (parsed, context, expanded, visible, Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($0.element, $0.offset + 1) }))
            }
            let response = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.sourceRevision == revision else { return }
            self.document = response.0.document; self.result = response.0.result; self.context = response.1
            self.manualExpanded = response.2; self.searchExpanded = []; self.visible = response.3; self.rowNumbers = response.4
            self.busy = false; self.parseTask = nil; self.renderVersion += 1
            self.rowsVersion += 1; self.rowChanges = nil
            if !self.query.isEmpty { self.scheduleSearch() }
        }
        parseTask = task; return task
    }
    @discardableResult func toggle(_ id: Int) -> Task<Void, Never>? {
        guard let document, document.nodes[id].canExpand else { return nil }
        var manual = manualExpanded, temporary = searchExpanded
        if expanded(id) {
            manual.remove(id)
            searchRevealAllowed = false
            // A manual collapse wins until an explicit next/previous reveal.
            temporary = Set(temporary.filter { $0 != id && !document.ancestors(of: $0).contains(id) })
        } else { manual.insert(id) }
        return project(manual: manual, temporary: temporary)
    }
    @discardableResult func expandAll() -> Task<Void, Never>? { project(manual: [], temporary: [], all: true) }
    @discardableResult func collapseAll() -> Task<Void, Never>? {
        searchRevealAllowed = false
        return project(manual: [], temporary: [])
    }

    @discardableResult private func project(manual: Set<Int>, temporary: Set<Int>, all: Bool = false,
                                           reveal: Int? = nil) -> Task<Void, Never>? {
        guard let document else { return nil }
        projectionTask?.cancel(); projectionRevision = UUID()
        let request = projectionRevision, source = sourceRevision
        let oldRows = visible, oldVersion = rowsVersion
        projecting = true
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> (Set<Int>, [Int], [Int: Int], JSONTreeRowChanges)? in
                do {
                    var expanded = manual
                    if all {
                        for node in document.nodes {
                            if node.id & 255 == 0 { try Task.checkCancellation() }
                            if node.canExpand { expanded.insert(node.id) }
                        }
                    }
                    let visible = try JSONTreeOperations.projection(document, expanded: expanded.union(temporary))
                    let changes = try JSONTreeRowChanges.between(oldRows, visible, baseVersion: oldVersion)
                    return (expanded, visible, Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($0.element, $0.offset + 1) }), changes)
                } catch { return nil }
            }
            let response = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.sourceRevision == source, self.projectionRevision == request else { return }
            if let response {
                self.manualExpanded = response.0; self.searchExpanded = temporary; self.visible = response.1; self.rowNumbers = response.2
                self.rowChanges = response.3; self.rowsVersion += 1
                if let reveal { self.scrollTarget = reveal; self.scrollRequest += 1 }
            }
            self.projecting = false; self.projectionTask = nil; self.renderVersion += 1
        }
        projectionTask = task; return task
    }
    @discardableResult func scheduleSearch() -> Task<Void, Never>? {
        searchTask?.cancel(); queryRevision = UUID(); searchRevealAllowed = true
        matches = []; matchesByNode = [:]; activeMatch = nil; scrollTarget = nil; renderVersion += 1
        _ = project(manual: manualExpanded, temporary: [])
        guard let document, !query.isEmpty else { searching = false; return nil }
        let query = query, request = queryRevision, source = sourceRevision
        searching = true
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> ([JSONTreeMatch], [Int: JSONTreeNodeMatches])? in
                do {
                    try await Task.sleep(for: .milliseconds(180))
                    let matches = try JSONTreeOperations.search(query, in: document)
                    var byNode: [Int: JSONTreeNodeMatches] = [:]
                    for (index, match) in matches.enumerated() {
                        if index & 255 == 0 { try Task.checkCancellation() }
                        if match.field == .key { byNode[match.nodeID, default: JSONTreeNodeMatches()].key.append(index) }
                        else { byNode[match.nodeID, default: JSONTreeNodeMatches()].value.append(index) }
                    }
                    return (matches, byNode)
                } catch { return nil }
            }
            let response = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.sourceRevision == source, self.queryRevision == request else { return }
            self.searching = false
            guard let response else { return }
            self.matches = response.0; self.matchesByNode = response.1; self.renderVersion += 1
            if !self.matches.isEmpty {
                self.activeMatch = 0
                if self.searchRevealAllowed { await self.navigateMatch(0)?.value }
            }
        }
        searchTask = task; return task
    }
    @discardableResult func nextMatch(backwards: Bool = false) -> Task<Void, Never>? {
        guard !matches.isEmpty else { return nil }
        // A single hidden match must reveal again, even though its index doesn't change.
        let next = ((activeMatch ?? (backwards ? 0 : -1)) + (backwards ? -1 : 1) + matches.count) % matches.count
        return navigateMatch(next)
    }
    @discardableResult private func navigateMatch(_ index: Int) -> Task<Void, Never>? {
        guard let document else { return nil }
        activeMatch = index
        let id = matches[index].nodeID
        selection = id
        return project(manual: manualExpanded, temporary: Set(document.ancestors(of: id)), reveal: id)
    }
    func moveSelection(_ offset: Int) {
        guard !visible.isEmpty else { return }
        let old = selection.flatMap { visible.firstIndex(of: $0) } ?? (offset > 0 ? -1 : visible.count)
        selection = visible[min(visible.count - 1, max(0, old + offset))]
        scrollTarget = selection; scrollRequest += 1
    }
    func moveHorizontal(right: Bool) {
        guard let document, let id = selection else { return }
        let node = document.nodes[id]
        if right {
            if node.canExpand, !expanded(id) { toggle(id) }
            else if let first = node.children.first { selection = first; scrollTarget = first; scrollRequest += 1 }
        } else {
            if node.canExpand, expanded(id) { toggle(id) }
            else if let parent = node.parent { selection = parent; scrollTarget = parent; scrollRequest += 1 }
        }
    }
}
