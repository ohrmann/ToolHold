import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif
private var plainFileOptions:JSONEditorOptions {var o=JSONEditorOptions();o.syntax = .plainText;o.rainbowBrackets=false;o.matchingBrackets=false;return o}
private func explicitClipboardText()->String? {
    #if os(macOS)
    NSPasteboard.general.string(forType:.string)
    #else
    UIPasteboard.general.string
    #endif
}
struct SVGWorkspaceView:View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Bindable var workspace:SVGWorkspace
    @State private var commands=JSONEditorCommands()
    @State private var fraction=0.45
    @State private var importing=false
    @State private var exporting=false
    @State private var file=TextExportDocument("")
    @State private var fileIssue:String?
    var body:some View {
        VStack(spacing:8){
            ViewThatFits(in:.horizontal){HStack{actions;Spacer();options};VStack{HStack{actions;Spacer()};HStack{options;Spacer()}}}.buttonStyle(.bordered)
            GeometryReader{g in TextToolPanelLayout(wide:g.size.width>=760,fraction:fraction,collapse:0){
                VStack(alignment:.leading){HStack{Text("Input").font(.headline);Spacer();Button("Open SVG"){importing=true};Button("Clear"){commands.clear?()}};JSONTextEditor(text:$workspace.input,commands:commands,options:plainFileOptions,placeholder:"SVG source or Data URI",contentName:"SVG Input",showsLineNumbers:false)}.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
                TextToolDivider(wide:g.size.width>=760,length:g.size.width>=760 ? g.size.width:g.size.height,fraction:$fraction)
                VStack(alignment:.leading){HStack{Text("Output").font(.headline);Spacer();Button("Copy"){TextClipboard.copy(workspace.output)}.disabled(workspace.result==nil);Button("Export…"){file=TextExportDocument(workspace.output);exporting=true}.disabled(workspace.result==nil)};JSONTextEditor(text:.constant(workspace.output),editable:false,options:plainFileOptions,placeholder:"Encoded output appears here",contentName:"SVG Output")}.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
            }}
            Text(fileIssue ?? workspace.status).font(.callout).frame(maxWidth:.infinity,alignment:.leading)
            if let result=workspace.result{Text("Percent URI: \(result.percentURI.utf8.count) bytes · Base64 URI: \(result.base64URI.utf8.count) bytes").font(.caption).frame(maxWidth:.infinity,alignment:.leading)}
            Text("Encoding is not sanitization. SVG scripts/URLs are retained as data and never executed here. Masks are monochrome.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(12).animation(reduced ? nil:.easeInOut(duration:0.2),value:workspace.result != nil)
        .fileImporter(isPresented:$importing,allowedContentTypes:[.svg,.plainText]){result in guard case .success(let url)=result else{return};Task{do{let data=try await Task.detached{try LocalImageFile.read(url,limit:1024*1024)}.value;guard let text=String(data:data,encoding:.utf8) else{fileIssue="Choose a UTF-8 SVG.";return};commands.replace?(.init(location:0,length:workspace.input.utf16.count),text)}catch{fileIssue="Could not read SVG."}}}
        .fileExporter(isPresented:$exporting,document:file,contentType:.plainText,defaultFilename:"svg-data-uri.txt"){_ in}
    }
    private var actions:some View {HStack{Button("Encode"){workspace.run()}.keyboardShortcut(.return,modifiers:.command);Button("Decode URI"){workspace.run(decode:true)};if workspace.busy{Button("Cancel"){workspace.cancel()}}}.fixedSize()}
    private var options:some View {HStack{Picker("Encoding",selection:$workspace.base64){Text("Percent").tag(false);Text("Base64").tag(true)};Picker("Output",selection:$workspace.style){ForEach(["Data URI","Background","Mask"],id:\.self){Text($0).tag($0)}}}.fixedSize()}
}
struct CurlWorkspaceView:View {
    @Bindable var workspace:CurlWorkspace
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var commands=JSONEditorCommands()
    @State private var fraction=0.45
    @State private var jump=0
    @State private var exporting=false
    @State private var file=TextExportDocument("")
    var body:some View {
        VStack(spacing:8){
            ViewThatFits(in:.horizontal){HStack{actions;Spacer();settings};VStack{HStack{actions;Spacer()};HStack{settings;Spacer()}}}.buttonStyle(.bordered)
            GeometryReader{g in TextToolPanelLayout(wide:g.size.width>=760,fraction:fraction,collapse:0){
                VStack(alignment:.leading){HStack{Text("cURL Input").font(.headline);Spacer();Button("Paste"){if let text=explicitClipboardText(){commands.replace?(.init(location:0,length:workspace.input.utf16.count),text)}};Button("Clear"){commands.clear?()}};ZStack{
                    JSONTextEditor(text:$workspace.input,jumpTarget:workspace.issue?.range,jumpRequest:jump,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,commands:commands,options:plainFileOptions,presentationHidden:workspace.masked,usesPrivacyContainer:true,privateUndo:true,placeholder:"curl 'https://example.com'",contentName:"cURL Input").accessibilityHidden(workspace.masked).allowsHitTesting(!workspace.masked)
                    if workspace.masked{ContentUnavailableView("Sensitive content hidden",systemImage:"eye.slash",description:Text("Reveal to edit, or paste explicitly."))}
                }}.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
                TextToolDivider(wide:g.size.width>=760,length:g.size.width>=760 ? g.size.width:g.size.height,fraction:$fraction)
                VStack(alignment:.leading){HStack{Text("Generated code").font(.headline);Spacer();Button("Copy code"){TextClipboard.copy(workspace.result?.code ?? "")}.disabled(workspace.result==nil || workspace.masked);Button("Export…"){file=TextExportDocument(workspace.result?.code ?? "");exporting=true}.disabled(workspace.result==nil || workspace.masked)};ZStack{
                    JSONTextEditor(text:.constant(workspace.result?.code ?? ""),editable:false,options:plainFileOptions,presentationHidden:workspace.masked,usesPrivacyContainer:true,contentName:"Generated request").accessibilityHidden(workspace.masked)
                    if workspace.masked{ContentUnavailableView("Code hidden",systemImage:"eye.slash")}
                }}.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
            }}
            HStack{Text(workspace.status).font(.callout).textSelection(.enabled);Spacer();if workspace.issue?.range != nil{Button("Show Source"){commands.resignFocus?();workspace.masked=false;jump+=1}}}
            if let result=workspace.result{ScrollView{VStack(alignment:.leading){ForEach(result.issues,id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:80)}
            Text("No requests are sent. Default redaction covers auth/cookie headers only; URLs and bodies can contain secrets.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(12).animation(reduced ? nil:.easeInOut(duration:0.2),value:workspace.result != nil).onChange(of:phase){_,phase in if phase == .background{commands.resignFocus?();workspace.masked=true}}
        .fileExporter(isPresented:$exporting,document:file,contentType:.plainText,defaultFilename:"request."+workspace.language.fileExtension){_ in}
    }
    private var actions:some View {HStack{Button("Generate"){workspace.run()}.keyboardShortcut(.return,modifiers:.command).disabled(workspace.input.isEmpty);if workspace.busy{Button("Cancel"){workspace.cancel()}};Button(workspace.masked ? "Reveal / Edit":"Hide sensitive content"){commands.resignFocus?();workspace.masked.toggle()}}.fixedSize()}
    private var settings:some View {HStack{Picker("Target",selection:$workspace.language){ForEach(RequestLanguage.allCases){Text($0.rawValue).tag($0)}};Toggle("Include secrets",isOn:$workspace.includeSecrets)}.fixedSize()}
}
struct ConnectionWorkspaceView:View {
    @Bindable var workspace:ConnectionWorkspace
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var commands=JSONEditorCommands()
    @State private var fraction=0.4
    @State private var target:NSRange?
    @State private var jump=0
    @State private var selected:Int?
    @State private var edit=""
    @State private var editing=false
    @State private var editCommands=JSONEditorCommands()
    var body:some View {
        VStack(spacing:8){
            ViewThatFits(in:.horizontal){HStack{actions;Spacer();profile};VStack{HStack{actions;Spacer()};profile}}.buttonStyle(.bordered)
            GeometryReader{g in TextToolPanelLayout(wide:g.size.width>=760,fraction:fraction,collapse:0){
                VStack(alignment:.leading){HStack{Text("Source").font(.headline);Spacer();Button("Paste"){if let text=explicitClipboardText(){commands.replace?(.init(location:0,length:workspace.input.utf16.count),text)}};Button("Clear"){commands.clear?()}};ZStack{
                    JSONTextEditor(text:$workspace.input,jumpTarget:target,jumpRequest:jump,animateJumps:!reduced,highlightJumps:true,focusOnJump:false,commands:commands,options:plainFileOptions,presentationHidden:workspace.masked,usesPrivacyContainer:true,privateUndo:true,placeholder:"Enter a connection string",contentName:"Connection source").accessibilityHidden(workspace.masked).allowsHitTesting(!workspace.masked)
                    if workspace.masked{ContentUnavailableView("Source hidden",systemImage:"eye.slash",description:Text("Reveal/Edit or paste explicitly. No connection is attempted."))}
                }}.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
                TextToolDivider(wide:g.size.width>=760,length:g.size.width>=760 ? g.size.width:g.size.height,fraction:$fraction)
                fieldsPanel
            }}
            Text(workspace.status).font(.callout).frame(maxWidth:.infinity,alignment:.leading)
            if let document=workspace.document{Text(document.issues.joined(separator:"\n")).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)}
        }.padding(12).animation(reduced ? nil:.easeInOut(duration:0.2),value:editing).animation(reduced ? nil:.easeInOut(duration:0.2),value:workspace.document != nil).onChange(of:phase){_,phase in if phase == .background{commands.resignFocus?();editCommands.resignFocus?();editCommands.purgeUndo?();workspace.masked=true;editing=false;edit=""}}
        .onChange(of:workspace.input){_,_ in selected=nil;editing=false;edit="";target=nil}
    }
    private var actions:some View {HStack{Button("Inspect"){workspace.run()}.keyboardShortcut(.return,modifiers:.command).disabled(workspace.input.isEmpty);if workspace.busy{Button("Cancel"){workspace.cancel()}};Button(workspace.masked ? "Reveal / Edit":"Hide sensitive content"){commands.resignFocus?();editCommands.resignFocus?();workspace.masked.toggle();if workspace.masked{editCommands.purgeUndo?();editing=false;edit=""}}}.fixedSize()}
    private var profile:some View {Picker("Profile",selection:$workspace.profile){ForEach(ConnectionProfile.allCases){Text($0.rawValue).tag($0)}}.fixedSize()}
    private var fields:[ConnectionField]{workspace.document?.fields.filter{workspace.search.isEmpty || $0.name.localizedCaseInsensitiveContains(workspace.search) || (!workspace.masked || !$0.sensitive && !$0.unknown) && $0.value.localizedCaseInsensitiveContains(workspace.search)} ?? []}
    private var fieldsPanel:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{TextField("Search fields",text:$workspace.search).textFieldStyle(.roundedBorder);Menu("Copy"){
                Button("Copy redacted string"){if let text=try? workspace.document?.redacted(hideAll:workspace.hideAllValues){TextClipboard.copy(text)}}.disabled(workspace.document==nil)
                Toggle("Redact all values",isOn:$workspace.hideAllValues)
                Button("Copy exact string with secrets"){TextClipboard.copy(workspace.input)}.disabled(workspace.masked || workspace.document==nil)
            }}
            List(fields,selection:$selected){field in
                VStack(alignment:.leading,spacing:3){Text(field.role == field.name.lowercased() ? field.name : "\(field.name) · \(field.role)").font(.caption).foregroundStyle(.secondary);Text(workspace.masked && (field.sensitive || field.unknown) ? "Hidden":String(field.value.prefix(240))).font(.system(.body,design:.monospaced)).lineLimit(2)}.tag(field.id)
                    .contextMenu{fieldActions(field)}
            }.listStyle(.plain)
            if let selected,let field=workspace.document?.fields.first(where:{$0.id==selected}) {
                HStack{Text(field.name).font(.headline);Spacer();Menu("Actions"){fieldActions(field)}}
                if editing {
                    JSONTextEditor(text:$edit,commands:editCommands,options:plainFileOptions,presentationHidden:workspace.masked,usesPrivacyContainer:true,privateUndo:true,contentName:"Edited connection value").frame(height:95)
                    HStack{Button("Apply"){editCommands.resignFocus?();workspace.apply(id:field.id,value:edit);editCommands.purgeUndo?();editing=false;edit=""};Button("Cancel"){editCommands.resignFocus?();editCommands.purgeUndo?();editing=false;edit=""}}
                }
            }
            Text("Fields retain source order and duplicates. Redacted copies contain placeholders, not usable credentials/ports. TLS/connectivity are not verified.").font(.caption).foregroundStyle(.secondary)
        }.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10))
    }
    @ViewBuilder private func fieldActions(_ field:ConnectionField)->some View {
        Button("Show Source"){commands.resignFocus?();workspace.masked=false;target=field.range;jump+=1}
        Button("Edit value"){workspace.masked=false;selected=field.id;edit=field.value;editing=true}
        Button(field.sensitive || field.unknown ? "Copy secret value":"Copy value"){TextClipboard.copy(field.value)}.disabled(workspace.masked && (field.sensitive || field.unknown))
    }
}
