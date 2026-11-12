import Foundation
import Observation

@MainActor @Observable final class BasicAuthWorkspaceSession {
    var username = "" { didSet { if !username.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var password = "" { didSet { if !password.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var preferences: BasicAuthPreferences {
        didSet { repository.save(preferences); if preferences.options != oldValue.options { invalidate() } }
    }
    var showPassword = false
    var showHeader = false
    private(set) var sourceRevision = UUID()
    private(set) var result: BasicAuthResult?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var rejectedInput: BasicAuthIssue?
    typealias Worker = @Sendable (BasicAuthRequest) async -> BasicAuthResult
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private let repository: BasicAuthPreferencesRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    var canCopy: Bool { !busy && result?.artifact != nil }
    var statusText: String {
        if busy { return "Processing" }
        if wasCancelled { return "Cancelled" }
        guard let result else { return "Ready" }
        switch result.status {
        case .success: return "Header generated"
        case .invalidCredentials: return "Invalid input"
        case .unrepresentableText: return "Encoding unavailable"
        case .resourceLimit: return "Resource limit reached"
        case .cancelled: return "Cancelled"
        case .processingFailure: return "Processing failed"
        }
    }
    init(repository: BasicAuthPreferencesRepository = .init(), worker: @escaping Worker = { BasicAuthProcessor.build($0) }) {
        self.repository = repository; preferences = repository.load(); self.worker = worker
    }
    private func stop() { task?.cancel(); task = nil; requestID = UUID(); busy = false }
    private func invalidate() {
        stop(); sourceRevision = UUID(); result = nil; wasCancelled = false; rejectedInput = nil
        showHeader = false
    }
    func refreshPreferences() { preferences = repository.load() }
    func hideSensitiveData() { showPassword = false; showHeader = false }
    func reject(_ issue: BasicAuthIssue) {
        rejectedInput = .init(code: issue.code, field: issue.field, message: "Input rejected. " + issue.message + " Previous values are unchanged.")
    }
    func clear() { username = ""; password = ""; invalidate(); hideSensitiveData() }
    func cancel() { let running = busy; stop(); if running { wasCancelled = true } }
    func copyText(fullHeader: Bool) -> String? {
        guard canCopy, let artifact = result?.artifact else { return nil }
        return fullHeader ? artifact.fullHeader : artifact.headerValue
    }
    @discardableResult func run() -> Task<Void, Never> {
        stop(); busy = true; wasCancelled = false; rejectedInput = nil
        let id = requestID, revision = sourceRevision, worker = worker
        let snapshot = BasicAuthRequest(username: username, password: password, options: preferences.options)
        let job = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let child = Task.detached(priority: .userInitiated) { await worker(snapshot) }
            let value = await withTaskCancellationHandler { await child.value } onCancel: { child.cancel() }
            guard !Task.isCancelled, let self, self.requestID == id, self.sourceRevision == revision else { return }
            if value.status == .cancelled { self.wasCancelled = true } else { self.result = value }
            self.busy = false; self.task = nil
        }
        task = job; return job
    }
}
