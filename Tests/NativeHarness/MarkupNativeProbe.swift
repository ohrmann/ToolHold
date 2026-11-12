import AppKit
import SwiftUI
import WebKit
@testable import Developer_Toolbox

@main struct MarkupNativeProbe {
    enum Failure: Error {case check(String)}
    @MainActor static func main() {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do {try await run();print("MARKUP_NATIVE_PASSED");exit(0)}
            catch {print("MARKUP_NATIVE_FAILED \(error)");exit(1)}
        };NSApplication.shared.run()
    }
    @MainActor static func check(_ value: Bool,_ name:String) throws {guard value else{throw Failure.check(name)};print("MARKUP_OK \(name)")}
    @MainActor static func views<T:NSView>(_ type:T.Type,_ view:NSView)->[T] {((view as? T).map{[$0]} ?? [])+view.subviews.flatMap{views(type,$0)}}
    @MainActor static func wait(_ w:MarkupWorkspace) async throws {for _ in 0..<1200 {if !w.busy{return};try await Task.sleep(for:.milliseconds(20))};throw Failure.check("worker timeout")}
    @MainActor static func pause(_ host:NSView,_ ms:Int=200) async {try? await Task.sleep(for:.milliseconds(ms));host.layoutSubtreeIfNeeded();host.displayIfNeeded()}
    @MainActor static func js(_ view:WKWebView,_ code:String) async throws -> Any? {try await view.evaluateJavaScript(code)}
    @MainActor static func run() async throws {
        let defaults=UserDefaults(suiteName:"toolbox.markup.native-tests")!;defaults.removePersistentDomain(forName:"toolbox.markup.native-tests")
        defer{defaults.removePersistentDomain(forName:"toolbox.markup.native-tests")}
        let window=NSWindow(contentRect:.init(x:60,y:60,width:1200,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Code & Markup — synthetic verification";window.makeKeyAndOrderFront(nil)
        if CommandLine.arguments.contains("--preview-consent-only") {try await previewConsent(window,defaults);window.close();return}
        if CommandLine.arguments.contains("--interactions-only") {try await interactions(window,defaults);window.close();return}
        if CommandLine.arguments.contains("--performance-only") {try await performance(window,defaults);window.close();return}
        let sources:[MarkupTool:String]=[.sql:"select a from t",.xml:"<r><a>😀</a></r>",.yaml:"a: [1, 2]",.html:"<p>Hello</p>",.css:"a { color: red; }",.javascript:"const x=1;",.markdown:"# Hello\n\n**bold**",.preview:"<h1>Hello</h1>",.mjml:"<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>"]
        for tool in CommandLine.arguments.contains("--preview-only") ? [] : MarkupTool.allCases {
            let w=MarkupWorkspace(tool,defaults:defaults);w.options.live=false
            let host=NSHostingView(rootView:CodeMarkupWorkspaceView(workspace:w));window.contentView=host
            await pause(host);w.input=sources[tool]!;w.run();try await wait(w);await pause(host)
            try check(w.result?.succeeded==true,"\(tool.rawValue) native flow")
            let inputs=views(NSTextView.self,host).filter{$0.isEditable}
            try check(inputs.count==1,"\(tool.rawValue) one input editor")
            let input=inputs[0],identity=ObjectIdentifier(input),original=w.input
            window.makeFirstResponder(input);input.setSelectedRange(NSRange(location:(input.string as NSString).length,length:0));input.insertText(" ",replacementRange:input.selectedRange())
            await pause(host,50);try check(w.input==original+" ","\(tool.rawValue) native edit")
            input.undoManager?.undo();await pause(host,50);try check(w.input==original,"\(tool.rawValue) Undo")
            input.undoManager?.redo();await pause(host,50);try check(w.input==original+" ","\(tool.rawValue) Redo")
            window.setContentSize(.init(width:390,height:800));window.appearance=NSAppearance(named:.darkAqua);await pause(host)
            try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==identity},"\(tool.rawValue) resize/theme identity")
            try check(w.input==original+" ","\(tool.rawValue) resize/theme data")
            window.setContentSize(.init(width:1200,height:800));window.appearance=NSAppearance(named:.aqua);await pause(host,80)
            w.disappeared()
        }
        let w=MarkupWorkspace(.preview,defaults:defaults);w.options.live=false;w.options.document=true
        let host=NSHostingView(rootView:CodeMarkupWorkspaceView(workspace:w));window.contentView=host;await pause(host)
        w.input="""
        <html><head><style>@import 'http://127.0.0.1:18765/style';p{background:url(http://127.0.0.1:18765/css)}</style></head><body>
        <script>window.__toolboxRan=true;fetch('http://127.0.0.1:18765/script')</script>
        <img src='http://127.0.0.1:18765/image' onerror='window.__toolboxRan=true'>
        <iframe src='http://127.0.0.1:18765/frame'></iframe><form action='http://127.0.0.1:18765/form'><input autofocus><button>send</button></form>
        <h1>Safe</h1>
        """+String(repeating:"<p>row</p>",count:150)+"</body></html>"
        w.run();try await wait(w);await pause(host,1800)
        guard let web=views(WKWebView.self,host).first else{throw Failure.check("webview missing")}
        for _ in 0..<50 {if (try? await js(web,"document.body.innerText.includes('Safe')")) as? Bool == true{break};await pause(host,100)}
        try check((try await js(web,"document.body.innerText.includes('Safe')")) as? Bool == true,"preview DOM rendered")
        try check((try await js(web,"typeof window.__toolboxRan")) as? String == "undefined","page scripts never executed")
        try check((try await js(web,"document.querySelectorAll('script,iframe,base,link').length")) as? Int == 0,"active elements absent")
        try check(!web.configuration.websiteDataStore.isPersistent,"ephemeral website data store")
        try check(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript,"page JS disabled")
        _=try await js(web,"scrollTo(0,900)");await pause(host,100)
        let before=(try await js(web,"scrollY")) as? Double ?? 0
        let input=views(NSTextView.self,host).first{$0.isEditable}!,identity=ObjectIdentifier(input)
        w.input=w.input.replacingOccurrences(of:"Safe",with:"Updated");w.run();try await wait(w);await pause(host,600)
        let after=(try await js(web,"scrollY")) as? Double ?? 0
        print("SCROLL_MEASURE before=\(before) after=\(after)")
        try check(before>500 && abs(before-after)<3,"preview update retains scroll")
        try check((try await js(web,"document.body.innerText.includes('Updated')")) as? Bool == true,"latest preview revision visible")
        try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==identity},"preview update keeps native input")
        var widths:[CGFloat]=[];withAnimation(.easeInOut(duration:0.2)){w.collapsed=true}
        for _ in 0..<20 {await pause(host,16);widths.append(input.enclosingScrollView?.frame.width ?? 0)}
        try check(Set(widths.map{Int($0)}).count>2,"collapse has intermediate native geometry")
        withAnimation(.easeInOut(duration:0.2)){w.collapsed=false};await pause(host,280)
        try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==identity},"collapse preserves editor")
        window.setContentSize(.init(width:1000,height:760));await pause(host)
        if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:rep);try rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/toolbox-markup-mac-light.png"))}
        window.appearance=NSAppearance(named:.darkAqua);await pause(host)
        if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:rep);try rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/toolbox-markup-mac-dark.png"))}
        window.close()
    }
    /// Run with a sandbox-signed probe. --load-public-resources additionally contacts
    /// the public image/font URLs from the owner's reported template, only after opt-in.
    @MainActor static func previewConsent(_ window:NSWindow,_ defaults:UserDefaults) async throws {
        let w=MarkupWorkspace(.mjml,defaults:defaults)
        let host=NSHostingView(rootView:CodeMarkupWorkspaceView(workspace:w));window.contentView=host;await pause(host)
        let source="""
        <mjml><mj-head><mj-font name="Manrope" href="https://fonts.googleapis.com/css?family=Manrope"/>
        <mj-attributes><mj-all font-family="Manrope, Helvetica, Arial, sans-serif"/></mj-attributes></mj-head>
        <mj-body background-color="#070e07"><mj-section><mj-column>
        <mj-text color="#ffffff">A gift for you!</mj-text>
        <mj-image width="162px" src="https://github.com/ricfreire/mautic-theme-loyalclient/blob/main/assets/logo.png?raw=true"/>
        <mj-image width="180px" src="https://github.com/ricfreire/mautic-theme-loyalclient/blob/main/assets/gift.png?raw=true"/>
        <mj-raw><script>window.__previewScript=true;fetch('https://example.invalid/blocked')</script>
        <iframe src="https://example.invalid/blocked"></iframe></mj-raw>
        </mj-column></mj-section></mj-body></mjml>
        """
        w.input=source;w.pasted(automatic:true);try await wait(w);await pause(host,1800)
        guard let editor=views(NSTextView.self,host).first(where:{$0.isEditable}),let offline=views(WKWebView.self,host).first else{throw Failure.check("native preview missing")}
        let editorID=ObjectIdentifier(editor),compiled=w.output
        try check(w.result?.succeeded == true,"MJML compiled in sandbox")
        try check((try await js(offline,"document.body.innerText.includes('A gift for you!')")) as? Bool == true,"sandboxed offline preview visible")
        try check((try await js(offline,"performance.getEntriesByType('resource').filter(x=>x.name.startsWith('https:')).length")) as? Int == 0,"no external loads before consent")
        // Replace a snapshot while the first WK document is still being prepared/loaded.
        let race=MarkupPreviewCoordinator(failure:.constant(nil))
        let renderer=MarkupPreviewView(snapshot:w.snapshot!,failure:.constant(nil))
        let raceView=renderer.make(race)
        for i in 0..<6 {race.update(.init(nonce:"race\(i)",html:"<html><body>Race \(i)</body></html>",images:[:]),dark:false,markdown:false)}
        await pause(host,1000)
        try check((try await js(raceView,"document.body.innerText")) as? String == "Race 5","initial-load snapshot race publishes latest")
        race.stop()
        if CommandLine.arguments.contains("--load-public-resources") {
            w.setExternalResourcesAllowed(true);try await wait(w);await pause(host,1000)
            guard let online=views(WKWebView.self,host).first else{throw Failure.check("opt-in view missing")}
            try check(online !== offline,"consent creates isolated network-enabled renderer")
            var count=0
            for _ in 0..<120 {
                count=(try? await js(online,"Array.from(document.images).filter(x=>x.complete&&x.naturalWidth>0).length")) as? Int ?? 0
                if count == 2 {break};await pause(host,100)
            }
            try check(count==2,"two real HTTPS images loaded after explicit consent")
            let fontLoaded=(try await js(online,"Array.from(document.fonts).some(f=>f.family.includes('Manrope')&&f.status==='loaded')")) as? Bool == true
            try check(fontLoaded,"external Manrope stylesheet and font loaded")
            try check((try await js(online,"typeof window.__previewScript")) as? String == "undefined","page script still blocked after consent")
            try check((try await js(online,"document.querySelectorAll('script,iframe').length")) as? Int == 0,"active elements remain absent")
            try check(w.output==compiled,"remote loading preserves exact compiler HTML")
            window.appearance=NSAppearance(named:.darkAqua);await pause(host)
            try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==editorID},"consent/theme preserve native input")
            w.setExternalResourcesAllowed(false);try await wait(w);await pause(host,600)
            guard let blocked=views(WKWebView.self,host).first else{throw Failure.check("blocked renderer missing")}
            try check(blocked !== online,"block revokes renderer and its nonpersistent store")
            try check((try await js(blocked,"document.querySelectorAll('img[src^=https]').length")) as? Int == 0,"remote image references removed after blocking")
            w.setExternalResourcesAllowed(true);try await wait(w);await pause(host,200)
        }
        w.input=source.replacingOccurrences(of:"A gift for you!",with:"Updated gift")
        try check(!w.allowsExternalResources,"edit immediately revokes permission")
        w.run();try await wait(w);await pause(host,600)
        guard let final=views(WKWebView.self,host).first else{throw Failure.check("final renderer missing")}
        try check((try await js(final,"document.body.innerText.includes('Updated gift')")) as? Bool == true,"edit renders current offline snapshot")
        try check((try await js(final,"document.querySelectorAll('img[src^=https]').length")) as? Int == 0,"edit cannot auto-load new external URLs")
        try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==editorID},"edit/revoke retain native input identity")
        let fresh=MarkupWorkspace(.mjml,defaults:defaults)
        try check(!fresh.allowsExternalResources && fresh.input.isEmpty,"new session is offline and empty")
    }
    @MainActor static func interactions(_ window:NSWindow,_ defaults:UserDefaults) async throws {
        let w=MarkupWorkspace(.markdown,defaults:defaults)
        let host=NSHostingView(rootView:CodeMarkupWorkspaceView(workspace:w));window.contentView=host;await pause(host)
        guard let editor=views(NSTextView.self,host).first(where:{$0.isEditable}) else {throw Failure.check("editor missing")}
        window.makeFirstResponder(editor)
        editor.setMarkedText("中",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:0,length:0))
        await pause(host,600)
        try check(editor.hasMarkedText(),"native IME is composing")
        try check(!w.busy && w.result == nil,"IME does not trigger preview")
        editor.unmarkText();await pause(host,850);try await wait(w)
        try check(w.result?.succeeded == true,"IME commit renders preview")
        w.options.live=false
        let identity=ObjectIdentifier(editor)
        for _ in 0..<15 {editor.insertText("a",replacementRange:editor.selectedRange());await pause(host,16);try check(!editor.string.isEmpty,"rapid input retains native text")}
        w.input=String(repeating:"longword ",count:2500);w.options.wrap=false;await pause(host,450)
        let scroll=editor.enclosingScrollView!,before=scroll.contentView.bounds.origin.x
        w.show(.init(message:"Synthetic target",offset:18000,length:8));var positions:[CGFloat]=[]
        for _ in 0..<35 {await pause(host,16);positions.append(scroll.contentView.bounds.origin.x)}
        print("MARKUP_JUMP horizontal before=\(before) after=\(positions.last ?? 0) frames=\(Set(positions.map{Int($0)}).count)")
        try check((positions.last ?? 0)>1000 && Set(positions.map{Int($0)}).count>2,"Show Source horizontal smooth motion")
        w.options.wrap=true;await pause(host,400);w.show(.init(message:"Start",offset:0));await pause(host,450)
        w.show(.init(message:"End",offset:20000));var ys:[CGFloat]=[]
        for _ in 0..<35 {await pause(host,16);ys.append(scroll.contentView.bounds.origin.y)}
        try check((ys.last ?? 0)>200 && Set(ys.map{Int($0)}).count>2,"Show Source wrapped smooth motion")
        try check(views(NSTextView.self,host).contains{ObjectIdentifier($0)==identity},"wrap navigation retains editor")
        w.show(.init(message:"Old",offset:0));w.show(.init(message:"Latest",offset:20000));await pause(host,500)
        try check(scroll.contentView.bounds.origin.y>200,"latest navigation wins")
        JSONEditorNavigation.jump(editor,to:0,animated:false,focus:false)
        JSONEditorNavigation.jump(editor,to:20000,animated:false,focus:false)
        await pause(host,80)
        try check(scroll.contentView.bounds.origin.y>200,"nonanimated Reduce Motion navigation path")
    }

    @MainActor static func performance(_ window:NSWindow,_ defaults:UserDefaults) async throws {
        let w=MarkupWorkspace(.preview,defaults:defaults);w.options.live=false
        let host=NSHostingView(rootView:CodeMarkupWorkspaceView(workspace:w));window.contentView=host;await pause(host)
        for pass in 0..<2 {
            w.input="<h1>Small</h1>";let start=ContinuousClock.now;w.run();try await wait(w)
            print("MARKUP_SMALL pass=\(pass) elapsed=\(start.duration(to:.now))")
        }
        w.input=String(repeating:"<p>value</p>\n",count:18000)
        var gaps:[Double]=[];let start=Date();var last=start;w.run()
        while w.busy {try await Task.sleep(for:.milliseconds(10));let now=Date();gaps.append(now.timeIntervalSince(last));last=now}
        try check(w.result?.succeeded == true,"large preview generated")
        guard let web=views(WKWebView.self,host).first else{throw Failure.check("large preview webview")}
        for _ in 0..<80 {if (try? await js(web,"document.querySelectorAll('p').length")) as? Int == 18000 {break};await pause(host,50)}
        try check((try await js(web,"document.querySelectorAll('p').length")) as? Int == 18000,"large preview rendered")
        print("MARKUP_HEARTBEAT maxGapMs=\((gaps.max() ?? 0)*1000) samples=\(gaps.count) elapsed=\(Date().timeIntervalSince(start))")
        _=try await js(web,"scrollTo(0,document.body.scrollHeight)");await pause(host,200)
        try check(((try await js(web,"scrollY")) as? Double ?? 0)>10000,"large preview end scroll")
    }

}
