import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct QRCodeGeneratorView: View {
    @Bindable var workspace: QRCodeWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var commands = JSONEditorCommands()
    @State private var importing = false
    @State private var exporting = false
    @State private var output: QRExport?
    @State private var fileMessage: String?
    private var animation: Animation? { reduced || ProcessInfo.processInfo.arguments.contains("--reduce-motion") ? nil : .easeInOut(duration:0.2) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
            let layout = wide ? AnyLayout(HStackLayout(alignment:.top,spacing:16)) : AnyLayout(VStackLayout(alignment:.leading,spacing:12))
            layout {
                ScrollView(.vertical) {
                    VStack(alignment:.leading,spacing:14) {
                        input
                        actions
                        appearance
                        logo
                        exportOptions
                        Button("Reset Appearance") { workspace.resetAppearance(); fileMessage = nil }
                            .accessibilityHint("Restore appearance defaults and remove the logo. Input stays unchanged.")
                            .accessibilityIdentifier("qr-reset")
                    }.padding(2)
                }
                .accessibilityIdentifier("qr-controls")
                .frame(maxWidth:.infinity)
                .frame(height:wide ? nil : max(200,geometry.size.height*0.47))
                .frame(maxHeight:wide ? .infinity : nil)
                .animation(animation,value:workspace.contentKind)
                .animation(animation,value:workspace.preferences.appearanceExpanded)
                .animation(animation,value:workspace.preferences.logoExpanded)
                .animation(animation,value:workspace.preferences.exportExpanded)
                preview(maxSide:wide ? min(300,max(120,geometry.size.height-220)) : min(240,max(100,geometry.size.height*0.3)))
                    .frame(width:wide ? min(340,geometry.size.width*0.34) : nil)
            }.padding(12)
        }
        .navigationTitle("QR Code Generator")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("Done") { commands.resignFocus?(); UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil) } } }
        #endif
        .fileImporter(isPresented:$importing,allowedContentTypes:[.png,.jpeg,.heic,.heif],allowsMultipleSelection:false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { workspace.loadLogo(url) }
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { fileMessage = "Image selection is unavailable. Try a local PNG, JPEG or HEIC file." }
            }
        }
        .fileExporter(isPresented:$exporting,document:output.map { QRCodeExportDocument($0.data) },contentType:output?.format == .svg ? .svg : .png,defaultFilename:output?.filename ?? "qr-code.png") { result in
            switch result {
            case .success: fileMessage = "Image exported"
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { fileMessage = "Export was not completed. Choose a writable local destination." }
            }
            output = nil
        }
        .onDisappear { commands.resignFocus?() }
        .onChange(of:workspace.revision) { _,_ in fileMessage = nil }
        #if os(macOS)
        .onExitCommand { workspace.cancel() }
        #else
        .onKeyPress(.escape) { guard workspace.busy || workspace.preparing || workspace.loadingLogo else { return .ignored }; workspace.cancel(); return .handled }
        #endif
    }
    private var input: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Text("Input").font(.headline)
                Spacer()
                Button("Clear Input",systemImage:"trash") { commands.clear?(); commands.purgeUndo?(); workspace.clear(); fileMessage = nil }
                    .accessibilityIdentifier("qr-clear")
            }
            Picker("Content",selection:Binding(get:{workspace.contentKind},set:{ kind in
                commands.resignFocus?()
                #if os(macOS)
                NSApp.keyWindow?.makeFirstResponder(nil)
                #else
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
                #endif
                workspace.contentKind = kind
            })) { ForEach(QRContentKind.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.menu).accessibilityIdentifier("qr-content-kind")
            JSONTextEditor(text:$workspace.input,commands:commands,
                options:.init(syntax:.plainText,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:true),
                presentationHidden:workspace.contentKind != .freeText, privateUndo:true,placeholder:"Free text",contentName:"QR",showsLineNumbers:false)
                .frame(height:workspace.contentKind == .freeText ? 150 : 0).background(.background,in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(.secondary.opacity(0.25)))
                .accessibilityIdentifier("qr-input")
            if workspace.contentKind != .freeText { QRCodeContentForm(kind:workspace.contentKind,fields:$workspace.fields) }
            Text("\(workspace.payload.utf8.count) UTF-8 bytes" + (workspace.contentKind == .freeText && !workspace.input.isEmpty && workspace.input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? " · whitespace-only content" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var actions: some View {
        ViewThatFits(in:.horizontal) {
            HStack { generate; correction }
            VStack(alignment:.leading,spacing:8) { generate; correction }
        }
    }
    private var generate: some View {
        HStack {
            Button("Generate",systemImage:"qrcode") { workspace.generate() }
                .keyboardShortcut(.return,modifiers:.command).disabled(workspace.payload.isEmpty || workspace.loadingLogo)
                .accessibilityIdentifier("qr-generate")
            if workspace.busy || workspace.preparing || workspace.loadingLogo { Button("Cancel") { workspace.cancel() }.accessibilityIdentifier("qr-cancel") }
        }.fixedSize()
    }
    private var correction: some View {
        HStack {
            if workspace.logo != nil { Text("Correction H · required for logo").font(.caption) }
            else {
                Picker("Correction",selection:$workspace.preferences.correction) { ForEach(QRCorrection.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).fixedSize().accessibilityIdentifier("qr-correction")
            }
        }
    }
    private var appearance: some View {
        DisclosureGroup("Appearance",isExpanded:$workspace.preferences.appearanceExpanded) {
            VStack(alignment:.leading,spacing:12) {
                Picker("Pattern",selection:$workspace.preferences.style) { ForEach(QRModuleStyle.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).accessibilityIdentifier("qr-style")
                if workspace.preferences.style == .rounded {
                    slider("Rounding",value:$workspace.preferences.rounding,range:0...0.5,label:String(format:"%.2f",workspace.preferences.rounding),id:"qr-rounding")
                }
                QRColorControl(title:"Pattern color",value:$workspace.preferences.foreground,identifier:"qr-foreground")
                QRColorControl(title:"Background",value:$workspace.preferences.background,identifier:"qr-background")
                slider("Background opacity",value:$workspace.preferences.opacity,range:0...1,label:"\(Int((workspace.preferences.opacity*100).rounded()))%",id:"qr-opacity")
                if workspace.preferences.opacity < 1 {
                    Picker("Preview surface",selection:$workspace.preferences.surface) { ForEach(QRSurface.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                    if workspace.preferences.surface == .custom { QRColorControl(title:"Surface",value:$workspace.preferences.customSurface,identifier:"qr-surface") }
                    Text("The surface is used for the local check. It is not exported. Reading on other backgrounds may differ.").font(.caption).foregroundStyle(.secondary)
                }
                if workspace.preferences.contrastWarning { Label("Low contrast or inverted colors may be difficult to read.",systemImage:"exclamationmark.triangle").font(.caption) }
            }.padding(.top,8)
        }
    }
    private var logo: some View {
        DisclosureGroup("Logo",isExpanded:$workspace.preferences.logoExpanded) {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Button(workspace.logo == nil ? "Add Image…" : "Replace Image…",systemImage:"photo") { commands.resignFocus?(); importing = true }.accessibilityIdentifier("qr-logo-import")
                    if workspace.logo != nil { Button("Remove",role:.destructive) { workspace.removeLogo() }.accessibilityIdentifier("qr-logo-remove") }
                }
                if let logo = workspace.logo {
                    HStack { Image(decorative:logo.image,scale:1).resizable().scaledToFit().frame(width:48,height:48); Text("\(logo.image.width) × \(logo.image.height) px · local image").font(.caption) }
                    slider("Logo size",value:$workspace.preferences.logoSize,range:0.1...0.2,label:"\(Int((workspace.preferences.logoSize*100).rounded()))%",id:"qr-logo-size")
                    Stepper("Padding: \(workspace.preferences.logoPadding) module(s)",value:$workspace.preferences.logoPadding,in:1...2).font(.caption)
                    QRColorControl(title:"Logo background",value:$workspace.preferences.logoBackground,identifier:"qr-logo-background")
                    slider("Logo background opacity",value:$workspace.preferences.logoBackgroundOpacity,range:0...1,label:"\(Int((workspace.preferences.logoBackgroundOpacity*100).rounded()))%",id:"qr-logo-opacity")
                    Text("QR modules leave a clear area around the logo. Placement or size may adjust to preserve QR markers. A transparent logo background reveals the code background.").font(.caption).foregroundStyle(.secondary)
                } else { Text("PNG, JPEG or HEIC · up to 8 MiB / 40 MP").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top,8)
        }
    }
    private var exportOptions: some View {
        DisclosureGroup("Export Options",isExpanded:$workspace.preferences.exportExpanded) {
            VStack(alignment:.leading,spacing:8) {
                Picker("Format",selection:$workspace.preferences.format) { ForEach(QRExportFormat.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("qr-format")
                Picker("Minimum size",selection:$workspace.preferences.exportSize) { ForEach([512,1024,2048,4096],id:\.self) { Text("\($0) px").tag($0) } }.pickerStyle(.menu)
                Text("The actual size uses whole pixels per module. SVG keeps QR geometry scalable; an imported logo stays raster.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top,8)
        }
    }
    private func preview(maxSide: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Preview").font(.headline); Spacer(); if workspace.busy || workspace.preparing || workspace.loadingLogo { ProgressView().controlSize(.small).accessibilityLabel("Processing QR") } }.frame(minHeight:24)
            GeometryReader { g in
                let side = max(1,min(g.size.width,g.size.height))
                ZStack {
                    QRCheckerboard().clipShape(RoundedRectangle(cornerRadius:8))
                    if let artifact = workspace.artifact {
                        Image(decorative:artifact.image,scale:1).resizable().interpolation(.none).scaledToFit()
                            .accessibilityLabel(workspace.isCurrent ? "Generated QR code" : "Previous QR preview, out of date")
                    } else { VStack(spacing:8) { Image(systemName:"qrcode").font(.system(size:44)).foregroundStyle(.secondary); Text("Your QR code will appear here").font(.caption).foregroundStyle(.secondary) } }
                }.frame(width:side,height:side).frame(maxWidth:.infinity,maxHeight:.infinity)
                    .accessibilityIdentifier("qr-preview")
            }.frame(height:maxSide)
            VStack(alignment:.leading,spacing:4) {
                Label(workspace.status,systemImage:workspace.issue != nil ? "exclamationmark.triangle" : workspace.canOutput ? "checkmark.circle" : "info.circle")
                    .font(.caption).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("qr-status")
                if let a = workspace.artifact {
                    Text("\(workspace.isCurrent ? "" : "Previous · ")Version \(a.matrix.version) · \(a.matrix.size) × \(a.matrix.size) modules · \(a.side) × \(a.side) px").font(.caption).foregroundStyle(.secondary)
                    if a.verifiedSide != a.image.width && a.verification.passed { Text("Readable at \(a.verifiedSide) × \(a.verifiedSide) px · export size check").font(.caption).foregroundStyle(.secondary) }
                    if a.logoMoved { Label("Logo placed near center to preserve QR markers",systemImage:"info.circle").font(.caption) }
                    if a.logoReduced { Text("Logo reduced to keep QR markers clear").font(.caption).foregroundStyle(.secondary) }
                    if let fraction = a.logoWidthFraction {
                        Text("Logo area: \(Int((fraction*100).rounded()))% of code width").font(.caption).foregroundStyle(.secondary)
                        if a.enlargesLogo { Text("The logo will be enlarged beyond its pixel resolution.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let message = workspace.copyMessage ?? fileMessage { Text(message).font(.caption).accessibilityIdentifier("qr-feedback") }
            }.frame(minHeight:46,alignment:.topLeading)
            HStack {
                Button("Copy Image",systemImage:"doc.on.doc") { workspace.prepare(.png) { QRCodeClipboard.copy($0.data); workspace.copied() } }
                    .disabled(!workspace.canOutput).accessibilityIdentifier("qr-copy")
                Spacer()
                Button("Export \(workspace.preferences.format.rawValue)…",systemImage:"square.and.arrow.up") {
                    workspace.prepare(workspace.preferences.format) { output = $0; exporting = true }
                }.disabled(!workspace.canOutput || exporting).accessibilityIdentifier("qr-export")
            }.controlSize(.regular)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).animation(animation,value:workspace.artifact?.logoMoved)
            .animation(animation,value:workspace.artifact?.logoReduced)
            .animation(animation,value:workspace.issue).animation(animation,value:workspace.copyMessage ?? fileMessage)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String, id: String) -> some View {
        VStack(alignment:.leading,spacing:3) { HStack { Text(title); Spacer(); Text(label).monospacedDigit().foregroundStyle(.secondary) }.font(.caption); Slider(value:value,in:range).accessibilityLabel(title).accessibilityIdentifier(id) }
    }
}
private struct QRColorControl: View {
    let title: String
    @Binding var value: QRColor
    let identifier: String
    @State private var hex = ""
    var body: some View {
        HStack {
            Text(title).frame(maxWidth:.infinity,alignment:.leading)
            QRCodeColorWell(color:$value,label:title,identifier:identifier)
                #if os(macOS)
                .frame(width:44,height:28)
                #else
                .frame(width:44,height:44)
                #endif
            TextField("#RRGGBB",text:$hex).font(.caption.monospaced()).textFieldStyle(.roundedBorder).frame(width:88)
                .accessibilityLabel(title+" hexadecimal").accessibilityIdentifier(identifier+"-hex")
                .onSubmit { if let color = QRColor(hex:hex) { value = color }; hex = value.hex }
                .onChange(of:hex) { _,text in if let color = QRColor(hex:text), color != value { value = color } }
        }.onAppear { hex = value.hex }.onChange(of:value) { _,v in if QRColor(hex:hex) != v { hex = v.hex } }
    }
}
private struct QRCheckerboard: View {
    var body: some View {
        Canvas { context,size in
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.95)))
            for y in 0...Int(size.height/12) { for x in 0...Int(size.width/12) where (x+y)%2 == 0 {
                context.fill(Path(CGRect(x:x*12,y:y*12,width:12,height:12)),with:.color(Color(white:0.82)))
            } }
        }.accessibilityHidden(true)
    }
}
