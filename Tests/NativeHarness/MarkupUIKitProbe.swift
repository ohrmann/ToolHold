import SwiftUI
import UIKit
import WebKit
@testable import Developer_Toolbox

@main final class MarkupUIKitProbe: UIResponder, UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {setbuf(stdout,nil);return true}
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {
        let c=UISceneConfiguration(name:"Default",sessionRole:session.role);c.delegateClass=MarkupProbeScene.self;return c
    }
    func connect(_ scene:UIWindowScene) {
        window=UIWindow(windowScene:scene);window?.makeKeyAndVisible()
        Task { @MainActor in do{try await run();print("MARKUP_UIKIT_PASSED");exit(0)}catch{print("MARKUP_UIKIT_FAILED \(error)");exit(1)} }
    }
    enum Failure:Error {case check(String)}
    func check(_ value:Bool,_ name:String)throws {guard value else{throw Failure.check(name)};print("MARKUP_UIKIT_OK \(name)")}
    func views<T:UIView>(_ type:T.Type,_ view:UIView)->[T] {((view as? T).map{[$0]} ?? [])+view.subviews.flatMap{views(type,$0)}}
    func pause(_ view:UIView,_ ms:Int=180) async {try? await Task.sleep(for:.milliseconds(ms));view.layoutIfNeeded()}
    func wait(_ w:MarkupWorkspace) async throws {for _ in 0..<1200{if !w.busy{return};try await Task.sleep(for:.milliseconds(20))};throw Failure.check("worker timeout")}
    func run() async throws {
        let defaults=UserDefaults(suiteName:"toolbox.markup.uikit-tests")!;defaults.removePersistentDomain(forName:"toolbox.markup.uikit-tests");defer{defaults.removePersistentDomain(forName:"toolbox.markup.uikit-tests")}
        print("MARKUP_UIKIT_WIDTH \(window?.bounds.width ?? 0)")
        let sources:[MarkupTool:String]=[.sql:"select a from t",.xml:"<r><a>😀</a></r>",.yaml:"a: [1,2]",.html:"<p>Hello</p>",.css:"a { color: red; }",.javascript:"const x=1;",.markdown:"# Hello",.preview:"<h1>Hello</h1>",.mjml:"<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>"]
        for tool in MarkupTool.allCases {
            let w=MarkupWorkspace(tool,defaults:defaults);w.options.live=false
            let host=UIHostingController(rootView:CodeMarkupWorkspaceView(workspace:w));window?.rootViewController=host
            await pause(host.view);w.input=sources[tool]!;w.run();try await wait(w);await pause(host.view)
            try check(w.result?.succeeded==true,"\(tool.rawValue) processing")
            guard let editor=views(UITextView.self,host.view).first(where:{$0.isEditable}) else{throw Failure.check("input editor")}
            var colors=Set<String>()
            if let manager=editor.textLayoutManager,let content=manager.textContentManager {
                manager.enumerateRenderingAttributes(from:content.documentRange.location,reverse:false) { _,attributes,_ in
                    if let color=attributes[.foregroundColor] as? UIColor {colors.insert(color.resolvedColor(with:editor.traitCollection).description)}
                    return true
                }
            }
            print("MARKUP_UIKIT_COLORS \(tool.rawValue) distinct=\(colors.count) textkit2=\(editor.textLayoutManager != nil)")
            try check(colors.count >= (tool == .markdown ? 1 : 2),"\(tool.rawValue) native syntax colors")
            let identity=ObjectIdentifier(editor),source=w.input
            editor.becomeFirstResponder();editor.selectedRange=NSRange(location:(editor.text as NSString).length,length:0);editor.insertText(" ");await pause(host.view,60)
            try check(w.input==source+" ","\(tool.rawValue) native edit")
            editor.undoManager?.undo();await pause(host.view,60);try check(w.input==source,"\(tool.rawValue) Undo")
            editor.undoManager?.redo();await pause(host.view,60);try check(w.input==source+" ","\(tool.rawValue) Redo")
            editor.resignFirstResponder();host.overrideUserInterfaceStyle = .dark;await pause(host.view)
            try check(views(UITextView.self,host.view).contains{ObjectIdentifier($0)==identity},"\(tool.rawValue) theme identity")
            if tool.isPreview {withAnimation(.easeInOut(duration:0.2)){w.collapsed=true};await pause(host.view,260);w.collapsed=false;await pause(host.view,260);try check(views(UITextView.self,host.view).contains{ObjectIdentifier($0)==identity},"\(tool.rawValue) collapse identity")}
            w.disappeared()
        }
        let ime=MarkupWorkspace(.markdown,defaults:defaults);ime.options.live=true
        let imeHost=UIHostingController(rootView:CodeMarkupWorkspaceView(workspace:ime));window?.rootViewController=imeHost;await pause(imeHost.view)
        let imeEditor=views(UITextView.self,imeHost.view).first{$0.isEditable}!
        imeEditor.becomeFirstResponder();imeEditor.setMarkedText("中",selectedRange:NSRange(location:1,length:0));imeEditor.delegate?.textViewDidChange?(imeEditor);await pause(imeHost.view,600)
        try check(imeEditor.markedTextRange != nil && !ime.busy && ime.result == nil,"IME defers live preview")
        imeEditor.unmarkText();imeEditor.delegate?.textViewDidChange?(imeEditor);await pause(imeHost.view,850);try await wait(ime)
        try check(ime.result?.succeeded == true,"IME commit renders")
        imeEditor.resignFirstResponder();ime.disappeared()
        let w=MarkupWorkspace(.preview,defaults:defaults);w.options.live=false;w.options.document=true
        let host=UIHostingController(rootView:CodeMarkupWorkspaceView(workspace:w));window?.rootViewController=host
        await pause(host.view)
        w.input="<html><head><style>@import 'http://127.0.0.1:18765/uikitstyle';p{background:url(http://127.0.0.1:18765/uikitcss)}</style></head><body><script>window.__ran=true</script><img src='http://127.0.0.1:18765/uikitimage' onerror='window.__ran=true'><iframe src='http://127.0.0.1:18765/uikitframe'></iframe><h1>Safe</h1>"+String(repeating:"<p>row</p>",count:150)+"</body></html>"
        w.run();try await wait(w);await pause(host.view,1500)
        guard let web=views(WKWebView.self,host.view).first else{throw Failure.check("webview missing")}
        for _ in 0..<50{if (try? await web.evaluateJavaScript("document.body.innerText.includes('Safe')")) as? Bool == true{break};await pause(host.view,100)}
        try check((try await web.evaluateJavaScript("document.body.innerText.includes('Safe')")) as? Bool == true,"preview loaded")
        try check((try await web.evaluateJavaScript("typeof window.__ran")) as? String == "undefined","script execution blocked")
        try check(!web.configuration.websiteDataStore.isPersistent,"nonpersistent data store")
        _=try await web.evaluateJavaScript("scrollTo(0,900)");await pause(host.view,100)
        let before=(try await web.evaluateJavaScript("scrollY")) as? Double ?? 0
        w.input=w.input.replacingOccurrences(of:"Safe",with:"Updated");w.run();try await wait(w);await pause(host.view,600)
        let after=(try await web.evaluateJavaScript("scrollY")) as? Double ?? 0
        print("MARKUP_UIKIT_SCROLL \(before) -> \(after)")
        try check(before>500&&abs(before-after)<3,"preview scroll retained")
        let data=UIGraphicsImageRenderer(bounds:host.view.bounds).pngData { _ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true) }
        try data.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-markup-uikit.png"))
    }
}
final class MarkupProbeScene:UIResponder,UIWindowSceneDelegate {
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions){if let scene=scene as? UIWindowScene{(UIApplication.shared.delegate as? MarkupUIKitProbe)?.connect(scene)}}
}
