import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class QRCodeUIKitProbe: UIResponder, UIApplicationDelegate {
    var window:UIWindow?
    let suite = "QRUIKit."+UUID().uuidString
    var workspace:QRCodeWorkspaceSession!
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        setbuf(stdout,nil); workspace = .init(defaults:UserDefaults(suiteName:suite)!); return true
    }
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name:"Default",sessionRole:session.role); c.delegateClass = QRProbeScene.self; return c
    }
    func connect(_ scene:UIWindowScene) {
        window = UIWindow(windowScene:scene); window?.rootViewController = UIHostingController(rootView:QRCodeGeneratorView(workspace:workspace)); window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run(); print("T028_UIKIT_PASSED"); exit(0) } catch { print("T028_UIKIT_FAILED \(error)"); exit(1) } }
    }
    enum Failure:Error { case check(String) }
    func check(_ condition:@autoclosure () -> Bool,_ label:String) throws { guard condition() else { throw Failure.check(label) }; print("QR_UIKIT_OK \(label)") }
    func all<T:UIView>(_ type:T.Type,_ view:UIView) -> [T] { ((view as? T).map{[$0]} ?? []) + view.subviews.flatMap{all(type,$0)} }
    func settle(_ ms:Int = 100) async { try? await Task.sleep(for:.milliseconds(ms)); window?.layoutIfNeeded() }
    func ready() async throws {
        for _ in 0..<500 where workspace.busy || workspace.preparing { await settle(10) }
        try check(!workspace.busy && !workspace.preparing,"worker-complete")
    }
    func run() async throws {
        defer { UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
        await settle(300)
        guard let input = all(UITextView.self,window!).first else { throw Failure.check("input") }
        let identity = ObjectIdentifier(input)
        input.becomeFirstResponder(); input.insertText("Привет 🌍")
        await settle(); try check(workspace.input == "Привет 🌍","native-unicode-input")
        input.undoManager?.undo(); await settle(); try check(workspace.input.isEmpty,"native-undo")
        input.undoManager?.redo(); await settle(); try check(workspace.input == "Привет 🌍","native-redo")
        let caret = input.selectedRange; workspace.generate(); try await ready()
        try check(workspace.canOutput && input.selectedRange == caret && input.isFirstResponder,"generate-keeps-caret-focus")
        for source in ["e\u{301} é 中文", "a\r\nb\u{0}"] {
            workspace.input = source; workspace.generate(); try await ready()
            try check(workspace.canOutput && workspace.artifact?.matrix.payload == Data(source.utf8),"exact-unicode-reference")
        }
        for style in QRModuleStyle.allCases { workspace.preferences.style = style; try await ready(); try check(workspace.canOutput,"style-\(style.rawValue)") }
        workspace.preferences.opacity = 0; try await ready()
        try check(workspace.artifact?.verification == .readable(conditional:true),"transparent-check")
        window?.overrideUserInterfaceStyle = .dark; await settle()
        try check(all(UITextView.self,window!).contains { ObjectIdentifier($0) == identity },"dark-retains-editor")
        var copied:QRExport?
        await workspace.prepare(.png) { copied = $0 }?.value
        try check(copied?.data.starts(with:[137,80,78,71]) == true,"final-png-check")
        workspace.clear(); await settle()
        try check(input.text.isEmpty && !workspace.canOutput,"clear-input-result")
    }
}
@MainActor final class QRProbeScene:UIResponder,UIWindowSceneDelegate {
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }; (UIApplication.shared.delegate as? QRCodeUIKitProbe)?.connect(scene)
    }
}
