import UIKit
import SwiftUI
import CryptoKit
@testable import Developer_Toolbox

@main @MainActor final class JWTEncoderUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let suite = "T078UIKitProbe." + UUID().uuidString
    var workspace: JWTEncoderWorkspaceSession!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        setbuf(stdout, nil); workspace = JWTEncoderWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: suite)!)); return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: session.role); c.delegateClass = JWTEncoderProbeScene.self; return c
    }
    func connect(_ scene: UIWindowScene) {
        window = UIWindow(windowScene: scene); window?.rootViewController = UIHostingController(rootView: JWTEncoderView(workspace: workspace)); window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run(); print("T078_UIKIT_PASSED"); exit(0) } catch { print("T078_UIKIT_FAILED \(error)"); exit(1) } }
    }
    enum Failure: Error { case check(String) }
    func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("T078_UIKIT_OK \(name)") }
    func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) } }
    func settle(_ ms: Int = 120) async { try? await Task.sleep(for: .milliseconds(ms)); window?.layoutIfNeeded() }
    struct Vector: Decodable, Sendable { let alg: String, header: String, payload: String, key: String, encoding: String, message: String, signature: String; var alternateKey: String? }
    func run() async throws {
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await settle(300)
        try check(workspace.artifact == nil && workspace.key.isEmpty, "initial-empty")
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: Bundle.main.url(forResource: "vectors", withExtension: "json")!))
        for v in vectors {
            let request = JWTEncoderRequest(header: v.header, payload: v.payload, key: v.key, keyEncoding: .init(rawValue: v.encoding)!)
            let result = await Task.detached { JWTEncoderProcessor.process(request) }.value
            try check(result.status == .generated, "crypto-" + v.alg)
            print("T078_UIKIT_CRYPTO \(v.alg) \(result.artifact!.token)") // disposable public fixtures only
            if let alternate = v.alternateKey {
                var second = request; second.key = alternate
                let immutable = second
                let other = await Task.detached { JWTEncoderProcessor.process(immutable) }.value
                try check(other.status == .generated, "alternate-key-" + v.alg)
            }
        }
        // Same production adapters and commands as the workspace, hosted together so
        // the probe can inspect native responders/managers without inventing UI logic.
        let keyCommands = JWTSigningKeyCommands(), jsonCommands = JSONEditorCommands()
        let holder = ProbeHolder()
        window!.rootViewController = UIHostingController(rootView: ProbeEditors(workspace: workspace, holder: holder, keyCommands: keyCommands, jsonCommands: jsonCommands))
        await settle(250)
        guard let key = all(UITextView.self, window!).first(where: { $0.accessibilityIdentifier == "jwt-encoder-key" }),
              let json = all(UITextView.self, window!).first(where: { $0.accessibilityLabel == "Probe Header input" }) else { throw Failure.check("native-editors") }
        let identity = ObjectIdentifier(key)
        key.becomeFirstResponder(); key.insertText("abc"); await settle()
        try check(workspace.key == "abc", "native-key-input")
        key.undoManager?.undo(); await settle(); try check(workspace.key.isEmpty, "native-key-undo")
        key.undoManager?.redo(); await settle(); try check(workspace.key == "abc", "native-key-redo")
        keyCommands.paste?("a\tb\n"); await settle()
        try check(workspace.key == "a\tb\n", "native-paste-retains-whitespace")
        keyCommands.resignFocus?(); holder.visible = false; await settle()
        try check(key.superview == nil && !key.becomeFirstResponder() && key.accessibilityValue == nil, "hidden-key-detached-no-focus-no-ax-value")
        holder.visible = true; await settle()
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "retained-key-identity")
        keyCommands.clear?(); key.undoManager?.undo(); await settle()
        try check(workspace.key.isEmpty && !key.undoManager!.canUndo, "clear-key-purges-private-history")
        let original = workspace.header
        json.becomeFirstResponder(); json.selectedRange = .init(location: 0, length: 0); json.insertText(" "); await settle()
        json.undoManager?.undo(); await settle(); try check(workspace.header == original, "json-native-undo")
        json.undoManager?.redo(); await settle(); try check(workspace.header == " " + original, "json-native-redo")
        let edit = JWTEncoderProcessor.algorithmEdit(header: workspace.header, algorithm: .hs512)!
        jsonCommands.replace?(edit.0, edit.1); await settle()
        try check(workspace.header.contains("HS512"), "apply-algorithm-native-replacement")
        json.undoManager?.undo(); await settle(); try check(workspace.header.contains("HS256"), "algorithm-replacement-undo")
        try check(json.undoManager !== key.undoManager, "key-json-native-histories-independent")
        jsonCommands.purgeUndo?(); workspace.clear(); await settle()
        try check(!json.undoManager!.canUndo && workspace.key.isEmpty && workspace.artifact == nil, "clear-all-json-history")
        json.resignFirstResponder()
        window!.rootViewController = UIHostingController(rootView: JWTEncoderView(workspace: workspace))
        workspace.key = String(repeating: "k", count: 32)
        await workspace.run().value; await settle(250)
        workspace.tokenRevealed = true; await settle(250)
        window?.overrideUserInterfaceStyle = .dark; await settle()
        if let window { UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }.pngData().map { try? $0.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t078-final.png")) } }
        workspace.hide(); await settle()
        try check(!all(UITextView.self, window!).contains { $0.accessibilityLabel == "Generated JWT result" }, "masked-token-not-in-native-tree")
        print("T078_UIKIT_NATIVE_COMPLETE")
    }
}
@MainActor @Observable final class ProbeHolder { var visible = true }
struct ProbeEditors: View {
    @Bindable var workspace: JWTEncoderWorkspaceSession
    @Bindable var holder: ProbeHolder
    let keyCommands: JWTSigningKeyCommands
    let jsonCommands: JSONEditorCommands
    var body: some View {
        VStack {
            JWTSigningKeyEditor(text: $workspace.key, commands: keyCommands, visible: holder.visible).frame(height: 140)
            JSONTextEditor(text: $workspace.header, commands: jsonCommands, privateUndo: true, contentName: "Probe Header")
        }
    }
}
@MainActor final class JWTEncoderProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let scene = scene as? UIWindowScene { (UIApplication.shared.delegate as? JWTEncoderUIKitProbe)?.connect(scene) }
    }
}
