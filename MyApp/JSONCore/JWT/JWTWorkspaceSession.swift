import Foundation
import Observation

@MainActor @Observable final class JWTWorkspaceSession {
    enum Section: String, CaseIterable { case claims = "Claims", header = "Header", payload = "Payload", signature = "Signature" }
    enum Copy { case token, raw(JWTComponent), formatted(JWTComponent), value(Int), fragment(Int), signature }
    var input = "" {
        didSet {
            guard !input.utf16.elementsEqual(oldValue.utf16) else { return }
            cancel(); sourceRevision = UUID(); result = nil; evaluation = nil; selection = nil; wasCancelled = false
            inputDiagnostic = nil; headerDiagnostic = nil; payloadDiagnostic = nil; clearJumps()
        }
    }
    var preferences: JWTPreferences {
        didSet { repository.save(preferences); if oldValue.timeZoneMode != preferences.timeZoneMode { refreshTime() } }
    }
    var section = Section.claims
    var selection: Int?
    var inputCollapsed = false
    var fraction = 0.4
    private(set) var masked = false
    private(set) var sourceRevision = UUID()
    private(set) var renderVersion = 0
    private(set) var rowsVersion = 0
    private(set) var result: JWTInspectionResult?
    private(set) var evaluation: JWTTimeEvaluation?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var inputTarget: NSRange?
    private(set) var headerTarget: NSRange?
    private(set) var payloadTarget: NSRange?
    private(set) var jumpRequest = 0
    private(set) var inputDiagnostic: JSONDiagnostic?
    private(set) var headerDiagnostic: JSONDiagnostic?
    private(set) var payloadDiagnostic: JSONDiagnostic?
    @ObservationIgnored private let repository: JWTPreferencesRepository
    @ObservationIgnored private let worker: @Sendable (String, JWTBudget) async -> JWTInspectionResult
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var clockRequest = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeTask: Task<Void, Never>?
    init(repository: JWTPreferencesRepository = .init(), worker: @escaping @Sendable (String, JWTBudget) async -> JWTInspectionResult = { JWTProcessor.inspect($0, budget: $1) }) {
        self.repository = repository; preferences = repository.load(); self.worker = worker
    }
    deinit { task?.cancel(); timeTask?.cancel() }
    func clearJumps() { inputTarget = nil; headerTarget = nil; payloadTarget = nil; jumpRequest += 1 }
    func setMasked(_ value: Bool) { clearJumps(); masked = value }
    func cancel() { task?.cancel(); task = nil; timeTask?.cancel(); request = UUID(); clockRequest = UUID(); wasCancelled = busy; busy = false }
    func disappear() { clearJumps(); cancel() }
    func clear() { input = ""; result = nil; evaluation = nil }
    func refreshPreferences() { preferences = repository.load() }
    func didPaste() { if preferences.decodeOnPaste && !masked { run() } }
    @discardableResult func run() -> Task<Void, Never> {
        guard !masked else { return Task {} }
        cancel(); busy = true; wasCancelled = false; clearJumps()
        let revision = sourceRevision, request = request, text = input, worker = worker
        let work = Task { [weak self] in
            let budget = JWTBudget()
            let detached = Task.detached(priority: .userInitiated) { await worker(text, budget) }
            let watchdog = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { detached.cancel() } }
            let response = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            watchdog.cancel()
            guard !Task.isCancelled, let self, self.sourceRevision == revision, self.request == request else { return }
            self.busy = false; self.task = nil
            if response.processing == .cancelled { self.wasCancelled = true; return }
            self.result = response; self.renderVersion += 1; self.rowsVersion += 1
            self.inputDiagnostic = Self.diagnostic(response.issues.first(where: { $0.anchor?.space == .input }), source: text)
            self.headerDiagnostic = Self.diagnostic(response.issues.first(where: { $0.anchor?.space == .json(.header) }), source: response.parts[.header]?.text ?? "")
            self.payloadDiagnostic = Self.diagnostic(response.issues.first(where: { $0.anchor?.space == .json(.payload) }), source: response.parts[.payload]?.text ?? "")
            self.refreshTime()
        }
        task = work; return work
    }
    @discardableResult func refreshTime(now: Date = .now) -> Task<Void, Never> {
        timeTask?.cancel(); clockRequest = UUID()
        guard let result else { evaluation = nil; return Task {} }
        let id = result.id, clock = clockRequest, local = preferences.timeZoneMode == .local
        let work = Task { [weak self] in
            let detached = Task.detached { JWTNumericDate.evaluate(result, now: now, local: local) }
            let value = await withTaskCancellationHandler { await detached.value } onCancel: { detached.cancel() }
            guard !Task.isCancelled, let self, self.result?.id == id, self.clockRequest == clock else { return }
            self.evaluation = value; self.renderVersion += 1; self.timeTask = nil
        }
        timeTask = work; return work
    }
    func display(_ component: JWTComponent) -> String {
        guard let part = result?.parts[component] else { return "" }
        return preferences.jsonPresentation == .formatted ? part.presentation?.text ?? part.text ?? "" : part.text ?? ""
    }
    func copy(_ kind: Copy) -> String? {
        guard !masked, let result else { return nil }
        switch kind {
        case .token: return result.token
        case .raw(let part): return result.parts[part]?.text
        case .formatted(let part): return result.parts[part]?.presentation?.text
        case .signature:
            guard let encoded = result.parts[.signature]?.encoded, !encoded.isEmpty else { return nil }; return encoded
        case .value(let id):
            guard let document = result.parts[.payload]?.document, document.nodes.indices.contains(id) else { return nil }
            let node = document.nodes[id]
            return node.kind == .object || node.kind == .array ? nil : node.scalar
        case .fragment(let id):
            guard let document = result.parts[.payload]?.document, document.nodes.indices.contains(id) else { return nil }
            return document.fragment(id)
        }
    }
    func show(_ anchor: JWTAnchor) {
        guard !masked else { return }
        clearJumps()
        switch anchor.space {
        case .input: inputCollapsed = false; inputTarget = anchor.range
        case .json(let part):
            preferences.jsonPresentation = .raw
            section = part == .header ? .header : .payload
            if part == .header { headerTarget = anchor.range } else { payloadTarget = anchor.range }
        case .bytes: break // Byte offsets must not become text offsets.
        }
    }
    func showClaim(_ id: Int) {
        guard !masked, let part = result?.parts[.payload], let doc = part.document, doc.nodes.indices.contains(id) else { return }
        clearJumps(); section = .payload
        payloadTarget = preferences.jsonPresentation == .formatted ? part.presentation?.nodeRanges[id] ?? doc.nodes[id].range : doc.nodes[id].range
    }
    static func diagnostic(_ issue: JWTIssue?, source: String) -> JSONDiagnostic? {
        guard let issue, let anchor = issue.anchor else { return nil }
        if let diagnostic = issue.diagnostic { return diagnostic }
        let coordinates = JSONSourceCoordinates(source).location(at: anchor.range.location)
        return .init(severity: issue.severity == .error ? .error : .warning, code: issue.code, message: issue.message, range: anchor.range, line: coordinates.line, column: coordinates.column)
    }
}
