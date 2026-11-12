import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class IdentifierUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let suite = "T022UIKitProbe." + UUID().uuidString
    var workspace: IdentifierWorkspaceSession!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        setbuf(stdout, nil); workspace = IdentifierWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: suite)!)); return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: session.role); c.delegateClass = IdentifierProbeScene.self; return c
    }
    func connect(_ scene: UIWindowScene) {
        window = UIWindow(windowScene: scene); window?.rootViewController = UIHostingController(rootView: IdentifierGeneratorView(workspace: workspace)); window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run(); print("T022_UIKIT_PASSED"); exit(0) } catch { print("T022_UIKIT_FAILED \(error)"); exit(1) } }
    }
    enum Failure: Error { case check(String) }
    func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("T022_UIKIT_OK \(name)") }
    func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) } }
    func settle(_ ms: Int = 120) async { try? await Task.sleep(for: .milliseconds(ms)); window?.layoutIfNeeded() }
    func run() async throws {
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite); UIPasteboard.general.items = [] }
        await settle(250)
        try check(!all(UITextView.self, window!).contains { $0.accessibilityIdentifier == "identifier-custom-alphabet" }, "unused-alphabet-not-in-native-tree")
        workspace.preferences.kind = .nanoID; workspace.preferences.nanoAlphabetPreset = .custom
        await settle(250)
        guard let editor = all(UITextView.self, window!).first(where: { $0.accessibilityIdentifier == "identifier-custom-alphabet" }) else { throw Failure.check("editor") }
        let identity = ObjectIdentifier(editor)
        editor.becomeFirstResponder(); editor.insertText("ab"); await settle()
        try check(workspace.customAlphabet == "ab", "native-input")
        editor.undoManager?.undo(); await settle()
        try check(workspace.customAlphabet.isEmpty, "native-undo")
        editor.undoManager?.redo(); await settle()
        try check(workspace.customAlphabet == "ab", "native-redo")
        let caret = editor.selectedRange
        await workspace.run()?.value; await settle()
        try check(editor.selectedRange == caret && editor.isFirstResponder, "generate-keeps-caret-focus")
        window?.overrideUserInterfaceStyle = .dark; await settle()
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "theme-keeps-editor")
        editor.selectedRange = NSRange(location: 0, length: editor.text.utf16.count)
        UIPasteboard.general.string = "a\tb"; editor.paste(nil); await settle()
        try check(workspace.customAlphabet == "a\tb" && workspace.validationIssue != nil, "paste-retains-invalid-whitespace")
        editor.resignFirstResponder(); workspace.preferences.nanoAlphabetPreset = .urlSafe; await settle(250)
        try check(editor.superview == nil && editor.text == "a\tb", "hidden-editor-detached-retained")
        workspace.preferences.nanoAlphabetPreset = .custom; await settle(250)
        try check(all(UITextView.self, window!).contains { ObjectIdentifier($0) == identity }, "reopen-same-native-editor")
        // The full app's Clear action is covered by XCTest. Here exercise the
        // exact adapter command with its native private UndoManager.
        editor.resignFirstResponder()
        let originalController = window!.rootViewController
        let commands = IdentifierAlphabetCommands()
        window!.rootViewController = UIHostingController(rootView: IdentifierAlphabetEditor(text: Binding(get: { self.workspace.customAlphabet }, set: { self.workspace.customAlphabet = $0 }), commands: commands))
        await settle(250)
        guard let field = all(UITextView.self, window!).first else { throw Failure.check("command-editor") }
        field.becomeFirstResponder(); field.insertText("x"); await settle()
        commands.resignFocus?(); commands.clear?(); workspace.clear(); await settle()
        field.undoManager?.undo(); await settle()
        try check(workspace.customAlphabet.isEmpty && field.text.isEmpty && !field.undoManager!.canUndo, "clear-no-undo-resurrection")
        window!.rootViewController = originalController; await settle(250)
        workspace.preferences.kind = .uuidV4; workspace.countText = "10000"
        await workspace.run()?.value; await settle(250)
        guard let table = all(UITableView.self, window!).first else { throw Failure.check("table") }
        try check(table.numberOfRows(inSection: 0) == 10000 && table.visibleCells.count < 100, "bounded-ten-thousand-rows")
        print("T022_UIKIT_VISIBLE_CELLS \(table.visibleCells.count)")
        table.scrollToRow(at: .init(row: 9999, section: 0), at: .bottom, animated: true)
        var origins = [Double]()
        for _ in 0..<16 { await settle(25); origins.append(Double(table.contentOffset.y)) }
        print("T022_UIKIT_SCROLL \(origins)")
        try check(Set(origins.map { Int($0) }).count > 3 && table.indexPathsForVisibleRows?.contains(.init(row: 9999, section: 0)) == true, "continuous-last-row-motion")
        try check(workspace.copyValue(at: 9999) == workspace.batch?.values.last, "last-row-exact-copy-value")
        workspace.selection = 9999; workspace.showDetails = true; await settle(350)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T022UIKit.png")
        let image = UIGraphicsImageRenderer(bounds: window!.bounds).image { _ in window!.drawHierarchy(in: window!.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: url)
        print("T022_UIKIT_SCREENSHOT \(url.path)")
    }
}
@MainActor final class IdentifierProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }; (UIApplication.shared.delegate as? IdentifierUIKitProbe)?.connect(scene)
    }
}
