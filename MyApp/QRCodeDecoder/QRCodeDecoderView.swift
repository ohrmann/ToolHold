import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct QRCodeDecoderView: View {
    @Bindable var workspace: QRCodeDecoderWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var importing = false
    @State private var exporting = false
    @State private var output: QRDecodedExport?
    @State private var message: String?
    @State private var command = QRImageViewCommand()
    @State private var dropping = false
    @State private var revealTask: Task<Void,Never>?
    @State private var revealID = UUID()
    @FocusState private var listFocused: Bool
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif
    private var animation: Animation? { reduced || ProcessInfo.processInfo.arguments.contains("--reduce-motion") ? nil : .easeInOut(duration:0.2) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
            VStack(alignment:.leading,spacing:10) {
                controls
                HStack(spacing:8) {
                    if workspace.busy { ProgressView().controlSize(.small) }
                    Text(workspace.status).font(.callout).foregroundStyle(workspace.issue == nil ? Color.secondary : .orange)
                        .accessibilityIdentifier("qr-decoder-status").lineLimit(2)
                    Spacer(minLength:0)
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }.frame(minHeight:28,alignment:.leading)
                let layout = wide ? AnyLayout(HStackLayout(alignment:.top,spacing:14)) : AnyLayout(VStackLayout(alignment:.leading,spacing:10))
                layout {
                    imagePane(wide:wide,height:geometry.size.height)
                        .frame(width:wide ? (workspace.inputExpanded ? max(240,geometry.size.width*0.4) : 140) : nil)
                        .frame(maxHeight:wide ? .infinity : nil)
                    VStack(alignment:.leading,spacing:8) {
                        resultsList(height:wide ? min(180,geometry.size.height*0.26) : min(100,max(50,CGFloat(workspace.snapshot?.items.count ?? 1)*48)))
                        QRCodeDecodedResultView(item:workspace.selected,showsBytes:$workspace.showsBytes,wordWrap:$workspace.wordWrap,detailsExpanded:$workspace.detailsExpanded,canOutput:workspace.canOutput,copy:copy,export:export,reveal:reveal)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }.padding(12)
                .animation(animation,value:workspace.inputExpanded)
                .animation(animation,value:workspace.detailsExpanded)
        }
        .navigationTitle("QR Code Decoder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of:photo) { _,item in
            guard let item else { return }
            workspace.importImage {
                guard let data = try await item.loadTransferable(type:Data.self) else { throw QRDecodeIssue(.loading,"The selected photo could not be loaded.") }
                return try QRCodeDecoderImageLoader.decode(data)
            }
            photo = nil
        }
        #endif
        .fileImporter(isPresented:$importing,allowedContentTypes:[.png,.jpeg,.heic,.heif,.tiff,.gif],allowsMultipleSelection:false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { workspace.importFile(url) }
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { workspace.report("Image selection was not completed. Try a local image.") }
            }
        }
        .fileExporter(isPresented:$exporting,document:output.map { QRCodeDecodedExportDocument($0.data) },contentType:output?.isText == true ? .plainText : .data,defaultFilename:output?.filename ?? "qr-result.bin") { result in
            switch result {
            case .success: message = "Payload exported"
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { message = "Export was not completed. Choose a writable destination." }
            }
            output = nil
        }
        .onChange(of:workspace.revision) { _,_ in message = nil; cancelReveal() }
        .onDisappear { cancelReveal() }
        .onDrop(of:[UTType.image.identifier,UTType.fileURL.identifier],isTargeted:$dropping) { receiveDrop($0) }
        .overlay(RoundedRectangle(cornerRadius:8).stroke(dropping ? Color.green : .clear,lineWidth:2))
        #if os(macOS)
        .onExitCommand { if workspace.busy { workspace.cancel() } }
        #endif
    }
    @ViewBuilder private var controls: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:8) { importControls; Spacer(minLength:4); scanControls }
            VStack(alignment:.leading,spacing:8) { HStack { importControls }; HStack { scanControls } }
        }
    }
    @ViewBuilder private var importControls: some View {
        Button("Open Image…",systemImage:"photo") { importing = true }
            .keyboardShortcut("o",modifiers:.command).accessibilityIdentifier("qr-decoder-open")
        #if os(macOS)
        Button("Paste Image",systemImage:"doc.on.clipboard") { paste() }.accessibilityIdentifier("qr-decoder-paste")
        #else
        QRCodePasteImageButton(receive:receiveProviders).frame(width:100,height:36)
        PhotosPicker(selection:$photo,matching:.images,preferredItemEncoding:.current) { Label("Photo…",systemImage:"photo.on.rectangle") }
            .accessibilityIdentifier("qr-decoder-photo")
        #endif
    }
    @ViewBuilder private var scanControls: some View {
        Button("Scan Again",systemImage:"arrow.clockwise") { workspace.scanAgain() }
            .keyboardShortcut(.return,modifiers:.command).disabled(workspace.source == nil || workspace.busy).accessibilityIdentifier("qr-decoder-scan")
        if workspace.busy { Button("Cancel") { workspace.cancel() }.accessibilityIdentifier("qr-decoder-cancel") }
        Button("Clear",systemImage:"trash") { exporting = false; output = nil; workspace.clear(); command = .init(); message = nil }
            .disabled(workspace.source == nil && !workspace.busy).accessibilityIdentifier("qr-decoder-clear")
    }
    private func imagePane(wide: Bool,height: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Button { withAnimation(animation) { workspace.inputExpanded.toggle() } } label: { Label("Image",systemImage:workspace.inputExpanded ? "chevron.down" : "chevron.right").font(.headline) }
                    .buttonStyle(.plain).accessibilityValue(workspace.inputExpanded ? "Expanded" : "Collapsed").accessibilityIdentifier("qr-decoder-image-disclosure")
                Spacer()
                if workspace.source?.hasAlpha == true {
                    Picker("Scan surface",selection:Binding(get:{ workspace.surface },set:{ workspace.setSurface($0) })) {
                        ForEach(QRScanSurface.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize().accessibilityLabel("Scan surface")
                }
            }
            QRCodeImageViewport(image:workspace.snapshot?.image ?? workspace.source?.image,sourceID:workspace.source?.id,items:workspace.snapshot?.items ?? [],selectedID:workspace.selectedID,command:command,reducedMotion:animation == nil,select:{ id,zoom in
                workspace.select(id); if zoom { reveal() }
            },paste:paste,interaction:cancelReveal)
            .overlay {
                if workspace.source == nil { VStack(spacing:8) { Image(systemName:"qrcode.viewfinder").font(.largeTitle); Text("Open, paste or drop a QR image").multilineTextAlignment(.center) }.foregroundStyle(.secondary).padding().allowsHitTesting(false) }
            }
            .frame(height:workspace.inputExpanded ? (wide ? nil : min(180,max(90,height*0.18))) : 0)
            .frame(maxHeight:workspace.inputExpanded && wide ? .infinity : nil)
            .clipped().opacity(workspace.inputExpanded ? 1 : 0).accessibilityHidden(!workspace.inputExpanded)
            if workspace.inputExpanded {
                HStack {
                    Button { send(.zoomOut) } label: { Image(systemName:"minus.magnifyingglass") }.accessibilityLabel("Zoom out")
                    Button { send(.zoomIn) } label: { Image(systemName:"plus.magnifyingglass") }.accessibilityLabel("Zoom in")
                    Button("Fit") { send(.fit) }
                    Spacer()
                }.disabled(workspace.source == nil)
                if let source = workspace.source {
                    Text(source.dimensions + " · " + source.scanDimensions).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func resultsList(height: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text("Results\(workspace.snapshot.map { " · \($0.items.count)\($0.limited ? "+" : "")" } ?? "")").font(.headline)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing:3) {
                        ForEach(workspace.snapshot?.items ?? []) { item in
                            Button { workspace.select(item.id) } label: {
                                HStack(alignment:.top,spacing:8) {
                                    Text("\(item.id+1)").font(.system(.caption,design:.monospaced).weight(.semibold)).frame(minWidth:22)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(QRDecodedPresentation.preview(item)).lineLimit(1)
                                        Text(item.kind).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength:0)
                                }.padding(7).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(RoundedRectangle(cornerRadius:5).fill(workspace.selectedID == item.id ? Color.green.opacity(0.17) : .clear))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(item.id)
                                .accessibilityLabel("Code \(item.id+1), \(item.kind), \(QRDecodedPresentation.preview(item))")
                                .accessibilityAddTraits(workspace.selectedID == item.id ? .isSelected : [])
                                .accessibilityIdentifier("qr-decoder-result-\(item.id)")
                        }
                        if workspace.snapshot?.items.isEmpty != false { Text("Found QR codes will appear here").font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(8) }
                    }
                }.frame(height:height).focusable().focused($listFocused)
                    .onKeyPress(.upArrow) { workspace.selectOffset(-1); return .handled }
                    .onKeyPress(.downArrow) { workspace.selectOffset(1); return .handled }
                    .onChange(of:workspace.selectedID) { _,id in if let id { withAnimation(animation) { proxy.scrollTo(id,anchor:.center) } } }
                    .overlay(RoundedRectangle(cornerRadius:6).stroke(.separator.opacity(0.5)))
            }
        }
    }
    private func paste() {
        #if os(macOS)
        QRDecodedClipboard.paste(into:workspace)
        #else
        // Standard Command-V is an explicit user paste request. The visible Paste control handles consent separately.
        receiveProviders(UIPasteboard.general.itemProviders)
        #endif
    }
    private func receiveProviders(_ providers: [NSItemProvider]) {
        guard providers.count == 1, let provider = providers.first else { workspace.report("Choose one image at a time."); return }
        let box = QRImageProvider(provider)
        workspace.importImage { try await box.load() }
    }
    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else { workspace.report("Choose one image at a time."); return true }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { receiveProviders(providers); return true }
        // File URL data stays memory-only; URL handling validates local regular files and content.
        let box = QRImageProvider(provider)
        workspace.importImage {
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                _ = box.provider.loadDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier) { data,_ in
                    if let data { continuation.resume(returning:data) } else { continuation.resume(throwing:QRDecodeIssue(.loading,"The dropped file could not be loaded.")) }
                }
            }
            guard let url = URL(dataRepresentation:data,relativeTo:nil), url.isFileURL else { throw QRDecodeIssue(.unsupported,"Drop a local image, not a web link.") }
            return try QRCodeDecoderImageLoader.decode(QRCodeDecoderImageLoader.readFile(url))
        }
        return true
    }
    private func copy(_ format: QRDecodeOutput) {
        guard workspace.canOutput, let item = workspace.selected, let value = QRDecodedPresentation.copy(item,as:format) else { return }
        QRDecodedClipboard.copy(value); message = "\(format.rawValue) copied"
    }
    private func export(_ text: Bool) {
        guard workspace.canOutput, let item = workspace.selected, let value = QRDecodedExport(item:item,text:text) else { return }
        output = value; exporting = true
    }
    private func cancelReveal() { revealTask?.cancel(); revealTask = nil; revealID = UUID() }
    private func send(_ action: QRImageViewCommand.Action) { cancelReveal(); command = .init(action:action) }
    private func reveal() {
        guard let item = workspace.selected else { return }
        let wasCollapsed = !workspace.inputExpanded
        cancelReveal(); let id = revealID, sourceID = workspace.source?.id
        withAnimation(animation) { workspace.inputExpanded = true }
        if wasCollapsed {
            // Wait for actual viewport geometry after disclosure; never zoom a zero-height scroll view.
            revealTask = Task { @MainActor in
                do { try await Task.sleep(for:.milliseconds(animation == nil ? 20 : 220)) } catch { return }
                guard revealID == id, workspace.source?.id == sourceID, workspace.selectedID == item.id else { return }
                command = .init(action:.reveal(item.bounds)); revealTask = nil
            }
        } else { command = .init(action:.reveal(item.bounds)) }
    }
}
