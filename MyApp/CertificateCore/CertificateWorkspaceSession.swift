import Foundation
import Observation

@MainActor @Observable final class CertificateWorkspaceSession {
    var input = "" { didSet { if !publishing && !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
    var selectedID = 0
    var inputCollapsed = false
    var localDates = false { didSet { defaults.set(localDates,forKey:Self.prefix+"localDates") } }
    var wordWrap = true { didSet { defaults.set(wordWrap,forKey:Self.prefix+"wordWrap") } }
    var inspectOnPaste = true { didSet { defaults.set(inspectOnPaste,forKey:Self.prefix+"inspectOnPaste") } }
    private(set) var busy = false
    private(set) var cancelled = false
    private(set) var result: CertificateResult?
    private(set) var fileSource: Data?
    private(set) var preview = ""
    private(set) var fileLabel = ""
    private(set) var target: NSRange?
    private(set) var jumpRequest = 0
    @ObservationIgnored private var publishing = false
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var pipeline: Task<Void,Never>?
    @ObservationIgnored private var active: Task<Response,Never>?
    @ObservationIgnored private let defaults: UserDefaults
    private static let prefix = "developerToolbox.certificate."
    private enum Source: Sendable { case text(String), file(URL), bytes(Data) }
    private struct Job { let id: UUID; let source: Source; let inspect: Bool }
    private struct Response: Sendable { let bytes: Data?; let text: String?; let label: String; let result: CertificateResult?; var preview = "" }
    @ObservationIgnored private var pending: Job?
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") ? UserDefaults(suiteName:"developerToolbox.navigation.ui-tests")! : .standard)
        localDates = self.defaults.bool(forKey:Self.prefix+"localDates")
        wordWrap = self.defaults.object(forKey:Self.prefix+"wordWrap") as? Bool ?? true
        inspectOnPaste = self.defaults.object(forKey:Self.prefix+"inspectOnPaste") as? Bool ?? true
    }
    deinit { pipeline?.cancel(); active?.cancel() }
    var selected: CertificateEntry? { result?.entries.first { $0.id == selectedID } }
    func cancel() { requestID = UUID(); pending = nil; active?.cancel(); cancelled = busy; busy = false }
    private func invalidate() { cancel(); result = nil; fileSource = nil; preview = ""; fileLabel = ""; cancelled = false; target = nil; jumpRequest += 1 }
    func clear() { input = ""; invalidate(); selectedID = 0 }
    func editInput() { invalidate(); inputCollapsed = false }
    func usePEM() {
        guard let selected else { return }
        let text = selected.pem; guard text.utf16.count <= CertificateLimits.editor else { return }
        input = text; fileSource = nil; preview = ""; fileLabel = ""; inputCollapsed = false; run()
    }
    func showSource() { guard let range = selected?.sourceRange, fileSource == nil else { return }; inputCollapsed = false; target = range; jumpRequest += 1 }
    @discardableResult func run() -> Task<Void,Never> { enqueue(fileSource.map { .bytes($0) } ?? .text(input)) }
    @discardableResult func importFile(_ url: URL) -> Task<Void,Never> { enqueue(.file(url),inspect:inspectOnPaste) }
    @discardableResult private func enqueue(_ source: Source, inspect: Bool = true) -> Task<Void,Never> {
        active?.cancel(); requestID = UUID(); pending = .init(id:requestID,source:source,inspect:inspect); busy = true; cancelled = false
        if let pipeline { return pipeline }
        let task = Task { [weak self] in
            while let job = self?.takePending() {
                let worker = Task.detached(priority:.userInitiated) { () -> Response in
                    do {
                        let bytes: Data, label: String
                        switch job.source {
                        case .text(let text):
                            guard text.utf16.prefix(CertificateLimits.editor+1).count <= CertificateLimits.editor else { throw CertificateFailure(.resource,"Editable PEM exceeds 262,144 UTF-16 units. Import a file instead.") }
                            bytes = Data(text.utf8); label = ""
                        case .file(let url): bytes = try CertificateFileLoader.read(url); label = "Imported certificate file"
                        case .bytes(let data): bytes = data; label = "Imported certificate file"
                        }
                        let result = job.inspect ? CertificateProcessor.inspect(bytes) : nil
                        let sourceText = String(data:bytes,encoding:.utf8).flatMap { $0.hasPrefix("-----") || $0.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("-----") ? $0 : nil }
                        let editableText = sourceText.flatMap { $0.utf16.prefix(CertificateLimits.editor+1).count <= CertificateLimits.editor ? $0 : nil }
                        let preview = sourceText.map { String(decoding:$0.utf8.prefix(65536),as:UTF8.self) } ?? "Binary DER · \(bytes.count) bytes"
                        return .init(bytes:bytes,text:editableText,label:label,result:result,preview:preview)
                    } catch is CancellationError { return .init(bytes:nil,text:nil,label:"",result:.init(status:.cancelled,entries:[],message:"Cancelled",evaluatedAt:.now)) }
                    catch let e as CertificateFailure { return .init(bytes:nil,text:nil,label:"",result:.init(status:e.kind == .resource ? .resourceLimit : .failed,entries:[],message:e.message,evaluatedAt:.now)) }
                    catch { return .init(bytes:nil,text:nil,label:"",result:.init(status:.failed,entries:[],message:"The file could not be imported.",evaluatedAt:.now)) }
                }
                self?.active = worker; let response = await worker.value
                guard let self else { return }
                if self.requestID == job.id {
                    self.busy = false
                    // Atomic source/result publication; never turn an imported preview into editable full input.
                    if !response.label.isEmpty, let bytes = response.bytes {
                        if let text = response.text {
                            self.publishing = true; self.input = text; self.publishing = false
                            self.fileSource = nil; self.preview = ""; self.fileLabel = ""
                        } else {
                            self.fileSource = bytes; self.fileLabel = response.label + " · \(bytes.count) bytes"
                            self.preview = response.preview
                        }
                    }
                    self.result = response.result; self.selectedID = response.result?.entries.first?.id ?? 0
                }
            }
            self?.active = nil; self?.pipeline = nil
        }
        pipeline = task; return task
    }
    private func takePending() -> Job? { defer { pending = nil }; return pending }
}
