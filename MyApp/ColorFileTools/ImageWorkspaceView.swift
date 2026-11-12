import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif
struct RasterExportDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.data]}
    let data:Data
    init(_ data:Data){self.data=data}
    init(configuration:ReadConfiguration)throws{data=configuration.file.regularFileContents ?? Data()}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{FileWrapper(regularFileWithContents:data)}
}
struct ImageWorkspaceView:View {
    @Bindable var workspace:ImageWorkspace
    var tool:Int
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var importing=false
    @State private var exporting=false
    @State private var file=RasterExportDocument(Data())
    @State private var exportType=UTType.png
    @State private var extensionName="png"
    @State private var zoom=1.0
    @State private var pixelSize=false
    @State private var fullPreview:CGImage?
    @State private var previewIssue:String?
    @State private var targetKB=200
    @State private var useTarget=false
    @State private var fileIssue:String?
    @State private var selectedMetadata:MetadataRow?
    var body:some View {
        VStack(spacing:8){
            ViewThatFits(in:.horizontal){HStack{fileActions;Spacer();resultActions};VStack{HStack{fileActions;Spacer()};HStack{resultActions;Spacer()}}}.buttonStyle(.bordered)
            GeometryReader {g in
                let wide=g.size.width>=800
                let layout=wide ? AnyLayout(HStackLayout(alignment:.top,spacing:12)):AnyLayout(VStackLayout(spacing:12))
                layout {
                    ScrollView {controls.padding(12)}.frame(maxWidth:wide ? 330:.infinity,maxHeight:wide ? .infinity:240).background(.background,in:RoundedRectangle(cornerRadius:10))
                    if tool==65{metadataPanel}else{previewPanel}
                }
            }
            HStack(alignment:.top){Image(systemName:workspace.busy ? "hourglass":"info.circle");Text(fileIssue ?? workspace.status).font(.callout).textSelection(.enabled);Spacer();if workspace.busy{Button("Cancel"){workspace.cancel()}}}.frame(minHeight:28,alignment:.top)
        }.padding(12).animation(reduced ? nil:.easeInOut(duration:0.2),value:selectedMetadata?.id).animation(reduced ? nil:.easeInOut(duration:0.2),value:useTarget)
        .fileImporter(isPresented:$importing,allowedContentTypes:[.image,.data]){result in if case .success(let url)=result{fileIssue=nil;workspace.load(url:url)}}
        .fileExporter(isPresented:$exporting,document:file,contentType:exportType,defaultFilename:"image."+extensionName){result in if case .failure = result{fileIssue="Export could not complete. The source file is unchanged."}}
        .dropDestination(for:URL.self){urls,_ in guard urls.count==1,let url=urls.first,url.isFileURL else{return false};workspace.load(url:url);return true}
        .task(id:"\(workspace.revision)-\(workspace.busy)-\(workspace.showAfter)-\(pixelSize)") {
            fullPreview=nil;previewIssue=nil
            guard pixelSize,let data=workspace.showAfter ? workspace.result?.data:workspace.source?.data else{return}
            do{let image=try await RasterWorker.shared.preview(data:data);guard !Task.isCancelled else{return};fullPreview=image}catch{if !Task.isCancelled{previewIssue="Full-resolution preview unavailable."}}
        }
        .onChange(of:workspace.revision){_,_ in selectedMetadata=nil}
        .onChange(of:workspace.showAfter){_,_ in selectedMetadata=nil}
        .onChange(of:workspace.options.format){_,format in if !format.lossy{useTarget=false;workspace.options.targetBytes=nil};if tool==64,workspace.source?.type != format.uti{workspace.keepSourceFormat=false}}
        .onChange(of:phase){_,phase in if phase == .background{workspace.revealGPS=false;selectedMetadata=nil}}
    }
    private var fileActions:some View {HStack{
        Button("Open",systemImage:"folder"){importing=true}
        Button("Paste Image",systemImage:"clipboard"){paste()}
        Button("Clear",systemImage:"xmark.circle"){workspace.clear();selectedMetadata=nil}.disabled(workspace.source==nil)
    }.fixedSize()}
    private var resultActions:some View {HStack{
        Button("Export File…",systemImage:"square.and.arrow.up"){guard let result=workspace.result else{return};file=RasterExportDocument(result.data);exportType=UTType(result.format.uti) ?? .data;extensionName=result.format.fileExtension;exporting=true}.disabled(workspace.result==nil || workspace.busy)
        if tool != 65 {Button("Copy Image"){copyImage()}.disabled(workspace.result==nil || workspace.busy)}
    }.fixedSize()}
    private var controls:some View {
        VStack(alignment:.leading,spacing:12){
            if let source=workspace.source {
                Text("Source").font(.headline)
                Text("\(source.orientedWidth) × \(source.orientedHeight) px · \(ByteCountFormatter.string(fromByteCount:Int64(source.data.count),countStyle:.file))").font(.callout)
                Text("\(source.type) · \(source.frames) frame(s)").font(.caption).foregroundStyle(.secondary)
                if tool==65 {
                    Text("Metadata cleanup").font(.headline)
                    Button("Remove GPS without re-encoding"){workspace.run(gps:true)}.disabled(workspace.busy || !["public.jpeg","public.tiff"].contains(source.type) || source.frames != 1)
                    Text("GPS-only copying is verified for JPEG/TIFF. PNG requires a clean copy. Clean copy requires re-encoding. JPEG / HEIC can lose quality. Pixel text and steganography remain.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Output",selection:$workspace.options.format){ForEach(RasterFormat.available){format in Text(format.rawValue.uppercased()).tag(format)}}
                if tool==64 {
                    Toggle("Keep source format",isOn:$workspace.keepSourceFormat).onChange(of:workspace.keepSourceFormat){_,keep in if keep,let source=workspace.source,let format=RasterFormat.available.first(where:{$0.uti==source.type}){workspace.options.format=format}}
                    if workspace.keepSourceFormat && !RasterFormat.available.contains(where:{$0.uti==source.type}){Text("Source format has no verified encoder. Choose an output format and turn off Keep source format.").font(.caption)}
                    resizeControls
                }
                if workspace.options.format.lossy {
                    Text("Quality · \(Int(workspace.options.quality*100))%").font(.callout)
                    Slider(value:$workspace.options.quality,in:0...1).accessibilityLabel("Encoding quality")
                    if tool==64{
                        Toggle("Target file size",isOn:$useTarget).onChange(of:useTarget){_,on in workspace.options.targetBytes=on ? max(1,targetKB)*1024:nil}
                        if useTarget{HStack{TextField("KiB",value:$targetKB,format:.number).textFieldStyle(.roundedBorder).onChange(of:targetKB){_,n in workspace.options.targetBytes=max(1,min(65536,n))*1024};Text("KiB")};Text("Up to 12 trials at fixed dimensions. Target may not be reached.").font(.caption)}
                    }
                }
                if !workspace.options.format.preservesAlpha {
                    Picker("Transparency matte",selection:matte){Text("White").tag(true);Text("Black").tag(false)}
                    if source.hasAlpha{Text("Transparency will be flattened.").font(.caption)}
                }
                Button(tool==65 ? "Create clean copy":tool==64 ? "Resize / Compress":"Convert"){workspace.run()}.keyboardShortcut(.return,modifiers:.command).disabled(workspace.busy || source.frames != 1 || tool==64 && workspace.keepSourceFormat && !RasterFormat.available.contains(where:{$0.uti==source.type}))
                if tool==65 {Text("Recognized descriptive metadata removed; technical sRGB properties retained. Original file is not modified.").font(.caption)}
                ForEach(source.notices,id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}
                if let result=workspace.result {
                    Divider();Text("Output").font(.headline)
                    Text("\(result.width) × \(result.height) px · \(ByteCountFormatter.string(fromByteCount:Int64(result.data.count),countStyle:.file))")
                    Text(String(format:"Size change: %+.1f%%",100*(Double(result.data.count)/Double(source.data.count)-1))).font(.caption)
                    if result.format.lossy{Text("Output quality: \(Int((result.quality*100).rounded()))%").font(.caption)}
                    ForEach(result.changes,id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}
                }
            } else {ContentUnavailableView("Open an image",systemImage:"photo",description:Text("Choose, drop or explicitly paste one image. Files stay local."))}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var matte:Binding<Bool>{Binding(get:{workspace.options.matte[0]==1},set:{workspace.options.matte=$0 ? [1,1,1]:[0,0,0]})}
    private var resizeControls:some View {
        VStack(alignment:.leading,spacing:8){
            Picker("Resize mode",selection:$workspace.options.mode){ForEach(ResizeMode.allCases.filter{$0 != .original},id:\.self){Text($0.rawValue).tag($0)}}
            if workspace.options.mode == .percentage {TextField("Percent",value:$workspace.options.percent,format:.number).textFieldStyle(.roundedBorder)}
            else {
                HStack{Text("Width");TextField("Pixels",value:Binding(get:{workspace.options.width},set:{workspace.options.width=$0;workspace.options.widthIsAuthority=true}),format:.number).textFieldStyle(.roundedBorder)}
                HStack{Text("Height");TextField("Pixels",value:Binding(get:{workspace.options.height},set:{workspace.options.height=$0;workspace.options.widthIsAuthority=false}),format:.number).textFieldStyle(.roundedBorder)}
                if workspace.options.mode == .dimensions {Toggle("Lock aspect ratio",isOn:$workspace.options.lockAspect)}
            }
            Toggle("Allow upscaling",isOn:$workspace.options.allowUpscale)
            if let source=workspace.source,let size=try? workspace.options.dimensions(source){Text("Planned output: \(size.0) × \(size.1) px").font(.caption)}
            if workspace.options.mode == .fill{Text("Fill crops the center of the source to the selected box.").font(.caption)}
        }
    }
    private var previewPanel:some View {
        VStack(spacing:8){
            if workspace.result != nil && workspace.status != "Completed" && !workspace.status.hasPrefix("Target not reached") {Text("Previous result · \(workspace.status)").font(.caption).foregroundStyle(.secondary)}
            HStack{Picker("Preview",selection:$workspace.showAfter){Text("Before").tag(false);Text("After").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(maxWidth:180)
                Spacer();Button("Fit"){pixelSize=false;zoom=1};Button("100%"){pixelSize=true;zoom=1}
                Button("−"){zoom=max(0.25,zoom/1.5)}.accessibilityLabel("Zoom out");Button("+"){zoom=min(4,zoom*1.5)}.accessibilityLabel("Zoom in")
            }
            GeometryReader{g in
                if let image=pixelSize ? fullPreview : (workspace.showAfter ? workspace.result?.preview : workspace.source?.thumbnail) {
                    let width=Double(image.width),height=Double(image.height),scale=pixelSize ? 1:min(g.size.width/width,g.size.height/height)
                    ScrollView([.horizontal,.vertical]){Image(decorative:image,scale:1).resizable().interpolation(.high).frame(width:width*scale*zoom,height:height*scale*zoom).background{ColorCheckerboard()}.padding(1)}
                } else {ContentUnavailableView(workspace.showAfter ? "No output yet":"No image",systemImage:"photo",description:Text("Run the operation to preview the actual encoded output."))}
            }
            Text(previewIssue ?? (pixelSize ? "100% uses full-resolution decoded pixels":"Fit preview decoded from file bytes · up to 1600 px")).font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity).background(.background,in:RoundedRectangle(cornerRadius:10))
    }
    private var metadataPanel:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{TextField("Search metadata",text:$workspace.search).textFieldStyle(.roundedBorder);Button(workspace.revealGPS ? "Hide GPS":"Reveal GPS"){workspace.revealGPS.toggle();selectedMetadata=nil}}
            Picker("Inventory",selection:$workspace.showAfter){Text("Original").tag(false);Text("Cleaned").tag(true)}.pickerStyle(.segmented)
            List(filteredMetadata){row in
                VStack(alignment:.leading,spacing:3){Text(row.path).font(.caption).foregroundStyle(.secondary);HStack{Text(row.isGPS && !workspace.revealGPS ? "Sensitive location hidden":String(row.value.prefix(240))).font(.system(.body,design:.monospaced)).lineLimit(2);Spacer();Button("Details"){selectedMetadata=row}.disabled(row.isGPS && !workspace.revealGPS)}}
                    .contextMenu{Button("Copy value"){TextClipboard.copy(row.copyValue)}.disabled(row.isGPS && !workspace.revealGPS)}
            }.listStyle(.plain)
            if let row=selectedMetadata {VStack(alignment:.leading){HStack{Text(row.type).font(.caption);Spacer();Button("Copy value"){TextClipboard.copy(row.copyValue)};Button("Close"){selectedMetadata=nil}};ScrollView{Text(row.value).font(.system(.body,design:.monospaced)).textSelection(.enabled)}.frame(maxHeight:130)}.padding(8)}
            Text("\(filteredMetadata.count) exposed tags. Dates retain their original timezone information; missing GPS is not 0,0.").font(.caption).foregroundStyle(.secondary)
        }.padding(12).background(.background,in:RoundedRectangle(cornerRadius:10))
    }
    private var filteredMetadata:[MetadataRow]{let rows=workspace.showAfter ? workspace.result?.metadata ?? []:workspace.source?.metadata ?? [];return workspace.search.isEmpty ? rows:rows.filter{$0.path.localizedCaseInsensitiveContains(workspace.search) || (!$0.isGPS || workspace.revealGPS) && $0.value.localizedCaseInsensitiveContains(workspace.search)}}
    private func paste(){
        #if os(macOS)
        for type in ["public.png","public.jpeg","public.heic","public.tiff","com.compuserve.gif","org.webmproject.webp"] {if let data=NSPasteboard.general.data(forType:NSPasteboard.PasteboardType(type)){workspace.load(data:data);return}}
        if let image=NSImage(pasteboard:NSPasteboard.general),let data=image.tiffRepresentation{workspace.load(data:data);fileIssue="Clipboard raster: original file metadata may not be available.";return}
        #else
        for type in ["public.png","public.jpeg","public.heic","public.tiff","com.compuserve.gif","org.webmproject.webp"] {if let data=UIPasteboard.general.data(forPasteboardType:type){workspace.load(data:data);return}}
        if let image=UIPasteboard.general.image,let data=image.pngData(){workspace.load(data:data);fileIssue="Clipboard raster: original file metadata may not be available.";return}
        #endif
        fileIssue="Clipboard does not contain a supported image."
    }
    private func copyImage(){guard let result=workspace.result else{return}
        #if os(macOS)
        guard let image=NSImage(data:result.data) else{return};NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects([image])
        #else
        guard let image=UIImage(data:result.data) else{return};UIPasteboard.general.image=image
        #endif
    }
}
