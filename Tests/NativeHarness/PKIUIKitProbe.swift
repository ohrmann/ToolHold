import SwiftUI
import UIKit
@testable import Developer_Toolbox
@main final class PKIUIKitProbe:UIResponder,UIApplicationDelegate {
    var window:UIWindow?
    enum Failure:Error{case check(String)}
    func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{setbuf(stdout,nil);return true}
    func application(_ app:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration{let c=UISceneConfiguration(name:"Default",sessionRole:session.role);c.delegateClass=PKIProbeScene.self;return c}
    func connect(_ scene:UIWindowScene){window=UIWindow(windowScene:scene);window?.makeKeyAndVisible();Task{@MainActor in do{try await run();print("PKI_UIKIT_PASSED");exit(0)}catch{print("PKI_UIKIT_FAILED \(error)");exit(1)}}}
    func check(_ value:Bool,_ name:String)throws{guard value else{throw Failure.check(name)};print("PKI_UIKIT_OK \(name)")}
    func views<T:UIView>(_ type:T.Type,_ root:UIView)->[T]{((root as? T).map{[$0]} ?? [])+root.subviews.flatMap{views(type,$0)}}
    func pause(_ view:UIView,_ ms:Int=160)async{try? await Task.sleep(for:.milliseconds(ms));view.layoutIfNeeded()}
    func run()async throws{
        print("PKI_UIKIT_WIDTH \(window?.bounds.width ?? 0)")
        let e=PKIEngine(),g=try await e.generate(PKIGenerationDraft(),csr:false),key=try await e.exportKey(token:await e.token(),key:g.key.handle,password:"synthetic",unencrypted:false)
        let csr=try await e.generate(PKIGenerationDraft(),csr:true),pfx=try await e.createPFX(privateKey:Data(key.pem.utf8),certificate:g.object.data,extras:Data(),password:"synthetic",keyPassword:"synthetic",name:"PUBLIC TEST")
        for tool in PKITool.allCases where tool != .expiry {
            let s=PKIWorkspace(tool:tool);s.masked=false
            switch tool {case .certificate:break;case .csr:s.mode=1;s.input=csr.object.pem;case .converter:s.input=g.object.pem;case .pfx:try s.load(pfx,name:"test.p12",slot:0);s.password="synthetic";case .chain:s.input=g.object.pem;s.roots=g.object.pem;s.hostname="localhost";case .matcher:s.input=g.object.pem;s.second=key.pem;s.password="synthetic";case .key:s.input=key.pem;s.password="synthetic";default:break}
            let host=UIHostingController(rootView:PKIWorkspaceView(workspace:s));window?.rootViewController=host;await pause(host.view);await s.run().value;await pause(host.view)
            try check(s.result != nil,"tool \(tool.rawValue) source→result \(s.message)")
            if let editor=views(UITextView.self,host.view).first(where:{$0.isEditable}),tool == .converter {
                let identity=ObjectIdentifier(editor),original=editor.text ?? "";editor.becomeFirstResponder();editor.selectedRange=NSRange(location:original.utf16.count,length:0);editor.insertText(" ");await pause(host.view)
                try check(s.result == nil,"typing invalidates old result")
                editor.undoManager?.undo();await pause(host.view);try check(editor.text==original,"Undo")
                editor.undoManager?.redo();await pause(host.view);try check(editor.text==original+" ","Redo")
                editor.resignFirstResponder();host.overrideUserInterfaceStyle = .dark;await pause(host.view)
                try check(views(UITextView.self,host.view).contains{ObjectIdentifier($0)==identity},"theme preserves native identity")
                withAnimation(.easeInOut(duration:0.2)){s.inputCollapsed=true};await pause(host.view);withAnimation(.easeInOut(duration:0.2)){s.inputCollapsed=false};await pause(host.view)
                try check(views(UITextView.self,host.view).contains{ObjectIdentifier($0)==identity},"collapse preserves editor")
                await s.run().value
            }
            host.overrideUserInterfaceStyle = .dark;await pause(host.view);if tool == .certificate { screenshot(host.view,"certificate-dark") }
            host.overrideUserInterfaceStyle = .light;await pause(host.view)
            if tool == .certificate { screenshot(host.view,"certificate-light") }
            s.concealSecrets();await pause(host.view)
        }
        let folder=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        try Data(g.object.pem.utf8).write(to:folder.appendingPathComponent("public-fixture.pem"))
        let expiry=PKIExpirationWorkspace(),host=UIHostingController(rootView:PKIExpirationView(workspace:expiry));window?.rootViewController=host;expiry.scan([folder]);while expiry.busy{await pause(host.view,20)}
        try check(expiry.report?.rows.count==1,"expiration report")
        try check(PKIWorkspace(tool:.key).input.isEmpty,"empty fresh session")
    }
    func screenshot(_ view:UIView,_ name:String){let image=UIGraphicsImageRenderer(bounds:view.bounds).image{_ in view.drawHierarchy(in:view.bounds,afterScreenUpdates:true)};if let bytes=image.pngData(){try? bytes.write(to:URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("pki-"+name+".png"))}}
}
final class PKIProbeScene:UIResponder,UIWindowSceneDelegate{func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions){if let scene=scene as? UIWindowScene{(UIApplication.shared.delegate as? PKIUIKitProbe)?.connect(scene)}}}
