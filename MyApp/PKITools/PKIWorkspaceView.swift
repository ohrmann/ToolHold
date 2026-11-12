import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// A small presentation shell for the seven related PKI operations. Crypto remains in PKICore.
struct PKIWorkspaceView: View {
    @Bindable var workspace: PKIWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var accessiblePanelHeight = 600.0
    private var accessibleLayout: Bool { dynamicType.isAccessibilitySize }
    private var actionLayout: AnyLayout { accessibleLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 8)) }
    @State private var fraction = 0.43
    @State private var importing = false
    @State private var importSlot = 0
    @State private var exporting = false
    @State private var document = PKIExportDocument(Data())
    @State private var filename = "certificate.pem"
    @State private var exportMessage = ""
    @State private var keyToExport: Int32?
    @State private var keySheetActive = false
    @State private var plainKey = false
    @State private var pemKey = true
    @State private var confirmPlain = false
    @State private var pendingSensitive: PKIExport?
    @State private var folderDocument = PKIDirectoryDocument(files:[:])
    @State private var exportingFolder = false
    #if os(macOS)
    @State private var localSavePanel: NSSavePanel?
    @State private var localExportTask: Task<Void,Never>?
    @State private var localExportID = UUID()
    #endif
    @State private var target: NSRange?
    @State private var jump = 0
    @State private var editorEpoch = 0
    @State private var packagingExpanded = false
    @FocusState private var inventoryFocused: Bool
    private var motion: Animation? { reduceMotion || (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") && ProcessInfo.processInfo.arguments.contains("--reduce-motion")) ? nil : .easeInOut(duration:0.2) }
    private var generates: Bool { workspace.tool == .certificate || (workspace.tool == .csr && workspace.mode == 0) }
    private var action: String { switch workspace.tool { case .certificate: "Generate"; case .csr: workspace.mode == 0 ? "Create CSR" : "Inspect CSR"; case .converter: "Convert"; case .pfx: workspace.mode == 0 ? "Unlock" : "Create PFX"; case .chain: "Validate Chain"; case .matcher: "Match Key"; default: "Inspect Key" } }
    var body: some View {
        GeometryReader { viewport in
          ScrollView(.vertical) {
           VStack(alignment:.leading,spacing:8) {
            if accessibleLayout {
                VStack(alignment:.leading,spacing:12) { actions; modes }
            } else { ViewThatFits(in:.horizontal) {
                HStack { actions; Spacer(); modes }
                VStack(alignment:.leading) { actions; modes }
            } }
            HStack {
                if workspace.busy { ProgressView().controlSize(.small) }
                Text(workspace.message).font(.callout).textSelection(.enabled).accessibilityIdentifier("pki-status")
                Spacer(minLength:0)
            }.frame(minHeight:26).animation(motion,value:workspace.message)
            Text(caveat).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if !exportMessage.isEmpty { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
            GeometryReader { area in
                let wide = area.size.width >= 850
                SecurityToolPanelLayout(wide:wide,fraction:fraction,collapsed:workspace.inputCollapsed) {
                    inputPanel.opacity(workspace.inputCollapsed ? 0 : 1).clipped().allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
                    SecurityPanelDivider(wide:wide,length:wide ? area.size.width : area.size.height,fraction:$fraction).opacity(workspace.inputCollapsed ? 0 : 1)
                    outputPanel
                }
            }
            .frame(minHeight:accessibleLayout ? accessiblePanelHeight : 0)
           }.padding(12)
            .frame(minHeight:viewport.size.height,maxHeight:accessibleLayout ? nil : viewport.size.height,alignment:.topLeading)
          }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("pki-workspace-scroll")
        }.toolNavigationTitle(ToolID(rawValue:String(format:"T-%03d",workspace.tool.rawValue))!)
        .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.plainText]) { result in
            if case .success(let url) = result { workspace.importFile(url,slot:importSlot) }
        }
        #if os(iOS)
        // macOS uses the owned local writer: do not hand its sensitive payloads
        // to an unpresented document exporter or its retained preparation state.
        .fileExporter(isPresented:$exporting,document:document,contentTypes:[.data],defaultFilename:filename,onCompletion: { result in
            exportMessage = PKIExportOutcome(result).message
            document = .init(Data()); workspace.pendingExport = nil
        },onCancellation: {
            exportMessage = PKIExportOutcome.cancelled.message
            document = .init(Data()); workspace.pendingExport = nil
        })
        .fileExporter(isPresented:$exportingFolder,document:folderDocument,contentTypes:[.folder],defaultFilename:"converted-objects",onCompletion: { result in
            exportMessage = PKIExportOutcome(result).message
            folderDocument = .init(files:[:])
        },onCancellation: { exportMessage = PKIExportOutcome.cancelled.message; folderDocument = .init(files:[:]) })
        #endif
        .background { if workspace.tool == .pfx { Button("Find inventory") { inventoryFocused = true }.keyboardShortcut("f",modifiers:.command).hidden().accessibilityHidden(true) } }
        .onChange(of:workspace.pendingExport?.id) { _,_ in if let artifact = workspace.pendingExport, !keySheetActive { save(artifact) } }
        .onChange(of:workspace.revision) { _,_ in target = nil; jump += 1; exportMessage = ""; clearExportPresentation() }
        .onChange(of:scenePhase) { _,phase in if phase == .background { concealPresentation() } }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in concealPresentation() }
        .onDisappear { clearExportPresentation() }
        #endif
        .sheet(isPresented:Binding(get:{ keyToExport != nil },set:{ if !$0 { keyToExport = nil } }),onDismiss:{ keySheetActive = false; if let artifact = workspace.pendingExport { save(artifact) } }) { keyExportSheet.onAppear { keySheetActive = true } }
        .confirmationDialog("Export private material unchanged?",isPresented:Binding(get:{ pendingSensitive != nil },set:{ if !$0 { pendingSensitive = nil } }),titleVisibility:.visible) {
            Button("Export original private material",role:.destructive) { if let artifact = pendingSensitive { save(artifact); pendingSensitive = nil } }
        } message: { Text("Envelope conversion does not add encryption. Protect the exported file.") }
    }
    private func concealPresentation() {
        workspace.concealSecrets()
        clearExportPresentation()
    }
    private func clearExportPresentation() {
        exportMessage = ""
        exporting = false; exportingFolder = false; document = .init(Data()); folderDocument = .init(files:[:]); pendingSensitive = nil; keyToExport = nil; confirmPlain = false
        #if os(macOS)
        localSavePanel?.cancel(nil); localSavePanel = nil
        localExportID = UUID(); localExportTask?.cancel(); localExportTask = nil
        #endif
    }
    private var caveat: String {
        switch workspace.tool {
        case .certificate: "Development only · self-signed certificates are not automatically trusted."
        case .csr: "A CSR is a signing request, not an issued or trusted certificate."
        case .chain: workspace.systemTrust ? "System trust on this device · network fetch disabled · fresh revocation not checked." : "Trust limited to provided anchors · revocation not checked (offline)."
        case .matcher: "Match proves key possession, not certificate trust or current validity."
        case .converter: "Exact DER payloads are preserved. Conversion does not decrypt or protect keys."
        case .pfx: "Local container processing · no Keychain import · private exports are encrypted by default."
        default: "Only public metadata is shown; no private parameters or key material in reports."
        }
    }
    private var actions: some View {
        actionLayout {
            Button(action) { workspace.run() }.keyboardShortcut(.return,modifiers:.command).disabled(workspace.busy).accessibilityIdentifier("pki-run")
            if workspace.busy { Button("Cancel") { workspace.cancel() } }
            Button("Clear") { workspace.clear(); editorEpoch += 1; target = nil; keyToExport = nil; document = .init(Data()) }
            Button(workspace.inputCollapsed ? "Edit Input" : "Hide Input") { withAnimation(motion) { workspace.inputCollapsed.toggle() } }
        }.buttonStyle(.bordered).controlSize(accessibleLayout ? .regular : .small)
         .fixedSize(horizontal:false,vertical:true).multilineTextAlignment(.leading)
    }
    @ViewBuilder private var modes: some View {
        actionLayout {
            if workspace.tool == .csr || workspace.tool == .pfx {
                Picker("Mode",selection:$workspace.mode) {
                    Text(workspace.tool == .csr ? "Generate" : "Inspect / Extract").tag(0)
                    Text(workspace.tool == .csr ? "Inspect" : "Create PFX").tag(1)
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Menu("Options",systemImage:"slider.horizontal.3") { Toggle("Word Wrap",isOn:$workspace.wordWrap) }
        }.controlSize(.small)
    }
    @ViewBuilder private var inputPanel: some View {
        if generates { generationForm.securityToolPanel() }
        else {
            VStack(alignment:.leading,spacing:8) {
                inputSettings
                if workspace.tool == .chain {
                    ScrollView { VStack(spacing:12) { source(0,"Leaf certificate",secret:false).frame(height:150); source(2,"Intermediates",secret:false).frame(height:150); source(3,"Trusted anchors",secret:false).frame(height:150).disabled(workspace.systemTrust) } }
                } else if workspace.tool == .matcher || (workspace.tool == .pfx && workspace.mode == 1) {
                    source(0,"Certificate / leaf",secret:false)
                    source(1,"Private key",secret:true)
                    if workspace.tool == .pfx { source(2,"Additional certificates",secret:false) }
                } else { source(0,workspace.tool == .pfx ? "PFX file" : "Input",secret:workspace.tool == .key || workspace.tool == .converter || workspace.tool == .csr) }
            }.securityToolPanel()
        }
    }
    @ViewBuilder private var inputSettings: some View {
        if [.pfx,.key,.matcher].contains(workspace.tool) { SecureField("Input password (if encrypted)",text:$workspace.password).textFieldStyle(.roundedBorder) }
        if workspace.tool == .matcher { Stepper("Certificate in bundle: \(workspace.selectedCertificate+1)",value:$workspace.selectedCertificate,in:0...63).font(.caption) }
        if workspace.tool == .converter {
            Picker("DER type",selection:$workspace.typeHint) { ForEach(["Automatic","CERTIFICATE","CERTIFICATE REQUEST","PUBLIC KEY","RSA PUBLIC KEY","PRIVATE KEY","RSA PRIVATE KEY","EC PRIVATE KEY","ENCRYPTED PRIVATE KEY"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.menu)
        }
        if workspace.tool == .pfx {
            if workspace.mode == 0 {
                Toggle("Allow legacy PFX decryption",isOn:$workspace.legacy)
                Toggle("Inspect contents without a MAC",isOn:$workspace.unverified)
            } else { exportPasswords; TextField("Friendly name",text:$workspace.friendlyName).textFieldStyle(.roundedBorder) }
        }
        if workspace.tool == .chain {
            Picker("Policy",selection:$workspace.policy) { Text("TLS Server").tag(0); Text("TLS Client").tag(1); Text("Basic X.509").tag(2) }.pickerStyle(.menu)
            if workspace.policy == 0 { TextField("Hostname or IP (SAN only)",text:$workspace.hostname).textFieldStyle(.roundedBorder) }
            DatePicker("Verify at",selection:$workspace.verifyDate)
            Toggle("System trust on this device (offline)",isOn:$workspace.systemTrust)
        }
    }
    private func source(_ slot: Int, _ title: String, secret: Bool) -> some View {
        PKISourceEditor(text:Binding(get:{ slot == 0 ? workspace.input : slot == 1 ? workspace.second : slot == 2 ? workspace.extras : workspace.roots },set:{ value in switch slot { case 0: workspace.input = value; case 1: workspace.second = value; case 2: workspace.extras = value; default: workspace.roots = value } }),title:title,file:workspace.fileNames[slot],secret:secret,masked:$workspace.masked,wordWrap:workspace.wordWrap,hidden:workspace.inputCollapsed,target:slot == 0 ? target : nil,jump:jump,reduceMotion:reduceMotion,clearEpoch:editorEpoch,open:{ importSlot = slot; importing = true },edit:{ workspace.editText(slot) },dropped:{ workspace.importFile($0,slot:slot) },workspace:workspace)
    }
    private var generationForm: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Picker("Profile",selection:$workspace.draft.profile) { ForEach(PKIProfile.allCases) { Text($0.title).tag($0) } }
                Toggle("Use an existing private key",isOn:$workspace.draft.useImportedKey)
                if workspace.draft.useImportedKey {
                    PKISourceEditor(text:$workspace.draft.importedKey,title:"Private key PEM",file:nil,secret:true,masked:$workspace.masked,wordWrap:true,hidden:workspace.inputCollapsed,target:nil,jump:0,reduceMotion:reduceMotion,clearEpoch:editorEpoch,open:{ importSlot = 4; importing = true },edit:{},dropped:{ workspace.importFile($0,slot:4) },workspace:workspace).frame(height:150)
                    SecureField("Key password",text:$workspace.draft.keyPassword).textFieldStyle(.roundedBorder)
                } else { Picker("Key algorithm",selection:$workspace.draft.algorithm) { ForEach(PKIAlgorithm.allCases) { Text($0.rawValue).tag($0) } } }
                Text("Subject").font(.headline)
                field("Common name",$workspace.draft.commonName); field("Organization",$workspace.draft.organization); field("Organizational unit",$workspace.draft.unit)
                field("Locality",$workspace.draft.locality); field("State / Province",$workspace.draft.state); field("Country (2 letters)",$workspace.draft.country)
                actionLayout { Text("Subject Alternative Names").font(.headline); Spacer(); Button("Add",systemImage:"plus") { withAnimation(motion) { workspace.draft.sans.append(.init()) } }.disabled(workspace.draft.sans.count >= 128) }
                ForEach($workspace.draft.sans) { $san in
                    actionLayout { Picker("Type",selection:$san.kind) { ForEach(PKISAN.Kind.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(minWidth:85)
                        TextField("Value",text:$san.value).textFieldStyle(.roundedBorder)
                        Button("Remove",systemImage:"minus.circle") { withAnimation(motion) { workspace.draft.sans.removeAll { $0.id == san.id } } }.labelStyle(.iconOnly)
                    }
                }
                if workspace.draft.profile == .root { Stepper("CA path length: \(workspace.draft.pathLength)",value:$workspace.draft.pathLength,in:0...8) }
                if workspace.tool == .certificate { DatePicker("Not before",selection:$workspace.draft.notBefore); DatePicker("Not after",selection:$workspace.draft.notAfter) }
                Text("The key is generated only when you choose \(action). Nothing is installed or trusted automatically.").font(.caption).foregroundStyle(.secondary)
            }.padding(2)
        }
    }
    private func field(_ title: String, _ text: Binding<String>) -> some View { VStack(alignment:.leading,spacing:3) { Text(title).font(.caption).foregroundStyle(.secondary); TextField(title,text:text).textFieldStyle(.roundedBorder).labelsHidden() } }
    private var outputPanel: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Result").font(.headline); Spacer() }
            if let result = workspace.result { resultView(result) }
            else { ContentUnavailableView("Ready for \(action.lowercased())",systemImage:"lock.shield",description:Text("All processing stays on this device.")) }
        }.securityToolPanel()
    }
    @ViewBuilder private func resultView(_ result: PKIWorkspaceResult) -> some View {
        switch result {
        case .generated(let generated):
            ScrollView { VStack(alignment:.leading,spacing:12) {
                objectActions(generated.object)
                if workspace.tool == .certificate { certificateSummary(generated.object.data) }
                else { Text("PKCS#10 request · signature verified").font(.headline) }
                Button("Export Private Key…") { keyToExport = generated.key.handle; plainKey = false }.accessibilityIdentifier("pki-export-private")
                Text(generated.key.report).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                publicText(generated.object.pem)
            }.frame(maxWidth:.infinity,alignment:.leading) }.accessibilityIdentifier("pki-generated-result")
        case .csr(let info):
            ScrollView { VStack(alignment:.leading,spacing:12) { Text(info.signatureValid ? "Signature valid" : "Signature invalid").font(.headline); objectActions(info.object); publicText(info.summary); Text("Original request is available through explicit Copy / Export. Sensitive attribute values are omitted from this summary.").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading) }
        case .objects(let objects): converterResult(objects)
        case .key(let key): ScrollView { VStack(alignment:.leading,spacing:12) { publicText(key.report); Button("Copy Public Key") { SecurityToolClipboard.copy(key.publicPEM) }; Button("Export Public Key") { save(.init(bytes:Data(key.publicPEM.utf8),filename:"public-key.pem")) }; if key.isPrivate { Button("Export Private Key…") { keyToExport = key.handle } } }.frame(maxWidth:.infinity,alignment:.leading) }
        case .match(let match,let key): ScrollView { VStack(alignment:.leading,spacing:12) { Label(match ? "Match · possession verified" : "Different public keys",systemImage:match ? "checkmark.shield" : "xmark.shield").font(.headline); publicText(key.report); Text("Certificate trust and expiry do not affect key matching.").font(.caption) }.frame(maxWidth:.infinity,alignment:.leading) }
        case .chain(let result): ScrollView { VStack(alignment:.leading,spacing:12) { Label(result.valid ? "Validation passed" : "Validation did not pass",systemImage:result.valid ? "checkmark.shield" : "exclamationmark.shield").font(.headline); Button("Copy Report") { SecurityToolClipboard.copy(result.report) }; publicText(result.report) }.frame(maxWidth:.infinity,alignment:.leading) }
        case .pfx(let inventory): pfxResult(inventory)
        case .package(let data): VStack(alignment:.leading,spacing:12) { Label("PFX created and verified",systemImage:"checkmark.shield"); Text("\(data.count) bytes · encrypted keys/certificates · SHA-256 integrity MAC"); Button("Export PFX") { save(.init(bytes:data,filename:"identity.p12",sensitive:true)) }; Spacer() }
        }
    }
    private func publicText(_ text: String) -> some View { Text(text).font(.system(.callout,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
    private func certificateSummary(_ der: Data) -> some View {
        let c = CertificateDER.inspect(der)
        return VStack(alignment:.leading,spacing:6) { Text(CertificateDisplay.safe(c.subject)).font(.headline); Text(c.validity(at:.now)); if let date = c.notAfter { Text("Expires \(CertificateDisplay.date(date))").font(.caption) }; Text("SHA-256: \(c.sha256)").font(.caption).textSelection(.enabled) }
    }
    private func objectActions(_ object: PKIObject) -> some View {
        actionLayout {
            Menu("Export") {
                Button("PEM") { requestSave(object,pem:true) }; Button("DER") { requestSave(object,pem:false) }
            }
            Button("Copy PEM") { SecurityToolClipboard.copy(object.pem) }.disabled(object.sensitive && workspace.masked)
            if let range = object.sourceRange, workspace.files[0] == nil { Button("Show Source") { withAnimation(motion) { workspace.inputCollapsed = false }; target = range; jump += 1 } }
        }.controlSize(.small)
    }
    private func converterResult(_ objects: [PKIObject]) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("\(objects.count) objects").font(.caption); Spacer(); Menu("Export All") {
                Button("Copy PEM bundle") { SecurityToolClipboard.copy(objects.map(\.pem).joined(separator:"\n")) }.disabled(objects.contains(where:\.sensitive) && workspace.masked)
                Button("Separate DER files…") { exportAll(objects,pem:false) }.disabled(objects.contains(where:\.sensitive) && workspace.masked)
                Button("Separate PEM files…") { exportAll(objects,pem:true) }.disabled(objects.contains(where:\.sensitive) && workspace.masked)
            } }
            List(objects) { object in
                VStack(alignment:.leading,spacing:6) {
                    Text("\(object.id+1) · \(object.label)").font(.headline)
                    Text("\(object.data.count) bytes · SHA-256: \(object.fingerprint)").font(.caption).textSelection(.enabled)
                    if object.sensitive { Text("Private material · envelope preserved without adding protection").font(.caption).foregroundStyle(.secondary) }
                    objectActions(object)
                }.padding(.vertical,4)
            }.listStyle(.plain)
        }
    }
    private func pfxResult(_ inventory: PKIPFXInfo) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(inventory.verified ? "Integrity MAC verified" : "Unverified contents · private extraction disabled").font(.callout)
            DisclosureGroup("Protection details") { publicText(inventory.protection).font(.caption) }
            TextField("Search inventory",text:$workspace.search).textFieldStyle(.roundedBorder).focused($inventoryFocused)
            List(inventory.bags.filter { workspace.search.isEmpty || $0.summary.localizedCaseInsensitiveContains(workspace.search) }) { bag in
                VStack(alignment:.leading,spacing:6) {
                    publicText(bag.summary)
                    if let data = bag.certificateDER {
                        certificateSummary(data)
                        HStack {
                            Button("Export certificate") { save(.init(bytes:Data(PEMEnvelopeReader.encode(data,label:"CERTIFICATE").utf8),filename:"certificate-\(bag.id+1).pem")) }
                            Toggle("Include in subset",isOn:Binding(get:{ workspace.includedCerts.contains(bag.certificate) },set:{ if $0 { workspace.includedCerts.insert(bag.certificate) } else { workspace.includedCerts.remove(bag.certificate) } })).font(.caption)
                        }
                    }
                    if let key = bag.publicKey {
                        Text("\(key.algorithm) · \(key.bits) bits · SPKI \(key.fingerprint)").font(.caption).textSelection(.enabled)
                        Text("Matching certificate indexes: " + (bag.matchingCertificates.isEmpty ? "none" : bag.matchingCertificates.map { String($0+1) }.joined(separator:", "))).font(.caption)
                        Button("Export Private Key…") { keyToExport = key.handle }.disabled(!inventory.verified)
                    }
                }.padding(.vertical,6)
            }.listStyle(.plain)
            DisclosureGroup("Create / Repackage",isExpanded:Binding(get:{ packagingExpanded },set:{ value in withAnimation(motion) { packagingExpanded = value } })) {
                VStack(alignment:.leading,spacing:8) {
                    exportPasswords
                    TextField("Friendly name",text:$workspace.friendlyName).textFieldStyle(.roundedBorder)
                    Picker("Identity key",selection:$workspace.selectedPFXKey) { Text("Certificate-only").tag(Int32(-1)); ForEach(inventory.bags.filter { $0.key >= 0 }) { Text("Bag \($0.id+1)").tag($0.key) } }
                    Picker("Leaf",selection:$workspace.selectedPFXLeaf) { Text("None").tag(Int32(-1)); ForEach(inventory.bags.filter { $0.certificate >= 0 }) { Text("Bag \($0.id+1)").tag($0.certificate) } }
                    Text("Subset includes the selected key, leaf and checked certificates only.").font(.caption).foregroundStyle(.secondary)
                    actionLayout { Button("Export Subset") { workspace.repackage(subset:true) }.disabled(!inventory.verified || workspace.busy); Button("Change Container Password") { workspace.repackage(subset:false) }.disabled(!inventory.rewritable || workspace.busy) }
                    if !inventory.rewritable { Text("Whole rewrite is unavailable for this bag/attribute profile. Use an explicit subset.").font(.caption) }
                }.padding(.top,8)
            }
        }
    }
    private var exportPasswords: some View { VStack(spacing:6) { SecureField("New export password",text:$workspace.newPassword); SecureField("Confirm export password",text:$workspace.confirmPassword) }.textFieldStyle(.roundedBorder) }
    private var keyExportSheet: some View {
      ScrollView {
        VStack(alignment:.leading,spacing:16) {
            Text("Export Private Key").font(.title2)
            Text("PKCS#8 · encrypted by default. This file contains sensitive key material.").font(.callout)
            #if os(iOS)
            Text("Files and temporary export copies use system/provider protection. Choose a trusted destination. Unencrypted exports contain the private key.").font(.caption).fixedSize(horizontal:false,vertical:true)
            #endif
            Toggle("Unencrypted export",isOn:$plainKey)
            if !plainKey { exportPasswords }
            if !plainKey && !workspace.confirmPassword.isEmpty && !workspace.exportPasswordsMatch {
                Text("Passwords must match exactly, including Unicode encoding.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Encoding",selection:$pemKey) { Text("PEM").tag(true); Text("DER").tag(false) }.pickerStyle(.segmented)
            actionLayout { Button("Cancel") { keyToExport = nil }; Spacer(); Button("Export…") { if plainKey { confirmPlain = true } else if let key = keyToExport { workspace.privateExport(key:key,unencrypted:false,pem:pemKey); keyToExport = nil } }.disabled(!plainKey && (workspace.newPassword.isEmpty || !workspace.exportPasswordsMatch)).accessibilityIdentifier("pki-export-confirm") }
        }.padding(24)
      }.frame(idealWidth:440,idealHeight:accessibleLayout ? 650 : 420)
        .confirmationDialog("Export an unencrypted private key?",isPresented:$confirmPlain,titleVisibility:.visible) {
            Button("Export unencrypted private key",role:.destructive) { if let key = keyToExport { workspace.privateExport(key:key,unencrypted:true,pem:pemKey); keyToExport = nil } }
        } message: { Text("Anyone with this file can use the private key. Nothing is installed in Keychain.") }

    }
    private func requestSave(_ object: PKIObject, pem: Bool) {
        let artifact = PKIExport(bytes:pem ? Data(object.pem.utf8) : object.data,filename:"object-\(object.id+1).\(pem ? "pem" : "der")",sensitive:object.sensitive)
        if object.sensitive && !object.label.contains("ENCRYPTED") { pendingSensitive = artifact } else { save(artifact) }
    }
    private func save(_ artifact: PKIExport) {
        #if os(macOS)
        saveLocally(filename:artifact.filename,bytes:artifact.bytes)
        #else
        document = .init(artifact.bytes); filename = artifact.filename; exporting = true
        #endif
    }
    private func exportAll(_ objects: [PKIObject], pem: Bool) {
        let files = Dictionary(uniqueKeysWithValues:objects.map { ("object-\($0.id+1).\(pem ? "pem" : "der")",pem ? Data($0.pem.utf8) : $0.data) })
        #if os(macOS)
        saveLocally(filename:"converted-objects",bytes:Data(),files:files)
        #else
        folderDocument = .init(files:files); exportingFolder = true
        #endif
    }
    #if os(macOS)
    private func saveLocally(filename: String, bytes: Data, files: [String:Data]? = nil) {
        guard localSavePanel == nil, localExportTask == nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename; panel.canCreateDirectories = true
        panel.message = files == nil ? "Local export removes inherited access permissions. For provider-managed locations, protection depends on the provider." : "Choose a new folder name. Existing folders are preserved."
        localSavePanel = panel
        // Keep payloads in view-owned state, not in a completion closure retained by AppKit.
        document = .init(bytes); folderDocument = .init(files:files ?? [:])
        let directoryExport = files != nil
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard localSavePanel === panel else { return }
            defer { localSavePanel = nil; document = .init(Data()); folderDocument = .init(files:[:]); workspace.pendingExport = nil }
            guard response == .OK else { exportMessage = (response == .cancel ? PKIExportOutcome.cancelled : .failed).message; return }
            guard let url = panel.url else { exportMessage = PKIExportOutcome.failed.message; return }
            let payload = document.bytes, entries = directoryExport ? folderDocument.files : nil, request = UUID()
            localExportID = request; exportMessage = "Saving…"
            let worker = Task.detached(priority:.userInitiated) { () -> PKIExportOutcome in
                do { try PKISecureLocalExport.coordinatedWrite(payload,files:entries,to:url); return .success }
                catch { return PKIExportOutcome(.failure(error)) }
            }
            localExportTask = Task { @MainActor in
                let outcome = await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
                guard localExportID == request else { return }
                localExportTask = nil; exportMessage = outcome.message
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:completion) }
        else { panel.begin(completionHandler:completion) }
    }
    #endif
}

struct PKISourceEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Binding var text: String
    let title: String, file: String?, secret: Bool
    @Binding var masked: Bool
    let wordWrap: Bool, hidden: Bool, target: NSRange?, jump: Int, reduceMotion: Bool, clearEpoch: Int
    let open: () -> Void, edit: () -> Void
    var dropped: ((URL) -> Void)? = nil
    var workspace: PKIWorkspace? = nil
    @State private var commands = JSONEditorCommands()
    @State private var concealActionID = UUID()
    private var sourceActionsLayout: AnyLayout { dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout()) }
    private var concealed: Bool { hidden || (secret && masked) || file != nil }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            sourceActionsLayout { Text(title).font(.headline); Spacer(); Button("Open",systemImage:"folder",action:open).labelStyle(.iconOnly); Button("Paste") { if let value = SecurityToolClipboard.paste() { edit(); if concealed { text = value } else { commands.replace?(.init(location:0,length:text.utf16.count),value) } } }; if secret { Button(masked ? "Reveal" : "Hide") { commands.resignFocus?(); masked.toggle() } } }.controlSize(.small)
            ZStack {
                JSONTextEditor(text:$text,jumpTarget:target,jumpRequest:jump,animateJumps:!reduceMotion,highlightJumps:true,focusOnJump:false,commands:commands,options:.init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:wordWrap),presentationHidden:concealed,usesPrivacyContainer:secret,privateUndo:true,placeholder:"Paste PEM or open a local file",contentName:title,showsLineNumbers:false)
                    .opacity(concealed ? 0 : 1).allowsHitTesting(!concealed).accessibilityHidden(concealed)
                if let file { VStack { Label(file,systemImage:"doc"); Text("Binary snapshot loaded in memory").font(.caption); Button("Use Text Input",action:edit) } }
                else if secret && masked { Label("Sensitive content hidden",systemImage:"eye.slash").font(.callout).foregroundStyle(.secondary).allowsHitTesting(false) }
            }.frame(minHeight:50)
        }.onDrop(of:[UTType.fileURL.identifier],isTargeted:nil) { providers in
            guard let dropped, let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { value,_ in
                let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation:$0,relativeTo:nil) }
                if let url { Task { @MainActor in dropped(url) } }
            }; return true
        }.onChange(of:hidden) { _,value in if value { commands.resignFocus?() } }
        .onAppear {
            if secret {
                let editorCommands = commands
                workspace?.setConcealAction(id:concealActionID) { editorCommands.resignFocus?() }
            }
        }
        .onDisappear { workspace?.removeConcealAction(id:concealActionID) }
        .onChange(of:clearEpoch) { _,_ in commands.purgeUndo?(); commands.cancelNavigation?() }
    }
}
struct PKIDirectoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    let files: [String:Data]
    init(files:[String:Data]) { self.files = files }
    init(configuration:ReadConfiguration) throws { files = [:] }
    func makeFileWrapper() -> FileWrapper {
        let folder = FileWrapper(directoryWithFileWrappers:files.mapValues { PKIExportDocument($0).makeFileWrapper() })
        var attributes = folder.fileAttributes
        attributes[FileAttributeKey.posixPermissions.rawValue] = 0o700
        folder.fileAttributes = attributes
        return folder
    }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { makeFileWrapper() }
}

struct PKIExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data,.plainText] }
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    init(configuration:ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func makeFileWrapper() -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents:bytes)
        // Keep NSFileType and other required Foundation attributes when restricting permissions.
        var attributes = wrapper.fileAttributes
        attributes[FileAttributeKey.posixPermissions.rawValue] = 0o600
        #if os(iOS)
        attributes[FileAttributeKey.protectionKey.rawValue] = FileProtectionType.complete.rawValue
        #endif
        wrapper.fileAttributes = attributes
        return wrapper
    }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { makeFileWrapper() }
}
