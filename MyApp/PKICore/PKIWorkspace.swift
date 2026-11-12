import Foundation
import Observation
#if canImport(CertificateCore)
import CertificateCore
#endif

public enum PKITool: Int, CaseIterable, Sendable { case certificate = 69, csr, converter, pfx, chain, matcher, key, expiry }
public enum PKIWorkspaceResult: Sendable {
    case generated(PKIGenerated), csr(PKICSRInfo), objects([PKIObject]), pfx(PKIPFXInfo), key(PKIKeyInfo), match(Bool, PKIKeyInfo), chain(PKIChainResult), package(Data)
}
public struct PKIExport: Identifiable, Sendable {
    public let id = UUID(), bytes: Data, filename: String, sensitive: Bool
    public init(bytes: Data, filename: String, sensitive: Bool = false) { self.bytes = bytes; self.filename = filename; self.sensitive = sensitive }
}
private struct PKIJob: Sendable {
    let revision: Int, tool: PKITool, mode: Int, input: Data, second: Data, extras: Data, roots: Data, password: String, newPassword: String, name: String
    let draft: PKIGenerationDraft, selectedCertificate: Int, hint: String?, policy: Int, host: String, time: Date, system: Bool, legacy: Bool, unverified: Bool
}
@MainActor @Observable public final class PKIWorkspace {
    public let tool: PKITool
    public var input = "" { didSet { if !publishing && !input.utf16.elementsEqual(oldValue.utf16) { files[0] = nil; invalidate() } } }
    public var second = "" { didSet { if !publishing && !second.utf16.elementsEqual(oldValue.utf16) { files[1] = nil; invalidate() } } }
    public var extras = "" { didSet { if !publishing && !extras.utf16.elementsEqual(oldValue.utf16) { files[2] = nil; invalidate() } } }
    public var roots = "" { didSet { if !publishing && !roots.utf16.elementsEqual(oldValue.utf16) { files[3] = nil; invalidate() } } }
    public var password = "" { didSet { if !password.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    public var newPassword = "" { didSet { if !newPassword.utf8.elementsEqual(oldValue.utf8) { exportChanged() } } }
    public var confirmPassword = "" { didSet { if !confirmPassword.utf8.elementsEqual(oldValue.utf8) { exportChanged() } } }
    /// Encryption consumes exact UTF-8; canonical Unicode equality is not password equality.
    public var exportPasswordsMatch: Bool { newPassword.utf8.elementsEqual(confirmPassword.utf8) }
    public var friendlyName = "ToolHold" { didSet { if !friendlyName.utf8.elementsEqual(oldValue.utf8) { exportChanged() } } }
    public var draft = PKIGenerationDraft() { didSet { if draft != oldValue { invalidate() } } }
    public var mode = 0 { didSet { if mode != oldValue { invalidate() } } }
    public var typeHint = "Automatic" { didSet { if !typeHint.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    public var policy = 0 { didSet { if policy != oldValue { invalidate() } } }
    public var hostname = "" { didSet { if !hostname.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    public var verifyDate = Date() { didSet { if verifyDate != oldValue { invalidate() } } }
    public var systemTrust = false { didSet { if systemTrust != oldValue { invalidate() } } }
    public var legacy = false { didSet { if legacy != oldValue { invalidate() } } }
    public var unverified = false { didSet { if unverified != oldValue { invalidate() } } }
    public var selectedCertificate = 0 { didSet { if tool == .matcher { invalidate() } } }
    public var selectedID = 0
    public var selectedPFXKey: Int32 = -1 { didSet { exportChanged() } }
    public var selectedPFXLeaf: Int32 = -1 { didSet { exportChanged() } }
    public var includedCerts = Set<Int32>() { didSet { exportChanged() } }
    public var masked = true
    public var inputCollapsed = false
    public var search = ""
    public var wordWrap = true
    public private(set) var files: [Int: Data] = [:]
    public private(set) var fileNames: [Int: String] = [:]
    public private(set) var result: PKIWorkspaceResult?
    public private(set) var status: PKIStatus = .ready
    public private(set) var message = "Ready"
    public private(set) var busy = false
    public private(set) var token: UUID?
    public private(set) var revision = 0
    public var pendingExport: PKIExport?
    @ObservationIgnored private let engine = PKIEngine()
    @ObservationIgnored private var publishing = false
    @ObservationIgnored private var concealing = false
    @ObservationIgnored private var concealActions: [UUID:@MainActor () -> Void] = [:]
    @ObservationIgnored private var pipeline: Task<Void,Never>?
    @ObservationIgnored private var active: Task<(PKIWorkspaceResult,UUID),Error>?
    @ObservationIgnored private var pending: PKIJob?
    @ObservationIgnored private var io: Task<Void,Never>?
    public init(tool: PKITool) { self.tool = tool }
    deinit { pipeline?.cancel(); active?.cancel(); io?.cancel() }
    private func exportChanged() { guard !concealing else { return }; pendingExport = nil; io?.cancel(); if io != nil && status != .processing { busy = false }; if tool == .pfx && mode == 1 { invalidate() } }
    private func invalidate() { revision += 1; active?.cancel(); io?.cancel(); pending = nil; result = nil; token = nil; pendingExport = nil; busy = false; status = .ready; message = "Not processed" }
    public func cancel() { revision += 1; pending = nil; active?.cancel(); io?.cancel(); busy = false; pendingExport = nil; status = .cancelled; message = "Cancelled" }
    public func clear() {
        cancel(); publishing = true; input = ""; second = ""; extras = ""; roots = ""; publishing = false
        password = ""; newPassword = ""; confirmPassword = ""; draft = PKIGenerationDraft(); hostname = ""; friendlyName = "ToolHold"; search = ""; selectedPFXKey = -1; selectedPFXLeaf = -1
        files = [:]; fileNames = [:]; result = nil; token = nil; selectedID = 0; includedCerts = []; masked = true; status = .ready; message = "Ready"
        let e = engine; let rev = revision; Task { let artifact = await e.token(); guard revision == rev else { return }; await e.clear(ifCurrent: artifact) }
    }
    public func bytes(_ slot: Int) -> Data { files[slot] ?? Data((slot == 0 ? input : slot == 1 ? second : slot == 2 ? extras : roots).utf8) }
    public func load(_ data: Data, name: String, slot: Int) throws {
        guard data.count <= (tool == .pfx && slot == 0 ? PKILimits.pfx : PKILimits.file) else { throw PKIFailure("File exceeds its import limit", status: .resourceLimit) }
        invalidate(); publishing = true; defer { publishing = false }
        let text = String(data: data, encoding: .utf8).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-----") && $0.utf16.count <= 262144 ? $0 : nil }
        if let text {
            files[slot] = nil; fileNames[slot] = nil
            switch slot { case 0: input = text; case 1: second = text; case 2: extras = text; default: roots = text }
        } else { files[slot] = data; fileNames[slot] = CertificateDisplay.safe(name, limit: 160) }
    }
    public func editText(_ slot: Int) { files[slot] = nil; fileNames[slot] = nil; invalidate() }
    public func reportError(_ error: Error) {
        busy = false
        if error is CancellationError { status = .cancelled; message = "Cancelled" }
        else if let e = error as? PKIFailure { status = e.status; message = e.message }
        else if let e = error as? CertificateFailure { status = e.kind == .resource ? .resourceLimit : e.kind == .unsupported ? .unsupported : .invalidInput; message = e.message }
        else { status = .invalidInput; message = "Invalid or unsupported ASN.1 input" }
    }
    public func importFile(_ url: URL, slot: Int) {
        io?.cancel(); let rev = revision, limit = tool == .pfx && slot == 0 ? PKILimits.pfx : PKILimits.file
        io = Task { let task = Task.detached { try CertificateFileLoader.read(url, limit: limit) }
            do { let data = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() }); guard rev == revision, !Task.isCancelled else { return }; if slot == 4 { let reader = PKIEngine(); let objects = try await reader.convert(data); guard objects.count == 1, let object = objects.first, object.sensitive else { throw PKIFailure("Choose one private key") }; guard rev == revision, !Task.isCancelled else { return }; draft.importedKey = object.pem } else { try load(data, name: url.lastPathComponent, slot: slot) } }
            catch { guard rev == revision, !Task.isCancelled else { return }; reportError(error) }
        }
    }
    @discardableResult public func run() -> Task<Void,Never> {
        revision += 1; let rev = revision; active?.cancel(); pendingExport = nil; busy = true; status = .processing; message = "Processing…"
        guard [input,second,extras,roots].allSatisfy({ $0.utf16.count <= 262144 }) else { reportError(PKIFailure("Editable input exceeds 262,144 UTF-16 units; open a file instead", status: .resourceLimit)); return Task {} }
        if tool == .pfx && mode == 1 && !exportPasswordsMatch { reportError(PKIFailure("Export passwords do not match")); return Task {} }
        pending = .init(revision: rev, tool: tool, mode: mode, input: bytes(0), second: bytes(1), extras: bytes(2), roots: bytes(3), password: password, newPassword: newPassword, name: friendlyName, draft: draft, selectedCertificate: selectedCertificate, hint: typeHint == "Automatic" ? nil : typeHint, policy: policy, host: hostname, time: verifyDate, system: systemTrust, legacy: legacy, unverified: unverified)
        if let pipeline { return pipeline }
        let task = Task { [weak self] in
            while let self, let job = self.pending {
                self.pending = nil; let e = self.engine
                let worker = Task.detached(priority: .userInitiated) { () throws -> (PKIWorkspaceResult,UUID) in
                    try Task.checkCancellation(); let result: PKIWorkspaceResult
                    switch job.tool {
                    case .certificate: result = .generated(try await e.generate(job.draft, csr: false))
                    case .csr: result = job.mode == 0 ? .generated(try await e.generate(job.draft, csr: true)) : .csr(try await e.inspectCSR(job.input))
                    case .converter: result = .objects(try await e.convert(job.input, hint: job.hint))
                    case .key: result = .key(try await e.inspectKey(job.input, password: job.password))
                    case .matcher: let value = try await e.match(certificate: job.input, certificateIndex: job.selectedCertificate, privateKey: job.second, password: job.password); result = .match(value.0,value.1)
                    case .pfx:
                        if job.mode == 0 { result = .pfx(try await e.openPFX(job.input, password: job.password, legacy: job.legacy, unverified: job.unverified)) }
                        else { result = .package(try await e.createPFX(privateKey: job.second.isEmpty ? nil : job.second, certificate: job.input, extras: job.extras, password: job.newPassword, keyPassword: job.password, name: job.name)) }
                    case .chain: result = .chain(try await e.validateChain(leaf: job.input, intermediates: job.extras, roots: job.roots, policy: job.policy, host: job.host, at: job.time, system: job.system))
                    case .expiry: throw PKIFailure("Use the batch report workspace", status: .unsupported)
                    }
                    try Task.checkCancellation(); return (result, await e.token())
                }
                self.active = worker
                do { let (result,token) = try await worker.value; if self.revision == job.revision { self.result = result; self.token = token; self.busy = false; self.status = .completed; self.message = "Completed"; self.selectedID = 0
                    switch result { case .csr(let value) where !value.signatureValid: self.status = .completedWithWarnings; self.message = "Request signature is invalid"
                    case .pfx(let value): self.selectedPFXKey = value.bags.first(where: { $0.key >= 0 })?.key ?? -1; self.selectedPFXLeaf = value.bags.first(where: { $0.certificate >= 0 })?.certificate ?? -1; self.includedCerts = []; if !value.verified { self.status = .completedWithWarnings; self.message = "Integrity not authenticated" }
                    case .key(let value) where !value.consistent: self.status = .completedWithWarnings; self.message = "Key consistency or strength is not confirmed"
                    case .chain(let value) where !value.valid: self.status = .completedWithWarnings; self.message = "Chain validation did not pass"
                    case .match(false,_): self.status = .completedWithWarnings; self.message = "Keys do not match"
                    default: break }
                } } catch { if self.revision == job.revision { self.result = nil; self.token = nil; self.reportError(error) } }
            }
            self?.active = nil; self?.pipeline = nil
        }
        pipeline = task; return task
    }
    public func privateExport(key: Int32, unencrypted: Bool, pem: Bool) {
        guard let token, !busy else { return }; let rev = revision, pass = newPassword
        if !unencrypted && !exportPasswordsMatch { reportError(PKIFailure("Export passwords do not match")); return }
        busy = true; message = "Preparing private export…"; io = Task {
            do { let object = try await engine.exportKey(token: token, key: key, password: pass, unencrypted: unencrypted); guard revision == rev, !Task.isCancelled else { return }; busy = false; pendingExport = .init(bytes: pem ? Data(object.pem.utf8) : object.data, filename: pem ? "private-key.pem" : "private-key.der", sensitive: true); message = "Private export ready" }
            catch { guard revision == rev, !Task.isCancelled else { return }; reportError(error) }
        }
    }
    public func repackage(subset: Bool) {
        guard let token, !busy else { return }; guard exportPasswordsMatch else { reportError(PKIFailure("Export passwords do not match")); return }
        let rev = revision, pass = newPassword, key = selectedPFXKey, leaf = selectedPFXLeaf, extras = includedCerts.filter { $0 != leaf }.sorted(), name = friendlyName
        busy = true; message = "Preparing new PFX…"; io = Task {
            do { let bytes = try await (subset ? engine.subsetPFX(token: token, key: key, leaf: leaf, extras: extras, name: name, password: pass) : engine.repackagePFX(token: token, password: pass)); guard revision == rev, !Task.isCancelled else { return }; busy = false; pendingExport = .init(bytes: bytes, filename: "identity.p12", sensitive: true); message = "New PFX ready" }
            catch { guard revision == rev, !Task.isCancelled else { return }; reportError(error) }
        }
    }
    /// Background privacy is presentation cleanup, not an edit to a completed result.
    /// Cancelling IO also prevents an already-running export from publishing after concealment.
    public func setConcealAction(id: UUID, action: @escaping @MainActor () -> Void) { concealActions[id] = action }
    public func removeConcealAction(id: UUID) { concealActions[id] = nil }
    public func concealSecrets() {
        guard !concealing else { return }
        concealing = true; defer { concealing = false }
        // Native responder commands must run BEFORE observation removes a focused editor.
        // Each view registers weak-editor commands only in its own workspace/window.
        for action in Array(concealActions.values) { action() }
        masked = true; io?.cancel(); io = nil; pendingExport = nil
        if status != .processing { busy = false }
        newPassword = ""; confirmPassword = ""
    }
}
