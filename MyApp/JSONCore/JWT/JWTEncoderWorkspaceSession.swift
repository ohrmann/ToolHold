import Foundation
import Observation

@MainActor @Observable final class JWTEncoderWorkspaceSession {
    var header: String { didSet { if !header.utf16.elementsEqual(oldValue.utf16) { invalidate(); synchronizeAlgorithm() } } }
    var payload = "{}" { didSet { if !payload.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var key = "" { didSet { if !key.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    /// Derived presentation state only; never an input to signing.
    private(set) var algorithm: JWTSigningAlgorithm?
    @ObservationIgnored private(set) var algorithmTask: Task<Void, Never>?
    var unsignedConsent = false { didSet { if unsignedConsent != oldValue { invalidate() } } }
    var preferences: JWTEncoderPreferences {
        didSet {
            repository.save(preferences)
            if preferences.keyEncoding != oldValue.keyEncoding || preferences.serialization != oldValue.serialization { invalidate() }
        }
    }
    var fraction = 0.57
    var masked = false
    var keyRevealed = true
    var tokenRevealed = true
    private(set) var revision = UUID()
    private(set) var editorEpoch = UUID()
    private(set) var result: JWTEncoderResult?
    private(set) var artifact: JWTEncoderArtifact?
    private(set) var busy = false
    private(set) var jumpRequest = 0
    private(set) var headerTarget: NSRange?
    private(set) var payloadTarget: NSRange?
    @ObservationIgnored private let repository: JWTEncoderPreferencesRepository
    @ObservationIgnored private let worker: @Sendable (JWTEncoderRequest, JWTEncoderMode, JWTBudget) async -> JWTEncoderResult
    private struct Job { let id: UUID; let request: JWTEncoderRequest; let mode: JWTEncoderMode }
    @ObservationIgnored private var pending: Job?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var pipeline: Task<Void, Never>?
    @ObservationIgnored private var active: Task<JWTEncoderResult, Never>?
    init(repository: JWTEncoderPreferencesRepository = .init(), worker: @escaping @Sendable (JWTEncoderRequest, JWTEncoderMode, JWTBudget) async -> JWTEncoderResult = { JWTEncoderProcessor.process($0, mode: $1, budget: $2) }) {
        self.repository = repository; let value = repository.load(); preferences = value; algorithm = value.signedAlgorithm
        header = Self.template(value.signedAlgorithm); self.worker = worker
    }
    deinit { pipeline?.cancel(); active?.cancel(); algorithmTask?.cancel() }
    static func template(_ alg: JWTSigningAlgorithm) -> String { "{\n  \"alg\": \"\(alg.rawValue)\",\n  \"typ\": \"JWT\"\n}" }
    private func synchronizeAlgorithm() {
        algorithmTask?.cancel()
        let source = header
        algorithmTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let worker = Task.detached(priority: .userInitiated) { JWTEncoderProcessor.headerAlgorithm(source) }
            let value = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.header.utf16.elementsEqual(source.utf16) else { return }
            self.algorithm = value
            if let value, value != .none { self.preferences.signedAlgorithm = value }
        }
    }
    private func invalidate() {
        cancel(); revision = UUID(); result = nil; artifact = nil; clearJumps()
    }
    func clearJumps() { headerTarget = nil; payloadTarget = nil; jumpRequest += 1 }
    func cancel() {
        pending = nil; active?.cancel(); requestID = UUID()
        if busy { result = .init(status: .cancelled) }
        busy = false
    }
    func clear() {
        cancel(); key = ""; unsignedConsent = false
        algorithm = preferences.signedAlgorithm
        header = Self.template(preferences.signedAlgorithm); payload = "{}"
        result = nil; artifact = nil; keyRevealed = true; tokenRevealed = true; masked = false
        clearJumps(); editorEpoch = UUID()
    }
    func hide() { keyRevealed = false; tokenRevealed = false; masked = true; clearJumps() }
    func reveal() { masked = false; keyRevealed = true; tokenRevealed = true }
    func concealSecrets() { keyRevealed = false; tokenRevealed = false; clearJumps() }
    func disappear() { cancel(); clearJumps() }
    var snapshot: JWTEncoderRequest { .init(header: header, payload: payload, key: key, keyEncoding: preferences.keyEncoding, serialization: preferences.serialization, unsignedConsent: unsignedConsent, revision: revision) }
    /// At most one active operation and one replaceable pending snapshot. Cancelling
    /// a non-interruptible SecKey call never launches another concurrent crypto call.
    @discardableResult func run(_ mode: JWTEncoderMode = .generate) -> Task<Void, Never> {
        guard !masked else { return Task {} }
        active?.cancel(); clearJumps(); busy = true; requestID = UUID()
        pending = .init(id: requestID, request: snapshot, mode: mode)
        if let pipeline { return pipeline }
        let task = Task { [weak self] in
            while let job = self?.takePending() {
                let budget = JWTBudget(), worker = self!.worker
                let task = Task.detached(priority: .userInitiated) { await worker(job.request, job.mode, budget) }
                self?.active = task
                let watchdog = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { task.cancel() } }
                var response = await task.value; watchdog.cancel()
                if ContinuousClock.now >= budget.deadline {
                    response = .init(status: .resourceLimit, issues: [.init(code: "ENCODER-DEADLINE", component: .operation, severity: .error, message: "Processing time limit reached.")], issueCount: 1)
                }
                self?.publish(response, for: job)
            }
            self?.active = nil; self?.pipeline = nil
        }
        pipeline = task; return task
    }
    private func takePending() -> Job? { let value = pending; pending = nil; return value }
    private func publish(_ response: JWTEncoderResult, for job: Job) {
        guard revision == job.request.revision, requestID == job.id else { return }
        busy = false; result = response
        if let artifact = response.artifact { self.artifact = artifact }
    }
    func didPaste() { if preferences.checkJSONOnPaste { run(.jsonOnly) } }
    func diagnostic(_ component: JWTEncoderIssue.Component) -> JSONDiagnostic? {
        result?.issues.first(where: { $0.component == component && $0.severity == .error })?.diagnostic
    }
    func show(_ issue: JWTEncoderIssue, related: Bool = false) {
        guard !masked, result?.issues.contains(where: { $0.id == issue.id }) == true, let diagnostic = issue.diagnostic else { return }
        let range = related ? diagnostic.related.first?.range : diagnostic.range
        guard let range else { return }
        clearJumps()
        switch issue.component {
        case .header: headerTarget = range
        case .payload: payloadTarget = range
        default: return
        }
    }
    func copy(bearer: Bool = false) -> String? {
        guard !masked, let artifact, artifact.revision == revision else { return nil }
        return (bearer ? "Bearer " : "") + artifact.token
    }
}
