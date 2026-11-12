import Foundation
import Observation

@MainActor @Observable public final class QRCodeDecoderWorkspaceSession {
    public typealias Worker = @Sendable (QRDecodeSource,QRScanSurface) async throws -> QRDecodeSnapshot
    public typealias Loader = @Sendable () async throws -> QRDecodeSource
    public private(set) var source: QRDecodeSource?
    public private(set) var snapshot: QRDecodeSnapshot?
    public private(set) var phase: QRDecodePhase = .empty
    public private(set) var busy = false
    public private(set) var issue: String?
    public private(set) var revision = UUID()
    public private(set) var selectedID: Int?
    public private(set) var publication = UUID()
    public var inputExpanded = true
    public var detailsExpanded = false
    public var showsBytes = false
    public var wordWrap = true
    public private(set) var surface: QRScanSurface = .white
    @ObservationIgnored private let worker: Worker
    @ObservationIgnored private var pump: Task<Void,Never>?
    @ObservationIgnored private var child: Task<QRDecodeSource,Error>?
    @ObservationIgnored private var scanner: Task<QRDecodeSnapshot,Error>?
    @ObservationIgnored private var pending: Request?
    private struct Request: Sendable { let revision: UUID; let loader: Loader?; let source: QRDecodeSource?; let surface: QRScanSurface }
    public init(worker: @escaping Worker = { try QRCodeDecoderProcessor.scan($0,surface:$1) }) { self.worker = worker }
    deinit { pump?.cancel(); child?.cancel(); scanner?.cancel() }
    public var selected: QRDecodedItem? { snapshot?.items.first { $0.id == selectedID } }
    public var canOutput: Bool { !busy && snapshot?.source.id == source?.id && snapshot?.surface == surface && selected?.readable == true }
    public var status: String {
        if let issue { return issue }
        switch phase {
        case .empty: return "Open or paste an image containing a QR code"
        case .loading: return snapshot == nil ? "Loading image…" : "Previous image · loading…"
        case .scanning: return snapshot == nil ? "Reading QR codes…" : "Reading again · previous results"
        case .ready:
            let items = snapshot?.items ?? []
            if snapshot?.limited == true { return "100+ codes · result limit reached" }
            let valid = items.filter(\.readable).count
            if valid == 0 { return "Possible QR code found, but content could not be decoded" }
            return "\(valid) readable · \(items.count) QR code\(items.count == 1 ? "" : "s") detected"
        case .noCodes: return "No QR code found. Try a clearer image or a larger crop of the code."
        case .failed: return "Could not read this image"
        case .cancelled: return "Cancelled"
        }
    }
    public func select(_ id: Int) {
        guard let item = snapshot?.items.first(where:{ $0.id == id }) else { return }
        selectedID = id; showsBytes = item.text == nil
    }
    public func selectOffset(_ delta: Int) {
        guard let items = snapshot?.items, !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        select(items[max(0,min(items.count-1,current+delta))].id)
    }
    public func importData(_ data: Data) { importImage { try QRCodeDecoderImageLoader.decode(data) } }
    public func importFile(_ url: URL) { importImage { try QRCodeDecoderImageLoader.decode(QRCodeDecoderImageLoader.readFile(url)) } }
    public func importImage(_ loader: @escaping Loader) { enqueue(loader:loader,source:nil) }
    public func scanAgain() { guard let source else { return }; enqueue(loader:nil,source:source) }
    public func setSurface(_ value: QRScanSurface) { guard surface != value else { return }; surface = value; scanAgain() }
    public func report(_ message: String) { issue = message }
    private func enqueue(loader: Loader?, source: QRDecodeSource?) {
        revision = UUID(); child?.cancel(); scanner?.cancel()
        issue = nil; busy = true; phase = loader == nil ? .scanning : .loading
        pending = Request(revision:revision,loader:loader,source:source,surface:surface)
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while let request = self?.pending {
                self?.pending = nil
                do {
                    let prepared: QRDecodeSource
                    if let loader = request.loader {
                        let child = Task.detached(priority:.userInitiated) { try await loader() }; self?.child = child
                        let result = await withTaskCancellationHandler { await child.result } onCancel: { child.cancel() }
                        self?.child = nil
                        guard self?.revision == request.revision else { continue }
                        prepared = try result.get()
                        self?.source = prepared; self?.snapshot = nil; self?.selectedID = nil; self?.phase = .scanning
                    } else if let old = request.source { prepared = old } else { continue }
                    guard let worker = self?.worker, self?.revision == request.revision else { continue }
                    let scanner = Task.detached(priority:.userInitiated) { try await worker(prepared,request.surface) }; self?.scanner = scanner
                    let result = await withTaskCancellationHandler { await scanner.result } onCancel: { scanner.cancel() }
                    self?.scanner = nil
                    guard let self, self.revision == request.revision, !Task.isCancelled else { continue }
                    let snapshot = try result.get()
                    self.snapshot = snapshot; self.busy = false; self.issue = nil; self.publication = UUID()
                    self.phase = snapshot.items.isEmpty ? .noCodes : .ready
                    if !snapshot.items.contains(where:{ $0.id == self.selectedID }) {
                        self.selectedID = snapshot.items.first(where:\.readable)?.id ?? snapshot.items.first?.id
                    }
                    self.showsBytes = self.selected?.text == nil
                } catch {
                    guard let self, self.revision == request.revision, !Task.isCancelled else { continue }
                    self.busy = false; self.phase = error is CancellationError ? .cancelled : .failed
                    self.issue = error is CancellationError ? "Cancelled" : (error as? QRDecodeIssue)?.message ?? "Could not load or read the image. Try a local supported image."
                }
            }
            self?.pump = nil
        }
    }
    public func cancel() {
        revision = UUID(); pending = nil; child?.cancel(); scanner?.cancel(); busy = false; phase = .cancelled; issue = nil
    }
    public func clear() {
        cancel(); source = nil; snapshot = nil; selectedID = nil; phase = .empty; issue = nil; publication = UUID()
    }
}
