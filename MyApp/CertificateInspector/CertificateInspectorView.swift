import SwiftUI
import UniformTypeIdentifiers

struct CertificateInspectorView: View {
    @Bindable var workspace: CertificateWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var importing = false
    @State private var exporting = false
    @State private var exportPEM = true
    @State private var document = CertificateExportDocument(Data())
    @State private var exportMessage: String?
    @State private var fraction = 0.38
    @State private var expanded: Set<Int> = []
    private var reduced: Bool { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration:0.2) }
    private var options: JSONEditorOptions { .init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:workspace.wordWrap) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack { operations; Spacer(); controls }
                VStack(alignment:.leading) { operations; controls }
            }
            HStack(spacing:8) {
                if workspace.busy { ProgressView().controlSize(.small) }
                Text(workspace.busy ? "Inspecting…" : workspace.cancelled ? "Cancelled" : workspace.result?.message ?? "Ready · paste PEM or import a certificate")
                    .font(.callout).lineLimit(2).accessibilityIdentifier("certificate-status")
                Spacer(minLength:0)
            }.frame(minHeight:26)
            Text("Trust, certificate signatures and revocation are not evaluated.").font(.caption).foregroundStyle(.secondary)
            if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
            GeometryReader { area in
                let wide = area.size.width >= 780
                SecurityToolPanelLayout(wide:wide,fraction:fraction,collapsed:workspace.inputCollapsed) {
                    input.opacity(workspace.inputCollapsed ? 0 : 1).clipped().allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
                    SecurityPanelDivider(wide:wide,length:wide ? area.size.width : area.size.height,fraction:$fraction).opacity(workspace.inputCollapsed ? 0 : 1)
                    details
                }
            }
        }.padding(12).navigationTitle("X.509 Certificate Inspector")
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.plainText],allowsMultipleSelection:false) { result in
                if case .success(let urls) = result, let url = urls.first { workspace.importFile(url) }
                else if case .failure = result { exportMessage = "Import cancelled or unavailable." }
            }
            .fileExporter(isPresented:$exporting,document:document,contentTypes:[.data],defaultFilename:exportPEM ? "certificate.pem" : "certificate.der",onCompletion:{ result in
                let outcome = PKIExportOutcome(result)
                exportMessage = outcome == .success ? "Certificate exported." : outcome.message
                document = .init(Data())
            },onCancellation:{ exportMessage = PKIExportOutcome.cancelled.message; document = .init(Data()) })
            .onDrop(of:[UTType.fileURL.identifier],isTargeted:nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { value,_ in
                    let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation:$0,relativeTo:nil) }
                    if let url { Task { @MainActor in workspace.importFile(url) } }
                }; return true
            }
    }
    private var operations: some View {
        HStack {
            Button("Inspect") { workspace.run() }.keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("certificate-inspect")
            Button("Paste") { if let text = SecurityToolClipboard.paste() {
                if workspace.fileSource != nil { workspace.editInput(); workspace.input = text }
                else { commands.replace?(.init(location:0,length:workspace.input.utf16.count),text) }
                if workspace.inspectOnPaste { workspace.run() }
            } }
            Button("Open File",systemImage:"folder") { importing = true }.keyboardShortcut("o",modifiers:.command)
            if workspace.busy { Button("Cancel") { workspace.cancel() } }
            Button("Clear") { commands.clear?(); commands.purgeUndo?(); workspace.clear() }
        }.buttonStyle(.bordered).controlSize(.small)
    }
    private var controls: some View {
        HStack {
            Button(workspace.inputCollapsed ? "Edit Input" : "Hide Input",systemImage:workspace.inputCollapsed ? "sidebar.left" : "sidebar.right") {
                commands.resignFocus?(); withAnimation(motion) { workspace.inputCollapsed.toggle() }
            }
            Menu("Options",systemImage:"slider.horizontal.3") {
                Toggle("Word Wrap",isOn:$workspace.wordWrap); Toggle("Local dates",isOn:$workspace.localDates); Toggle("Inspect on paste/import",isOn:$workspace.inspectOnPaste)
            }.menuStyle(.borderlessButton)
        }.controlSize(.small)
    }
    private var input: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack { Text("Input").font(.headline); Spacer(); if workspace.fileSource != nil { Button("Edit PEM") { workspace.usePEM() }.disabled((workspace.selected?.pem.utf16.count ?? .max) > CertificateLimits.editor) } }
            if workspace.fileSource != nil {
                Text(workspace.fileLabel).font(.caption).foregroundStyle(.secondary)
                Text("Preview · full source remains in memory").font(.caption2).foregroundStyle(.secondary)
            }
            ZStack {
                JSONTextEditor(text:$workspace.input,jumpTarget:workspace.target,jumpRequest:workspace.jumpRequest,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,onPaste:{ if workspace.inspectOnPaste { workspace.run() } },commands:commands,options:options,presentationHidden:workspace.fileSource != nil,privateUndo:true,placeholder:"Paste a PEM certificate or import PEM / DER.",contentName:"Certificate PEM",showsLineNumbers:false)
                    .opacity(workspace.fileSource == nil ? 1 : 0).allowsHitTesting(workspace.fileSource == nil).accessibilityHidden(workspace.fileSource != nil)
                if workspace.fileSource != nil { JSONTextEditor(text:.constant(workspace.preview),editable:false,options:options,contentName:"Certificate preview",showsLineNumbers:false) }
            }
        }.securityToolPanel()
    }
    private var details: some View {
        VStack(alignment:.leading,spacing:8) {
            if let result = workspace.result, !result.entries.isEmpty {
                if result.entries.count > 1 {
                    Picker("Certificate",selection:$workspace.selectedID) { ForEach(result.entries) { entry in Text("\(entry.id+1) · \(CertificateDisplay.safe(entry.subject,limit:60))").tag(entry.id) } }.pickerStyle(.menu)
                }
                if let entry = workspace.selected {
                    HStack {
                        Text("Certificate \(entry.id+1)").font(.headline); Spacer()
                        actions(entry)
                    }
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:12) {
                            Text(entry.parsed ? entry.validity(at:result.evaluatedAt) : "Unable to inspect this entry").font(.headline)
                            Text("Evaluated \(CertificateDisplay.date(result.evaluatedAt,local:workspace.localDates))").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(entry.issues.enumerated()),id:\.offset) { _,issue in Label(issue,systemImage:"exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                            ForEach(entry.fields) { field in fieldRow(field.name,field.value) }
                            if let date = entry.notBefore { fieldRow("Not before",CertificateDisplay.date(date,local:workspace.localDates)) }
                            if let date = entry.notAfter { fieldRow("Not after",CertificateDisplay.date(date,local:workspace.localDates)) }
                            fieldRow("Certificate SHA-256",entry.sha256)
                            fieldRow("SHA-1 · legacy fingerprint",entry.sha1)
                            if let digest = entry.spkiDigest { fieldRow("SPKI SHA-256",digest) }
                            ForEach(entry.extensions) { ext in
                                DisclosureGroup(isExpanded:Binding(get:{ expanded.contains(ext.id) },set:{ value in withAnimation(motion) { if value { expanded.insert(ext.id) } else { expanded.remove(ext.id) } } })) {
                                    LazyVStack(alignment:.leading,spacing:10) {
                                        ForEach(ext.fields) { field in fieldRow(field.name,field.value) }
                                        fieldRow("Raw extension DER",ext.rawHex)
                                    }.padding(.top,6)
                                } label: { Text(CertificateDER.name(ext.oid)+(ext.critical ? " · Critical" : "")).font(.callout.weight(.medium)) }
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.defaultScrollAnchor(.top)
                }
            } else {
                ContentUnavailableView("Inspect a certificate",systemImage:"checkmark.seal",description:Text(workspace.result?.message ?? "Paste PEM or import a PEM/DER file. All processing stays on this device."))
            }
        }.securityToolPanel()
    }
    private func fieldRow(_ name: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            HStack { Text(name).font(.caption).foregroundStyle(.secondary); Spacer(); Button { SecurityToolClipboard.copy(value) } label:{ Image(systemName:"doc.on.doc") }.buttonStyle(.borderless).help("Copy full original value").accessibilityLabel("Copy \(name)") }
            Text(CertificateDisplay.safe(value)).font(.system(.callout,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func actions(_ entry: CertificateEntry) -> some View {
        Menu("Actions",systemImage:"ellipsis.circle") {
            Button("Show in Input") { withAnimation(motion) { workspace.showSource() } }.disabled(entry.sourceRange == nil || workspace.fileSource != nil)
            Button("Copy PEM") { SecurityToolClipboard.copy(entry.pem) }
            Button("Copy SHA-256") { SecurityToolClipboard.copy(entry.sha256) }
            Button("Copy summary") { SecurityToolClipboard.copy(entry.fields.map { "\($0.name): \($0.value)" }.joined(separator:"\n")+"\nTrust and revocation not evaluated.") }
            Button("Export PEM…") { exportPEM = true; document = .init(Data(entry.pem.utf8)); exporting = true }
            Button("Export DER…") { exportPEM = false; document = .init(entry.der); exporting = true }
        }.accessibilityIdentifier("certificate-actions")
    }
}
