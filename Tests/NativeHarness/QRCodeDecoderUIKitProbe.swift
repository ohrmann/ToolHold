import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class QRCodeDecoderUIKitProbe: UIResponder, UIApplicationDelegate {
    var window:UIWindow?
    let workspace=QRCodeDecoderWorkspaceSession()
    func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool { setbuf(stdout,nil);return true }
    func application(_ app:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {
        let config=UISceneConfiguration(name:"Default",sessionRole:session.role);config.delegateClass=QRDecoderProbeScene.self;return config
    }
    func connect(_ scene:UIWindowScene) {
        window=UIWindow(windowScene:scene);window?.rootViewController=UIHostingController(rootView:QRCodeDecoderView(workspace:workspace));window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run();print("T029_UIKIT_PASSED");exit(0) } catch { print("T029_UIKIT_FAILED \(error)");exit(1) } }
    }
    enum Failure:Error { case check(String) }
    func check(_ condition:@autoclosure ()->Bool,_ name:String) throws { guard condition() else { throw Failure.check(name) };print("T029_UIKIT_OK \(name)") }
    func all<T:UIView>(_ type:T.Type,_ root:UIView)->[T] { ((root as? T).map{[$0]} ?? [])+root.subviews.flatMap{all(type,$0)} }
    func settle(_ ms:Int=100) async { try? await Task.sleep(for:.milliseconds(ms));window?.layoutIfNeeded() }
    func ready() async throws { for _ in 0..<300 where workspace.busy { await settle(10) };try check(!workspace.busy,"worker-complete") }
    func run() async throws {
        await settle(250)
        let data=try Data(contentsOf:Bundle.main.url(forResource:"fixture",withExtension:"png")!)
        workspace.importData(data);try await ready();await settle(200)
        guard let editor=all(UITextView.self,window!).first, let viewport=all(QRDecoderScrollView.self,window!).first else { throw Failure.check("native-views") }
        let identity=ObjectIdentifier(editor)
        try check(workspace.selected?.text == "👩🏽‍💻 e\u{301} 中文","unicode-exact")
        try check(!editor.isEditable && editor.isSelectable,"readonly-native-text")
        editor.selectedRange=NSRange(location:0,length:2);let range=editor.selectedRange
        window?.overrideUserInterfaceStyle = .dark;await settle()
        try check(all(UITextView.self,window!).contains{ObjectIdentifier($0)==identity} && editor.selectedRange == range,"theme-keeps-selection-identity")
        try check(editor.frame.height>60,"narrow-output-height")
        viewport.perform(.zoomIn,animated:false);await settle()
        try check(viewport.zoomScale>viewport.minimumZoomScale,"native-zoom")
        try check(viewport.canvas?.layer.contents != nil && viewport.canvas?.layer.contentsScale == 1,"image-layer-no-retina-draw-backing")
        workspace.inputExpanded=false;await settle(250);workspace.inputExpanded=true;await settle(250)
        try check(all(UITextView.self,window!).contains{ObjectIdentifier($0)==identity},"disclosure-keeps-editor")
        viewport.perform(.fit,animated:false);await settle()
        if let canvas=viewport.canvas { try check(abs(canvas.center.x-viewport.bounds.width/2)<2,"fit-centers-letterbox") }
        workspace.scanAgain();workspace.cancel();try check(workspace.canOutput,"cancel-keeps-result")
        workspace.clear();await settle();try check(editor.text.isEmpty && workspace.snapshot==nil,"clear-removes-native-result")
        try check(QRCodeDecoderWorkspaceSession().snapshot==nil,"fresh-session-empty")
    }
}
@MainActor final class QRDecoderProbeScene:UIResponder,UIWindowSceneDelegate {
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
        guard let scene=scene as? UIWindowScene else { return };(UIApplication.shared.delegate as? QRCodeDecoderUIKitProbe)?.connect(scene)
    }
}
