import Foundation
import Observation

/// Memory-only working state. The Codable allowlist below contains appearance settings only.
@MainActor @Observable public final class QRCodeWorkspaceSession {
    public var input = "" { didSet { if !input.utf8.elementsEqual(oldValue.utf8) { updatePayload() } } }
    public var contentKind: QRContentKind = .freeText { didSet { if contentKind != oldValue { updatePayload() } } }
    public var fields = QRContentFields() { didSet { if contentKind != .freeText { updatePayload() } } }
    public private(set) var payload = ""
    private var contentIssue: String?
    private func updatePayload() {
        do { payload = try QRCodeContent.make(contentKind,text:input,fields:fields); contentIssue = nil }
        catch { payload = ""; contentIssue = (error as? QRIssue)?.message ?? "Check the content fields." }
        changed()
    }
    public var preferences: QRPreferences {
        didSet {
            guard preferences != oldValue else { return }
            if preferences.valid, let bytes = try? JSONEncoder().encode(preferences) { defaults.set(bytes,forKey:Self.key) }
            if preferences.design != oldValue.design { changed() }
        }
    }
    public private(set) var logo: QRLogo?
    public private(set) var artifact: QRArtifact?
    public private(set) var busy = false
    public private(set) var preparing = false
    public private(set) var loadingLogo = false
    public private(set) var issue: String?
    public private(set) var revision = UUID()
    public private(set) var publication = UUID()
    public private(set) var copyMessage: String?
    public static let key = "toolbox.qr.preferences.v1"
    public typealias Worker = @Sendable (String,QRPreferences,QRLogo?,QRArtifact?) async throws -> QRArtifact
    private struct Request: Sendable { let id: UUID; let source: String; let preferences: QRPreferences; let logo: QRLogo?; let previous: QRArtifact? }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private var publishedRevision: UUID?
    @ObservationIgnored private var pending: Request?
    @ObservationIgnored private var debounce: Task<Void,Never>?
    @ObservationIgnored private var pump: Task<Void,Never>?
    @ObservationIgnored private var child: Task<QRArtifact,Error>?
    @ObservationIgnored private var outputTask: Task<Void,Never>?
    @ObservationIgnored private var outputID = UUID()
    @ObservationIgnored private var logoTask: Task<Void,Never>?
    @ObservationIgnored private var logoID = UUID()
    public init(defaults: UserDefaults = .standard, worker: @escaping Worker = { try QRCodeProcessor.generate(source:$0,preferences:$1,logo:$2,previous:$3) }) {
        self.defaults = defaults; self.worker = worker
        preferences = defaults.data(forKey:Self.key).flatMap { try? JSONDecoder().decode(QRPreferences.self,from:$0) }.flatMap { $0.valid ? $0 : nil } ?? QRPreferences()
    }
    deinit { child?.cancel(); pump?.cancel(); debounce?.cancel(); outputTask?.cancel(); logoTask?.cancel() }
    public var isCurrent: Bool { publishedRevision == revision && artifact != nil }
    public var canOutput: Bool { isCurrent && !busy && !preparing && !loadingLogo && artifact?.verification.passed == true }
    public var status: String {
        if loadingLogo { return "Loading logo…" }
        if preparing { return "Preparing and checking final image…" }
        if busy { return artifact == nil ? "Generating and checking…" : "Updating · previous preview" }
        if let issue { return issue }
        if let artifact, isCurrent { return artifact.verification.message }
        return contentIssue ?? (payload.isEmpty ? "Enter content to generate a QR code" : "Not checked · Generate to update")
    }
    private func stopOutput() { outputID = UUID(); outputTask?.cancel(); outputTask = nil; preparing = false; copyMessage = nil }
    private func invalidate() {
        revision = UUID(); debounce?.cancel(); debounce = nil; child?.cancel(); pending = nil; busy = false; issue = nil; stopOutput()
    }
    private func changed() {
        invalidate()
        guard !payload.isEmpty else { if contentIssue == nil { artifact = nil }; publishedRevision = nil; return }
        busy = true
        let id = revision
        debounce = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(250)) } catch { return }
            guard let self, self.revision == id else { return }
            self.debounce = nil; self.enqueue()
        }
    }
    public func generate() { revision = UUID(); debounce?.cancel(); debounce = nil; child?.cancel(); stopOutput(); enqueue() }
    private func enqueue() {
        guard !payload.isEmpty else { busy = false; issue = contentIssue; if contentIssue == nil { artifact = nil }; publishedRevision = nil; return }
        issue = nil; busy = true
        pending = Request(id:revision,source:payload,preferences:preferences,logo:logo,previous:artifact)
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while let request = self?.pending {
                guard let worker = self?.worker else { return }; self?.pending = nil
                let child = Task.detached(priority:.userInitiated) { try await worker(request.source,request.preferences,request.logo,request.previous) }
                self?.child = child
                let result = await withTaskCancellationHandler { await child.result } onCancel: { child.cancel() }
                guard let self else { return }; self.child = nil
                if self.revision == request.id && !Task.isCancelled {
                    self.busy = false
                    switch result {
                    case .success(let artifact):
                        self.artifact = artifact; self.publishedRevision = request.id; self.publication = UUID(); self.issue = nil
                    case .failure(let error):
                        self.issue = error is CancellationError ? "Cancelled" : (error as? QRIssue)?.message ?? "The system could not process this QR code."
                        self.publishedRevision = nil
                    }
                }
            }
            self?.pump = nil
        }
    }
    public func cancel() {
        // An unchanged, previously valid result stays current after cancellation.
        debounce?.cancel(); debounce = nil; pending = nil; child?.cancel(); busy = false
        stopOutput(); logoID = UUID(); logoTask?.cancel(); logoTask = nil; loadingLogo = false
        revision = UUID(); if isCurrentSnapshot { publishedRevision = revision }
        issue = "Cancelled"
    }
    private var isCurrentSnapshot: Bool {
        guard let a = artifact else { return false }
        return a.matrix.payload == Data(payload.utf8) && a.preferences.design == preferences.design && a.logo?.id == logo?.id
    }
    public func clear() {
        logoID = UUID(); logoTask?.cancel(); logoTask = nil; loadingLogo = false
        input = ""; fields = .init(); payload = ""; contentIssue = nil; invalidate(); artifact = nil; publishedRevision = nil
    }
    public func resetAppearance() { removeLogo(); preferences = .init() }
    public func removeLogo() {
        logoID = UUID(); logoTask?.cancel(); logoTask = nil; loadingLogo = false
        if logo != nil { logo = nil; changed() }
    }
    public func setLogo(_ value: QRLogo) { logoID = UUID(); logoTask?.cancel(); loadingLogo = false; logo = value; changed() }
    public func loadLogo(_ url: URL) {
        logoID = UUID(); let id = logoID
        logoTask?.cancel(); stopOutput(); loadingLogo = true; issue = nil
        logoTask = Task { [weak self] in
            let child = Task.detached { try QRCodeLogoLoader.load(url) }
            let result = await withTaskCancellationHandler { await child.result } onCancel: { child.cancel() }
            guard let self, self.logoID == id, !Task.isCancelled else { return }
            self.loadingLogo = false; self.logoTask = nil
            switch result {
            case .success(let logo): self.logo = logo; self.changed()
            case .failure(let error): self.issue = error is CancellationError ? "Cancelled" : (error as? QRIssue)?.message ?? "The image could not be opened. Choose a local PNG, JPEG or HEIC file."
            }
        }
    }
    @discardableResult public func prepare(_ format: QRExportFormat, publish: @escaping @MainActor (QRExport) -> Void) -> Task<Void,Never>? {
        guard canOutput, let artifact else { return nil }
        stopOutput(); preparing = true
        let id = outputID, rev = revision
        let task = Task { [weak self] in
            let child = Task.detached(priority:.userInitiated) { try QRCodeProcessor.export(artifact,format:format) }
            let result = await withTaskCancellationHandler { await child.result } onCancel: { child.cancel() }
            guard let self, self.outputID == id, self.revision == rev, !Task.isCancelled else { return }
            self.preparing = false; self.outputTask = nil
            switch result {
            case .success(let output): publish(output)
            case .failure(let error): self.issue = error is CancellationError ? "Cancelled" : (error as? QRIssue)?.message ?? "The image could not be exported."
            }
        }
        outputTask = task; return task
    }
    public func copied() { copyMessage = "Image copied" }
}
