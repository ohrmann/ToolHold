import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class TokenDigestUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let suite = "TokenDigestUIKit." + UUID().uuidString
    var workspace: DigestWorkspaceSession!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        setbuf(stdout, nil); workspace = .init(isHMAC: true, defaults: UserDefaults(suiteName: suite)!); return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role); configuration.delegateClass = TokenDigestProbeScene.self; return configuration
    }
    func connect(_ scene: UIWindowScene) {
        window = UIWindow(windowScene: scene); window?.rootViewController = UIHostingController(rootView: HMACGeneratorView(workspace: workspace)); window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run(); print("TOKEN_DIGEST_UIKIT_PASSED"); exit(0) } catch { print("TOKEN_DIGEST_UIKIT_FAILED \(error)"); exit(1) } }
    }
    enum Failure: Error { case check(String) }
    func check(_ value: @autoclosure () -> Bool, _ name: String) throws { guard value() else { throw Failure.check(name) }; print("TOKEN_DIGEST_UIKIT_OK \(name)") }
    func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) } }
    func settle(_ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); window?.layoutIfNeeded() }
    func run() async throws {
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await settle(300)
        guard let key = all(UITextView.self, window!).first(where: { $0.accessibilityIdentifier == "digest-key" }),
              let message = all(UITextView.self, window!).first(where: { $0.accessibilityIdentifier == "digest-message" }) else { throw Failure.check("editors") }
        let identity = ObjectIdentifier(key)
        key.becomeFirstResponder(); key.insertText("key"); await settle()
        try check(workspace.key == "key", "native-key-input")
        key.undoManager?.undo(); await settle(); try check(workspace.key.isEmpty, "key-undo")
        key.undoManager?.redo(); await settle(); try check(workspace.key == "key", "key-redo")
        let caret = key.selectedRange
        workspace.text = "The quick brown fox jumps over the lazy dog"; await workspace.run()?.value; await settle()
        try check(workspace.value(.sha256) == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", "hmac-exact")
        try check(key.selectedRange == caret && key.isFirstResponder, "generate-keeps-caret-focus")
        window?.overrideUserInterfaceStyle = .dark; await settle()
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "dark-retains-native-editor")
        key.resignFirstResponder(); workspace.keyHidden = true; await settle()
        try check(!all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "hidden-key-detached")
        workspace.keyHidden = false; await settle()
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity } && key.text == "key", "revealed-key-same-editor")
        workspace.text = "é"; await workspace.run()?.value; await settle()
        workspace.text = "e\u{301}"; await settle()
        try check(!workspace.current && message.text.utf8.elementsEqual(workspace.text.utf8), "exact-unicode-native-update")
        workspace.preferences.mode = .file; await settle()
        try check(!all(UITextView.self, window!).contains { $0 === message }, "file-mode-detaches-source")
        workspace.preferences.mode = .text; await settle()
        try check(all(UITextView.self, window!).contains { $0 === message }, "text-mode-retains-source")
        key.becomeFirstResponder(); workspace.concealSecrets(); await settle()
        try check(key.superview == nil && !key.isFirstResponder, "background-conceal-active-editor-safe")
        let labels = all(UIView.self, window!).flatMap { [$0.accessibilityLabel, $0.accessibilityValue].compactMap { $0 } }.joined(separator: "|")
        try check(!labels.contains("f7bc83f430538424"), "hidden-result-no-plaintext-ax")
    }
}
@MainActor final class TokenDigestProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let delegate = UIApplication.shared.delegate as? TokenDigestUIKitProbe else { return }; delegate.connect(scene)
    }
}
