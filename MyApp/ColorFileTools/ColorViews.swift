import SwiftUI

extension SRGBA {
    var displayColor:Color {Color(.sRGB,red:r,green:g,blue:b,opacity:a)}
}
struct ColorCheckerboard:View {
    var body:some View {Canvas { context,size in
        let tile:CGFloat=12
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.white))
        for y in 0...Int(size.height/tile){for x in 0...Int(size.width/tile) where (x+y)%2==0 {context.fill(Path(CGRect(x:CGFloat(x)*tile,y:CGFloat(y)*tile,width:tile,height:tile)),with:.color(.gray.opacity(0.3)))}}
    }.accessibilityHidden(true)}
}
struct LocalColorControls:View {
    @Binding var text:String
    var title:String
    @State private var hsl=false
    private var color:SRGBA?{try? ColorParser.parse(text)}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Text(title).font(.headline)
            TextField("#77E375 · rgb() · hsl()",text:$text).textFieldStyle(.roundedBorder).font(.system(.body,design:.monospaced)).autocorrectionDisabled()
            ZStack {ColorCheckerboard();if let color{color.displayColor}}
                .frame(height:64).clipShape(RoundedRectangle(cornerRadius:8)).accessibilityLabel("Color preview")
            Picker("Channels",selection:$hsl){Text("RGB").tag(false);Text("HSL").tag(true)}.pickerStyle(.segmented)
            ForEach(0..<4){index in
                HStack {
                    Text((hsl ? ["Hue","Saturation","Lightness","Alpha"]:["Red","Green","Blue","Alpha"])[index]).frame(width:78,alignment:.leading)
                    Slider(value:channel(index),in:0...(hsl && index==0 ? 360:1)).accessibilityLabel((hsl ? ["Hue","Saturation","Lightness","Alpha"]:["Red","Green","Blue","Alpha"])[index])
                    TextField("Channel",value:numericChannel(index),format:.number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder).frame(width:76).accessibilityLabel((hsl ? ["Hue degrees","Saturation percent","Lightness percent","Alpha percent"]:["Red 0–255","Green 0–255","Blue 0–255","Alpha percent"])[index])
                }
            }
            HStack {ForEach(["#000000","#FFFFFF","#77E375","#2563EB","#9333EA","#EF4444"],id:\.self){hex in
                Button {text=hex} label:{RoundedRectangle(cornerRadius:4).fill((try! ColorParser.parse(hex)).displayColor).frame(width:26,height:26).overlay(RoundedRectangle(cornerRadius:4).stroke(.secondary.opacity(0.4)))}.buttonStyle(.plain).accessibilityLabel("Use \(hex)")
            }}
            if !text.isEmpty,color == nil {Text((try? resultError()) ?? "Unsupported color").font(.caption).foregroundStyle(.secondary)}
        }.padding(14).background(.background,in:RoundedRectangle(cornerRadius:10))
    }
    private func resultError()throws->String {do{_=try ColorParser.parse(text);return ""}catch{return error.localizedDescription}}
    private func components()->[Double] {let c=color ?? .black;if hsl{let h=c.hsl;return [h.h,h.s,h.l,c.a]};return [c.r,c.g,c.b,c.a]}
    private func valueText(_ i:Int)->String {let c=components()[i];return String(format:hsl && i==0 ? "%.0f°": "%.0f%%",c*(hsl && i==0 ? 1:100))}
    private func numericChannel(_ index:Int)->Binding<Double>{Binding(get:{components()[index]*(hsl ? (index==0 ? 1:100):(index==3 ? 100:255))},set:{value in
        var c=components();c[index]=value/(hsl ? (index==0 ? 1:100):(index==3 ? 100:255))
        if hsl{text="hsl(\(c[0]) \(c[1]*100)% \(c[2]*100)% / \(c[3]))"}
        else{text="rgb(\(c[0]*255) \(c[1]*255) \(c[2]*255) / \(c[3]))"}
    })}
    private func channel(_ index:Int)->Binding<Double>{Binding(get:{components()[index]},set:{value in
        var c=components();c[index]=value
        guard let color=try? (hsl ? SRGBA.hsl(c[0],c[1],c[2],c[3]):SRGBA(c[0],c[1],c[2],c[3])) else{return}
        // Use full Double precision, never round through an 8-bit HEX intermediate.
        text="rgb(\(color.r*255) \(color.g*255) \(color.b*255) / \(color.a))"
    })}
}
struct ColorConverterView:View {
    @Bindable var workspace:ColorWorkspace
    var body:some View {
        GeometryReader {g in
            ScrollView {
                let layout=g.size.width>=760 ? AnyLayout(HStackLayout(alignment:.top,spacing:12)):AnyLayout(VStackLayout(spacing:12))
                layout {
                    LocalColorControls(text:$workspace.input,title:"Input").frame(maxWidth:460)
                    VStack(alignment:.leading,spacing:16){
                        HStack {Text("Representations").font(.headline);Spacer();Button("Clear"){workspace.input=""}}
                        Picker("Decimal places",selection:$workspace.precision){ForEach(0...6,id:\.self){Text("\($0)").tag($0)}}
                        if let color=try? ColorParser.parse(workspace.input) {
                            ForEach(color.representations(precision:workspace.precision),id:\.0){name,value in
                                VStack(alignment:.leading){HStack{Text(name).font(.headline);Spacer();Button("Copy"){TextClipboard.copy(value)}};Text(value).font(.system(.body,design:.monospaced)).textSelection(.enabled)}
                            }
                            Button("Copy all"){TextClipboard.copy(color.representations(precision:workspace.precision).map{"\($0.0): \($0.1)"}.joined(separator:"\n"))}
                            Text("sRGB · HEX rounds channels to 8 bits. RGB/HSL rounding affects presentation only.").font(.caption).foregroundStyle(.secondary)
                        } else {ContentUnavailableView("Enter a color",systemImage:"paintpalette",description:Text("HEX, RGB and HSL with optional alpha."))}
                    }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:10))
                }.padding(12)
            }
        }
    }
}
struct ContrastView:View {
    @Bindable var workspace:ColorWorkspace
    private var result:ContrastResult? {guard let fg=try? ColorParser.parse(workspace.foreground),let bg=try? ColorParser.parse(workspace.background),let backdrop=try? ColorParser.parse(workspace.backdrop) else{return nil};return try? ContrastCalculator.evaluate(foreground:fg,background:bg,backdrop:backdrop)}
    var body:some View {
        GeometryReader {g in ScrollView {
            let layout=g.size.width>=900 ? AnyLayout(HStackLayout(alignment:.top,spacing:12)):AnyLayout(VStackLayout(spacing:12))
            layout {
                VStack {LocalColorControls(text:$workspace.foreground,title:"Foreground");Button("Swap foreground / background",systemImage:"arrow.up.arrow.down"){let t=workspace.foreground;workspace.foreground=workspace.background;workspace.background=t}.buttonStyle(.bordered);LocalColorControls(text:$workspace.background,title:"Background")}.frame(maxWidth:460)
                VStack(alignment:.leading,spacing:14){
                    Text("WCAG 2.2 contrast").font(.headline)
                    VStack(alignment:.leading,spacing:5){Text("Opaque backdrop").font(.callout);TextField("Backdrop color",text:$workspace.backdrop).textFieldStyle(.roundedBorder).accessibilityLabel("Opaque backdrop color")}
                    if let r=result {
                        Text(String(format:"%.2f : 1",r.ratio)).font(.largeTitle.monospacedDigit())
                        VStack(alignment:.leading){Text("Everyday developer tasks").font(.body);Text("Large text sample").font(.system(size:24));Text("Effective \(r.foreground.hex) on \(r.background.hex)").font(.caption)}.padding().frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(r.foreground.displayColor).background(r.background.displayColor,in:RoundedRectangle(cornerRadius:8))
                        ForEach(r.checks,id:\.0){name,pass in HStack{Image(systemName:pass ? "checkmark.circle":"xmark.circle");Text(name);Spacer();Text(pass ? "Pass":"Fail").bold()}}
                        Button("Copy report"){TextClipboard.copy("WCAG 2.2 · \(r.ratio):1\nForeground: \(workspace.foreground)\nBackground: \(workspace.background)\nBackdrop: \(workspace.backdrop)\nEffective: \(r.foreground.hex) / \(r.background.hex)\n"+r.checks.map{"\($0.0): \($0.1 ? "Pass":"Fail")"}.joined(separator:"\n"))}
                    } else {Text("Enter valid foreground/background colors and an opaque backdrop.")}
                    Text("Large text: at least 18 pt regular or 14 pt bold (24 / 18.67 CSS px). Decisions use the unrounded ratio. Alpha is composited in encoded sRGB. Non-text is a color-pair advisory, not an accessibility certification.").font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:10))
            }.padding(12)
        }}
    }
}
