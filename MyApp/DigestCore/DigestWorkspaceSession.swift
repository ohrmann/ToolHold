import Foundation
import Observation
#if SWIFT_PACKAGE
import EncodingCore
#endif

struct DigestPreferences: Codable, Equatable, Sendable {
    var mode = DigestSourceMode.text
    var algorithms: [DigestAlgorithm] = [.sha256]
    var hmac = DigestAlgorithm.sha256
    var keyProfile = ExactByteProfile.text
    var format = DigestFormat.hex
    var uppercase = false
    var expectedProfile = ExactByteProfile.hex
}
@MainActor @Observable final class DigestWorkspaceSession {
    let isHMAC: Bool
    var preferences: DigestPreferences {
        didSet {
            guard preferences != oldValue else { return }; save()
            if preferences.mode != oldValue.mode || preferences.algorithms != oldValue.algorithms || preferences.hmac != oldValue.hmac || preferences.keyProfile != oldValue.keyProfile { invalidate(); inspectKey() }
        }
    }
    var text = "" { didSet { if !text.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var key = "" { didSet { if !key.utf8.elementsEqual(oldValue.utf8) { invalidate(); inspectKey() } } }
    var allowEmptyKey = false { didSet { if allowEmptyKey != oldValue { invalidate() } } }
    var expected = ""
    var expectedAlgorithm = DigestAlgorithm.sha256
    var compareExpanded = false
    var keyHidden = false
    var resultHidden = false
    private(set) var keyCount: Int?
    private(set) var keyIssue: DigestIssue?
    private(set) var file: DigestFileInfo?
    private(set) var artifact: DigestArtifact?
    private(set) var issue: DigestIssue?
    private(set) var progress: DigestProgress?
    private(set) var busy = false
    private(set) var current = false
    typealias Worker = @Sendable (DigestRequest, @escaping @Sendable (DigestProgress) -> Void) async -> DigestResult
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var keyRevision = UUID()
    @ObservationIgnored private var fileRevision = UUID()
    @ObservationIgnored private var pending: (UUID, UUID, DigestRequest)?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var child: Task<DigestResult, Never>?
    @ObservationIgnored private var keyTask: Task<Void, Never>?
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    var preferenceKey: String { "toolbox.\(isHMAC ? "hmac" : "hash").preferences.v1" }
    init(isHMAC: Bool = false, defaults: UserDefaults = .standard, worker: @escaping Worker = { DigestProcessor.run($0, progress: $1) }) {
        self.isHMAC = isHMAC; self.defaults = defaults; self.worker = worker
        var prefs = defaults.data(forKey: "toolbox.\(isHMAC ? "hmac" : "hash").preferences.v1").flatMap { try? JSONDecoder().decode(DigestPreferences.self, from: $0) } ?? .init()
        prefs.algorithms = DigestAlgorithm.allCases.filter { prefs.algorithms.contains($0) }
        if !DigestAlgorithm.hmac.contains(prefs.hmac) { prefs.hmac = .sha256 }
        if prefs.expectedProfile == .text { prefs.expectedProfile = .hex }
        preferences = prefs
        if isHMAC { keyCount = 0 }
    }
    deinit { child?.cancel(); pump?.cancel(); keyTask?.cancel(); fileTask?.cancel() }
    private func save() { if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferenceKey) } }
    var canRun: Bool { !busy && (preferences.mode != .file || file != nil) && (isHMAC || !preferences.algorithms.isEmpty) }
    var canCopy: Bool { current && artifact != nil && !busy }
    var status: String {
        if busy { return progress.map { "Processing \($0.bytes)\($0.total.map { " / \($0)" } ?? "") bytes…" } ?? "Processing…" }
        if let issue { return issue.message }
        if let artifact { return current ? "\(artifact.bytes) bytes processed" : "Out of date — calculate again" }
        return preferences.mode == .file && file == nil ? "Choose a file" : "Ready"
    }
    var displayedAlgorithms: [DigestAlgorithm] { DigestAlgorithm.allCases.filter { artifact?.values[$0] != nil } }
    func value(_ algorithm: DigestAlgorithm) -> String? { artifact?.values[algorithm].map { preferences.format.string($0, uppercase: preferences.uppercase) } }
    private func stop() { request = UUID(); pending = nil; child?.cancel(); busy = false; progress = nil }
    private func invalidate() { stop(); revision = UUID(); current = false; issue = nil }
    func cancel() { stop(); issue = .init(status: .cancelled, message: "Cancelled") }
    func clear() {
        invalidate(); fileRevision = UUID(); fileTask?.cancel(); keyRevision = UUID(); keyTask?.cancel()
        text = ""; key = ""; expected = ""; file = nil; artifact = nil; keyIssue = nil; keyCount = isHMAC ? 0 : nil; allowEmptyKey = false; issue = nil
    }
    func resetSettings() { preferences = .init() }
    func concealSecrets() { if isHMAC { keyHidden = true; resultHidden = true } }
    func removeFile() { fileRevision = UUID(); fileTask?.cancel(); fileTask = nil; file = nil; invalidate() }
    @discardableResult func chooseFile(_ url: URL) -> Task<Void, Never> {
        removeFile(); let id = fileRevision
        guard url.isFileURL else { issue = .init(status: .ioFailure, message: "Choose a local file."); return Task {} }
        let task = Task { [weak self] in
            let info = await Task.detached { () -> DigestFileInfo in
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                return .init(url: url, name: DigestFileInfo.label(url.lastPathComponent), size: size.map(Int64.init))
            }.value
            guard let self, self.fileRevision == id, !Task.isCancelled else { return }; self.file = info
        }
        fileTask = task; return task
    }
    private func inspectKey() {
        guard isHMAC else { return }; keyRevision = UUID(); let id = keyRevision
        keyTask?.cancel(); keyCount = nil; keyIssue = nil
        let source = key, profile = preferences.keyProfile
        keyTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let child = Task.detached { () -> (Int?, DigestIssue?) in
                do { return (try ExactByteInputDecoder.decode(source, profile: profile, inputLimit: 65_536, byteLimit: 16_384).count, nil) }
                catch let error as ExactByteFailure { return (nil, .init(status: error.resourceLimit ? .resourceLimit : .invalidInput, message: error.message, field: "key", range: error.range)) }
                catch { return (nil, nil) }
            }
            let result = await withTaskCancellationHandler { await child.value } onCancel: { child.cancel() }
            guard let self, self.keyRevision == id, !Task.isCancelled else { return }; self.keyCount = result.0; self.keyIssue = result.1
        }
    }
    var comparison: String {
        guard !expected.isEmpty else { return "Not compared" }
        guard current, let bytes = artifact?.values[expectedAlgorithm] else { return "Calculate the selected algorithm first" }
        do {
            let value = try ExactByteInputDecoder.decode(expected, profile: preferences.expectedProfile, inputLimit: 1024, byteLimit: 512)
            guard value.count == bytes.count else { return "Invalid expected value — expected \(bytes.count) bytes" }
            return value == bytes ? "Match" : "Mismatch"
        } catch let error as ExactByteFailure { return "Invalid expected value — " + error.message }
        catch { return "Invalid expected value" }
    }
    func copy(_ algorithm: DigestAlgorithm, publish: (String) -> Void) { guard canCopy, let value = value(algorithm) else { return }; publish(value) }
    func copyAll(publish: (String) -> Void) {
        guard canCopy else { return }
        publish(displayedAlgorithms.compactMap { algorithm in value(algorithm).map { "\(isHMAC ? "HMAC-" : "")\(algorithm.title): \($0)" } }.joined(separator: "\n"))
    }
    @discardableResult func run() -> Task<Void, Never>? {
        guard canRun else { return nil }; stop(); busy = true; issue = nil
        let snapshot = DigestRequest(mode: preferences.mode, text: text, file: file?.url, algorithms: isHMAC ? [preferences.hmac] : preferences.algorithms,
                                     isHMAC: isHMAC, key: key, keyProfile: preferences.keyProfile, allowEmptyKey: allowEmptyKey)
        pending = (request, revision, snapshot)
        if pump == nil {
            pump = Task { [weak self] in
                while let (id, rev, snapshot) = self?.pending {
                    guard let worker = self?.worker else { return }; self?.pending = nil
                    let update: @Sendable (DigestProgress) -> Void = { [weak self] value in
                        Task { @MainActor [weak self] in guard let self, self.request == id, self.revision == rev, self.busy else { return }; self.progress = value }
                    }
                    let child = Task.detached(priority: .userInitiated) { await worker(snapshot, update) }; self?.child = child
                    let result = await withTaskCancellationHandler { await child.value } onCancel: { child.cancel() }
                    guard let self else { return }; self.child = nil
                    if !Task.isCancelled, self.request == id, self.revision == rev {
                        if let artifact = result.artifact { self.artifact = artifact; self.current = true
                            if !self.displayedAlgorithms.contains(self.expectedAlgorithm), let first = self.displayedAlgorithms.first { self.expectedAlgorithm = first }
                        }
                        if let issue = result.issue, issue.status != .cancelled { self.current = false }
                        self.issue = result.issue; self.busy = false; self.progress = nil
                    }
                }
                self?.pump = nil
            }
        }
        return pump
    }
}
