import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct GZipView: View {
    @Bindable var workspace: GZipWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @State private var commands = JSONEditorCommands()
    @State private var outputCommands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var dragStart: Double?
    @State private var details = false
    @State private var copied = false
    @State private var keyboard = false
    @State private var showOutputWithKeyboard = false
    private enum PickerPurpose { case source, exportFolder }
    @State private var sourcePickerPresented = false
    @State private var folderPickerPresented = false
    @State private var namingExport = false
    @State private var exportName = "compressed.gz"
    @State private var chooseFolderAfterNaming = false
    @State private var pickerRevision = UUID()
    @State private var pickerError: String?
    private var reduced: Bool { systemReduced || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration:0.2) }
    private var phoneKeyboard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && keyboard
        #else
        false
        #endif
    }
    private var editorOptions: JSONEditorOptions {
        .init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:workspace.preferences.wordWrap)
    }
    private var diagnostic: JSONDiagnostic? {
        guard !workspace.usesFile, let failure = workspace.result?.failure, let range = failure.textRange,
              let line = failure.line, let column = failure.column else { return nil }
        return .init(severity:.error,code:failure.code.rawValue,message:failure.message,range:range,line:line,column:column,precision:.exact)
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            let collapsed = !wide && (workspace.outputCollapsed || (phoneKeyboard && !showOutputWithKeyboard))
            VStack(alignment:.leading,spacing:8) {
                ViewThatFits(in:.horizontal) {
                    HStack { choices; Spacer(minLength:8); actions }
                    VStack(alignment:.leading,spacing:8) { choices; actions }
                }
                GZipStatusView(workspace:workspace,details:$details,show:show,cancel:{ cancelJump(); workspace.cancel() })
                if let error = pickerError ?? workspace.importFailure { Text(error).font(.callout).foregroundStyle(.red) }
                JSONPanelLayout(horizontal:wide,fraction:workspace.fraction,collapsed:collapsed) {
                    inputPanel
                    divider(wide:wide,length:wide ? geometry.size.width : geometry.size.height,collapsed:collapsed)
                    outputPanel(wide:wide,collapsed:collapsed)
                }.animation(motion,value:collapsed)
            }.padding(12)
                .animation(motion,value:workspace.result?.failure?.message)
                .animation(motion,value:details)
        }
        .navigationTitle("GZip Compress / Decompress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { workspace.refreshPreferences() }
        .onDisappear { cancelJump(); workspace.disappear() }
        .onChange(of:workspace.sourceRevision) { _,_ in cancelJump(); copied = false; details = false; namingExport = false; pickerError = nil }
        .onChange(of:workspace.publicationID) { _,_ in copied = false }
        .fileImporter(isPresented:$sourcePickerPresented,allowedContentTypes:[.data],allowsMultipleSelection:false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, workspace.sourceRevision == pickerRevision { workspace.select(url) }
            case .failure(let error): handlePickerError(error)
            }
        }
        .fileImporter(isPresented:$folderPickerPresented,allowedContentTypes:[.folder],allowsMultipleSelection:false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, workspace.sourceRevision == pickerRevision else { return }
                let access = url.startAccessingSecurityScopedResource()
                let work = workspace.run(.check,destination:.init(directory:url,name:exportName))
                Task { @MainActor in
                    await work.value
                    if access { url.stopAccessingSecurityScopedResource() }
                }
            case .failure(let error): handlePickerError(error)
            }
        }
        // Capture the revision in the presenting body so the first sheet cannot use
        // a stale @State value. Changing the filename must not be needed to refresh it.
        .sheet(isPresented:$namingExport,onDismiss:finishNaming) { [pickerRevision] in
            exportForm(revision:pickerRevision)
        }
        #if os(macOS)
        .onExitCommand { if workspace.busy { workspace.cancel() } }
        #else
        .onKeyPress(.escape) { guard workspace.busy else { return .ignored }; workspace.cancel(); return .handled }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)) { _ in keyboard = false; showOutputWithKeyboard = false }
        #endif
    }
    private var choices: some View {
        HStack(spacing:8) {
            Picker("Direction",selection:Binding(get:{ workspace.preferences.direction },set:{ commands.resignFocus?(); workspace.preferences.direction = $0 })) {
                ForEach(GZipDirection.allCases,id:\.self) { Text($0.title).tag($0) }
            }.fixedSize().accessibilityIdentifier("gzip-direction")
            Picker("Input",selection:Binding(get:{ workspace.usesFile },set:{ commands.resignFocus?(); workspace.usesFile = $0 })) {
                Text(workspace.options.direction == .compress ? "Text" : "Base64").tag(false)
                Text("File").tag(true)
            }.fixedSize().accessibilityIdentifier("gzip-source")
        }.pickerStyle(.menu)
    }
    private var actions: some View {
        HStack(spacing:8) {
            Button(workspace.options.direction.title) { cancelJump(); workspace.run() }
                .disabled(!workspace.canRun).keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("gzip-convert")
            Button("Check") { cancelJump(); workspace.run(.check) }.disabled(!workspace.canRun).accessibilityIdentifier("gzip-check")
            Menu {
                if workspace.options.direction == .compress {
                    Picker("Compression level",selection:$workspace.preferences.compressionLevel) {
                        ForEach(GZipLevel.allCases,id:\.self) { Text($0.title).tag($0) }
                    }
                } else {
                    Picker("Maximum decompressed output",selection:$workspace.preferences.maxOutput) {
                        ForEach(GZipOutputLimit.allCases,id:\.self) { Text($0.title).tag($0) }
                    }
                    if !workspace.usesFile {
                        Picker("Base64 policy",selection:$workspace.preferences.base64Mode) {
                            ForEach(Base64DecodeMode.allCases,id:\.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                Toggle("Check automatically on paste",isOn:$workspace.preferences.validateOnPaste)
                Toggle("Word Wrap",isOn:$workspace.preferences.wordWrap)
                Divider()
                Text("Gzip only. Multiple members supported; trailing data, including zero padding, is rejected.")
                Text("Processing stays on this device. Input files: up to 256 MiB; processing time: up to 60 seconds.")
            } label: { Label("Options",systemImage:"slider.horizontal.3") }.accessibilityIdentifier("gzip-options")
        }.fixedSize(horizontal:true,vertical:false)
    }
    private var inputPanel: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Text("Input · \(workspace.usesFile ? "File" : workspace.options.direction == .compress ? "UTF-8 Text" : "Base64")").font(.headline).lineLimit(1)
                Spacer(minLength:0)
                Button(workspace.usesFile ? "Remove" : "Clear",systemImage:"trash") {
                    if !workspace.usesFile { commands.clear?() }; workspace.clear()
                }.disabled(workspace.usesFile ? workspace.selectedFile == nil && !workspace.importing : workspace.input.isEmpty)
                    .accessibilityIdentifier("gzip-clear")
            }.frame(minHeight:30)
            ZStack(alignment:.topLeading) {
                JSONTextEditor(text:$workspace.input,diagnostic:diagnostic,jumpTarget:jumpTarget,jumpRequest:jumpRequest,
                    animateJumps:!reduced,highlightJumps:true,focusOnJump:false,onPaste:{ workspace.didPaste() },commands:commands,options:editorOptions,
                    placeholder:"Paste or type text. Processing stays on this device.",contentName:"GZip")
                    .accessibilityIdentifier("gzip-input").opacity(workspace.usesFile ? 0 : 1)
                    .accessibilityHidden(workspace.usesFile).allowsHitTesting(!workspace.usesFile)
                if workspace.usesFile { fileCard }
            }.clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(.secondary.opacity(0.3)))
        }.clipped()
    }
    private var fileCard: some View {
        VStack(alignment:.leading,spacing:12) {
            Button(workspace.selectedFile == nil ? "Choose File…" : "Replace File…",systemImage:"folder") { choose(.source) }
                .disabled(workspace.importing).accessibilityIdentifier("gzip-choose")
            if workspace.importing { ProgressView("Reading file information…") }
            if let file = workspace.selectedFile {
                Label(file.name,systemImage:"doc").font(.headline).lineLimit(2).accessibilityIdentifier("gzip-file-name")
                Text("Size at selection: " + Base64FileDisplay.bytes(file.size)).font(.callout)
            } else { Text("Choose one regular file. Large files are processed in blocks.").foregroundStyle(.secondary) }
            Text("The source is read only. Export saves a new file only when requested.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength:0)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(.background)
    }
    private func outputPanel(wide:Bool,collapsed:Bool) -> some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Text("Output").font(.headline).lineLimit(1); Spacer(minLength:0)
                Menu {
                    Button("Copy Text") { copy(.text) }.disabled(workspace.copyText(.text) == nil).accessibilityIdentifier("gzip-copy-text")
                    Button("Copy Base64") { copy(.base64) }.disabled(workspace.copyText(.base64) == nil).accessibilityIdentifier("gzip-copy-base64")
                } label: { Label(copied ? "Copied" : "Copy",systemImage:copied ? "checkmark" : "doc.on.doc") }
                .disabled(workspace.copyText(.text) == nil && workspace.copyText(.base64) == nil).accessibilityIdentifier("gzip-copy")
                Button("Export…",systemImage:"square.and.arrow.up") {
                    commands.resignFocus?(); outputCommands.resignFocus?()
                    pickerRevision = workspace.sourceRevision; exportName = workspace.suggestedName
                    chooseFolderAfterNaming = false; namingExport = true
                }
                    .disabled(!workspace.canExport).accessibilityIdentifier("gzip-export")
                if !wide {
                    Button {
                        outputCommands.resignFocus?()
                        if phoneKeyboard { showOutputWithKeyboard = collapsed; workspace.outputCollapsed = false }
                        else { workspace.outputCollapsed.toggle() }
                    } label: { Image(systemName:collapsed ? "chevron.down" : "chevron.up") }
                        .accessibilityLabel(collapsed ? "Expand Output" : "Collapse Output").accessibilityIdentifier("gzip-collapse")
                }
            }.frame(minHeight:30)
            HStack {
                Picker("Output view",selection:$workspace.outputView) {
                    ForEach(GZipWorkspaceSession.OutputView.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).fixedSize().disabled(workspace.artifact == nil).accessibilityIdentifier("gzip-output-view")
                Text(workspace.outputCaption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(minHeight:30)
            JSONTextEditor(text:.constant(workspace.outputText),editable:false,commands:outputCommands,options:editorOptions,
                placeholder:workspace.artifact?.bytes?.isEmpty == true ? "Empty result · 0 bytes" : "Compress or Decompress to preview a result. Export saves the complete output.",contentName:"GZip")
                .accessibilityIdentifier("gzip-output").clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(.secondary.opacity(0.3)))
                .opacity(collapsed ? 0 : 1).accessibilityHidden(collapsed).allowsHitTesting(!collapsed)
        }.clipped()
    }
    private func divider(wide:Bool,length:CGFloat,collapsed:Bool) -> some View {
        RoundedRectangle(cornerRadius:2).fill(.secondary.opacity(0.35))
            .frame(width:wide ? 4 : 34,height:wide ? 34 : 4).frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                guard !collapsed else { return }; if dragStart == nil { dragStart = workspace.fraction }
                workspace.fraction = min(0.75,max(0.25,(dragStart ?? 0.5) + (wide ? value.translation.width : value.translation.height) / max(1,length - 16)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Panel proportions").accessibilityValue("\(Int(workspace.fraction * 100)) percent input")
            .accessibilityAdjustableAction { direction in workspace.fraction = min(0.75,max(0.25,workspace.fraction + (direction == .increment ? 0.05 : -0.05))) }
            .contextMenu { Button("Reset split") { withAnimation(motion) { workspace.fraction = 0.5 } } }
    }
    private func exportForm(revision:UUID) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Export result").font(.headline)
            TextField("Filename",text:$exportName).textFieldStyle(.roundedBorder).accessibilityIdentifier("gzip-export-name")
            Text("Existing files are never replaced. Export creates a temporary .partial here; it may remain if the app is forcibly closed.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Next, choose a local folder to keep the exported file local.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel",role:.cancel) { namingExport = false }.accessibilityIdentifier("gzip-export-cancel"); Spacer()
                Button("Choose Folder…") {
                    guard workspace.sourceRevision == revision else { namingExport = false; return }
                    chooseFolderAfterNaming = true; namingExport = false
                }.disabled(!workspace.canExport || !GZipFileProcessor.validFilename(exportName) || workspace.sourceRevision != revision)
                    .accessibilityIdentifier("gzip-export-confirm")
            }
        }.padding(22).frame(idealWidth:420).presentationDetents([.medium])
    }
    private func choose(_ kind:PickerPurpose) {
        guard !sourcePickerPresented && !folderPickerPresented else { return }; commands.resignFocus?(); outputCommands.resignFocus?()
        pickerRevision = workspace.sourceRevision; pickerError = nil
        if kind == .source { sourcePickerPresented = true } else { folderPickerPresented = true }
    }
    private func handlePickerError(_ error:Error) {
        if (error as NSError).code != NSUserCancelledError { pickerError = "Selection unavailable. Choose a readable local file or folder." }
    }
    private func finishNaming() {
        guard chooseFolderAfterNaming, workspace.sourceRevision == pickerRevision, workspace.canExport else { chooseFolderAfterNaming = false; return }
        chooseFolderAfterNaming = false; choose(.exportFolder)
    }
    private func cancelJump() { commands.cancelNavigation?(); jumpTarget = nil; jumpRequest += 1 }
    private func show(_ range:NSRange) { commands.cancelNavigation?(); jumpTarget = range; jumpRequest += 1 }
    private func copy(_ kind:GZipWorkspaceSession.OutputView) {
        guard let text = workspace.copyText(kind) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
        #else
        UIPasteboard.general.string = text
        #endif
        copied = true
    }
}
