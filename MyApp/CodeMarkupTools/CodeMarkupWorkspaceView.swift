import SwiftUI
import UniformTypeIdentifiers

struct CodeMarkupWorkspaceView: View {
    @Bindable var workspace: MarkupWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.colorScheme) private var scheme
    @State private var jsonPreferences = JSONPreferencesRepository().load()
    @State private var commands=JSONEditorCommands()
    @State private var fraction=0.44
    @State private var showHTML=false
    @State private var importing=false
    @State private var exporting=false
    @State private var imageImporter=false
    @State private var imageReference=""
    @State private var imagesPanel=false
    @State private var viewportPopover=false
    @State private var customViewport=390
    @State private var file=TextExportDocument("")
    @State private var fileIssue:String?
    @State private var previewFailure:String?
    @State private var previewRetry=UUID()
    private var animation:Animation? {reduced ? nil : .easeInOut(duration:0.2)}
    var body: some View {
        VStack(spacing:8) {
            toolbar
            GeometryReader { g in
                let wide=g.size.width>=760
                TextToolPanelLayout(wide:wide,fraction:fraction,collapse:workspace.collapsed ? 1 : 0) {
                    inputPanel.opacity(workspace.collapsed ? 0 : 1).allowsHitTesting(!workspace.collapsed).accessibilityHidden(workspace.collapsed)
                    TextToolDivider(wide:wide,length:wide ? g.size.width : g.size.height,fraction:$fraction)
                    outputPanel
                }.animation(animation,value:workspace.collapsed)
            }
            diagnostics
        }.padding(12)
        .onAppear {jsonPreferences = JSONPreferencesRepository().load();workspace.inputIsComposing={commands.hasMarkedText?() ?? false};workspace.appeared()}
        .onChange(of:jsonPreferences) { _, value in JSONPreferencesRepository().save(value) }.onDisappear {workspace.disappeared();workspace.inputIsComposing=nil}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.data]) { result in
            guard case .success(let url)=result else{return}
            open(url)
        }
        .fileExporter(isPresented:$exporting,document:file,contentType:.data,defaultFilename:"result."+workspace.tool.fileExtension) { result in
            if case .failure = result {fileIssue="Export could not complete."}
        }
        .fileImporter(isPresented:$imageImporter,allowedContentTypes:[.png,.jpeg,.gif,.webP]) { result in
            guard case .success(let url)=result else{return}
            let reference=imageReference, revision=workspace.revision
            Task {
                do {
                    let image=try await Task.detached { () throws -> MarkupImage in
                        let accessed=url.startAccessingSecurityScopedResource();defer{if accessed{url.stopAccessingSecurityScopedResource()}}
                        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                        return try MarkupImage.decode(try handle.read(upToCount:5*1024*1024+1) ?? Data())
                    }.value
                    guard workspace.revision == revision else {fileIssue="Input changed while importing the image.";return}
                    if !workspace.mapImage(reference:reference,image:image){fileIssue="Preview image budget reached."}
                }catch{fileIssue="Use a PNG, JPEG, WebP or GIF up to 5 MiB and 8 megapixels."}
            }
        }
    }
    private var toolbar: some View {
        ViewThatFits(in:.horizontal) {
            HStack {actions;Spacer(minLength:8);settings}
            VStack(alignment:.leading,spacing:8){HStack{actions;Spacer()};HStack{settings;Spacer()}}
        }.buttonStyle(.bordered)
    }
    private var actions: some View {
        HStack(spacing:8){
            Button(workspace.tool.primary){workspace.run()}.keyboardShortcut(.return,modifiers:.command).disabled(workspace.input.isEmpty)
            if workspace.tool.canMinify {Button("Minify"){workspace.run("minify")}.disabled(workspace.input.isEmpty)}
            if workspace.tool.canValidate {Button("Validate"){workspace.run("validate")}.disabled(workspace.input.isEmpty)}
            if workspace.busy {Button("Cancel"){workspace.cancel()}}
            if workspace.tool.isPreview {
                Button(workspace.collapsed ? "Edit Input" : "Hide Input",systemImage:workspace.collapsed ? "sidebar.left" : "sidebar.leading") {
                    commands.resignFocus?();withAnimation(animation){workspace.collapsed.toggle()}
                }
            }
        }.fixedSize(horizontal:true,vertical:false)
    }
    private var settings: some View {
        HStack(spacing:8){
            if workspace.tool == .sql {
                Menu {
                    Picker("SQL dialect",selection:$workspace.options.dialect) {
                        ForEach(MarkupOptions.dialects,id:\.self) { Text(MarkupOptions.dialectName($0)).tag($0) }
                    }
                } label: {
                    Text("Dialect: \(MarkupOptions.dialectName(workspace.options.dialect))").lineLimit(1)
                }
                .help("Choose your database's SQL dialect. Formatting does not validate the query against a database.")
                .accessibilityLabel("SQL dialect")
                .accessibilityValue(MarkupOptions.dialectName(workspace.options.dialect))
            }
            if workspace.tool.isPreview {
                Menu(workspace.options.viewport == 0 ? "Viewport: Fit" : "Viewport: \(workspace.options.viewport) px") {
                    Button("Fit"){workspace.options.viewport=0};Button("Mobile · 390"){workspace.options.viewport=390};Button("Desktop · 1024"){workspace.options.viewport=1024}
                    Button("Custom…"){customViewport=max(280,workspace.options.viewport);viewportPopover=true}
                }.popover(isPresented:$viewportPopover) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Preview width").font(.headline)
                        TextField("Pixels",value:$customViewport,format:.number).textFieldStyle(.roundedBorder)
                        Text("280–1920 px").font(.caption).foregroundStyle(.secondary)
                        Button("Apply"){workspace.options.viewport=min(1920,max(280,customViewport));viewportPopover=false}
                    }.padding().frame(width:220)
                }
            }
            Menu("Options",systemImage:"slider.horizontal.3") {
                if workspace.tool == .mjml {Button("Insert MJML Example"){commands.replace?(.init(location:0,length:workspace.input.utf16.count),"<mjml>\n  <mj-body>\n    <mj-section>\n      <mj-column>\n        <mj-text>Hello from ToolHold</mj-text>\n      </mj-column>\n    </mj-section>\n  </mj-body>\n</mjml>")}.disabled(!workspace.input.isEmpty)}
                Toggle("Word Wrap",isOn:$workspace.options.wrap)
                if workspace.tool.isPreview {Toggle("Live Preview",isOn:$workspace.options.live)}
                else {Picker("Indentation",selection:$workspace.options.indent){Text("2 spaces").tag(2);Text("4 spaces").tag(4)}}
                if workspace.tool == .sql {
                    Picker("Keyword case",selection:$workspace.options.keywordCase){Text("Preserve").tag("preserve");Text("UPPERCASE").tag("upper");Text("lowercase").tag("lower")}
                }
                if workspace.tool == .javascript {Toggle("ES Module (off: Script)",isOn:$workspace.options.module)}
                if workspace.tool == .xml {Toggle("Preserve Text Nodes",isOn:$workspace.options.preserveXMLText)}
                if workspace.tool == .html || workspace.tool == .preview {
                    Toggle("Complete HTML document",isOn:$workspace.options.document)
                    Picker("Fragment context",selection:$workspace.options.fragmentContext){ForEach(["body","table","tbody","tr","select"],id:\.self){Text($0).tag($0)}}
                    if workspace.tool == .html {Toggle("Reindent layout whitespace",isOn:$workspace.options.relaxedHTML)}
                }
                if workspace.tool == .markdown {Toggle("GitHub Flavored Markdown",isOn:$workspace.options.gfm)}
                if workspace.tool.canValidate {Toggle("Validate automatically on paste",isOn:$jsonPreferences.validateOnPaste)}
            }.fixedSize()
        }
    }
    private var inputPanel: some View {
        VStack(alignment:.leading,spacing:6){
            HStack {Text("Input").font(.headline);Spacer();Button("Open",systemImage:"folder"){importing=true};Button("Clear",systemImage:"xmark.circle"){commands.clear?()}.disabled(workspace.input.isEmpty)}.buttonStyle(.borderless)
            JSONTextEditor(text:$workspace.input,diagnostic:editorDiagnostic,jumpTarget:workspace.jumpTarget,jumpRequest:workspace.jump,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,onPaste:{workspace.pasted(automatic:jsonPreferences.validateOnPaste)},commands:commands,options:editorOptions,placeholder:"Enter or paste \(workspace.tool.rawValue == "preview" ? "HTML" : workspace.tool.rawValue.uppercased())",contentName:"Input")
                .clipShape(RoundedRectangle(cornerRadius:6))
                .dropDestination(for:URL.self){urls,_ in guard urls.count==1,let url=urls.first,url.isFileURL else{return false};open(url);return true}
        }.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
    }
    private var outputPanel: some View {
        VStack(alignment:.leading,spacing:6){
            HStack {
                if workspace.tool.isPreview {
                    Picker("Representation",selection:$showHTML){Text("Preview").tag(false);Text(workspace.tool == .preview ? "Source" : "HTML").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(maxWidth:200)
                }else{Text("Output").font(.headline)}
                Spacer(minLength:4)
                Menu("Copy / Export") {
                    Button(workspace.tool == .preview ? "Copy Source" : workspace.tool == .markdown ? "Copy Safe HTML" : workspace.tool == .mjml ? "Copy HTML" : "Copy Output"){TextClipboard.copy(workspace.exportText)}
                    Button("Export \(workspace.tool == .preview ? "Source" : workspace.tool.isPreview ? "HTML" : "Output")…"){file=TextExportDocument(workspace.exportText);exporting=true}
                }.disabled(!workspace.canCopy)
            }
            ZStack {
                JSONTextEditor(text:.constant(workspace.output),editable:false,options:outputOptions,placeholder:"Result appears here",contentName:"Output")
                    .opacity(workspace.tool.isPreview && !showHTML ? 0 : 1).allowsHitTesting(!workspace.tool.isPreview || showHTML).accessibilityHidden(workspace.tool.isPreview && !showHTML)
                if workspace.tool.isPreview {
                    preview.opacity(showHTML ? 0 : 1).allowsHitTesting(!showHTML && workspace.result?.succeeded == true).accessibilityHidden(showHTML)
                }
            }.clipShape(RoundedRectangle(cornerRadius:6))
            if workspace.tool.isPreview {
                VStack(alignment:.leading,spacing:5) {
                    Text(workspace.allowsExternalResources ? "External HTTPS resources allowed · scripts blocked" : "Scripts and external resources blocked").font(.caption).foregroundStyle(.secondary)
                    ViewThatFits(in:.horizontal) {
                        HStack {externalResourceButton;Spacer(minLength:4);localImagesButton}
                        VStack(alignment:.leading,spacing:5) {externalResourceButton;localImagesButton}
                    }
                }
                if imagesPanel {imageControls.transition(.opacity.combined(with:.move(edge:.bottom)))}
            }
        }.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10)).animation(animation,value:imagesPanel)
    }
    private var externalResourceButton: some View {
        Button(workspace.allowsExternalResources ? "Block external resources" : "Load external resources",systemImage:workspace.allowsExternalResources ? "network.slash" : "network") {
            workspace.setExternalResourcesAllowed(!workspace.allowsExternalResources)
        }
        .buttonStyle(.borderless)
        .disabled(workspace.input.isEmpty || (workspace.busy && !workspace.allowsExternalResources))
        .help("Load HTTPS images, stylesheets and fonts from this document. This contacts external servers. Permission resets when Input changes; scripts remain blocked.")
    }
    private var localImagesButton: some View {
        Button("Preview Images…"){withAnimation(animation){imagesPanel.toggle()}}.buttonStyle(.borderless)
    }
    @ViewBuilder private var preview: some View {
        if let snapshot=workspace.snapshot {
            let external=workspace.allowsExternalResources && snapshot.allowsExternalResources
            GeometryReader { g in
                ScrollView(.horizontal){
                    MarkupPreviewView(snapshot:snapshot,dark:scheme == .dark,markdown:workspace.tool == .markdown,allowsExternalResources:external,failure:$previewFailure)
                        // Revoke in-flight resource loads and the nonpersistent cookie store immediately.
                        // Normal edits/theme/viewport updates keep the existing offline renderer identity.
                        .id("\(external)-\(previewRetry)")
                        .frame(width:workspace.options.viewport==0 ? max(1,g.size.width) : CGFloat(workspace.options.viewport),height:max(1,g.size.height))
                }
            }.overlay(alignment:.topLeading){if workspace.result == nil {Text("Updating — previous preview").font(.caption).padding(6).background(.regularMaterial)}}
        }else{
            ContentUnavailableView("Preview",systemImage:"doc.richtext",description:Text(workspace.input.isEmpty ? "Enter a document to preview it locally." : workspace.busy ? "Preparing local preview…" : "Render the input to see its static layout."))
        }
    }
    private var imageControls: some View {
        VStack(alignment:.leading,spacing:5){
            TextField("Exact image URL or relative name in source",text:$imageReference).textFieldStyle(.roundedBorder)
            HStack{Button("Choose Image…"){imageImporter=true}.disabled(imageReference.isEmpty);Spacer();Text("Preview only · first GIF frame").font(.caption).foregroundStyle(.secondary)}
            ForEach(workspace.imageMappings.keys.sorted(),id:\.self){key in HStack{Text(key).font(.caption).lineLimit(1);Spacer();Button("Remove"){workspace.removeImage(key)}}}
        }
    }
    private var diagnostics: some View {
        VStack(alignment:.leading,spacing:5){
            HStack {Image(systemName:workspace.result?.diagnostics.contains(where:{$0.severity=="error"}) == true ? "exclamationmark.triangle" : "info.circle");Text(workspace.status).font(.callout);Spacer()
                if !workspace.sizeSummary.isEmpty {Text(workspace.sizeSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)}
                if workspace.result != nil {Button(workspace.showDetails ? "Hide Details" : "Details"){withAnimation(animation){workspace.showDetails.toggle()}}.buttonStyle(.borderless)}
            }
            if let d=workspace.result?.diagnostics.first {
                if workspace.tool == .sql && workspace.result?.status == "invalid" {
                    Text("Could not format as \(MarkupOptions.dialectName(workspace.options.dialect)). Check that Dialect matches your database; this is not database validation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment:.top){Text(d.message).font(.callout).textSelection(.enabled);Spacer();if d.range(in:workspace.input) != nil {Button("Show Source"){withAnimation(animation){workspace.show(d)}}}}
                if let range=d.range(in:workspace.input) {Text(sourceLocation(d,range)).font(.caption).foregroundStyle(.secondary)}
            }
            if workspace.showDetails {
                Text(workspace.tool.engineDescription).font(.caption).foregroundStyle(.secondary)
                if let count=workspace.result?.diagnostics.count,count>100 {Text("\(count-100) additional diagnostics not shown.").font(.caption)}
                ForEach(workspace.result?.notices ?? [],id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}
                ForEach(Array((workspace.result?.diagnostics ?? []).dropFirst().prefix(99))){d in Button(d.message){workspace.show(d)}.buttonStyle(.borderless)}
            }
            if let message=fileIssue ?? previewFailure {HStack{Text(message).font(.caption);Spacer();if previewFailure != nil {Button("Retry Preview"){previewFailure=nil;previewRetry=UUID()}};Button("Dismiss"){fileIssue=nil;previewFailure=nil}}}
        }.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))
        .animation(animation,value:workspace.result?.diagnostics.first?.message).animation(animation,value:workspace.showDetails)
    }
    private var editorDiagnostic: JSONDiagnostic? {
        guard let d=workspace.result?.diagnostics.first,d.offset != nil,let range=d.range(in:workspace.input),workspace.result?.status != "resourceLimit" else{return nil}
        let p=JSONSourceCoordinates(workspace.input).location(at:range.location)
        return .init(severity:d.severity=="warning" ? .warning : .error,code:"markup",message:d.message,range:range,line:p.line,column:p.column,precision:d.offset==nil ? .region : .exact)
    }
    private func sourceLocation(_ d: MarkupDiagnostic, _ range: NSRange) -> String {
        let p=JSONSourceCoordinates(workspace.input).location(at:range.location)
        return d.offset == nil ? "Line \(p.line) · column not available" : "Line \(p.line), column \(p.column) (UTF-16)"
    }
    private func open(_ url: URL) {
            let revision=workspace.revision
            Task {
                do {
                    let text=try await Task.detached { () -> String in
                        let allowed=url.startAccessingSecurityScopedResource();defer{if allowed{url.stopAccessingSecurityScopedResource()}}
                        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                        let data=try handle.read(upToCount:1024*1024+1) ?? Data()
                        guard data.count<=1024*1024,let s=String(data:data,encoding:.utf8) else{throw CocoaError(.fileReadInapplicableStringEncoding)}
                        return s
                    }.value
                    guard workspace.revision==revision else{fileIssue="Input changed while opening the file.";return}
                    commands.replace?(.init(location:0,length:workspace.input.utf16.count),text)
                    workspace.pasted(automatic:jsonPreferences.validateOnPaste)
                }catch{fileIssue="Open requires a UTF-8 file up to 1 MiB."}
            }
    }
    private var outputOptions: JSONEditorOptions {
        if workspace.tool.isPreview {return .init(syntax:.markup,syntaxHighlighting:true,rainbowBrackets:false,matchingBrackets:false,wordWrap:workspace.options.wrap,validateVisibleRendering:true)}
        return editorOptions
    }
    private var editorOptions: JSONEditorOptions {
        let syntax: EditorSyntax = switch workspace.tool {
        case .yaml: .yaml; case .sql: .sql; case .css: .css; case .javascript: .javascript; case .markdown: .markdown; default: .markup
        }
        return .init(syntax:syntax,syntaxHighlighting:true,rainbowBrackets:false,matchingBrackets:false,wordWrap:workspace.options.wrap,validateVisibleRendering:true)
    }
}
