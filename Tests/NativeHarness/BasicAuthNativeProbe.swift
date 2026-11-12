import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

@main struct BasicAuthNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in do { try await run(); print("T021_NATIVE_PASSED") } catch { print("T021_NATIVE_FAILURE \(error)"); exit(1) }; exit(0) }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] { (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) } }
    @MainActor static func value(_ object: NSObject, _ key: String) -> AnyObject? {
        let sel = NSSelectorFromString(key); return object.responds(to: sel) ? object.perform(sel)?.takeUnretainedValue() : nil
    }
    @MainActor static func boolean(_ object: NSObject, _ key: String) -> Bool {
        let sel = NSSelectorFromString(key); guard object.responds(to: sel) else { return false }
        typealias Call = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: sel), to: Call.self)(object, sel)
    }
    @MainActor static func elements(_ root: Any, _ seen: inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let object = root as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return [] }
        return [object] + ((value(object, "accessibilityChildren") as? [Any]) ?? []).flatMap { elements($0, &seen) }
    }
    @MainActor static func ax() -> [NSObject] { var seen: Set<ObjectIdentifier> = []; return NSApp.windows.flatMap { elements($0, &seen) } }
    @MainActor static func press(_ identifier: String) throws {
        guard let object = ax().first(where: { value($0, "accessibilityIdentifier") as? String == identifier }), boolean(object, "accessibilityPerformPress") else { throw Failure.check("press-" + identifier) }
    }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("T021_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    static func encoded(_ source: String) -> String { Data(source.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func token(_ source: String) -> String { "eyJhbGciOiJub25lIn0." + encoded(source) + "." }
    @MainActor static func frame(_ id: String) -> NSRect? {
        guard let object = ax().first(where: { value($0, "accessibilityIdentifier") as? String == id }) else { return nil }
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    @MainActor static func run() async throws {
        let suite = "BasicAuthProbe." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldMenu = NSApp.mainMenu
        let main = NSMenu(), edit = NSMenu(), menuRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let nativePaste = edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menuRoot.submenu = edit; main.addItem(menuRoot); NSApp.mainMenu = main
        defer { NSApp.mainMenu = oldMenu }
        let w = BasicAuthWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: BasicAuthHeaderView(workspace: w))
        let window = NSWindow(contentRect: .init(x: 30, y: 30, width: 1040, height: 760), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 250)
        let fields = all(BasicAuthMacField.self, host)
        guard let user = fields.first(where: { $0.role == .username }), let password = fields.first(where: { $0.role == .password }) else { throw Failure.check("fields") }
        let ids = fields.map(ObjectIdentifier.init)
        try check(password.input is NSSecureTextField, "system-secure-control")
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } } ?? []
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved.map { entries in let item = NSPasteboardItem(); for (key, value) in entries { item.setData(value, forType: key) }; return item })
        }
        func paste(_ field: BasicAuthMacField, _ source: String) async {
            window.makeFirstResponder(field.input); await settle(host, 30)
            if let editor = field.currentEditor() as? NSTextView { editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0)) }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(source, forType: .string)
            field.pasteCredentials(nil); await settle(host, 60)
        }
        await paste(user, "Aladdin"); await paste(password, "open sesame")
        try check(w.username == "Aladdin" && w.password == "open sesame" && w.result == nil, "native-paste-no-build")
        guard let editor = password.currentEditor() as? NSTextView else { throw Failure.check("secure-editor") }
        let caret = editor.selectedRange()
        await w.run().value; await settle(host)
        try check(w.copyText(fullHeader: true) == "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==", "exact-header")
        try check(editor.selectedRange() == caret && window.firstResponder === editor, "build-preserves-caret-focus")
        try check(!ax().contains { value($0, "accessibilityValue") as? String == "open sesame" }, "secure-password-ax-hidden")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("bad\nvalue", forType: .string)
        try check(nativePaste.target === password && nativePaste.action == #selector(BasicAuthMacField.pasteCredentials(_:)), "main-edit-menu-routes-validated-paste")
        NSApp.sendAction(nativePaste.action!, to: nativePaste.target, from: nativePaste)
        await settle(host)
        try check(w.password == "open sesame" && w.canCopy, "main-edit-menu-rejects-controls")
        await paste(password, "bad\nvalue")
        try check(w.password == "open sesame" && w.rejectedInput?.code == .control && w.canCopy, "reject-control-paste-before-sanitization")
        await paste(user, "a:b")
        try check(w.username == "Aladdin" && w.rejectedInput?.code == .colon, "reject-username-colon")
        try check(editor.menu?.items.contains { $0.title == "Paste" && $0.target === password } == true, "native-menu-paste-target")
        window.makeFirstResponder(password.input); await settle(host)
        (password.currentEditor() as? NSTextView)?.setSelectedRange(.init(location: password.stringValue.utf16.count, length: 0))
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(":", forType: .string)
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9) { NSApp.postEvent(event, atStart: false) }
        await settle(host, 150)
        try check(w.password == "open sesame:" && !w.canCopy, "password-colon-kept")
        try press("basic-auth-show-password"); await settle(host, 240)
        try check(w.showPassword && password.input is NSSecureTextField, "show-keeps-secure-input")
        try press("basic-auth-show-password"); await settle(host, 240)
        await w.run().value; await settle(host)
        try press("basic-auth-reveal-header"); await settle(host, 250)
        try check(all(JSONNativeTextView.self, host).contains { $0.string == w.copyText(fullHeader: true) }, "revealed-exact-native-output")
        try press("basic-auth-reveal-header"); await settle(host, 250)
        try check(all(JSONNativeTextView.self, host).isEmpty, "hide-removes-output-from-native-tree")
        try press("basic-auth-copy-header"); await settle(host)
        try check(NSPasteboard.general.string(forType: .string) == w.copyText(fullHeader: true), "explicit-native-copy")
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 460, height: 760)); await settle(host, 250)
        try check(w.username == "Aladdin" && w.password == "open sesame:" && all(BasicAuthMacField.self, host).map(ObjectIdentifier.init) == ids, "theme-layout-retains-native-fields")
        window.makeFirstResponder(user.input); await settle(host)
        if let userEditor = user.currentEditor() as? NSTextView {
            userEditor.breakUndoCoalescing(); userEditor.insertText("x", replacementRange: .init(location: userEditor.string.utf16.count, length: 0)); userEditor.breakUndoCoalescing(); await settle(host)
            userEditor.undoManager?.undo(); await settle(host)
            try check(w.username == "Aladdin", "username-native-undo")
            userEditor.undoManager?.redo(); await settle(host)
            try check(w.username == "Aladdinx", "username-native-redo")
            userEditor.undoManager?.undo(); await settle(host)
        }
        let initialY = frame("basic-auth-reveal-header")?.minY ?? 0
        try press("basic-auth-show-password")
        var positions = [Int(initialY)]
        for _ in 0..<14 { await settle(host, 18); positions.append(Int(frame("basic-auth-reveal-header")?.minY ?? 0)) }
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        print("T021_MOTION reduced=\(reduced) frames=\(positions)")
        try check(reduced ? Set(positions).count <= 2 : Set(positions).count > 2, "bounded-reveal-motion")
        try press("basic-auth-show-password"); await settle(host, 250)
        try press("basic-auth-clear"); await settle(host)
        try check(w.username.isEmpty && w.password.isEmpty && !w.canCopy, "clear-model")
        window.makeFirstResponder(password.input); await settle(host)
        (password.currentEditor() as? NSTextView)?.undoManager?.undo(); await settle(host)
        try check(w.password.isEmpty && password.stringValue.isEmpty, "clear-cannot-resurrect-password")
        window.makeFirstResponder(user.input); await settle(host)
        (user.currentEditor() as? NSTextView)?.undoManager?.undo(); await settle(host)
        try check(w.username.isEmpty && user.stringValue.isEmpty, "clear-cannot-resurrect-username")
        window.makeFirstResponder(nil); await settle(host)
        try check(nativePaste.target == nil && nativePaste.action == #selector(NSText.paste(_:)), "restore-main-menu-after-field-editing")
        let fresh = BasicAuthWorkspaceSession(repository: .init(defaults: defaults))
        try check(fresh.username.isEmpty && fresh.password.isEmpty && fresh.result == nil, "fresh-session-empty")
        window.setContentSize(.init(width: 1040, height: 760)); await settle(host)
        for (label, source) in [("ordinary", "sample"), ("near-limit-ascii", String(repeating: "a", count: 196_589)), ("unicode", String(repeating: "😀", count: 45_000))] {
            w.username = ""; w.password = source
            let snapshot = BasicAuthRequest(username: "", password: source)
            let coreTime = await Task.detached {
                let start = ContinuousClock().now
                _ = BasicAuthProcessor.build(snapshot)
                return start.duration(to: ContinuousClock().now)
            }.value
            let clock = ContinuousClock(), start = ContinuousClock().now
            var heartbeat = clock.now, maximumGap = Duration.zero
            let timer = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                    let now = clock.now; maximumGap = max(maximumGap, heartbeat.duration(to: now)); heartbeat = now
                }
            }
            await w.run().value; await settle(host, 20); timer.cancel()
            print("T021_CORE \(label) elapsed=\(coreTime) mainHeartbeatMax=\(maximumGap)")
            print("T021_STRESS \(label) utf16=\(source.utf16.count) status=\(w.result!.status) elapsed=\(start.duration(to: clock.now))")
            try check(w.result?.status == .success, "bounded-stress-" + label)
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("T021_STRESS peakBytes=\(usage.ru_maxrss)")
        w.clear(); await settle(host, 100)
        if let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toolbox-t021-mac.png"))
        }
        window.close()
    }
}
