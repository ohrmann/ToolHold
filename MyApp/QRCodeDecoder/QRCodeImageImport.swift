import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Provider lifetime stays inside the operation. No pasteboard access happens until an explicit action.
final class QRImageProvider: @unchecked Sendable {
    let provider: NSItemProvider
    private let lock = NSLock()
    private var progress: Progress?
    private var cancelled = false
    init(_ provider: NSItemProvider) { self.provider = provider }
    private func store(_ value: Progress) { lock.lock(); progress = value; let cancelled = cancelled; lock.unlock(); if cancelled { value.cancel() } }
    private func cancel() { lock.lock(); cancelled = true; let value = progress; lock.unlock(); value?.cancel() }
    static let accepted: [UTType] = [.png,.jpeg,.heic,.heif,.tiff,.gif,.image]
    func load() async throws -> QRDecodeSource {
        try Task.checkCancellation()
        guard let type = Self.accepted.first(where:{ provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            throw QRDecodeIssue(.unsupported,"Paste or drop an image, not text or a web link.")
        }
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let value = provider.loadFileRepresentation(forTypeIdentifier:type.identifier) { [self] url,_ in
                    if let url {
                        do { continuation.resume(returning:try QRCodeDecoderImageLoader.readFile(url)) }
                        catch { continuation.resume(throwing:error) }
                    } else {
                        let fallback = provider.loadDataRepresentation(forTypeIdentifier:type.identifier) { data,_ in
                            guard let data else { continuation.resume(throwing:QRDecodeIssue(.loading,"The image provider could not deliver an image. Try saving it to Files first.")); return }
                            guard data.count <= QRDecodeBudget.encodedBytes else { continuation.resume(throwing:QRCodeDecoderImageLoader.sizeIssue); return }
                            continuation.resume(returning:data)
                        }
                        store(fallback)
                    }
                }
                store(value)
            }
        } onCancel: { self.cancel() }
        try Task.checkCancellation()
        return try QRCodeDecoderImageLoader.decode(data)
    }
}

#if os(iOS)
struct QRCodePasteImageButton: UIViewRepresentable {
    let receive: ([NSItemProvider]) -> Void
    func makeUIView(context: Context) -> QRImagePasteTarget {
        let view = QRImagePasteTarget()
        view.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers:[UTType.image.identifier])
        let button = UIPasteControl(configuration:UIPasteControl.Configuration())
        button.target = view; button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "qr-decoder-paste"
        view.addSubview(button)
        NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo:view.leadingAnchor),button.trailingAnchor.constraint(equalTo:view.trailingAnchor),button.topAnchor.constraint(equalTo:view.topAnchor),button.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        return view
    }
    func updateUIView(_ view: QRImagePasteTarget, context: Context) { view.receive = receive }
}
final class QRImagePasteTarget: UIView {
    var receive: ([NSItemProvider]) -> Void = { _ in }
    override func paste(itemProviders: [NSItemProvider]) { receive(itemProviders) }
}
#endif

@MainActor enum QRDecodedClipboard {
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.prepareForNewContents(with:.currentHostOnly)
        NSPasteboard.general.setString(value,forType:.string)
        #else
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier:Data(value.utf8)]],options:[.localOnly:true])
        #endif
    }
    #if os(macOS)
    static func paste(into workspace: QRCodeDecoderWorkspaceSession) {
        // Only metadata is inspected before the explicit user's Paste action reaches here.
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty {
            guard urls.count == 1 else { workspace.report("Choose one image at a time."); return }
            workspace.importFile(urls[0]); return
        }
        for type in [NSPasteboard.PasteboardType.png,.tiff] {
            if let data = pasteboard.data(forType:type) { workspace.importData(data); return }
        }
        workspace.report("The clipboard does not contain a supported image.")
    }
    #endif
}
