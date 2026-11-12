import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

@main struct TokenDigestNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in
            do { if ProcessInfo.processInfo.arguments.contains("--navigation-only") { try await navigationOnly() } else { try await run() }; print("T025_T027_NATIVE_PASSED") } catch { print("T025_T027_NATIVE_FAILED \(error)"); exit(1) }
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
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("DIGEST_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func navigationOnly() async throws {
        let suite = "Digest-navigation-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hash = DigestWorkspaceSession(defaults: defaults)
        hash.preferences.mode = .hex; hash.text = String(repeating: "a", count: 20_000) + "z"
        let host = NSHostingView(rootView: HashGeneratorView(workspace: hash))
        let window = NSWindow(contentRect: NSRect(x: 40,y: 40,width: 1100,height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); await settle(host, 250)
        await hash.run()?.value; await settle(host)
        let editor = all(NSTextView.self, host).first { $0.accessibilityIdentifier() == "digest-message" }!
        let scroll = editor.enclosingScrollView!
        scroll.contentView.scroll(to: .zero); try press("digest-show-error", in: window)
        var frames = [Double]()
        for _ in 0..<16 { await settle(host, 18); frames.append(scroll.contentView.bounds.origin.y) }
        print("DIGEST_FINAL_ERROR_FRAMES \(frames)")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        try check(reduced ? Set(frames.map(Int.init)).count == 1 : Set(frames.map(Int.init)).count > 2, "final-error-motion")
        try check(editor.selectedRange() == NSRange(location: 20_000, length: 1), "final-error-range")
        hash.text = String(repeating: "a", count: 20_001); await hash.run()?.value; await settle(host)
        scroll.contentView.scroll(to: .zero); try press("digest-show-error", in: window); await settle(host, 300)
        try check(editor.selectedRange() == NSRange(location: 20_001, length: 0) && scroll.contentView.bounds.origin.y > 1000, "eof-zero-range-reveal")
        let hmac = DigestWorkspaceSession(isHMAC: true, defaults: defaults)
        hmac.preferences.keyProfile = .hex; hmac.key = "xx"; hmac.keyHidden = true
        let hHost = NSHostingView(rootView: HMACGeneratorView(workspace: hmac)); window.contentView = hHost; await settle(hHost, 250)
        await hmac.run()?.value; await settle(hHost)
        try press("digest-show-error", in: window); await settle(hHost, 250)
        let key = all(NSTextView.self, hHost).first { $0.accessibilityIdentifier() == "digest-key" }
        try check(!hmac.keyHidden && key != nil && window.firstResponder === key && key?.selectedRange() == NSRange(location: 0,length: 1), "hidden-key-error-reveal-focus")
        window.close()
    }
    @MainActor static func run() async throws {
        let suite = "TokenDigest-native-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { entries in let item = NSPasteboardItem(); for (key, data) in entries { item.setData(data, forType: key) }; return item }) }
        let session = DigestWorkspaceSession(defaults: defaults)
        let host = NSHostingView(rootView: HashGeneratorView(workspace: session))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1100, height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); await settle(host, 250)
        guard let editor = all(NSTextView.self, host).first(where: { $0.accessibilityIdentifier() == "digest-message" }) else { throw Failure.check("message-editor") }
        let identity = ObjectIdentifier(editor)
        window.makeFirstResponder(editor); editor.insertText("abc", replacementRange: .init(location: 0, length: 0)); await settle(host)
        if session.text != "abc" { print("DIGEST_PROBE_INPUT_DEBUG native=\(editor.string) source=\(session.text) delegate=\(String(describing: editor.delegate)) responder=\(window.firstResponder === editor) editable=\(editor.isEditable)") }
        try check(session.text == "abc", "native-input")
        editor.undoManager?.undo(); await settle(host); try check(session.text.isEmpty, "undo")
        editor.undoManager?.redo(); await settle(host); try check(session.text == "abc", "redo")
        let caret = editor.selectedRange(); try press("digest-run", in: window)
        for _ in 0..<100 where session.busy { await settle(host, 5) }
        try check(session.value(.sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "native-hash")
        try check(editor.selectedRange() == caret && window.firstResponder === editor, "calculate-keeps-focus-caret")
        try press("digest-copy-sha256", in: window)
        try check(NSPasteboard.general.string(forType: .string) == session.value(.sha256), "native-copy")
        let rightScroll = all(NSScrollView.self, host).first { !($0.documentView is NSTextView) }!
        try press("digest-compare-toggle", in: window)
        var heights = [Double]()
        for _ in 0..<16 { await settle(host, 18); heights.append(Double(rightScroll.documentView?.frame.height ?? 0)) }
        print("DIGEST_COMPARE_FRAMES \(heights)")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        try check(reduced ? Set(heights.map(Int.init)).count == 1 : Set(heights.map(Int.init)).count > 2, "compare-motion")
        session.expected = session.value(.sha256)!; await settle(host); if session.comparison != "Match" { print("DIGEST_COMPARE_DEBUG current=\(session.current) comparison=\(session.comparison) source=\(session.text) expected=\(session.expected) selected=\(session.expectedAlgorithm) pref=\(session.preferences.expectedProfile)") }; try check(session.comparison == "Match", "compare-match")
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 390, height: 850)); await settle(host, 250)
        try check(all(NSTextView.self, host).contains { ObjectIdentifier($0) == identity }, "resize-dark-keeps-editor")
        try check(session.text == "abc" && session.current, "resize-dark-keeps-state")
        window.setContentSize(.init(width: 1100, height: 800)); await settle(host, 250)
        session.preferences.mode = .hex; session.text = String(repeating: "a", count: 20_000) + "z"
        await session.run()?.value; await settle(host, 100)
        guard let sourceScroll = editor.enclosingScrollView else { throw Failure.check("input-scroll") }
        sourceScroll.contentView.scroll(to: .zero)
        try press("digest-show-error", in: window)
        var errorOffsets = [Double]()
        for _ in 0..<16 { await settle(host, 18); errorOffsets.append(sourceScroll.contentView.bounds.origin.y) }
        print("DIGEST_ERROR_SCROLL_FRAMES \(errorOffsets)")
        try check(reduced ? Set(errorOffsets.map(Int.init)).count == 1 : Set(errorOffsets.map(Int.init)).count > 2, "error-scroll-motion")
        try check(editor.selectedRange() == NSRange(location: 20_000, length: 1), "error-exact-range")
        session.text = "abc"; session.preferences.mode = .text; await settle(host)
        session.preferences.mode = .file; await settle(host)
        try check(editor.superview == nil, "file-mode-detaches-retained-editor")
        try press("digest-choose-file", in: window); await settle(host, 250)
        try check(window.attachedSheet != nil || NSApp.windows.contains { $0 is NSOpenPanel }, "native-file-picker")
        window.attachedSheet?.cancelOperation(nil)
        for w in NSApp.windows { if let panel = w as? NSOpenPanel { panel.cancel(nil) } }
        await settle(host, 200)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileData = Data("file\u{0}🌱".utf8); try fileData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await session.chooseFile(url).value; try press("digest-run", in: window)
        for _ in 0..<100 where session.busy { await settle(host, 5) }
        try check(session.current && session.artifact?.bytes == Int64(fileData.count), "native-file-calculate")
        session.preferences.mode = .text; await settle(host)
        session.text = "é"; await session.run()?.value; session.text = "e\u{301}"; await settle(host)
        try check(!session.current && editor.string.utf8.elementsEqual(session.text.utf8), "canonical-distinct-native-source")
        try press("digest-clear", in: window); await settle(host)
        try check(!editor.undoManager!.canUndo && session.text.isEmpty, "clear-undo-purged")
        let hmac = DigestWorkspaceSession(isHMAC: true, defaults: defaults)
        let hHost = NSHostingView(rootView: HMACGeneratorView(workspace: hmac)); window.contentView = hHost
        window.setContentSize(.init(width: 1100, height: 800)); await settle(hHost, 250)
        guard let key = all(NSTextView.self, hHost).first(where: { $0.accessibilityIdentifier() == "digest-key" }) else { throw Failure.check("key-editor") }
        let keyIdentity = ObjectIdentifier(key)
        window.makeFirstResponder(key); key.insertText("key", replacementRange: .init(location: 0, length: 0)); await settle(hHost)
        key.undoManager?.undo(); await settle(hHost); try check(hmac.key.isEmpty, "key-undo")
        key.undoManager?.redo(); await settle(hHost); try check(hmac.key == "key", "key-redo")
        hmac.text = "The quick brown fox jumps over the lazy dog"; await hmac.run()?.value; await settle(hHost)
        try check(hmac.value(.sha256) == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", "hmac-native")
        try press("digest-key-visibility", in: window); await settle(hHost)
        let visible = ax(window).filter { value($0, "accessibilityHidden") as? Bool != true }
        try check(!visible.contains { (value($0, "accessibilityIdentifier") as? String) == "digest-key" }, "key-hidden-ax")
        try press("digest-key-visibility", in: window); await settle(hHost)
        try check(all(NSTextView.self, hHost).contains { ObjectIdentifier($0) == keyIdentity }, "key-reveal-retains-editor")
        hmac.concealSecrets(); await settle(hHost)
        let axText = ax(window).flatMap { [value($0,"accessibilityLabel") as? String, value($0,"accessibilityValue") as? String].compactMap { $0 } }.joined(separator: "|")
        try check(!axText.contains(hmac.value(.sha256)!), "hmac-hidden-result-ax")
        let token = TokenWorkspaceSession(defaults: defaults)
        let tHost = NSHostingView(rootView: TokenGeneratorView(workspace: token)); window.contentView = tHost; await settle(tHost, 250)
        try press("token-generate", in: window)
        for _ in 0..<100 where token.busy { await settle(tHost, 5) }
        try check(token.presentation?.values.first?.count == 43, "token-default")
        try press("token-copy-single", in: window)
        try check(NSPasteboard.general.string(forType: .string) == token.presentation?.values.first, "token-copy")
        token.bytesText = "1024"; token.countText = "1000"; await token.run()?.value; await settle(tHost, 250)
        guard let table = all(NSTableView.self, tHost).first, let scroll = table.enclosingScrollView else { throw Failure.check("token-table") }
        try check(table.numberOfRows == 1000 && table.subviews.count < 100 && !scroll.autohidesScrollers, "token-recycled-rows-scrollbar")
        let movement = NativeListScrollMotion(); movement.reveal(table.rect(ofRow: 999), in: scroll, animated: !reduced)
        var offsets = [Double]()
        for _ in 0..<16 { await settle(tHost, 18); offsets.append(scroll.contentView.bounds.origin.y) }
        print("TOKEN_SCROLL_FRAMES \(offsets)")
        try check(reduced ? Set(offsets.map(Int.init)).count == 1 : Set(offsets.map(Int.init)).count > 3, "token-scroll-motion")
        try check(scroll.contentView.bounds.maxY >= table.rect(ofRow: 999).maxY - 1, "token-offscreen-target")
        token.selection = 999; token.details = true; await settle(tHost, 250)
        token.concealSecrets(); await settle(tHost)
        let secret = token.presentation!.values.last!
        let hidden = ax(window).flatMap { [value($0,"accessibilityLabel") as? String, value($0,"accessibilityValue") as? String].compactMap { $0 } }.joined(separator: "|")
        try check(!hidden.contains(secret), "token-offscreen-ax-hidden")
        window.close()
    }
}
