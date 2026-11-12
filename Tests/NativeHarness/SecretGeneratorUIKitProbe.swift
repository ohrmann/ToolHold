import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class SecretGeneratorUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let suite = "SecretUIKitProbe." + UUID().uuidString
    var workspace: SecretGeneratorWorkspaceSession!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        setbuf(stdout, nil)
        workspace = .init(kind: .password, repository: .init(kind: .password, defaults: UserDefaults(suiteName: suite)!)); return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = SecretProbeScene.self; return configuration
    }
    func connect(_ scene: UIWindowScene) {
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UIHostingController(rootView: PasswordGeneratorView(workspace: workspace)); window?.makeKeyAndVisible()
        Task { @MainActor in
            do { try await run(); print("SECRET_UIKIT_PASSED"); exit(0) }
            catch { print("SECRET_UIKIT_FAILED \(error)"); exit(1) }
        }
    }
    enum Failure: Error { case check(String) }
    func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw Failure.check(name) }; print("SECRET_UIKIT_OK \(name)")
    }
    func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) } }
    func settle(_ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); window?.layoutIfNeeded() }
    func run() async throws {
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await settle(250)
        workspace.advanced = true; workspace.mode = .custom; await settle(250)
        guard let editor = all(UITextView.self, window!).first(where: { $0.accessibilityIdentifier == "secret-custom-alphabet" }) else { throw Failure.check("custom-editor") }
        let identity = ObjectIdentifier(editor)
        editor.becomeFirstResponder(); editor.insertText("ab"); await settle()
        try check(workspace.customAlphabet == "ab", "input")
        editor.undoManager?.undo(); await settle(); try check(workspace.customAlphabet.isEmpty, "undo")
        editor.undoManager?.redo(); await settle(); try check(workspace.customAlphabet == "ab", "redo")
        let caret = editor.selectedRange
        await workspace.run()?.value; await settle()
        try check(editor.selectedRange == caret && editor.isFirstResponder, "generate-keeps-caret-focus")
        window?.overrideUserInterfaceStyle = .dark; await settle()
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "dark-keeps-editor")
        editor.resignFirstResponder(); workspace.advanced = false; await settle(250)
        try check(editor.superview == nil && editor.text == "ab", "hidden-editor-detached-retained")
        workspace.advanced = true; await settle(250)
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "reopen-same-editor")
        workspace.clear(); workspace.advanced = false; workspace.countText = "1000"; workspace.lengthText = "128"
        await workspace.run()?.value; await settle(250)
        guard let table = all(UITableView.self, window!).first else { throw Failure.check("table") }
        try check(table.numberOfRows(inSection: 0) == 1000 && table.visibleCells.count < 80, "virtualized-thousand-results")
        print("SECRET_UIKIT_VISIBLE_CELLS \(table.visibleCells.count)")
        table.scrollToRow(at: .init(row: 999, section: 0), at: .bottom, animated: true)
        var samples = [Double]()
        for _ in 0..<20 { await settle(25); samples.append(Double(table.contentOffset.y)) }
        print("SECRET_UIKIT_SCROLL \(samples)")
        try check(Set(samples.map(Int.init)).count > 3 && table.indexPathsForVisibleRows!.contains(.init(row: 999, section: 0)), "animated-last-row")
        workspace.selection = 999; workspace.showDetails = true; await settle(250)
        let value = workspace.batch!.values.last!
        workspace.concealSecrets(); await settle(200)
        let labels = all(UIView.self, window!).flatMap { view in
            [view.accessibilityLabel, view.accessibilityValue] + (view.accessibilityElements ?? []).compactMap { ($0 as? UIAccessibilityElement)?.accessibilityLabel }
        }.compactMap { $0 }.joined(separator: "|")
        try check(workspace.hidden && !labels.contains(value), "hidden-batch-details-ax")
        try check(workspace.copyValue(at: 999) == value, "hidden-explicit-copy-exact")
        let phrase = SecretGeneratorWorkspaceSession(kind: .passphrase, repository: .init(kind: .passphrase, defaults: UserDefaults(suiteName: suite)!))
        window?.rootViewController = UIHostingController(rootView: PassphraseGeneratorView(workspace: phrase))
        await settle(250); await phrase.run()?.value; await settle()
        try check(phrase.batch?.dictionaryVersion != nil && phrase.batch?.values.count == 1, "simulator-bundled-wordlist")
    }
}
@MainActor final class SecretProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let delegate = UIApplication.shared.delegate as? SecretGeneratorUIKitProbe else { return }
        delegate.connect(scene)
    }
}
