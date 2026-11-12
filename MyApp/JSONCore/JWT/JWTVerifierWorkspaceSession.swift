import Foundation
import Observation
#if SWIFT_PACKAGE
import CertificateCore
#endif

@MainActor @Observable final class JWTVerifierWorkspaceSession {
    var token = "" { didSet { if !token.utf16.elementsEqual(oldValue.utf16) { invalidate(clearInspection:true) } } }
    var key = "" { didSet { if !key.utf16.elementsEqual(oldValue.utf16) { keyIndex = nil; keyChoices = []; keyIssue = nil; invalidate() } } }
    var algorithm: JWTSigningAlgorithm? { didSet { if algorithm != oldValue { invalidate() } } }
    var format = JWTVerificationKeyFormat.publicPEM { didSet { defaults.set(format.rawValue,forKey:Self.prefix+"format"); if format != oldValue { keyIndex = nil; keyChoices = []; keyIssue = nil; invalidate() } } }
    var keyIndex: Int? { didSet { if keyIndex != oldValue { invalidate() } } }
    var policy = JWTClaimsPolicy() { didSet { if policy != oldValue { invalidate() } } }
    var wordWrap = true { didSet { defaults.set(wordWrap,forKey:Self.prefix+"wordWrap") } }
    var hidden = false
    private(set) var result: JWTVerifierResult?
    private(set) var inspection: JWTInspectionResult?
    private(set) var keyChoices: [JWTKeyChoice] = []
    private(set) var keyIssue: String?
    private(set) var busy = false
    private(set) var cancelled = false
    private(set) var timeStale = false
    private(set) var target: NSRange?
    private(set) var headerTarget: NSRange?
    private(set) var payloadTarget: NSRange?
    private(set) var jumpRequest = 0
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var pipeline: Task<Void,Never>?
    @ObservationIgnored private var active: Task<JWTVerifierResult,Never>?
    @ObservationIgnored private var inspectTask: Task<Void,Never>?
    @ObservationIgnored private var keyTask: Task<Void,Never>?
    @ObservationIgnored private var expiryTask: Task<Void,Never>?
    @ObservationIgnored private var importTask: Task<Void,Never>?
    @ObservationIgnored private let defaults: UserDefaults
    private static let prefix = "developerToolbox.jwtVerifier."
    typealias Worker = @Sendable (JWTVerifierRequest) async -> JWTVerifierResult
    @ObservationIgnored private let worker: Worker
    private struct Job { let id: UUID; let request: JWTVerifierRequest }
    @ObservationIgnored private var pending: Job?
    init(defaults: UserDefaults? = nil, worker: @escaping Worker = { JWTVerifierProcessor.process($0) }) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") ? UserDefaults(suiteName:"developerToolbox.navigation.ui-tests")! : .standard)
        self.worker = worker
        format = self.defaults.string(forKey:Self.prefix+"format").flatMap(JWTVerificationKeyFormat.init(rawValue:)) ?? .publicPEM
        wordWrap = self.defaults.object(forKey:Self.prefix+"wordWrap") as? Bool ?? true
    }
    deinit { pipeline?.cancel(); active?.cancel(); inspectTask?.cancel(); keyTask?.cancel(); expiryTask?.cancel(); importTask?.cancel() }
    private func invalidate(clearInspection: Bool = false) { cancel(); revision = UUID(); result = nil; if clearInspection { inspection = nil }; cancelled = false; timeStale = false; expiryTask?.cancel(); inspectTask?.cancel(); keyTask?.cancel(); importTask?.cancel(); target = nil; headerTarget = nil; payloadTarget = nil; jumpRequest += 1 }
    func cancel() { pending = nil; active?.cancel(); requestID = UUID(); cancelled = busy; busy = false }
    func clear() { token = ""; key = ""; keyIndex = nil; keyChoices = []; keyIssue = nil; algorithm = nil; policy = .init(); invalidate(clearInspection:true); hidden = false }
    var snapshot: JWTVerifierRequest { .init(token:token,key:key,algorithm:algorithm,format:format,keyIndex:keyIndex,policy:policy,revision:revision) }
    @discardableResult func inspectPaste() -> Task<Void,Never> {
        inspectTask?.cancel(); let source = token, r = revision
        let task = Task { [weak self] in
            let work = Task.detached(priority:.userInitiated) { JWTProcessor.inspect(source) }
            let value = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.revision == r else { return }; self.inspection = value
        }; inspectTask = task; return task
    }
    @discardableResult func loadKeys() -> Task<Void,Never> {
        keyTask?.cancel(); let source = key, r = revision
        let task = Task { [weak self] in
            let work = Task.detached(priority:.userInitiated) { () -> ([JWTKeyChoice],String?) in
                do { return (try JWKReader.choices(source),nil) } catch { return ([],"Local JWK/JWKS could not be read. Check structure and limits.") }
            }
            let value = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.revision == r else { return }; self.keyChoices = value.0; self.keyIssue = value.1
        }; keyTask = task; return task
    }
    @discardableResult func run() -> Task<Void,Never> {
        active?.cancel(); requestID = UUID(); pending = .init(id:requestID,request:snapshot); busy = true; cancelled = false
        if let pipeline { return pipeline }
        let task = Task { [weak self] in
            while let job = self?.takePending() {
                guard let worker = self?.worker else { return }
                let work = Task.detached(priority:.userInitiated) { await worker(job.request) }; self?.active = work
                let response = await work.value
                guard let self else { return }
                if self.revision == job.request.revision && self.requestID == job.id {
                    self.busy = false; self.result = response; self.inspection = response.inspection; self.timeStale = false; self.scheduleExpiry()
                }
            }; self?.active = nil; self?.pipeline = nil
        }; pipeline = task; return task
    }
    private func takePending() -> Job? { defer { pending = nil }; return pending }
    func checkClock() { if let expiry = result?.expiresAt, Date.now >= expiry { timeStale = true } }
    private func scheduleExpiry() {
        expiryTask?.cancel(); guard let expiry = result?.expiresAt, result?.claimsPassed == true else { return }
        let delay = expiry.timeIntervalSinceNow
        if delay <= 0 { timeStale = true; return }
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(min(delay,86400))) } catch { return }
            self?.checkClock(); if self?.timeStale == false { self?.scheduleExpiry() }
        }
    }
    func show(_ issue: JWTIssue, related: Bool = false) {
        guard !hidden else { return }
        let anchors = related ? issue.related : issue.anchor.map { [$0] } ?? []
        target = nil; headerTarget = nil; payloadTarget = nil
        guard let anchor = anchors.first else { return }
        switch anchor.space {
        case .input: target = anchor.range
        case .json(.header): headerTarget = anchor.range
        case .json(.payload): payloadTarget = anchor.range
        default: return
        }
        jumpRequest += 1
    }
    @discardableResult func importKey(_ url: URL) -> Task<Void,Never> {
        importTask?.cancel(); let r = revision, selected = format
        let task = Task { [weak self] in
            let work = Task.detached(priority:.userInitiated) { () -> (String?,String?) in
                do {
                    let data = try CertificateFileLoader.read(url,limit:selected == .certificate ? 400000 : selected == .jwk ? 262144 : 65536)
                    if data.first == 0x30, selected == .publicPEM || selected == .certificate {
                        let label = selected == .certificate ? "CERTIFICATE" : (try? PublicKeyMaterialImporter.rsaPKCS1(data)) != nil ? "RSA PUBLIC KEY" : "PUBLIC KEY"
                        return (PEMEnvelopeReader.encode(data,label:label),nil)
                    }
                    if let text = String(data:data,encoding:.utf8) { return (text,nil) }
                    guard selected == .publicPEM || selected == .certificate else { return (nil,"This key source requires text.") }
                    return (PEMEnvelopeReader.encode(data,label:selected == .certificate ? "CERTIFICATE" : "PUBLIC KEY"),nil)
                } catch { return (nil,"The key file could not be imported within the selected format limits.") }
            }
            let value = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.revision == r else { return }
            if let text = value.0 { self.key = text; if self.format == .jwk { self.loadKeys() } }; self.keyIssue = value.1
        }; importTask = task; return task
    }
}
