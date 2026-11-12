import Foundation
import Observation

@MainActor @Observable final class IdentifierWorkspaceSession {
    var preferences: IdentifierPreferences {
        didSet {
            guard preferences != oldValue else { return }
            repository.save(preferences); settingsChanged()
        }
    }
    var countText: String {
        didSet {
            guard countText != oldValue else { return }
            if let count = Self.number(countText), (1...10_000).contains(count) { preferences.count = count }
            settingsChanged()
        }
    }
    var lengthText: String {
        didSet {
            guard lengthText != oldValue else { return }
            if let count = Self.number(lengthText), (1...256).contains(count) { preferences.nanoLength = count }
            settingsChanged()
        }
    }
    var customAlphabet = "" { didSet { if customAlphabet != oldValue { settingsChanged() } } }
    var selection: Int?
    var showDetails = false
    private(set) var batch: IdentifierBatch?
    private(set) var busy = false { didSet { if busy != oldValue { renderVersion &+= 1 } } }
    private(set) var copying = false { didSet { if copying != oldValue { renderVersion &+= 1 } } }
    private(set) var issue: IdentifierIssue?
    private(set) var renderVersion = 0
    private(set) var batchVersion = 0
    private(set) var rows = [Int]()
    private(set) var rowNumbers = [Int: Int]()
    typealias Worker = @Sendable (IdentifierGenerator, IdentifierOptions) async -> IdentifierResult
    typealias Serializer = @Sendable (IdentifierBatch, IdentifierCopyFormat) async throws -> String
    @ObservationIgnored private let repository: IdentifierPreferencesRepository
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private let serializer: Serializer
    @ObservationIgnored private let makeEngine: @Sendable () -> IdentifierGenerator
    @ObservationIgnored private var engine: IdentifierGenerator
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var copyRequest = UUID()
    @ObservationIgnored private var revision = UUID()
    init(repository: IdentifierPreferencesRepository = .init(), makeEngine: @escaping @Sendable () -> IdentifierGenerator = { IdentifierGenerator() },
         worker: @escaping Worker = runIdentifierGeneration,
         serializer: @escaping Serializer = { batch, format in try IdentifierSerialization.text(batch, format: format) }) {
        self.repository = repository; self.worker = worker; self.serializer = serializer
        self.makeEngine = makeEngine; engine = makeEngine()
        let prefs = repository.load(); preferences = prefs; countText = String(prefs.count); lengthText = String(prefs.nanoLength)
    }
    deinit { task?.cancel(); copyTask?.cancel() }
    static func number(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.count <= 6, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }
    var options: IdentifierOptions {
        .init(kind: preferences.kind, count: Self.number(countText) ?? 0, uuidCase: preferences.uuidCase,
              ulidMonotonic: preferences.ulidMonotonic, nanoLength: Self.number(lengthText) ?? 0,
              alphabet: preferences.nanoAlphabetPreset, customAlphabet: customAlphabet)
    }
    var validationIssue: IdentifierIssue? { options.issue }
    var canGenerate: Bool { !busy && validationIssue == nil }
    var canCopy: Bool { !busy && !copying && batch != nil }
    var settingsDiffer: Bool { batch.map { $0.options != options.effective } ?? false }
    var selectedValue: String? { guard let selection, let batch, batch.values.indices.contains(selection) else { return nil }; return batch.values[selection] }
    var statusText: String {
        if busy { return batch == nil ? "Generating…" : "Previous batch; generating…" }
        if copying { return "Preparing copy…" }
        if let issue { return issue.message }
        if settingsDiffer { return "Settings changed — Generate to apply" }
        if let batch { return "Generated \(batch.values.count) identifier\(batch.values.count == 1 ? "" : "s")" }
        return "Ready"
    }
    private func stopCopy() { copyRequest = UUID(); copyTask?.cancel(); copyTask = nil; copying = false }
    private func stop() { request = UUID(); task?.cancel(); task = nil; busy = false; stopCopy() }
    private func settingsChanged() { stop(); revision = UUID(); issue = nil }
    func cancel() { let running = busy || copying; stop(); if running { issue = .init(.cancelled, "Cancelled") } }
    func clear() {
        stop(); revision = UUID(); engine = makeEngine(); batch = nil; selection = nil; showDetails = false
        customAlphabet = ""; if preferences.nanoAlphabetPreset == .custom { preferences.nanoAlphabetPreset = .urlSafe }
        issue = nil; rows = []; rowNumbers = [:]; batchVersion &+= 1; renderVersion &+= 1
    }
    @discardableResult func run() -> Task<Void, Never>? {
        guard canGenerate else { return nil }
        stop(); issue = nil; busy = true
        let id = request, rev = revision, options = options.effective, engine = engine, worker = worker
        let job = Task { [weak self] in
            let child = Task.detached(priority: .userInitiated) { await worker(engine, options) }
            let value = await withTaskCancellationHandler { await child.value } onCancel: { child.cancel() }
            guard !Task.isCancelled, let self, self.request == id, self.revision == rev else { return }
            if let batch = value.batch {
                self.batch = batch; self.selection = nil; self.showDetails = false
                self.rows = Array(batch.values.indices)
                self.rowNumbers = Dictionary(uniqueKeysWithValues: self.rows.map { ($0, $0 + 1) })
                self.batchVersion &+= 1; self.renderVersion &+= 1
            }
            self.issue = value.issue; self.busy = false; self.task = nil
        }
        task = job; return job
    }
    @discardableResult func copyAll(_ format: IdentifierCopyFormat, publish: @escaping @MainActor (String) -> Void) -> Task<Void, Never>? {
        guard canCopy, let batch else { return nil }
        stopCopy(); copying = true
        let id = copyRequest, rev = revision, serializer = serializer
        let job = Task { [weak self] in
            let child = Task.detached(priority: .userInitiated) { try await serializer(batch, format) }
            do {
                let text = try await withTaskCancellationHandler { try await child.value } onCancel: { child.cancel() }
                guard !Task.isCancelled, let self, self.copyRequest == id, self.revision == rev, self.batch?.id == batch.id else { return }
                self.copying = false; self.copyTask = nil; publish(text)
            } catch {
                guard !Task.isCancelled, let self, self.copyRequest == id else { return }
                self.copying = false; self.copyTask = nil
                self.issue = (error as? IdentifierIssue) ?? .init(.cancelled, "Copy cancelled")
            }
        }
        copyTask = job; return job
    }
    func copyValue(at index: Int) -> String? { guard canCopy, let batch, batch.values.indices.contains(index) else { return nil }; return batch.values[index] }
}

private func runIdentifierGeneration(_ engine: IdentifierGenerator, _ options: IdentifierOptions) async -> IdentifierResult {
    await engine.generate(options)
}
