import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

@main struct JWTEncoderNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in
            do { try await run(); print("T078_NATIVE_PASSED") } catch { print("T078_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) } }
    @MainActor static func value(_ object: NSObject, _ key: String) -> AnyObject? {
        let selector = NSSelectorFromString(key); return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }
    @MainActor static func elements(_ root: Any, _ seen: inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let object = root as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return [] }
        return [object] + (["accessibilityChildren", "accessibilityRows", "accessibilityContents"].flatMap { (value(object, $0) as? [Any]) ?? [] }).flatMap { elements($0, &seen) }
    }
    @MainActor static func ax(_ window: NSWindow) -> [NSObject] { var seen: Set<ObjectIdentifier> = []; return elements(window, &seen) + (window.contentView.map { all(NSView.self, $0).flatMap { elements($0, &seen) } } ?? []) }
    @MainActor static func press(_ id: String, in window: NSWindow) throws {
        guard let object = ax(window).first(where: { value($0, "accessibilityIdentifier") as? String == id }) else { throw Failure.check("missing-" + id) }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        typealias Call = @convention(c) (AnyObject, Selector) -> Bool
        guard object.responds(to: selector), unsafeBitCast(object.method(for: selector), to: Call.self)(object, selector) else { throw Failure.check("press-" + id) }
    }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("T078_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func run() async throws {
        let suite = "T078-native-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { entries in let item = NSPasteboardItem(); for (key, data) in entries { item.setData(data, forType: key) }; return item }) }
        let session = JWTEncoderWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: AnyView(JWTEncoderView(workspace: session)))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1300, height: 850), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 300)
        try check(session.artifact == nil && session.key.isEmpty, "initial-empty")
        session.keyRevealed = true; await settle(host)
        guard let key = all(NSTextView.self, host).first(where: { $0.accessibilityIdentifier() == "jwt-encoder-key" }),
              let header = all(NSTextView.self, host).first(where: { $0.accessibilityLabel() == "JWT Encoder Header input" }),
              let payload = all(NSTextView.self, host).first(where: { $0.accessibilityLabel() == "JWT Encoder Payload input" }) else { throw Failure.check("native-editors") }
        let identities = [ObjectIdentifier(key),ObjectIdentifier(header),ObjectIdentifier(payload)]
        window.makeFirstResponder(key); key.insertText(String(repeating: "0123456789abcdef", count: 4), replacementRange: .init(location: 0, length: 0)); await settle(host)
        try check(session.key.utf8.count == 64, "native-key-input")
        key.undoManager?.undo(); await settle(host); try check(session.key.isEmpty, "key-undo")
        key.undoManager?.redo(); await settle(host); try check(session.key.utf8.count == 64, "key-redo")
        let caret = key.selectedRange()
        try press("jwt-encoder-generate", in: window)
        for _ in 0..<100 where session.busy { await settle(host, 10) }; await settle(host)
        try check(session.artifact != nil && key.selectedRange() == caret && window.firstResponder === key, "generate-keeps-caret-focus")
        let artifact = session.artifact!.id
        try press("jwt-encoder-copy", in: window)
        try check(NSPasteboard.general.string(forType: .string) == session.artifact?.token, "explicit-copy-exact-token")
        try press("jwt-encoder-check", in: window)
        for _ in 0..<100 where session.busy { await settle(host, 10) }; try check(session.artifact?.id == artifact, "check-retains-current-token")
        window.makeFirstResponder(header)
        let edit = JWTEncoderProcessor.algorithmEdit(header: session.header, algorithm: .hs512)!
        header.insertText(edit.1, replacementRange: edit.0); await settle(host, 250)
        try check(session.algorithm == .hs512, "manual-header-updates-selector")
        try check(session.header.contains("HS512"), "apply-algorithm-native-command")
        header.undoManager?.undo(); await settle(host, 220); try check(session.header.contains("HS256") && session.algorithm == .hs256, "apply-algorithm-undo")
        header.undoManager?.redo(); await settle(host, 220); try check(session.header.contains("HS512") && session.algorithm == .hs512, "apply-algorithm-redo")
        try check(header.undoManager !== key.undoManager && header.undoManager !== payload.undoManager, "isolated-native-histories")
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 430, height: 850)); await settle(host, 250)
        window.setContentSize(.init(width: 1300, height: 850)); await settle(host, 250)
        try check(identities.allSatisfy { id in all(NSTextView.self, host).contains { ObjectIdentifier($0) == id } }, "resize-theme-keeps-native-editors")
        session.keyRevealed = true; await settle(host)
        window.makeFirstResponder(key); NSPasteboard.general.clearContents(); NSPasteboard.general.setString("a\tb", forType: .string)
        try press("jwt-encoder-paste-key", in: window); await settle(host)
        try check(session.key == "a\tb", "paste-does-not-sanitize")
        try press("jwt-encoder-clear-key", in: window); await settle(host)
        key.undoManager?.undo(); await settle(host)
        try check(session.key.isEmpty && !key.undoManager!.canUndo, "clear-key-no-undo-resurrection")
        key.window?.makeFirstResponder(nil); session.keyRevealed = false; await settle(host)
        _ = window.makeFirstResponder(key)
        try check(key.accessibilityValue() == nil && window.firstResponder !== key, "hidden-key-cannot-focus-or-expose-value")
        session.key = String(repeating: "k", count: 64); session.header = JWTEncoderWorkspaceSession.template(.hs512)
        session.payload = "{\n" + (0..<900).map { "\"k\($0)\":1,\n" }.joined()
        await session.run(.jsonOnly).value; await settle(host, 250)
        try check(session.result?.status == .invalidInput && session.artifact == nil, "invalid-input-diagnostics-no-stale-token")
        guard let scroll = payload.enclosingScrollView else { throw Failure.check("payload-scroll") }
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        try press("jwt-encoder-show-detection", in: window)
        var positions: [Double] = []
        for _ in 0..<16 { await settle(host, 20); positions.append(scroll.contentView.bounds.origin.y) }
        print("T078_SOURCE_MOTION \(positions)")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        try check(positions.last! > 1000 && (reduced || Set(positions.map(Int.init)).count > 3), "offscreen-detection-smooth-navigation")
        guard let issue = session.result?.issues.first else { throw Failure.check("diagnostic") }
        session.show(issue, related: true)
        for _ in 0..<16 { await settle(host, 20) }
        try check(session.payloadTarget == issue.diagnostic?.related.first?.range, "related-navigation-uses-parser-anchor")
        // An unterminated long string has its related start genuinely offscreen.
        session.payload = "{\"s\":\"" + String(repeating: "abcdef ", count: 12000)
        await session.run(.jsonOnly).value; await settle(host, 250)
        try press("jwt-encoder-show-detection", in: window)
        for _ in 0..<16 { await settle(host, 20) }
        try check(scroll.contentView.bounds.origin.y > 1000, "one-line-wrapped-detection")
        let stringIssue = session.result!.issues.first!
        session.show(stringIssue, related: true)
        for _ in 0..<16 { await settle(host, 20) }
        try check(scroll.contentView.bounds.origin.y < 40, "related-string-start-offscreen-navigation")
        session.preferences.wordWrap = false; await settle(host, 250)
        try press("jwt-encoder-show-detection", in: window)
        var horizontal: [Double] = []
        for _ in 0..<16 { await settle(host, 20); horizontal.append(scroll.contentView.bounds.origin.x) }
        print("T078_HORIZONTAL_MOTION \(horizontal)")
        try check(horizontal.last! > 1000 && (reduced || Set(horizontal.map(Int.init)).count > 3), "word-wrap-off-horizontal-detection")
        session.show(stringIssue, related: true)
        for _ in 0..<16 { await settle(host, 20) }
        try check(scroll.contentView.bounds.origin.x < 60, "horizontal-related-returns-to-start")
        // Losing key-window status (menus, another window) must never mask a draft.
        let unrelated = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: unrelated)
        await settle(host)
        try check(!session.masked, "unrelated-window-resign-does-not-mask")
        for width in [430.0, 800.0, 1300.0] {
            window.setContentSize(.init(width: width, height: 850)); await settle(host, 180)
            try check(header.accessibilityValue() != nil && payload.accessibilityValue() != nil, "both-json-fields-visible-at-\(Int(width))")
            try check(identities.allSatisfy { id in all(NSTextView.self, host).contains { ObjectIdentifier($0) == id } }, "stable-editors-at-\(Int(width))")
        }
        session.hide(); await settle(host)
        try check(header.accessibilityValue() == nil && payload.accessibilityValue() == nil && session.copy() == nil, "global-mask-native-privacy")
        session.reveal(); await settle(host)
        // Clear All retires editors after purging their own managers. Exercise the same
        // production command on a standalone retained editor, not a test implementation.
        let commands = JSONEditorCommands()
        host.rootView = AnyView(JSONTextEditor(text: Binding(get: { session.header }, set: { session.header = $0 }), commands: commands, privateUndo: true, contentName: "Purge probe"))
        await settle(host)
        guard let field = all(NSTextView.self, host).first else { throw Failure.check("purge-editor") }
        window.makeFirstResponder(field); field.insertText(" ", replacementRange: .init(location: 0, length: 0)); await settle(host)
        try check(field.undoManager!.canUndo, "json-native-undo-registered")
        commands.purgeUndo?(); session.clear(); await settle(host)
        try check(!field.undoManager!.canUndo && session.artifact == nil && session.key.isEmpty, "clear-all-history-and-working-data")
        field.window?.makeFirstResponder(nil)
        host.rootView = AnyView(JWTEncoderView(workspace: session))
        session.key = String(repeating: "k", count: 64)
        session.payload = "{\"s\":\"" + String(repeating: "a", count: 195000) + "\"}"
        await settle(host, 150)
        let pulse = Task { @MainActor in
            var values: [Double] = [], previous = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = Date(); values.append(now.timeIntervalSince(previous) * 1000); previous = now
            }
            return values
        }
        let began = Date()
        await session.run().value; await settle(host, 100)
        pulse.cancel(); let gaps = await pulse.value
        print("T078_NATIVE_PUBLICATION elapsedMS=\(Date().timeIntervalSince(began) * 1000) maxHeartbeatGapMS=\(gaps.max() ?? 0) tokenBytes=\(session.artifact?.byteCount ?? 0)")
        try check(session.artifact != nil && (gaps.max() ?? 0) < 500, "near-limit-session-main-actor-responsive")
        print("T078_NATIVE_FINAL_OK")
    }
}
