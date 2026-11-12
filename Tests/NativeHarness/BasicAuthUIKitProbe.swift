import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class BasicAuthUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let suite = "BasicAuthUIKitProbe." + UUID().uuidString
    var w: BasicAuthWorkspaceSession!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        setbuf(stdout, nil); w = BasicAuthWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: suite)!)); return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: session.role); c.delegateClass = BasicAuthProbeScene.self; return c
    }
    func connect(_ scene: UIWindowScene) {
        window = UIWindow(windowScene: scene); window?.rootViewController = UIHostingController(rootView: BasicAuthHeaderView(workspace: w)); window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run(); print("T021_UIKIT_PASSED"); exit(0) } catch { print("T021_UIKIT_FAILED \(error)"); exit(1) } }
    }
    enum Failure: Error { case check(String) }
    func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw Failure.check(name) }; print("T021_UIKIT_OK \(name)")
    }
    func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] { (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) } }
    func settle(_ milliseconds: Int = 120) async { try? await Task.sleep(for: .milliseconds(milliseconds)); window?.layoutIfNeeded() }
    func run() async throws {
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await settle(250)
        let fields = all(BasicAuthUIKitField.self, window!)
        guard let user = fields.first(where: { $0.role == .username }), let pass = fields.first(where: { $0.role == .password }) else { throw Failure.check("fields") }
        let ids = fields.map(ObjectIdentifier.init)
        // Dedicated synthetic probe clipboard only; no user's app or working data is used.
        // No eager read of an existing clipboard: iOS may wait for paste permission.
        // This dedicated Simulator contains only synthetic test clipboard data.
        defer { UIPasteboard.general.items = [] }
        user.becomeFirstResponder(); UIPasteboard.general.string = "Aladdin"; user.paste(nil); await settle()
        pass.becomeFirstResponder(); UIPasteboard.general.string = "open sesame"; pass.paste(nil); await settle()
        try check(w.username == "Aladdin" && w.password == "open sesame" && w.result == nil, "paste-exact-no-build")
        let caret = pass.selectedTextRange.map { pass.offset(from: pass.beginningOfDocument, to: $0.start) }
        await w.run().value; await settle()
        try check(w.copyText(fullHeader: true) == "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==", "exact-header")
        try check(pass.isFirstResponder && pass.selectedTextRange.map { pass.offset(from: pass.beginningOfDocument, to: $0.start) } == caret, "build-keeps-focus-caret")
        UIPasteboard.general.string = "bad\nvalue"; pass.paste(nil); await settle()
        try check(w.password == "open sesame" && w.rejectedInput?.code == .control && w.canCopy, "reject-control-paste")
        user.becomeFirstResponder(); UIPasteboard.general.string = "a:b"; user.paste(nil); await settle()
        try check(w.username == "Aladdin" && w.rejectedInput?.code == .colon, "reject-username-colon")
        w.showPassword = true; await settle(); w.showPassword = false; await settle()
        try check(pass.isSecureTextEntry && all(BasicAuthUIKitField.self, window!).map(ObjectIdentifier.init) == ids, "reveal-preserves-secure-fields")
        try check(!pass.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil), "password-copy-blocked")
        pass.becomeFirstResponder()
        let begin = pass.position(from: pass.beginningOfDocument, offset: 5)!
        pass.selectedTextRange = pass.textRange(from: begin, to: pass.endOfDocument)
        UIPasteboard.general.string = "NEW"; pass.paste(nil); await settle()
        pass.undoManager?.undo(); await settle()
        try check(w.password == "open sesame" && pass.selectedTextRange.map { pass.offset(from: pass.beginningOfDocument, to: $0.start) } == 5, "password-undo-restores-text-and-selection")
        pass.undoManager?.redo(); await settle()
        try check(w.password == "open NEW", "password-redo")
        pass.undoManager?.undo(); await settle()
        user.becomeFirstResponder(); user.selectedTextRange = user.textRange(from: user.endOfDocument, to: user.endOfDocument)
        print("T021_UNDO before=\(w.username.utf16.count) available=\(user.undoManager?.canUndo == true)")
        user.insertText("x"); await settle()
        print("T021_UNDO after=\(w.username.utf16.count) available=\(user.undoManager?.canUndo == true)")
        user.undoManager?.undo(); await settle()
        print("T021_UNDO undone=\(w.username.utf16.count) available=\(user.undoManager?.canRedo == true)")
        try check(w.username == "Aladdin", "username-native-undo")
        user.undoManager?.redo(); await settle()
        try check(w.username == "Aladdinx", "username-native-redo")
        user.synchronize("", eraseHistory: true); pass.synchronize("", eraseHistory: true); w.clear(); await settle()
        user.undoManager?.undo(); pass.undoManager?.undo(); await settle()
        try check(w.username.isEmpty && w.password.isEmpty && user.text == "" && pass.text == "", "clear-cannot-resurrect")
        window?.overrideUserInterfaceStyle = .dark; await settle()
        try check(all(BasicAuthUIKitField.self, window!).map(ObjectIdentifier.init) == ids, "theme-identity")
    }
}
@MainActor final class BasicAuthProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }; (UIApplication.shared.delegate as? BasicAuthUIKitProbe)?.connect(scene)
    }
}
