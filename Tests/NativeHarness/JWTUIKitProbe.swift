import UIKit
import SwiftUI
@testable import Developer_Toolbox

/// Standalone Simulator probe. Synthetic content only; does not change project signing.
@main @MainActor final class JWTUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let suite = "JWTUIKitProbe." + UUID().uuidString
    private var workspace: JWTWorkspaceSession!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        setbuf(stdout, nil)
        workspace = JWTWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: suite)!))
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = JWTProbeScene.self
        return configuration
    }
    func connect(_ scene: UIWindowScene) {
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UIHostingController(rootView: JWTInspectorView(workspace: workspace))
        window?.makeKeyAndVisible()
        Task { @MainActor in await run() }
    }
    func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] { (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) } }
    func settle() async { try? await Task.sleep(for: .milliseconds(350)); window?.layoutIfNeeded() }
    func run() async {
        await settle()
        workspace.input = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0."
        await workspace.run().value; workspace.section = .payload; await settle()
        let editors = all(JSONNativeTextView.self, window!)
        print("T020_UIKIT editors=\(editors.count)")
        guard let input = editors.first(where: { $0.isEditable }) else { print("T020_UIKIT_FAILED no-input"); exit(1) }
        let original = input.text ?? ""
        input.becomeFirstResponder(); input.insertText("x"); await settle()
        input.undoManager?.undo(); await settle()
        await workspace.run().value; await settle()
        input.resignFirstResponder(); workspace.setMasked(true); await settle()
        for editor in editors {
            print("T020_UIKIT mask=\(workspace.masked) roleEditable=\(editor.isEditable) nativeFlag=\(editor.privacyHidden) nativeHidden=\(editor.isHidden) axElement=\(editor.isAccessibilityElement) axChildrenHidden=\(editor.accessibilityElementsHidden) axValueNil=\(editor.accessibilityValue == nil)")
        }
        let hidden = editors.allSatisfy { $0.privacyHidden && $0.accessibilityValue == nil && !$0.canBecomeFirstResponder && $0.window == nil }
        workspace.setMasked(false); await settle()
        let retained = all(JSONNativeTextView.self, window!).contains { $0 === input } && input.text == original
        input.becomeFirstResponder(); input.undoManager?.redo(); await settle()
        let redo = input.text == original + "x"
        input.undoManager?.undo(); await settle()
        let passed = hidden && retained && redo && input.text == original
        print("T020_UIKIT retained=\(retained) detached=\(hidden) undoRedo=\(redo)")
        print(passed ? "T020_UIKIT_NATIVE_PASSED" : "T020_UIKIT_NATIVE_FAILED")
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        exit(passed ? 0 : 1)
    }
}

@MainActor final class JWTProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        (UIApplication.shared.delegate as? JWTUIKitProbe)?.connect(windowScene)
    }
}
