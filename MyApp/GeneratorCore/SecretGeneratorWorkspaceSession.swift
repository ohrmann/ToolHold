import Foundation
import Observation

@MainActor @Observable final class SecretGeneratorWorkspaceSession {
    let kind: SecretGeneratorKind
    var preferences: SecretGeneratorPreferences {
        didSet { guard preferences != oldValue else { return }; repository.save(preferences); settingsChanged() }
    }
    var lengthText: String {
        didSet {
            guard lengthText != oldValue else { return }
            if let n = Self.number(lengthText), (8...128).contains(n) { preferences.length = n }
            settingsChanged()
        }
    }
    var countText: String {
        didSet {
            guard countText != oldValue else { return }
            if let n = Self.number(countText), (1...1000).contains(n) {
                if kind == .password { preferences.passwordCount = n } else { preferences.phraseCount = n }
            }
            settingsChanged()
        }
    }
    var wordsText: String {
        didSet {
            guard wordsText != oldValue else { return }
            if let n = Self.number(wordsText), (4...16).contains(n) { preferences.wordCount = n }
            settingsChanged()
        }
    }
    var mode = PasswordAlphabetMode.standard { didSet { if mode != oldValue { settingsChanged() } } }
    var customAlphabet = "" { didSet { if customAlphabet != oldValue { settingsChanged() } } }
    var exclusions = "" { didSet { if exclusions != oldValue { settingsChanged() } } }
    var advanced = false
    var showDetails = false
    var selection: Int?
    private(set) var hidden = false { didSet { if hidden != oldValue { renderVersion &+= 1 } } }
    private(set) var batch: SecretBatch?
    private(set) var busy = false { didSet { if busy != oldValue { renderVersion &+= 1 } } }
    private(set) var copying = false { didSet { if copying != oldValue { renderVersion &+= 1 } } }
    private(set) var issue: SecretIssue?
    private(set) var renderVersion = 0
    private(set) var batchVersion = 0
    private(set) var rows = [Int]()
    private(set) var rowNumbers = [Int: Int]()
    typealias Worker = @Sendable (SecretGeneratorRequest) async -> SecretResult
    typealias Serializer = @Sendable (SecretBatch, SecretCopyFormat) async throws -> String
    @ObservationIgnored private let repository: SecretGeneratorPreferencesRepository
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private let serializer: Serializer
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var child: Task<SecretResult, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private var pending: (id: UUID, revision: UUID, options: SecretGeneratorRequest)?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var copyRequest = UUID()
    init(kind: SecretGeneratorKind, repository: SecretGeneratorPreferencesRepository? = nil,
         worker: @escaping Worker = { SecretGenerator.generate($0) },
         serializer: @escaping Serializer = { try SecretSerialization.text($0, format: $1) }) {
        self.kind = kind; self.repository = repository ?? .init(kind: kind); self.worker = worker; self.serializer = serializer
        let prefs = self.repository.load(); preferences = prefs
        lengthText = String(prefs.length); wordsText = String(prefs.wordCount)
        countText = String(kind == .password ? prefs.passwordCount : prefs.phraseCount)
    }
    deinit { child?.cancel(); pump?.cancel(); copyTask?.cancel() }
    static func number(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.count <= 4, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }; return Int(text)
    }
    var options: SecretGeneratorRequest {
        switch kind {
        case .password:
            .password(.init(length: Self.number(lengthText) ?? 0, count: Self.number(countText) ?? 0, mode: mode,
                lowercase: preferences.lowercase, uppercase: preferences.uppercase, digits: preferences.digits, symbols: preferences.symbols,
                requireEveryGroup: preferences.requireEveryGroup, excludeSimilar: preferences.excludeSimilar, exclusions: exclusions, customAlphabet: customAlphabet))
        case .passphrase:
            .passphrase(.init(wordCount: Self.number(wordsText) ?? 0, count: Self.number(countText) ?? 0,
                separator: preferences.separator, letterCase: preferences.letterCase, appendDigit: preferences.appendDigit))
        }
    }
    var validationIssue: SecretIssue? { options.issue }
    var canGenerate: Bool { !busy && validationIssue == nil }
    var canCopy: Bool { !busy && !copying && batch != nil }
    var settingsDiffer: Bool { batch.map { $0.options != options.effective } ?? false }
    var selectedValue: String? {
        guard let batch, let selection, batch.values.indices.contains(selection) else { return nil }; return batch.values[selection]
    }
    var statusText: String {
        if busy { return batch == nil ? "Generating…" : "Previous results; generating…" }
        if copying { return "Preparing copy…" }
        if let issue { return issue.message }
        if settingsDiffer { return "Settings changed — Generate to apply" }
        if let batch { return "Generated \(batch.values.count) \(kind == .password ? "password" : "phrase")\(batch.values.count == 1 ? "" : "s")" }
        return "Ready"
    }
    private func stopCopy() { copyRequest = UUID(); copyTask?.cancel(); copyTask = nil; copying = false }
    private func stop() { request = UUID(); pending = nil; child?.cancel(); busy = false; stopCopy() }
    private func settingsChanged() { stop(); revision = UUID(); issue = nil }
    func cancel() { let running = busy || copying; stop(); if running { issue = .init(.cancelled, "Cancelled") } }
    func concealSecrets() { hidden = true; stopCopy() }
    func toggleVisibility() { hidden.toggle() }
    func clear() {
        stop(); revision = UUID(); batch = nil; selection = nil; showDetails = false
        customAlphabet = ""; exclusions = ""; mode = .standard
        rows = []; rowNumbers = [:]; issue = nil; batchVersion &+= 1; renderVersion &+= 1
    }
    func resetSettings() {
        customAlphabet = ""; exclusions = ""; mode = .standard; preferences = .init()
        lengthText = "13"; wordsText = "6"; countText = "1"; settingsChanged()
    }
    /// A single worker plus one replaceable pending request, even if a test worker ignores cancellation.
    @discardableResult func run() -> Task<Void, Never>? {
        guard canGenerate else { return nil }
        stop(); issue = nil; busy = true
        pending = (request, revision, options.effective)
        if pump == nil {
            let job = Task { [weak self] in
                while let snapshot = self?.pending {
                    guard let worker = self?.worker else { return }
                    self?.pending = nil
                    let child = Task.detached(priority: .userInitiated) { await worker(snapshot.options) }
                    self?.child = child
                    let result = await withTaskCancellationHandler { await child.value } onCancel: { child.cancel() }
                    guard let self else { return }
                    self.child = nil
                    if !Task.isCancelled, self.request == snapshot.id, self.revision == snapshot.revision {
                        if let batch = result.batch {
                            self.batch = batch; self.selection = batch.values.count == 1 ? 0 : nil; self.showDetails = false
                            self.rows = Array(batch.values.indices)
                            self.rowNumbers = Dictionary(uniqueKeysWithValues: self.rows.map { ($0, $0 + 1) })
                            self.batchVersion &+= 1; self.renderVersion &+= 1
                        }
                        self.issue = result.issue; self.busy = false
                    }
                }
                self?.pump = nil
            }
            pump = job
        }
        return pump
    }
    @discardableResult func copyAll(_ format: SecretCopyFormat, publish: @escaping @MainActor (String) -> Void) -> Task<Void, Never>? {
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
                self.issue = (error as? SecretIssue) ?? .init(.cancelled, "Copy cancelled")
            }
        }
        copyTask = job; return job
    }
    func copyValue(at index: Int) -> String? {
        guard canCopy, let batch, batch.values.indices.contains(index) else { return nil }; return batch.values[index]
    }
}
