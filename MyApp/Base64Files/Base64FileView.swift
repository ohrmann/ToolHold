import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct Base64FileView: View {
    @Bindable var workspace: Base64FileWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var jumpWork: Task<Void,Never>?
    private enum PickerPurpose { case source, exportFolder }
    @State private var pickerPurpose = PickerPurpose.source
    @State private var pickerPresented = false
    @State private var namingExport = false
    @State private var exportName = "decoded.bin"
    @State private var folder: URL?
    @State private var folderAccess = false
    @State private var exportRevision = UUID()
    @State private var pickerError: String?
    @State private var dragStart: Double?
    @State private var details = false
    @State private var copied = false
    @State private var showingImage = false
    @State private var image: Base64FileImagePreview?
    @State private var previewWork: Task<Void,Never>?
    @State private var keyboard = false
    @State private var showOutputWithKeyboard = false
    private var reduced: Bool { systemReduced || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration: 0.2) }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone && keyboard
        #else
        return false
        #endif
    }
    private var editorOptions: JSONEditorOptions {
        .init(syntax: .plainText, syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: workspace.preferences.wordWrap)
    }
    private var diagnostic: JSONDiagnostic? {
        guard !workspace.usesFile, let failure = workspace.result?.failure, let range = failure.textRange else { return nil }
        return Base64EditorDiagnosticAdapter.make(.init(code: .invalidSymbol, severity: .error, message: failure.message,
            range: range, line: failure.line, column: failure.column))
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            let outputCollapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment: .leading, spacing: 8) {
                choices
                actions
                status
                if workspace.inputCollapsed {
                    Button("Edit Input", systemImage: "chevron.down") { workspace.inputCollapsed = false }
                        .accessibilityIdentifier("b64file-edit-input")
                }
                Base64FilePanels(horizontal: wide, fraction: workspace.fraction, inputCollapsed: workspace.inputCollapsed,
                                 outputCollapsed: outputCollapsed) {
                    inputPanel
                    divider(wide, length: wide ? geometry.size.width : geometry.size.height)
                    outputPanel(wide: wide, collapsed: outputCollapsed)
                }
                .animation(motion, value: workspace.inputCollapsed)
                .animation(motion, value: outputCollapsed)
            }
            .padding(12)
            .animation(motion, value: workspace.result?.failure?.message)
            .animation(motion, value: details)
        }
        .navigationTitle("Base64 File / Image")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { workspace.refreshPreferences() }
        .onChange(of: workspace.usesFile) { _, file in
            if file { DispatchQueue.main.async { if workspace.usesFile { commands.resignFocus?() } } }
        }
        .onDisappear { workspace.disappear(); cancelNavigation(); previewWork?.cancel(); releaseFolder() }
        .onChange(of: workspace.sourceRevision) { _, _ in
            cancelNavigation(); details = false; copied = false; image = nil; previewWork?.cancel()
            namingExport = false; showingImage = false; pickerError = nil
        }
        .onChange(of: workspace.publicationID) { _, _ in copied = false; image = nil; previewWork?.cancel() }
        .fileImporter(isPresented: $pickerPresented,
                      allowedContentTypes: pickerPurpose == .source ? [.data] : [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if pickerPurpose == .source {
                    workspace.select(url)
                } else {
                    guard workspace.sourceRevision == exportRevision else { return }
                    pickerError = nil; releaseFolder(); folder = url; folderAccess = url.startAccessingSecurityScopedResource()
                    exportName = workspace.suggestedName; namingExport = true
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { pickerError = "Selection is unavailable. Choose a local file or folder." }
            }
        }
        .sheet(isPresented: $namingExport, onDismiss: releaseFolder) { exportForm }
        .sheet(isPresented: $showingImage, onDismiss: { previewWork?.cancel(); image = nil }) { imageSheet }
        #if os(macOS)
        .onExitCommand { workspace.cancel() }
        #else
        .onKeyPress(.escape) { guard workspace.busy else { return .ignored }; workspace.cancel(); return .handled }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false; showOutputWithKeyboard = false }
        #endif
    }
    private var choices: some View {
        ViewThatFits(in: .horizontal) {
            HStack { direction; format; alphabet; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 6) { HStack { direction; format }; alphabet }
        }.pickerStyle(.menu)
    }
    private var direction: some View {
        Picker("Direction", selection: Binding(get: { workspace.preferences.direction }, set: {
            commands.resignFocus?()
            workspace.preferences.direction = $0
        })) {
            Text("File → Base64").tag(Base64Direction.encode)
            Text("Base64 → File").tag(Base64Direction.decode)
        }.fixedSize().accessibilityIdentifier("b64file-direction")
    }
    private var format: some View {
        Picker("Format", selection: $workspace.preferences.format) {
            ForEach(Base64FileFormat.allCases, id: \.self) { Text($0.title).tag($0) }
        }.fixedSize().accessibilityIdentifier("b64file-format")
    }
    private var alphabet: some View {
        Picker("Alphabet", selection: Binding(get: {
            workspace.preferences.format == .dataURL ? .standard : workspace.preferences.alphabet
        }, set: { workspace.preferences.alphabet = $0 })) {
            ForEach(Base64Alphabet.allCases, id: \.self) { Text($0.title).tag($0) }
        }.fixedSize().disabled(workspace.preferences.format == .dataURL).accessibilityIdentifier("b64file-alphabet")
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button(workspace.preferences.direction.title) { workspace.run() }
                .keyboardShortcut(.return, modifiers: .command).disabled(!workspace.canRun).accessibilityIdentifier("b64file-convert")
            Button("Check") { workspace.run(.check) }.disabled(!workspace.canRun).accessibilityIdentifier("b64file-check")
            Spacer(minLength: 0)
            Menu {
                Button("Choose File…", action: chooseSource).keyboardShortcut("o", modifiers: .command)
                Divider()
                if workspace.preferences.direction == .decode {
                    Picker("Decode mode", selection: $workspace.preferences.decodeMode) {
                        ForEach(Base64DecodeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                if workspace.preferences.direction == .encode && workspace.preferences.format == .raw && workspace.preferences.alphabet == .urlSafe {
                    Toggle("Include '=' padding", isOn: $workspace.preferences.urlPadding)
                }
                Toggle("Check automatically on paste", isOn: $workspace.preferences.validateOnPaste)
                Toggle("Word Wrap", isOn: $workspace.preferences.wordWrap)
                Text("One file at a time. Processing stays on this device.")
            } label: { Label("Options", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("b64file-options")
        }
    }
    private var statusTitle: String {
        if workspace.busy { return "Processing" }
        if let saved = workspace.exportMessage { return saved }
        if workspace.wasCancelled { return "Cancelled" }
        guard let result = workspace.result else {
            return workspace.source == nil || (!workspace.usesFile && workspace.input.isEmpty) ? "Ready" : "Not checked"
        }
        switch result.status {
        case .success: return workspace.lastIntent == .check ? "Valid · checked" : "Completed"
        case .invalidBase64: return "Invalid Base64"
        case .unsupportedFormat: return "Unsupported format"
        case .sourceChanged: return "Source changed"
        case .resourceLimit: return "Resource limit reached"
        case .ioFailure: return "File operation failed"
        case .cancelled: return "Cancelled"
        }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: workspace.result?.failure == nil ? "info.circle" : "exclamationmark.triangle")
                Text(statusTitle).font(.callout).lineLimit(1).accessibilityIdentifier("b64file-status")
                Spacer(minLength: 0)
                if workspace.busy {
                    if let total = workspace.progress.total, total > 0 {
                        ProgressView(value: Double(min(total, workspace.progress.bytes)), total: Double(total)).frame(width: 64)
                    } else { ProgressView().controlSize(.small) }
                    Button("Cancel") { workspace.cancel() }.accessibilityIdentifier("b64file-cancel")
                }
            }.frame(minHeight: 30)
            if let warning = workspace.cleanupWarning {
                HStack { Text(warning).font(.caption).textSelection(.enabled); Button("Dismiss") { workspace.dismissCleanupWarning() } }
            }
            if let message = pickerError ?? workspace.importFailure { Text(message).font(.callout).accessibilityIdentifier("b64file-picker-error") }
            if let failure = workspace.result?.failure {
                Text(failure.message).font(.callout).lineLimit(3).help(failure.message).accessibilityIdentifier("b64file-error")
                HStack {
                    if let line = failure.line, let column = failure.column {
                        Text("Line \(line), column \(column) (UTF-16)").font(.caption)
                    } else if let offset = failure.byteOffset { Text("Byte offset \(offset) (0-based)").font(.caption) }
                    if let range = failure.textRange {
                        Button("Show Input") { show(range) }
                            .accessibilityIdentifier("b64file-show-input")
                    }
                    if !failure.context.isEmpty || failure.cleanupPath != nil { Button(details ? "Hide details" : "Details") { details.toggle() } }
                }.controlSize(.small)
                if details {
                    Text(failure.context).font(.system(.caption, design: .monospaced)).lineLimit(4).textSelection(.enabled)
                    if let path = failure.cleanupPath { Text("Partial export: " + Base64FileDisplay.safeLabel(path, limit: 500)).font(.caption).textSelection(.enabled) }
                }
            } else if let result = workspace.result, !result.notes.isEmpty {
                HStack(alignment: .top) {
                    Text(result.notes[0]).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    if result.notes.count > 1 { Button(details ? "Hide details" : "Details") { details.toggle() }.controlSize(.small) }
                }
                if details && result.notes.count > 1 {
                    ScrollView {
                        Text(result.notes.dropFirst().joined(separator: "\n")).font(.caption).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90)
                }
            }
        }
    }
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input").font(.headline); Spacer()
                Button("Clear", systemImage: "trash") {
                    if !workspace.usesFile { commands.clear?() }
                    workspace.clear()
                }.accessibilityIdentifier("b64file-clear")
                Button { commands.resignFocus?(); workspace.inputCollapsed = true } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Collapse Input").accessibilityIdentifier("b64file-collapse-input")
            }.frame(minHeight: 30)
            if workspace.preferences.direction == .decode {
                Picker("Input source", selection: Binding(get: { workspace.decodeFromFile }, set: {
                    commands.resignFocus?(); workspace.decodeFromFile = $0
                })) {
                    Text("Text").tag(false); Text("File").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("b64file-source")
            }
            if workspace.preferences.direction == .encode && workspace.preferences.format == .dataURL {
                HStack {
                    Text("MIME").font(.caption)
                    TextField(workspace.effectiveMIME, text: $workspace.mimeOverride).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("MIME type override").accessibilityIdentifier("b64file-mime")
                }
            }
            ZStack(alignment: .topLeading) {
                JSONTextEditor(text: $workspace.input, diagnostic: diagnostic, jumpTarget: jumpTarget, jumpRequest: jumpRequest,
                    animateJumps: !reduced, highlightJumps: true, focusOnJump: false,
                    onPaste: { workspace.didPaste() }, commands: commands, options: editorOptions,
                    placeholder: "Paste Base64 or a Data URL, then Decode. Choose the matching format above.", contentName: "Base64 file")
                    .accessibilityIdentifier("b64file-input")
                    .opacity(workspace.usesFile ? 0 : 1).accessibilityHidden(workspace.usesFile).allowsHitTesting(!workspace.usesFile)
                if workspace.usesFile { fileCard }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        }.clipped().opacity(workspace.inputCollapsed ? 0 : 1).accessibilityHidden(workspace.inputCollapsed).allowsHitTesting(!workspace.inputCollapsed)
    }
    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(workspace.selectedFile == nil ? "Choose File…" : "Replace File…", systemImage: "folder", action: chooseSource)
                .disabled(workspace.importing).accessibilityIdentifier("b64file-choose")
            if workspace.importing { ProgressView("Reading file information…") }
            if let file = workspace.selectedFile {
                Label(file.name, systemImage: "doc").font(.headline).lineLimit(2).accessibilityIdentifier("b64file-name")
                if let size = file.size { Text("Size at selection: " + Base64FileDisplay.bytes(size)).font(.callout) }
                Text("Type hint: \(file.mime)").font(.caption).foregroundStyle(.secondary)
            } else { Text("Choose one local file. Large files are processed in blocks.").foregroundStyle(.secondary) }
            Text("The source file is never modified. Image metadata is preserved.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.background)
    }
    private func outputPanel(wide: Bool, collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Result").font(.headline); Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy", systemImage: "doc.on.doc") { copy() }
                    .disabled(!workspace.canCopy).accessibilityIdentifier("b64file-copy")
                Button("Export…", systemImage: "square.and.arrow.up") {
                    guard !pickerPresented else { return }
                    commands.resignFocus?()
                    pickerError = nil; exportRevision = workspace.sourceRevision
                    pickerPurpose = .exportFolder; pickerPresented = true
                }.disabled(!workspace.canExport).accessibilityIdentifier("b64file-export")
                if !wide {
                    Button {
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                    .accessibilityLabel(collapsed ? "Expand Result" : "Collapse Result").accessibilityIdentifier("b64file-collapse-result")
                }
            }.frame(minHeight: 30)
            if let artifact = workspace.artifact {
                HStack {
                    Text("Snapshot · " + Base64FileDisplay.bytes(artifact.outputBytes)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Image preview") { previewImage() }.disabled(workspace.busy).accessibilityIdentifier("b64file-image")
                }
            }
            JSONTextEditor(text: .constant(workspace.outputText), editable: false, options: editorOptions,
                placeholder: "Encode or Decode to preview the result. Export writes the complete file.", contentName: "Base64 file")
                .accessibilityIdentifier("b64file-output")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .opacity(collapsed ? 0 : 1).accessibilityHidden(collapsed).allowsHitTesting(!collapsed)
        }.clipped()
    }
    private func divider(_ wide: Bool, length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.35))
            .frame(width: wide ? 4 : 34, height: wide ? 34 : 4).frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                if dragStart == nil { dragStart = workspace.fraction }
                workspace.fraction = min(0.75, max(0.25, (dragStart ?? 0.5) + (wide ? value.translation.width : value.translation.height) / max(1,length - 16)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Panel proportions")
            .accessibilityAdjustableAction { direction in workspace.fraction = min(0.75,max(0.25,workspace.fraction + (direction == .increment ? 0.05 : -0.05))) }
    }
    private var exportForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export to selected folder").font(.headline)
            TextField("Filename", text: $exportName).textFieldStyle(.roundedBorder).accessibilityIdentifier("b64file-export-name")
            Text("Existing files are never replaced. A temporary .partial is created here only during Export. If the app is forcibly closed, that partial file may remain.")
                .font(.callout).foregroundStyle(.secondary)
            Text("The chosen folder may belong to a cloud provider. Use a local folder to keep the exported file local.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { namingExport = false }
                Spacer()
                Button("Export") {
                    guard let folder, exportRevision == workspace.sourceRevision else { namingExport = false; return }
                    workspace.run(destination: .init(directory: folder, name: exportName)); namingExport = false
                }.disabled(!Base64FileProcessor.validFilename(exportName) || exportRevision != workspace.sourceRevision)
                    .accessibilityIdentifier("b64file-export-confirm")
            }
        }.padding(22).frame(idealWidth: 420).presentationDetents([.medium])
    }
    private var imageSheet: some View {
        VStack(spacing: 12) {
            if let image {
                if let bitmap = image.image { Image(decorative: bitmap, scale: 1).resizable().scaledToFit().accessibilityLabel("First image preview") }
                Text(image.message).font(.callout).textSelection(.enabled)
            } else { ProgressView("Preparing bounded preview…") }
            Button("Done") { showingImage = false; previewWork?.cancel() }
        }.padding().frame(idealWidth: 520, idealHeight: 440).presentationDetents([.medium,.large])
    }
    private func previewImage() {
        guard let artifact = workspace.artifact else { return }
        showingImage = true; image = nil; previewWork?.cancel()
        let revision = workspace.sourceRevision, publication = workspace.publicationID
        previewWork = Task {
            let worker = Task.detached(priority: .userInitiated) { Base64FileImagePreview.make(artifact.imageBytes, declared: artifact.mediaType) }
            let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, workspace.sourceRevision == revision, workspace.publicationID == publication else { return }
            image = value
        }
    }
    private func chooseSource() {
        guard !pickerPresented else { return }
        commands.resignFocus?()
        if workspace.preferences.direction == .decode { workspace.decodeFromFile = true }
        pickerError = nil; pickerPurpose = .source; pickerPresented = true
    }
    private func releaseFolder() {
        if folderAccess { folder?.stopAccessingSecurityScopedResource() }
        folder = nil; folderAccess = false
    }
    private func cancelNavigation() { jumpWork?.cancel(); jumpWork = nil; commands.cancelNavigation?(); jumpTarget = nil; jumpRequest += 1 }
    private func show(_ range: NSRange) {
        cancelNavigation()
        let collapsed = workspace.inputCollapsed, revision = workspace.sourceRevision
        workspace.inputCollapsed = false
        jumpWork = Task {
            if collapsed && !reduced { try? await Task.sleep(for: .milliseconds(220)) }
            guard !Task.isCancelled, workspace.sourceRevision == revision else { return }
            jumpTarget = range; jumpRequest += 1
        }
    }
    private func copy() {
        guard workspace.canCopy, let text = workspace.artifact?.copyText else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copied = true
    }
}

/// Both native editor identities survive axis changes and either panel's collapse.
private struct Base64FilePanels: Layout {
    var horizontal: Bool
    var fraction: Double
    var inputProgress: Double
    var outputProgress: Double
    init(horizontal: Bool, fraction: Double, inputCollapsed: Bool, outputCollapsed: Bool) {
        self.horizontal = horizontal; self.fraction = fraction
        inputProgress = inputCollapsed ? 1 : 0; outputProgress = outputCollapsed ? 1 : 0
    }
    var animatableData: AnimatablePair<Double, AnimatablePair<Double,Double>> {
        get { .init(fraction,.init(inputProgress,outputProgress)) }
        set { fraction = newValue.first; inputProgress = newValue.second.first; outputProgress = newValue.second.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions(by: .init(width: 600,height: 400)) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let available = max(0,(horizontal ? bounds.width : bounds.height) - 16)
        let first = max(0,(available * min(0.75,max(0.25,fraction)) * (1 - inputProgress)) +
            (max(0,available - 36) - available * min(0.75,max(0.25,fraction))) * outputProgress * (1 - inputProgress))
        for (index, offset, length) in [(0,CGFloat(0),first),(1,first,CGFloat(16)),(2,first + 16,available - first)] {
            subviews[index].place(at: .init(x: bounds.minX + (horizontal ? offset : 0),y: bounds.minY + (horizontal ? 0 : offset)),
                anchor: .topLeading, proposal: .init(width: horizontal ? length : bounds.width,height: horizontal ? bounds.height : length))
        }
    }
}
