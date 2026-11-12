import AppKit
import SwiftUI
import Observation
import Darwin
@testable import Developer_Toolbox
@main struct PKINativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() { setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular); Task { @MainActor in do { try await run(); print("PKI_NATIVE_PASSED"); exit(0) } catch { print("PKI_NATIVE_FAILED \(error)"); exit(1) } }; NSApplication.shared.run() }
    @MainActor static func check(_ value: Bool,_ name: String) throws { guard value else { throw Failure.check(name) }; print("PKI_OK \(name)") }
    @MainActor static func views<T:NSView>(_ type:T.Type,_ root:NSView)->[T] { ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { views(type,$0) } }
    @MainActor static func pause(_ host:NSView,_ ms:Int=180) async { try? await Task.sleep(for:.milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func screenshot(_ host:NSView,_ name:String) throws { guard let image=host.bitmapImageRepForCachingDisplay(in:host.bounds) else{return};host.cacheDisplay(in:host.bounds,to:image);if let png=image.representation(using:.png,properties:[:]){try png.write(to:URL(fileURLWithPath:"/tmp/pki-\(name).png"))} }
    @MainActor static func run() async throws {
        if CommandLine.arguments.contains("--export-only") { try await exportFlow(); return }
        let engine=PKIEngine(), generated=try await engine.generate(PKIGenerationDraft(),csr:false)
        let key=try await engine.exportKey(token:await engine.token(),key:generated.key.handle,password:"synthetic",unencrypted:false)
        let csr=try await engine.generate(PKIGenerationDraft(),csr:true)
        let pfx=try await engine.createPFX(privateKey:Data(key.pem.utf8),certificate:generated.object.data,extras:Data(),password:"synthetic",keyPassword:"synthetic",name:"PUBLIC TEST")
        let window=NSWindow(contentRect:.init(x:40,y:40,width:1200,height:840),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.makeKeyAndOrderFront(nil)
        for tool in PKITool.allCases where tool != .expiry {
            let s=PKIWorkspace(tool:tool);s.masked=false
            switch tool {
            case .certificate: break
            case .csr:s.mode=1;s.input=csr.object.pem
            case .converter:s.input=generated.object.pem+"\n"+generated.object.pem
            case .pfx:try s.load(pfx,name:"synthetic.p12",slot:0);s.password="synthetic"
            case .chain:s.input=generated.object.pem;s.roots=generated.object.pem;s.hostname="localhost"
            case .matcher:s.input=generated.object.pem;s.second=key.pem;s.password="synthetic"
            case .key:s.input=key.pem;s.password="synthetic"
            default:break
            }
            let host=NSHostingView(rootView:PKIWorkspaceView(workspace:s));window.contentView=host;await pause(host)
            await s.run().value;await pause(host)
            try check(s.result != nil,"tool \(tool.rawValue) source→result: \(s.message)")
            let editor=views(NSTextView.self,host).first(where:{$0.isEditable && !$0.isHidden})
            let identity=editor.map(ObjectIdentifier.init)
            if let editor,tool == .converter {
                try check(editor.enclosingScrollView?.rulersVisible != true,"plain input has no gutter stripe")
                window.makeFirstResponder(editor);editor.undoManager?.removeAllActions();editor.breakUndoCoalescing();let original=editor.string
                editor.insertText(" ",replacementRange:.init(location:editor.string.utf16.count,length:0));await pause(host)
                try check(s.result == nil,"typing invalidates result")
                editor.undoManager?.undo();await pause(host);try check(editor.string==original,"native Undo")
                editor.undoManager?.redo();await pause(host);try check(editor.string==original+" ","native Redo")
                await s.run().value;await pause(host)
            }
            window.appearance=NSAppearance(named:.darkAqua);await pause(host);try screenshot(host,"\(tool.rawValue)-dark")
            window.setContentSize(.init(width:390,height:840));await pause(host)
            if let identity { try check(views(NSTextView.self,host).contains { ObjectIdentifier($0)==identity },"stable editor at narrow width \(tool.rawValue)") }
            withAnimation(.easeInOut(duration:0.2)){s.inputCollapsed=true};await pause(host);withAnimation(.easeInOut(duration:0.2)){s.inputCollapsed=false};await pause(host)
            try check(s.result != nil,"collapse retains result \(tool.rawValue)")
            window.appearance=NSAppearance(named:.aqua);window.setContentSize(.init(width:1200,height:840));await pause(host)
            if tool == .certificate { try screenshot(host,"69-light") }
        }
        try await motion(window)
        try await performance(window,certificate:generated.object.pem)
        try check(PKIWorkspace(tool:.key).input.isEmpty,"fresh window has no private source")
        window.close()
    }
    @MainActor static func objectValue(_ element:NSObject,_ key:String) -> AnyObject? {
        let selector = NSSelectorFromString(key)
        return element.responds(to:selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }
    @MainActor static func boolValue(_ element:NSObject,_ key:String) -> Bool {
        let selector = NSSelectorFromString(key)
        guard element.responds(to:selector) else { return false }
        typealias Getter = @convention(c) (AnyObject,Selector) -> Bool
        return unsafeBitCast(element.method(for:selector),to:Getter.self)(element,selector)
    }
    @MainActor static func elements(_ root:Any,_ seen:inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let element = root as? NSObject, seen.insert(ObjectIdentifier(element)).inserted else { return [] }
        return [element] + ((objectValue(element,"accessibilityChildren") as? [Any]) ?? []).flatMap { elements($0,&seen) }
    }
    @MainActor static func find(_ identifier:String) -> NSObject? {
        var seen:Set<ObjectIdentifier> = []
        return NSApp.windows.flatMap { elements($0,&seen) }.first { objectValue($0,"accessibilityIdentifier") as? String == identifier }
    }
    @MainActor static func exportFlow() async throws {
        NSApp.accessibilitySetValue(true,forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        let s=PKIWorkspace(tool:.certificate);await s.run().value;s.newPassword="synthetic export";s.confirmPassword=s.newPassword
        let host=NSHostingView(rootView:PKIWorkspaceView(workspace:s));let window=NSWindow(contentRect:.init(x:40,y:40,width:1200,height:840),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);await pause(host,400)
        try check(s.result != nil,"result survives mounting generation form: \(s.message)");guard let button=find("pki-export-private") else { var seen:Set<ObjectIdentifier>=[];let ids=NSApp.windows.flatMap { elements($0,&seen) }.compactMap { objectValue($0,"accessibilityIdentifier") as? String };print("PKI_AX_IDS \(ids)");throw Failure.check("private export AX element absent") };try check(boolValue(button,"accessibilityPerformPress"),"open private key export sheet");await pause(host,400)
        guard let confirm=find("pki-export-confirm") else { throw Failure.check("password sheet confirm AX element absent") };try check(boolValue(confirm,"isAccessibilityEnabled"),"encrypted export enabled with matching passwords")
        try check(boolValue(confirm,"accessibilityPerformPress"),"confirm protected export")
        for _ in 0..<100 { if s.pendingExport != nil { break };await pause(host,20) };await pause(host,700)
        try check(s.pendingExport != nil,"protected artifact ready")
        try check(find("pki-export-confirm")==nil,"password sheet dismissed before file presenter")
        try check(!window.sheets.isEmpty,"native file exporter presented")
        print("PKI_EXPORT_PRESENTER sheet_count=\(window.sheets.count)")
        for panel in NSApp.windows.compactMap({$0 as? NSSavePanel}) { panel.cancel(nil) }
        await pause(host,200);window.close()
    }
    @MainActor static func motion(_ window:NSWindow) async throws {
        let state=PKIProbeEditorState();state.text=(0..<250).map { "row \($0) "+String(repeating:"x",count:75) }.joined(separator:"\n")
        let host=NSHostingView(rootView:PKIProbeEditor(state:state));window.contentView=host;window.setContentSize(.init(width:640,height:420));await pause(host,250)
        let editor=try unwrap(views(NSTextView.self,host).first),scroll=try unwrap(editor.enclosingScrollView)
        state.target=NSRange(location:state.text.utf16.count-50,length:30);state.jump+=1
        var points:[Int]=[];for _ in 0..<12 { await pause(host,30);points.append(Int(scroll.contentView.bounds.minY)) }
        try check(Set(points).count>2 && (points.last ?? 0)>100,"smooth offscreen source jump")
        print("PKI_MOTION \(points)")
        state.reduced=true;state.target=NSRange(location:0,length:10);state.jump+=1;await pause(host,100);try check(scroll.contentView.bounds.minY<60,"Reduce Motion direct destination")
        state.hidden=true;await pause(host);state.hidden=false;await pause(host);try check(editor.string==state.text,"collapse leaves source intact")
    }
    static func unwrap<T>(_ value:T?) throws -> T { guard let value else { throw Failure.check("missing native view") }; return value }
    @MainActor static func performance(_ window:NSWindow,certificate:String) async throws {
        var gaps:[Double]=[];var last=ContinuousClock.now
        let heartbeat=Task { @MainActor in while !Task.isCancelled { try? await Task.sleep(for:.milliseconds(10));let now=ContinuousClock.now,d=last.duration(to:now).components;gaps.append(Double(d.seconds)+Double(d.attoseconds)/1e18);last=now } }
        for algorithm in [PKIAlgorithm.p256,.rsa2048,.rsa4096] { let start=ContinuousClock.now;var draft=PKIGenerationDraft();draft.algorithm=algorithm;let e=PKIEngine();_ = try await e.generate(draft,csr:false);print("PKI_PERF key=\(algorithm.rawValue) duration=\(start.duration(to:.now))") }
        let folder=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let bundle=Data(Array(repeating:certificate,count:64).joined(separator:"\n").utf8)
        for i in 0..<64 { try bundle.write(to:folder.appendingPathComponent("bundle-\(i).pem")) }
        let w=PKIExpirationWorkspace(),host=NSHostingView(rootView:PKIExpirationView(workspace:w));window.contentView=host;await pause(host);let start=ContinuousClock.now;w.scan([folder])
        while w.busy { await pause(host,15) }
        try check(w.report?.rows.count==4096,"4096 expiration occurrences")
        print("PKI_PERF batch_bytes=\(bundle.count*64) rows=\(w.report?.rows.count ?? 0) duration=\(start.duration(to:.now))")
        await pause(host);try screenshot(host,"76-report")
        heartbeat.cancel();var r=rusage();getrusage(RUSAGE_SELF,&r);print("PKI_PERF peak_rss_bytes=\(r.ru_maxrss) main_actor_max_gap_ms=\((gaps.max() ?? 0)*1000)")
    }
}
@MainActor @Observable final class PKIProbeEditorState { var text="";var masked=false;var hidden=false;var target:NSRange?;var jump=0;var reduced=false }
struct PKIProbeEditor:View {
    @Bindable var state:PKIProbeEditorState
    var body:some View { PKISourceEditor(text:$state.text,title:"Synthetic source",file:nil,secret:false,masked:$state.masked,wordWrap:true,hidden:state.hidden,target:state.target,jump:state.jump,reduceMotion:state.reduced,clearEpoch:0,open:{},edit:{}) }
}
