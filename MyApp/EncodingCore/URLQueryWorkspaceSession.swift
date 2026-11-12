import Foundation
import Observation

@MainActor @Observable final class URLQueryWorkspaceSession {
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    private(set) var preferences: URLQueryPreferences
    private(set) var snapshot: URLQuerySnapshot?
    private(set) var draft: URLQueryDraft?
    private(set) var result: URLQueryInspection?
    private(set) var artifact: URLQueryArtifact?
    private(set) var buildIssues: [URLQueryIssue] = []
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var dirty = false
    private(set) var sourceRevision = UUID()
    private(set) var draftRevision = UUID()
    private(set) var listChange = URLQueryListChange.reload
    private(set) var listBaseRevision: UUID?
    private(set) var publicationID = UUID()
    var selectedID: Int?
    var outputForm = URLQueryOutputForm.preserve
    var inputCollapsed = false
    var fraction = 0.4
    var outputCollapsed = false
    var editName = ""
    var editValue = ""
    var editHasValue = true
    var replaceName = false
    var replaceValue = false
    private(set) var editingID: Int?
    private(set) var editIssue: String?
    var rows: [URLQueryRow] { draft?.rows ?? [] }
    var output: String? { outputForm == .preserve ? artifact?.preserve : artifact?.ascii }
    var canCopy: Bool { !busy && output != nil }
    var issues: [URLQueryIssue] { !buildIssues.isEmpty ? buildIssues : result?.issues ?? [] }
    var selectedRow: URLQueryRow? { guard let id = selectedID else { return nil }; return rows.first { $0.id == id } }
    var editingRow: URLQueryRow? { guard let id = editingID else { return nil }; return rows.first { $0.id == id } }
    var hasPendingEdit: Bool {
        guard let row = editingRow else { return false }
        return replaceName || replaceValue || editHasValue != row.hasValue ||
            !editName.utf16.elementsEqual((row.rawOnlyName ? "" : row.displayName).utf16) ||
            !editValue.utf16.elementsEqual((row.rawOnlyValue ? "" : row.displayValue ?? "").utf16)
    }
    var canUndo: Bool { _ = draftRevision; return !undoStack.isEmpty && !busy && editingID == nil }
    var canRedo: Bool { _ = draftRevision; return !redoStack.isEmpty && !busy && editingID == nil }
    typealias Inspector = @Sendable (String,URLQueryProfile) async -> URLQueryInspection
    typealias Builder = @Sendable (URLQuerySnapshot,URLQueryDraft) async -> URLQueryBuildResult
    @ObservationIgnored private let inspector: Inspector
    @ObservationIgnored private let builder: Builder
    @ObservationIgnored private let repository: URLQueryPreferencesRepository
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var request = UUID()
    private indirect enum Change { case replace(URLQueryRow), insert(URLQueryRow,Int), remove(Int), move(Int,Int), presence(Bool), group([Change]) }
    @ObservationIgnored private var undoStack: [Change] = []
    @ObservationIgnored private var redoStack: [Change] = []
    init(repository: URLQueryPreferencesRepository = .init(),
         inspector: @escaping Inspector = { URLQueryProcessor.inspect($0,profile:$1) },
         builder: @escaping Builder = { URLQueryProcessor.build($0,draft:$1) }) {
        self.repository = repository; preferences = repository.load(); self.inspector = inspector; self.builder = builder
    }
    func setWordWrap(_ value: Bool) { preferences.wordWrap = value; repository.save(preferences) }
    func setParseOnPaste(_ value: Bool) { preferences.parseOnPaste = value; repository.save(preferences) }
    @discardableResult func changeProfile(_ value: URLQueryProfile, discard: Bool = false) -> Bool {
        guard value != preferences.profile else { return true }
        guard discard || (!dirty && !hasPendingEdit) else { return false }
        stop(); preferences.profile = value; repository.save(preferences)
        snapshot = nil; draft = nil; artifact = nil; result = nil; buildIssues = []; selectedID = nil; cancelEdit(); historyReset(); dirty = false
        listChange = .reload; listBaseRevision = nil; draftRevision = UUID()
        parse(); return true
    }
    private func stop() { task?.cancel(); task = nil; request = UUID(); busy = false }
    private func historyReset() { undoStack.removeAll(); redoStack.removeAll() }
    private func invalidate() {
        stop(); snapshot = nil; draft = nil; result = nil; artifact = nil; buildIssues = []; selectedID = nil
        sourceRevision = UUID(); listChange = .reload; listBaseRevision = nil; draftRevision = UUID(); publicationID = UUID(); wasCancelled = false; dirty = false
        cancelEdit(); historyReset()
    }
    func clear() { if input.isEmpty { invalidate() } else { input = "" } }
    func cancel() { let running = busy; stop(); if running { wasCancelled = true } }
    @discardableResult func didPaste() -> Task<Void,Never>? { preferences.parseOnPaste ? parse() : nil }
    @discardableResult func parse() -> Task<Void,Never> {
        stop(); wasCancelled = false
        if snapshot != nil { return Task {} } // Same revision/profile is already parsed; preserve edits and Output.
        busy = true
        let source = input, revision = sourceRevision, profile = preferences.profile, token = request, worker = inspector
        let work = Task { [weak self] in
            let detached = Task.detached(priority:.userInitiated) { await worker(source,profile) }
            let value = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.request == token, self.sourceRevision == revision, self.preferences.profile == profile else { return }
            if value.status == .cancelled { self.wasCancelled = true }
            else {
                self.result = value; self.snapshot = value.snapshot; self.draft = value.snapshot.map(URLQueryDraft.init)
                self.artifact = nil; self.buildIssues = []; self.dirty = false; self.listChange = .reload; self.listBaseRevision = nil; self.draftRevision = UUID(); self.publicationID = UUID()
            }
            self.busy = false; self.task = nil
        }
        task = work; return work
    }
    @discardableResult func build() -> Task<Void,Never>? {
        guard let snapshot, let draft, editingID == nil else { return nil }
        stop(); wasCancelled = false; busy = true
        let token = request, source = sourceRevision, revision = draftRevision, worker = builder
        let work = Task { [weak self] in
            let detached = Task.detached(priority:.userInitiated) { await worker(snapshot,draft) }
            let value = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.request == token, self.sourceRevision == source, self.draftRevision == revision else { return }
            if value.status == .cancelled { self.wasCancelled = true }
            else { self.artifact = value.artifact; self.buildIssues = value.issues; self.publicationID = UUID() }
            self.busy = false; self.task = nil
        }
        task = work; return work
    }
    func beginEdit(_ id: Int) {
        guard !hasPendingEdit, let row = rows.first(where: { $0.id == id }) else { return }
        selectedID = id; editingID = id; replaceName = false; replaceValue = false
        editName = row.rawOnlyName ? "" : row.displayName
        editValue = row.rawOnlyValue ? "" : row.displayValue ?? ""; editHasValue = row.hasValue; editIssue = nil
    }
    func cancelEdit() { editingID = nil; editName = ""; editValue = ""; replaceName = false; replaceValue = false; editIssue = nil }
    @discardableResult func applyEdit() -> Bool {
        guard var row = editingRow else { return false }
        if row.rawOnlyName && !replaceName { /* preserve undecodable original */ }
        else if !editName.utf16.elementsEqual(row.displayName.utf16) { row.changedName = editName }
        if !editHasValue { row.rawValue = nil; row.value = nil; row.changedValue = nil }
        else if row.rawOnlyValue && !replaceValue { /* preserve undecodable original */ }
        else {
            if row.rawValue == nil { row.rawValue = ""; row.value = "" }
            if !editValue.utf16.elementsEqual((row.displayValue ?? "").utf16) || replaceValue { row.changedValue = editValue }
        }
        if replaceName { row.changedName = editName }
        var size = 0
        for item in rows {
            let value = item.id == row.id ? row : item
            size += (value.changedName ?? value.rawName).utf16.count + (value.changedValue ?? value.rawValue ?? "").utf16.count + (value.rawValue == nil ? 0 : 1) + 1
            if size > 262_144 { editIssue = "Draft exceeds the processing limit. Shorten the edited field."; return false }
        }
        cancelEdit(); perform(.replace(row)); return true
    }
    func add() {
        guard !busy, editingID == nil, var value = draft, value.rows.count < 262_144 else { return }
        let id = value.nextID; value.nextID += 1; draft = value
        let insertion = Change.insert(.init(id:id,rawName:"",rawValue:"",name:"",value:""),rows.count)
        perform(value.queryPresent ? insertion : .group([.presence(true),insertion])); beginEdit(id)
    }
    func remove(_ id: Int) { guard editingID == nil else { return }; perform(.remove(id)); if selectedID == id { selectedID = nil } }
    func move(_ id: Int, to index: Int) { guard editingID == nil else { return }; perform(.move(id,index)) }
    func setQueryPresent(_ value: Bool) { guard rows.isEmpty, editingID == nil else { return }; perform(.presence(value)) }
    func reset() {
        guard let snapshot else { return }; stop(); draft = .init(snapshot); artifact = nil; buildIssues = []
        selectedID = nil; cancelEdit(); historyReset(); dirty = false; listChange = .reload; listBaseRevision = nil; draftRevision = UUID()
    }
    func undo() { guard canUndo, let action = undoStack.popLast(), let inverse = mutate(action) else { return }; redoStack.append(inverse) }
    func redo() { guard canRedo, let action = redoStack.popLast(), let inverse = mutate(action) else { return }; undoStack.append(inverse) }
    private func perform(_ action: Change) {
        guard !busy, let inverse = mutate(action) else { return }; undoStack.append(inverse); redoStack.removeAll()
    }
    private func mutate(_ action: Change) -> Change? {
        guard draft != nil else { return nil }
        var inverse: Change?
        var update = URLQueryListChange.reload
        let base = draftRevision
        switch action {
        case .replace(let row):
            if let index = draft!.rows.firstIndex(where: { $0.id == row.id }) { inverse = .replace(draft!.rows[index]); draft!.rows[index] = row; update = .update(index) }
        case .insert(let row,let index): draft!.rows.insert(row,at:min(index,draft!.rows.count)); inverse = .remove(row.id); update = .insert(min(index,draft!.rows.count-1))
        case .remove(let id):
            if let index = draft!.rows.firstIndex(where: { $0.id == id }) { inverse = .insert(draft!.rows.remove(at:index),index); update = .remove(index) }
        case .move(let id,let target):
            if let index = draft!.rows.firstIndex(where: { $0.id == id }) {
                let row = draft!.rows.remove(at:index); draft!.rows.insert(row,at:max(0,min(target,draft!.rows.count))); inverse = .move(id,index); update = .move(index,max(0,min(target,draft!.rows.count-1)))
            }
        case .presence(let value): inverse = .presence(draft!.queryPresent); draft!.queryPresent = value
        case .group(let changes):
            var inverses: [Change] = []
            var rowUpdate: URLQueryListChange?
            for change in changes {
                if let action = mutate(change) { inverses.insert(action,at:0); if case .presence = change {} else { rowUpdate = listChange } }
            }
            inverse = .group(inverses); update = rowUpdate ?? .reload
        }
        if inverse != nil { listBaseRevision = base; listChange = update; stop(); artifact = nil; buildIssues = []; wasCancelled = false; dirty = true; draftRevision = UUID(); publicationID = UUID() }
        return inverse
    }
}
