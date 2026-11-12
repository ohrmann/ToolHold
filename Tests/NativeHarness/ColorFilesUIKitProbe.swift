import SwiftUI
import UIKit
import ImageIO
@testable import Developer_Toolbox
@main final class ColorFilesUIKitProbe:UIResponder,UIApplicationDelegate {
    var window:UIWindow?
    enum Failure:Error{case check(String)}
    func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{setbuf(stdout,nil);return true}
    func application(_ app:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration{let c=UISceneConfiguration(name:"Default",sessionRole:session.role);c.delegateClass=ColorFilesProbeScene.self;return c}
    func connect(_ scene:UIWindowScene){window=UIWindow(windowScene:scene);window?.makeKeyAndVisible();Task{@MainActor in do{try await run();print("COLOR_FILES_UIKIT_PASSED");exit(0)}catch{print("COLOR_FILES_UIKIT_FAILED \(error)");exit(1)}}}
    func check(_ v:Bool,_ name:String)throws{guard v else{throw Failure.check(name)};print("COLOR_FILES_UIKIT_OK \(name)")}
    func pause(_ view:UIView,_ ms:Int=150)async{try? await Task.sleep(for:.milliseconds(ms));view.layoutIfNeeded()}
    func views<T:UIView>(_ type:T.Type,_ root:UIView)->[T]{((root as? T).map{[$0]} ?? [])+root.subviews.flatMap{views(type,$0)}}
    func run()async throws{
        print("COLOR_FILES_UIKIT_WIDTH \(window?.bounds.width ?? 0)")
        let c=ColorWorkspace();c.input="#77e375"
        for view in [AnyView(ColorConverterView(workspace:c)),AnyView(ContrastView(workspace:ColorWorkspace()))]{let host=UIHostingController(rootView:view);window?.rootViewController=host;await pause(host.view);host.overrideUserInterfaceStyle = .dark;await pause(host.view);try check(!views(UITextField.self,host.view).isEmpty,"color native fields")}
        let svg=SVGWorkspace(),curl=CurlWorkspace(),connection=ConnectionWorkspace();curl.masked=false;connection.masked=false
        svg.input="<svg xmlns='http://www.w3.org/2000/svg'/>";curl.input="curl https://example.com";connection.input="redis://user:synthetic@localhost/0"
        let sources=[svg.input,curl.input,connection.input]
        let roots=[AnyView(SVGWorkspaceView(workspace:svg)),AnyView(CurlWorkspaceView(workspace:curl)),AnyView(ConnectionWorkspaceView(workspace:connection))]
        for i in 0..<3 {
            let host=UIHostingController(rootView:roots[i]);window?.rootViewController=host;await pause(host.view)
            switch i{case 0:svg.run();case 1:curl.run();default:connection.run()}
            for _ in 0..<300{if !svg.busy && !curl.busy && !connection.busy{break};await pause(host.view,20)}
            try check(i==0 ? svg.result != nil:i==1 ? curl.result != nil:connection.document != nil,"source→result \(i)")
            guard let editor=views(UITextView.self,host.view).first(where:{$0.isEditable}) else{throw Failure.check("editor")}
            let identity=ObjectIdentifier(editor);editor.becomeFirstResponder();editor.selectedRange=NSRange(location:editor.text.utf16.count,length:0);editor.insertText(" ");await pause(host.view)
            editor.undoManager?.undo();await pause(host.view);try check(editor.text==sources[i],"Undo \(i)")
            editor.undoManager?.redo();await pause(host.view);try check(editor.text==sources[i]+" ","Redo \(i)")
            editor.resignFirstResponder();host.overrideUserInterfaceStyle = .dark;await pause(host.view)
            try check(views(UITextView.self,host.view).contains{ObjectIdentifier($0)==identity},"theme identity \(i)")
        }
        let cxt=CGContext(data:nil,width:64,height:48,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        cxt.setFillColor(CGColor(red:0.4,green:0.7,blue:0.3,alpha:1));cxt.fill(CGRect(x:0,y:0,width:64,height:48))
        let bytes=try ImagePipeline.encode(cxt.makeImage()!,format:.png,quality:1),source=try ImagePipeline.load(bytes)
        for format in RasterFormat.available{var o=ImageOptions();o.format=format;let artifact=try ImagePipeline.transform(source,options:o);try check(artifact.width==64,"codec \(format.rawValue)")}
        for tool in 63...65{let w=ImageWorkspace(resize:tool==64),host=UIHostingController(rootView:ImageWorkspaceView(workspace:ImageWorkspace(),tool:tool));host.rootView=ImageWorkspaceView(workspace:w,tool:tool);window?.rootViewController=host;w.load(data:bytes);for _ in 0..<300{if !w.busy{break};await pause(host.view,20)};w.run();for _ in 0..<300{if !w.busy{break};await pause(host.view,20)};try check(w.result != nil,"image flow \(tool)");await pause(host.view)}
    }
}
final class ColorFilesProbeScene:UIResponder,UIWindowSceneDelegate {
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions){if let scene=scene as? UIWindowScene{(UIApplication.shared.delegate as? ColorFilesUIKitProbe)?.connect(scene)}}
}
