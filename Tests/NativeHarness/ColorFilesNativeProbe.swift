import AppKit
import SwiftUI
import ImageIO
import Darwin
import Observation
@testable import Developer_Toolbox
@main struct ColorFilesNativeProbe {
    enum Failure:Error{case check(String)}
    @MainActor static func main(){setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.regular);Task{@MainActor in do{try await run();print("COLOR_FILES_NATIVE_PASSED");exit(0)}catch{print("COLOR_FILES_NATIVE_FAILED \(error)");exit(1)}};NSApplication.shared.run()}
    @MainActor static func check(_ value:Bool,_ name:String)throws{guard value else{throw Failure.check(name)};print("COLOR_FILES_OK \(name)")}
    @MainActor static func views<T:NSView>(_ type:T.Type,_ root:NSView)->[T]{((root as? T).map{[$0]} ?? [])+root.subviews.flatMap{views(type,$0)}}
    @MainActor static func pause(_ host:NSView,_ ms:Int=180)async{try? await Task.sleep(for:.milliseconds(ms));host.layoutSubtreeIfNeeded();host.displayIfNeeded()}
    @MainActor static func run()async throws{
        if CommandLine.arguments.contains("--svg-layout-only"){try await svgLayout();return}
        if CommandLine.arguments.contains("--snippets-only"){try snippets();return}
        if CommandLine.arguments.contains("--performance"){try await performance();return}
        let window=NSWindow(contentRect:.init(x:30,y:30,width:1200,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.makeKeyAndOrderFront(nil)
        let c=ColorWorkspace(),cc=ColorWorkspace();c.input="hsl(120 50% 40% / 0.7)"
        for view in [AnyView(ColorConverterView(workspace:c)),AnyView(ContrastView(workspace:cc))]{let host=NSHostingView(rootView:view);window.contentView=host;await pause(host);window.setContentSize(.init(width:390,height:800));await pause(host);window.appearance=NSAppearance(named:.darkAqua);await pause(host);window.setContentSize(.init(width:1200,height:800));try check(!views(NSTextField.self,host).isEmpty,"color controls mounted narrow/dark");try screenshot(host,"color")}
        let svg=SVGWorkspace(),curl=CurlWorkspace(),connection=ConnectionWorkspace();curl.masked=false;connection.masked=false
        let samples=["<svg xmlns='http://www.w3.org/2000/svg'><text>é 🐱</text></svg>","curl 'https://example.com' --json '{\"x\":1}'","postgresql://user:synthetic@localhost/db"]
        let roots=[AnyView(SVGWorkspaceView(workspace:svg)),AnyView(CurlWorkspaceView(workspace:curl)),AnyView(ConnectionWorkspaceView(workspace:connection))]
        for i in 0..<3 {
            let host=NSHostingView(rootView:roots[i]);window.contentView=host;await pause(host)
            guard let input=views(NSTextView.self,host).first(where:{$0.isEditable}) else{throw Failure.check("editor absent")}
            let id=ObjectIdentifier(input);window.makeFirstResponder(input);input.insertText(samples[i],replacementRange:.init(location:0,length:input.string.utf16.count));await pause(host)
            switch i{case 0:svg.run();case 1:curl.run();default:connection.run()}
            for _ in 0..<300{if !svg.busy && !curl.busy && !connection.busy{break};await pause(host,20)}
            try check(i==0 ? svg.result != nil : i==1 ? curl.result != nil : connection.document != nil,"native source→result \(i)")
            input.undoManager?.removeAllActions();input.breakUndoCoalescing();window.makeFirstResponder(input);input.setSelectedRange(.init(location:input.string.utf16.count,length:0));input.insertText(" ",replacementRange:input.selectedRange());await pause(host)
            input.undoManager?.undo();await pause(host);try check(input.string==samples[i],"native Undo \(i)")
            input.undoManager?.redo();await pause(host);try check(input.string==samples[i]+" ","native Redo \(i)")
            window.setContentSize(.init(width:390,height:800));window.appearance=NSAppearance(named:.aqua);await pause(host)
            try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==id},"layout/theme editor identity \(i)")
            window.setContentSize(.init(width:1200,height:800));await pause(host)
            if i==1{curl.masked=true;await pause(host);try check(!input.isSelectable || input.isHidden || input.superview?.isHidden==true || window.firstResponder !== input,"private editor hide resigns focus")}
        }
        let context=CGContext(data:nil,width:640,height:480,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.4,green:0.7,blue:0.3,alpha:0.5));context.fill(CGRect(x:0,y:0,width:640,height:480))
        let bytes=try ImagePipeline.encode(context.makeImage()!,format:.png,quality:1)
        for tool in 63...65 {
            let w=ImageWorkspace(resize:tool==64),host=NSHostingView(rootView:ImageWorkspaceView(workspace:ImageWorkspace(),tool:tool))
            host.rootView=ImageWorkspaceView(workspace:w,tool:tool);window.contentView=host;w.load(data:bytes)
            for _ in 0..<300{if !w.busy{break};await pause(host,20)}
            w.run();for _ in 0..<300{if !w.busy{break};await pause(host,20)}
            try check(w.result != nil,"image workspace \(tool) complete")
            window.setContentSize(.init(width:390,height:800));await pause(host);window.setContentSize(.init(width:1200,height:800));await pause(host)
            try check(w.source?.data==bytes,"image snapshot survives resize \(tool)");try screenshot(host,"image-\(tool)")
        }
        try await sourceMotion(window)
        // Snapshot-free fresh windows and safe shell/connection operations.
        try check(CurlWorkspace().input.isEmpty && ConnectionWorkspace().input.isEmpty && ImageWorkspace().source==nil,"memory-only new sessions")
        try snippets()
        window.close()
    }
    @MainActor static func svgLayout()async throws{
        let workspace=SVGWorkspace()
        let host=NSHostingView(rootView:SVGWorkspaceView(workspace:workspace))
        let window=NSWindow(contentRect:.init(x:30,y:30,width:1200,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.contentView=host;window.makeKeyAndOrderFront(nil);await pause(host)
        guard let input=views(NSTextView.self,host).first(where:{$0.isEditable}),let scroll=input.enclosingScrollView else{throw Failure.check("SVG input")}
        let identity=ObjectIdentifier(input)
        for dark in [false,true] {
            window.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);await pause(host)
            try screenshot(host,dark ? "svg-dark":"svg-light")
            try check(!scroll.rulersVisible,"SVG plain input has no ruler/separator")
        }
        window.makeFirstResponder(input);input.insertText("<svg xmlns='http://www.w3.org/2000/svg'/>",replacementRange:.init(location:0,length:0));await pause(host)
        input.undoManager?.removeAllActions();input.breakUndoCoalescing();input.insertText(" ",replacementRange:.init(location:input.string.utf16.count,length:0));await pause(host)
        input.undoManager?.undo();await pause(host);try check(!input.string.hasSuffix(" "),"SVG Undo")
        input.undoManager?.redo();await pause(host);try check(input.string.hasSuffix(" "),"SVG Redo")
        window.setContentSize(.init(width:390,height:800));await pause(host)
        try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==identity} && !scroll.rulersVisible,"SVG narrow layout keeps editor and no ruler")
        window.close()
    }
    @MainActor static func sourceMotion(_ window:NSWindow)async throws{
        let state=ColorFilesJumpState()
        state.text="Server=localhost;"+(0..<180).map{"Application Name='row \($0) "+String(repeating:"x",count:75)+"';"}.joined()
        let document=try ConnectionProcessor.parse(state.text,profile:.sqlServer),target=document.fields.last!.range
        let host=NSHostingView(rootView:ColorFilesJumpView(state:state));window.contentView=host;window.setContentSize(.init(width:640,height:420));await pause(host,350)
        guard let editor=views(NSTextView.self,host).first,let scroll=editor.enclosingScrollView else{throw Failure.check("source navigation editor")}
        for wrap in [true,false] {
            state.wrap=wrap;await pause(host,300);scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView);await pause(host,80)
            state.reduced=false;state.target=target;state.jump+=1
            var points:[CGPoint]=[]
            for _ in 0..<12 {await pause(host,35);points.append(scroll.contentView.bounds.origin)}
            let positions=points.map{wrap ? $0.y:$0.x},distinct=Set(positions.map{Int($0)})
            print("SOURCE_MOTION wrap=\(wrap) samples=\(positions)")
            try check(distinct.count>2 && (positions.last ?? 0)>100,"smooth offscreen source jump wrap=\(wrap)")
            state.target=document.fields[0].range;state.jump+=1;await pause(host,40);state.target=target;state.jump+=1;await pause(host,450)
            try check((wrap ? scroll.contentView.bounds.minY:scroll.contentView.bounds.minX)>100,"latest source navigation wins wrap=\(wrap)")
            state.reduced=true;state.target=document.fields[0].range;state.jump+=1;await pause(host,100)
            try check((wrap ? scroll.contentView.bounds.minY:scroll.contentView.bounds.minX)<60,"Reduce Motion jump reaches start wrap=\(wrap)")
        }
    }
    @MainActor static func screenshot(_ view:NSView,_ name:String)throws{
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if let png=bitmap.representation(using:.png,properties:[:]){let url=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("color-files-"+name+".png");try png.write(to:url);print("SCREENSHOT \(url.path)")}
    }
    @MainActor static func performance()async throws{
        var gaps:[Double]=[],last=ContinuousClock.now
        let heartbeat=Task{@MainActor in while !Task.isCancelled{try? await Task.sleep(for:.milliseconds(10));let now=ContinuousClock.now,d=last.duration(to:now).components;gaps.append(Double(d.seconds)+Double(d.attoseconds)/1e18);last=now}}
        for (w,h) in [(4000,3000),(8000,5000)] {
            let summary=try await Task.detached{()throws->String in
                let start=ContinuousClock.now
                let bytes:Data=try autoreleasepool {
                let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.setFillColor(CGColor(red:0.3,green:0.7,blue:0.5,alpha:0.6));c.fill(CGRect(x:0,y:0,width:w,height:h))
                return try ImagePipeline.encode(c.makeImage()!,format:.png,quality:1)
                }
                let source=try ImagePipeline.load(bytes)
                var o=ImageOptions();o.mode = .fit;o.width=1000;o.height=1000;o.format = .jpeg
                let output=try ImagePipeline.transform(source,options:o)
                return "IMAGE_PERF \(w)x\(h) source_bytes=\(bytes.count) output_bytes=\(output.data.count) total=\(start.duration(to:.now))"
            }.value
            print(summary)
        }
        heartbeat.cancel();var usage=rusage();getrusage(RUSAGE_SELF,&usage)
        print("IMAGE_PERF peak_rss_bytes=\(usage.ru_maxrss) main_actor_max_gap_ms=\((gaps.max() ?? 0)*1000) samples=\(gaps.count)")
    }
    static func snippets()throws{
        let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("toolbox-generated-request-checks")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let request=try CurlProcessor.parse("curl 'https://example.com/test?x=%2F' --json '{\"message\":\"é 🐱\"}' -H 'X-Test: sample'")
        for language in RequestLanguage.allCases {
            let code=try RequestEmitters.generate(request,language:language).code
            try code.write(to:root.appendingPathComponent(language == .java ? "GeneratedRequest.java":"request."+language.fileExtension),atomically:true,encoding:.utf8)
        }
        print("GENERATED_FIXTURES \(root.path)")
    }
}

@MainActor @Observable final class ColorFilesJumpState {
    var text=""
    var target:NSRange?
    var jump=0
    var wrap=true
    var reduced=false
}
struct ColorFilesJumpView:View {
    @Bindable var state:ColorFilesJumpState
    var body:some View {var options=JSONEditorOptions();options.syntax = .plainText;options.wordWrap=state.wrap;return JSONTextEditor(text:$state.text,jumpTarget:state.target,jumpRequest:state.jump,animateJumps:!state.reduced,highlightJumps:true,focusOnJump:false,options:options,contentName:"Synthetic source navigation")}
}
