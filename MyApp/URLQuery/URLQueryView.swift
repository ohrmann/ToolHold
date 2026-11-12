import SwiftUI

struct URLQueryView: View {
    @Bindable var workspace: URLQueryWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var commands = JSONEditorCommands()
    @State private var jumpTarget: NSRange?
    @State private var jumpRequest = 0
    @State private var jumpTask: Task<Void,Never>?
    @State private var details = false
    @State private var componentsOpen = false
    @State private var outputOpen = false
    @State private var revealUserinfo = false
    @State private var copied = false
    @State private var dragStart: Double?
    @State private var pending: Pending?
    @State private var profileChoice: URLQueryProfile?
    @State private var resetConfirmation = false
    private enum Pending { case select(Int), build, add }
    private var reduced: Bool { reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var motion: Animation? { reduced ? nil : .easeInOut(duration:0.2) }
    private var primary: URLQueryIssue? { workspace.issues.first { $0.severity == .error } ?? workspace.issues.first }
    private var options: JSONEditorOptions {
        .init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:workspace.preferences.wordWrap)
    }
    private var title: String {
        if workspace.busy { return "Processing" }
        if workspace.wasCancelled { return "Cancelled" }
        if !workspace.buildIssues.isEmpty { return "Unable to build result" }
        switch workspace.result?.status {
        case .parsed: return "\(workspace.snapshot?.components.kind ?? "Reference") · \(workspace.rows.count) " + (workspace.rows.count == 1 ? "parameter" : "parameters") + (workspace.dirty ? " · Edited" : "")
        case .invalidSyntax: return "Invalid reference"
        case .resourceLimit: return "Processing limit reached"
        case .processingFailure: return "Processing failed"
        case .cancelled: return "Cancelled"
        default: return workspace.input.isEmpty ? "Ready" : "Not parsed"
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850
            VStack(alignment:.leading,spacing:8) {
                toolbar
                status
                URLQueryPanelLayout(horizontal:wide,fraction:workspace.fraction,progress:workspace.inputCollapsed ? 1 : 0) {
                    inputPanel.opacity(workspace.inputCollapsed ? 0 : 1).allowsHitTesting(!workspace.inputCollapsed).accessibilityHidden(workspace.inputCollapsed)
                    divider(wide,geometry.size)
                    inspector
                }
            }.padding()
                .animation(motion,value:workspace.inputCollapsed)
                .animation(motion,value:details)
                .animation(motion,value:primary?.code)
                .animation(motion,value:componentsOpen)
                .animation(motion,value:outputOpen)
        }
        .navigationTitle("URL Parser & Query Editor")
        .onChange(of:workspace.sourceRevision) { _,_ in cancelJump(); details = false; revealUserinfo = false; copied = false; pending = nil; profileChoice = nil; resetConfirmation = false }
        .onChange(of:workspace.publicationID) { _,_ in copied = false; if workspace.artifact != nil { withAnimation(motion) { outputOpen = true } } }
        .onChange(of:workspace.outputForm) { _,_ in copied = false }
        .onDisappear { cancelJump() }
        .confirmationDialog("Unsaved parameter changes",isPresented:Binding(get:{pending != nil},set:{if !$0 { pending = nil }}),titleVisibility:.visible) {
            Button("Apply Changes") { let action = pending; if workspace.applyEdit() { execute(action) }; pending = nil }
            Button("Discard Changes",role:.destructive) { let action = pending; workspace.cancelEdit(); execute(action); pending = nil }
            Button("Cancel",role:.cancel) { pending = nil }
        } message: { Text("Apply or discard the parameter edit before continuing.") }
        .alert("Change query profile?",isPresented:Binding(get:{profileChoice != nil},set:{if !$0 { profileChoice = nil }})) {
            Button("Discard Query Edits",role:.destructive) { if let value = profileChoice { cancelJump(); workspace.changeProfile(value,discard:true) }; profileChoice = nil }
            Button("Cancel",role:.cancel) { profileChoice = nil }
        } message: { Text("The meaning of '+' will change. Source text is preserved; query edits will be discarded.") }
        .alert("Reset query edits?",isPresented:$resetConfirmation) {
            Button("Reset",role:.destructive) { workspace.reset() }
            Button("Cancel",role:.cancel) {}
        } message: { Text("Return to the parsed query and clear query Undo history. Input stays unchanged.") }
    }
    private var toolbar: some View {
        ViewThatFits(in:.horizontal) {
            HStack { actions; Spacer(minLength:4); choices }
            VStack(alignment:.leading,spacing:6) { actions; choices }
        }
    }
    private var actions: some View {
        HStack(spacing:8) {
            Button("Parse") { cancelJump(); workspace.parse() }.keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("url-query-parse")
            Button("Build URL") { perform(.build) }.disabled(workspace.snapshot == nil || workspace.busy).accessibilityIdentifier("url-query-build")
            Button(workspace.inputCollapsed ? "Edit Input" : "Hide Input",systemImage:workspace.inputCollapsed ? "pencil" : "sidebar.left") {
                if !workspace.inputCollapsed { commands.resignFocus?() }
                withAnimation(motion) { workspace.inputCollapsed.toggle() }
            }.labelStyle(.titleOnly).accessibilityIdentifier("url-query-collapse-input")
        }.controlSize(.small)
    }
    private var choices: some View {
        HStack(spacing:6) {
            Picker("Query",selection:Binding(get:{workspace.preferences.profile},set:{ value in
                if workspace.dirty || workspace.hasPendingEdit { profileChoice = value }
                else { cancelJump(); workspace.changeProfile(value) }
            })) { ForEach(URLQueryProfile.allCases,id:\.self) { Text($0.title).tag($0) } }
                .pickerStyle(.menu).fixedSize().disabled(workspace.busy).accessibilityIdentifier("url-query-profile")
            Menu {
                Toggle("Parse automatically on paste",isOn:Binding(get:{workspace.preferences.parseOnPaste},set:workspace.setParseOnPaste))
                Toggle("Word Wrap",isOn:Binding(get:{workspace.preferences.wordWrap},set:workspace.setWordWrap))
            } label: { Image(systemName:"slider.horizontal.3") }.accessibilityLabel("Editor Options")
        }
    }
    private var status: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack {
                Label(title,systemImage:primary == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium)).lineLimit(2).accessibilityIdentifier("url-query-status")
                    .foregroundStyle(primary?.severity == .error ? Color.red : Color.secondary)
                Spacer(minLength:0)
                HStack { ZStack { if workspace.busy { ProgressView().controlSize(.mini) } }.frame(width:14,height:14)
                    Button("Cancel") { cancelJump(); workspace.cancel() }.controlSize(.small)
                }.opacity(workspace.busy ? 1 : 0).disabled(!workspace.busy).accessibilityHidden(!workspace.busy)
            }.frame(minHeight:28)
            if let issue = primary {
                Text(issue.message).font(.caption).lineLimit(3).textSelection(.enabled).accessibilityIdentifier("url-query-message")
                HStack {
                    if let range = issue.range {
                        let position = URLQueryPresentation.coordinates(workspace.input,offset:range.location)
                        Text("Line \(position.0), column \(position.1) · UTF-16\(issue.region ? " · region" : "")").font(.caption).foregroundStyle(.secondary)
                        Button("Show Input") { show(range) }.accessibilityIdentifier("url-query-show-input")
                    }
                    Button(details ? "Hide details" : "Details") { details.toggle() }
                }.controlSize(.small)
                if details {
                    ScrollView {
                        VStack(alignment:.leading,spacing:4) {
                            if let range = issue.range { Text(URLQueryPresentation.context(workspace.input,range:range)).font(.system(.caption,design:.monospaced)) }
                            ForEach(Array(workspace.issues.enumerated()),id:\.offset) { _,note in Text(note.message).font(.caption) }
                        }.frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                    }.frame(height:72)
                }
            }
        }
    }
    private var inputPanel: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text("Input").font(.headline); Spacer()
                Button("Clear",systemImage:"xmark.circle") { cancelJump(); commands.clear?(); workspace.clear() }
                    .disabled(workspace.input.isEmpty).accessibilityIdentifier("url-query-clear")
            }.frame(height:28)
            JSONTextEditor(text:$workspace.input,diagnostic:URLQueryEditorDiagnosticAdapter.make(primary,source:workspace.input),
                jumpTarget:jumpTarget,jumpRequest:jumpRequest,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,
                onPaste:{ workspace.didPaste() },commands:commands,options:options,
                placeholder:"Paste a URL or relative reference. Processing stays on this device.",contentName:"URL")
                .accessibilityIdentifier("url-query-input").clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(.secondary.opacity(0.25)))
            Text("Changing Input discards the parsed query and its edits.").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.clipped()
    }
    private var inspector: some View {
        VStack(alignment:.leading,spacing:6) {
            DisclosureGroup("Components",isExpanded:$componentsOpen) { components }
                .disabled(workspace.snapshot == nil)
            HStack(spacing:6) {
                Text("Query").font(.headline); Spacer(minLength:0)
                Button("Add",systemImage:"plus") { perform(.add) }.disabled(workspace.snapshot == nil || workspace.busy).accessibilityIdentifier("url-query-add")
                Menu {
                    Button("Undo Query Change") { workspace.undo() }.disabled(!workspace.canUndo)
                    Button("Redo Query Change") { workspace.redo() }.disabled(!workspace.canRedo)
                    Button("Reset Query Edits",role:.destructive) { resetConfirmation = true }.disabled(!workspace.dirty)
                    Toggle("Include '?'",isOn:Binding(get:{workspace.draft?.queryPresent ?? false},set:workspace.setQueryPresent))
                        .disabled(!workspace.rows.isEmpty || workspace.editingID != nil)
                } label: { Image(systemName:"ellipsis.circle") }.accessibilityLabel("Query Actions")
                    .disabled(workspace.snapshot == nil || workspace.busy).accessibilityIdentifier("url-query-actions")
            }.controlSize(.small)
            ZStack {
                URLQueryList(rows:workspace.rows,revision:workspace.draftRevision,baseRevision:workspace.listBaseRevision,change:workspace.listChange,reduceMotion:reduced,selection:workspace.selectedID,
                    enabled:!workspace.busy && workspace.editingID == nil,select:{perform(.select($0))},move:{id,index in withAnimation(motion) { workspace.move(id,to:index) } })
                    .clipShape(RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(.secondary.opacity(0.2)))
                if workspace.rows.isEmpty {
                    Text(workspace.snapshot == nil ? "Parse a reference to inspect its query." : workspace.draft?.queryPresent == true ? "Empty query · '?' is present" : "No query · add a parameter to begin")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding().allowsHitTesting(false)
                }
            }.frame(minHeight:65,maxHeight:.infinity)
            if workspace.editingID != nil { rowEditor }
            else if let row = workspace.selectedRow { selectedActions(row) }
            outputPanel
        }.clipped()
    }
    private var components: some View {
        ScrollView {
            if let snapshot = workspace.snapshot {
                let c = snapshot.components
                VStack(alignment:.leading,spacing:4) {
                    component("Scheme",snapshot.slice(c.scheme)); component("Authority",c.userinfo == nil || revealUserinfo ? snapshot.slice(c.authority) : "Hidden · contains userinfo")
                    if c.userinfo != nil {
                        HStack { Text("Userinfo: " + (revealUserinfo ? URLQueryPresentation.safe(snapshot.slice(c.userinfo) ?? "") : "Hidden")); Button(revealUserinfo ? "Hide" : "Reveal") { revealUserinfo.toggle() } }
                    }
                    component("Source host",snapshot.slice(c.host)); component("ASCII host",c.asciiHost); component("Unicode host · system display",c.unicodeHost)
                    component("Port",snapshot.slice(c.port)); component("Path",snapshot.slice(c.path)); component("Query",snapshot.slice(c.query)); component("Fragment",snapshot.slice(c.fragment))
                }.font(.caption).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(height:130)
    }
    private func component(_ name: String, _ value: String?) -> some View {
        Text(name + ": " + (value.map { $0.isEmpty ? "(empty)" : URLQueryPresentation.safe($0,limit:180) } ?? "(absent)"))
    }
    private var rowEditor: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text("Edit parameter").font(.subheadline.weight(.medium)); Spacer()
                Button("Cancel") { workspace.cancelEdit() }.accessibilityIdentifier("url-query-edit-cancel")
                Button("Apply") { workspace.applyEdit() }.accessibilityIdentifier("url-query-edit-apply")
            }.controlSize(.small)
            if workspace.editingRow?.rawOnlyName == true && !workspace.replaceName {
                Button("Raw name bytes · Replace as text") { workspace.replaceName = true }.font(.caption)
            } else {
                TextField("Name",text:$workspace.editName).textFieldStyle(.roundedBorder).accessibilityIdentifier("url-query-edit-name")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            Toggle("Has value (=)",isOn:$workspace.editHasValue).font(.caption).accessibilityIdentifier("url-query-has-value")
            if workspace.editingRow?.rawOnlyValue == true && !workspace.replaceValue {
                Button("Raw value bytes · Replace as text") { workspace.replaceValue = true }.font(.caption)
            }
            TextEditor(text:$workspace.editValue).font(.system(.caption,design:.monospaced)).autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .frame(height:65).disabled(!workspace.editHasValue || (workspace.editingRow?.rawOnlyValue == true && !workspace.replaceValue))
                .accessibilityLabel("Parameter value").accessibilityIdentifier("url-query-edit-value")
                .overlay(RoundedRectangle(cornerRadius:4).stroke(.secondary.opacity(0.2)))
            if let message = workspace.editIssue { Text(message).font(.caption).foregroundStyle(.red) }
        }.padding(6).background(.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:6))
    }
    private func selectedActions(_ row: URLQueryRow) -> some View {
        HStack(spacing:8) {
            Button("Edit") { workspace.beginEdit(row.id) }.accessibilityIdentifier("url-query-edit")
            if let range = row.sourceRange { Button("Original parameter") { show(range) }.accessibilityIdentifier("url-query-original") }
            Spacer(minLength:0)
            Menu {
                Button("Move Up") { move(row.id,by:-1) }
                Button("Move Down") { move(row.id,by:1) }
                Button("Delete Parameter",role:.destructive) { withAnimation(motion) { workspace.remove(row.id) } }
            } label: { Label("Actions",systemImage:"ellipsis.circle") }.accessibilityIdentifier("url-query-row-actions")
        }.font(.caption).controlSize(.small).disabled(workspace.busy)
    }
    private var outputPanel: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Button { outputOpen.toggle() } label: { Label("Output",systemImage:outputOpen ? "chevron.down" : "chevron.right") }.buttonStyle(.plain).font(.headline)
                Spacer(minLength:0)
                Picker("Output form",selection:$workspace.outputForm) { ForEach(URLQueryOutputForm.allCases,id:\.self) { Text($0.title).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).fixedSize().accessibilityIdentifier("url-query-output-form")
                Button(copied ? "Copied" : "Copy") { copy() }.disabled(!workspace.canCopy).accessibilityIdentifier("url-query-copy")
            }.controlSize(.small)
            if workspace.outputForm == .ascii, let issue = workspace.artifact?.asciiIssue { Text(issue.message).font(.caption).foregroundStyle(.orange) }
            if workspace.snapshot?.components.userinfo != nil { Text("Copy includes userinfo from the URL.").font(.caption2).foregroundStyle(.secondary) }
            JSONTextEditor(text:.constant(workspace.output ?? ""),editable:false,options:options,
                placeholder:workspace.output == "" ? "Empty reference · 0 characters" : workspace.artifact != nil && workspace.outputForm == .ascii ? "ASCII form unavailable; see the processing status." : "Build URL to see the result.",contentName:workspace.outputForm == .ascii ? "ASCII URI" : "URL")
                .accessibilityIdentifier("url-query-output")
                .frame(height:outputOpen ? 100 : 0).clipped().opacity(outputOpen ? 1 : 0)
                .allowsHitTesting(outputOpen).accessibilityHidden(!outputOpen)
        }
    }
    private func divider(_ wide: Bool, _ size: CGSize) -> some View {
        RoundedRectangle(cornerRadius:2).fill(.secondary.opacity(0.3))
            .frame(width:wide ? 4 : 32,height:wide ? 32 : 4).frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                guard !workspace.inputCollapsed else { return }
                if dragStart == nil { dragStart = workspace.fraction }
                workspace.fraction = min(0.7,max(0.25,(dragStart ?? 0.4)+(wide ? value.translation.width : value.translation.height)/max(1,(wide ? size.width : size.height)-12)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Panel proportions").accessibilityAdjustableAction { direction in
                workspace.fraction = min(0.7,max(0.25,workspace.fraction+(direction == .increment ? 0.05 : -0.05)))
            }
    }
    private func perform(_ action: Pending) {
        if workspace.hasPendingEdit { pending = action } else { workspace.cancelEdit(); execute(action) }
    }
    private func execute(_ action: Pending?) {
        guard let action else { return }
        switch action { case .select(let id): workspace.selectedID = id
        case .build: cancelJump(); workspace.build()
        case .add: workspace.add() }
    }
    private func move(_ id: Int, by delta: Int) { if let index = workspace.rows.firstIndex(where:{$0.id == id}) { withAnimation(motion) { workspace.move(id,to:index+delta) } } }
    private func cancelJump() { jumpTask?.cancel(); jumpTask = nil; commands.cancelNavigation?(); jumpTarget = nil; jumpRequest += 1 }
    private func show(_ range: NSRange) {
        cancelJump()
        let collapsed = workspace.inputCollapsed, revision = workspace.sourceRevision
        if collapsed { withAnimation(motion) { workspace.inputCollapsed = false } }
        jumpTask = Task { @MainActor in
            if collapsed && !reduced { try? await Task.sleep(for:.milliseconds(220)) }
            guard !Task.isCancelled, workspace.sourceRevision == revision else { return }
            jumpTarget = range; jumpRequest += 1
        }
    }
    private func copy() {
        guard workspace.canCopy, let text = workspace.output else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
        #else
        UIPasteboard.general.string = text
        #endif
        copied = true
    }
}
