import Foundation
import Observation

@MainActor @Observable final class TokenWorkspaceSession {
    var options: TokenOptions {
        didSet {
            guard options != oldValue else { return }
            save(); stop(); issue = nil
            refreshPresentationIfNeeded()
        }
    }
    var bytesText: String { didSet { if bytesText != oldValue { changedNumber() } } }
    var countText: String { didSet { if countText != oldValue { changedNumber() } } }
    private(set) var batch: TokenBatch?
    private(set) var presentation: TokenPresentation?
    private(set) var busy = false { didSet { renderVersion &+= 1 } }
    private(set) var copying = false { didSet { renderVersion &+= 1 } }
    private(set) var hidden = false { didSet { renderVersion &+= 1 } }
    private(set) var issue: SecretIssue?
    var selection: Int?
    var details = false
    private(set) var renderVersion = 0
    private(set) var rowsVersion = 0
    private(set) var rows = [Int]()
    private(set) var rowNumbers = [Int: Int]()
    typealias Worker = @Sendable (TokenOptions) async -> TokenResult
    private enum Work: Sendable { case generate(TokenOptions), present(TokenBatch, TokenOptions) }
    private struct Completion: Sendable { var batch: TokenBatch?; var presentation: TokenPresentation?; var issue: SecretIssue? }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var copyID = UUID()
    @ObservationIgnored private var pending: (UUID, Work)?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var child: Task<Completion, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    static let key = "toolbox.token.preferences.v1"
    init(defaults: UserDefaults = .standard, worker: @escaping Worker = { TokenGenerator.generate($0) }) {
        self.defaults = defaults; self.worker = worker
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(TokenOptions.self, from: $0) }
        let loaded = saved.flatMap { $0.valid ? $0 : nil } ?? TokenOptions()
        options = loaded; bytesText = String(loaded.bytes); countText = String(loaded.count)
    }
    deinit { child?.cancel(); pump?.cancel(); copyTask?.cancel() }
    private func save() { if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: Self.key) } }
    private func changedNumber() {
        stop(); issue = nil
        if let b = Self.number(bytesText), let c = Self.number(countText), (1...1024).contains(b), (1...1000).contains(c) {
            var v = options; v.bytes = b; v.count = c; options = v
        }
        if !busy { refreshPresentationIfNeeded() }
    }
    private func refreshPresentationIfNeeded() {
        if let batch, presentation?.encoding != options.encoding || presentation?.uppercase != options.uppercase {
            enqueue(.present(batch, options))
        }
    }
    static func number(_ text: String) -> Int? { guard !text.isEmpty, text.utf8.count <= 4, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }; return Int(text) }
    var valid: Bool { Self.number(bytesText).map { (1...1024).contains($0) } == true && Self.number(countText).map { (1...1000).contains($0) } == true }
    var canGenerate: Bool { !busy && valid }
    var canCopy: Bool { !busy && !copying && presentation != nil && presentation?.encoding == options.encoding && presentation?.uppercase == options.uppercase }
    var settingsDiffer: Bool { batch.map { $0.size != Self.number(bytesText) || $0.bytes.count != Self.number(countText) } ?? false }
    var status: String {
        if busy { return batch == nil ? "Generating…" : "Previous results · processing…" }
        if copying { return "Preparing copy…" }
        if let issue { return issue.message }
        if !valid { return "Bytes: 1–1024 · Count: 1–1000" }
        if settingsDiffer { return "Settings changed — Generate to apply" }
        return batch.map { "Generated \($0.bytes.count) token(s) · secret output" } ?? "Ready"
    }
    private func stopCopy() { copyID = UUID(); copyTask?.cancel(); copyTask = nil; copying = false }
    private func stop() { request = UUID(); pending = nil; child?.cancel(); busy = false; stopCopy() }
    func cancel() { stop(); issue = .init(.cancelled, "Cancelled") }
    func concealSecrets() { hidden = true; stopCopy() }
    func toggleVisibility() { hidden.toggle() }
    func clear() { stop(); batch = nil; presentation = nil; selection = nil; details = false; issue = nil; rows = []; rowNumbers = [:]; rowsVersion &+= 1; renderVersion &+= 1 }
    func resetSettings() { bytesText = "32"; countText = "1"; options = .init() }
    @discardableResult func run() -> Task<Void, Never>? { guard canGenerate else { return nil }; stop(); return enqueue(.generate(options)) }
    @discardableResult private func enqueue(_ work: Work) -> Task<Void, Never>? {
        issue = nil; busy = true; pending = (request, work)
        if pump == nil {
            pump = Task { [weak self] in
                while let (id, work) = self?.pending {
                    guard let worker = self?.worker else { return }; self?.pending = nil
                    let child = Task.detached(priority: .userInitiated) { () -> Completion in
                        let result: TokenResult, opts: TokenOptions
                        switch work {
                        case .generate(let v): result = await worker(v); opts = v
                        case .present(let b, let v): result = .init(batch: b); opts = v
                        }
                        guard let batch = result.batch else { return .init(issue: result.issue) }
                        do { return .init(batch: batch, presentation: try TokenGenerator.present(batch, encoding: opts.encoding, uppercase: opts.uppercase)) }
                        catch { return .init(issue: .init(.cancelled, "Cancelled")) }
                    }
                    self?.child = child
                    let result = await withTaskCancellationHandler { await child.value } onCancel: { child.cancel() }
                    guard let self else { return }; self.child = nil
                    if !Task.isCancelled, self.request == id {
                        if let batch = result.batch, let presentation = result.presentation {
                            let new = self.batch?.id != batch.id
                            self.batch = batch; self.presentation = presentation
                            if new { self.selection = batch.bytes.count == 1 ? 0 : nil; self.rows = Array(batch.bytes.indices); self.rowNumbers = Dictionary(uniqueKeysWithValues: self.rows.map { ($0, $0 + 1) }); self.rowsVersion &+= 1 }
                            self.renderVersion &+= 1
                        }
                        self.issue = result.issue; self.busy = false
                    }
                }
                self?.pump = nil
            }
        }
        return pump
    }
    @discardableResult func copyAll(json: Bool, publish: @escaping @MainActor (String) -> Void) -> Task<Void, Never>? {
        guard canCopy, let presentation else { return nil }; stopCopy(); copying = true
        let id = copyID, rev = request
        let task = Task { [weak self] in
            let child = Task.detached { try TokenGenerator.serialize(presentation, json: json) }
            do {
                let value = try await withTaskCancellationHandler { try await child.value } onCancel: { child.cancel() }
                guard let self, self.copyID == id, self.request == rev, !Task.isCancelled else { return }
                self.copying = false; self.copyTask = nil; publish(value)
            } catch { if let self, self.copyID == id { self.copying = false; self.copyTask = nil } }
        }
        copyTask = task; return task
    }
    func copy(_ index: Int, publish: (String) -> Void) {
        guard canCopy, let p = presentation, p.values.indices.contains(index) else { return }; publish(p.values[index])
    }
}
