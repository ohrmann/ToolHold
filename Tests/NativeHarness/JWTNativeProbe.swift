import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

@main struct JWTNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in do { try await run(); print("T020_NATIVE_PASSED") } catch { print("T020_NATIVE_FAILURE \(error)"); exit(1) }; exit(0) }
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
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("T020_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    static func encoded(_ source: String) -> String { Data(source.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func token(_ source: String) -> String { "eyJhbGciOiJub25lIn0." + encoded(source) + "." }
    @MainActor static func run() async throws {
        let suite = "JWTProbe." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let w = JWTWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: JWTInspectorView(workspace: w))
        let window = NSWindow(contentRect: .init(x: 40, y: 40, width: 1120, height: 820), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 300)
        let editors = all(JSONNativeTextView.self, host), ids = editors.map(ObjectIdentifier.init)
        guard let input = editors.first(where: { $0.isEditable }) else { throw Failure.check("input") }
        try check(editors.count == 3, "three-stable-native-editors")
        let raw = #"{"sub":"private-T020-marker","exp":1000,"s":"😀é"}"#
        let source = token(raw)
        window.makeFirstResponder(input); input.insertText(source, replacementRange: .init(location: 0, length: 0))
        await settle(host); let caret = input.selectedRange(); await w.run().value; await settle(host)
        try check(input.selectedRange() == caret && window.firstResponder === input, "decode-keeps-caret-focus")
        try check(w.result?.claims.count == 3, "claims-built")
        w.section = .payload; await settle(host)
        guard let payload = editors.first(where: { $0.accessibilityLabel() == "JWT Payload result" }) else { throw Failure.check("payload-editor") }
        try check(!payload.isEditable && payload.string.contains("private-T020-marker"), "readonly-json-presentation")
        input.breakUndoCoalescing(); input.insertText("x", replacementRange: .init(location: input.string.utf16.count, length: 0)); input.breakUndoCoalescing(); await settle(host)
        try check(w.result == nil && input.adornments.coordinates != nil, "edit-invalidates-without-gutter-clear")
        input.undoManager?.undo(); await settle(host); try check(w.input == source, "native-undo")
        input.undoManager?.redo(); await settle(host); try check(w.input == source + "x", "native-redo")
        input.undoManager?.undo(); await settle(host); await w.run().value; await settle(host)
        try press("jwt-mask"); await settle(host)
        try check(w.masked && input.accessibilityValue() == nil && payload.accessibilityValue() == nil, "native-values-hidden")
        try check(window.firstResponder !== input && !input.becomeFirstResponder(), "masked-input-cannot-focus")
        try check(!ax().contains { object in
            ["accessibilityValue", "accessibilityLabel"].contains { key in
                guard let text = value(object, key) as? String else { return false }
                return text.contains("private-T020-marker") || text.contains(source)
            }
        }, "masked-ax-tree-has-no-secret")
        // Restore all clipboard types after synthetic native Paste/Copy tests.
        let saved = NSPasteboard.general.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }) } ?? []
        defer {
            NSPasteboard.general.clearContents()
            let items = saved.map { data in let item = NSPasteboardItem(); for (type, bytes) in data { item.setData(bytes, forType: type) }; return item }
            if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("clipboard-sentinel", forType: .string)
        input.copy(nil); payload.copy(nil)
        try check(NSPasteboard.general.string(forType: .string) == "clipboard-sentinel", "masked-native-copy-denied")
        try press("jwt-mask"); await settle(host)
        try check(!w.masked && input.string == source && all(JSONNativeTextView.self, host).map(ObjectIdentifier.init) == ids, "reveal-preserves-editors-data")
        input.breakUndoCoalescing(); input.insertText("", replacementRange: .init(location: 0, length: input.string.utf16.count)); input.breakUndoCoalescing(); await settle(host)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(source, forType: .string)
        input.paste(nil); await settle(host, 300)
        while w.busy { await settle(host, 30) }
        try check(w.result?.claims.count == 3 && input.string == source, "native-paste-inspects-once")
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 560, height: 760)); await settle(host, 250)
        try check(w.input == source && all(JSONNativeTextView.self, host).map(ObjectIdentifier.init) == ids, "theme-resize-preserve-input-and-identity")
        try press("jwt-collapse-input")
        var heights: [Int] = []
        for _ in 0..<15 { await settle(host, 18); heights.append(Int(input.enclosingScrollView!.frame.height)) }
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        print("T020_COLLAPSE reduced=\(reduced) frames=\(heights)")
        try check(reduced ? Set(heights).count <= 2 : Set(heights).count > 2, "collapse-motion")
        try press("jwt-collapse-input"); await settle(host, 300)
        window.setContentSize(.init(width: 1120, height: 820)); host.appearance = NSAppearance(named: .aqua); await settle(host, 250)
        w.input = token("{\n" + (0..<700).map { "\"k\($0)\":0," }.joined(separator: "\n") + "\"bad\": ")
        let diagnosticWork = w.run()
        var diagnosticHeights = [Int(input.enclosingScrollView!.frame.height)]
        for _ in 0..<14 { await settle(host, 18); diagnosticHeights.append(Int(input.enclosingScrollView!.frame.height)) }
        await diagnosticWork.value
        print("T020_DIAGNOSTICS reduced=\(reduced) frames=\(diagnosticHeights)")
        try check(reduced ? Set(diagnosticHeights).count <= 2 : Set(diagnosticHeights).count > 2, "diagnostics-size-motion")
        guard let anchor = w.result?.issues.first(where: { $0.severity == .error })?.anchor else { throw Failure.check("eof-issue") }
        w.show(anchor); await settle(host, 30)
        var offsets: [Int] = []
        for _ in 0..<26 { await settle(host, 20); offsets.append(Int(payload.enclosingScrollView!.contentView.bounds.minY)) }
        print("T020_JUMP reduced=\(reduced) frames=\(offsets)")
        try check(reduced ? Set(offsets).count <= 2 : Set(offsets).count > 2, "smooth-decoded-json-eof-navigation")
        try check(payload.adornments.caretRect(at: anchor.range.location).map { payload.visibleRect.intersects($0) } == true, "decoded-eof-visible")
        w.preferences.wordWrap = false
        let long = "{\"s\":\"" + String(repeating: "a", count: 14000) + "\""
        w.input = token(long); await w.run().value; await settle(host, 200)
        guard let horizontalAnchor = w.result?.issues.first(where: { $0.severity == .error })?.anchor else { throw Failure.check("long-eof") }
        w.show(horizontalAnchor)
        var xs: [Int] = []
        for _ in 0..<26 { await settle(host, 20); xs.append(Int(payload.enclosingScrollView!.contentView.bounds.minX)) }
        print("T020_HORIZONTAL reduced=\(reduced) frames=\(xs)")
        try check(reduced ? Set(xs).count <= 2 : Set(xs).count > 2, "horizontal-decoded-navigation")
        try check(payload.adornments.caretRect(at: horizontalAnchor.range.location).map { payload.visibleRect.intersects($0) } == true, "horizontal-eof-visible")
        // UI stress uses many claims and a real native List, not an eager VStack.
        w.preferences.wordWrap = true; w.section = .claims
        let many = "{" + (0..<12000).map { "\"k\($0)\":0" }.joined(separator: ",") + "}"
        let start = ContinuousClock.now; w.input = token(many); let work = w.run()
        var gaps: [Double] = [], last = ProcessInfo.processInfo.systemUptime
        repeat { await settle(host, 10); let now = ProcessInfo.processInfo.systemUptime; gaps.append(now - last); last = now } while w.busy
        await work.value; await settle(host, 200)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("T020_NATIVE_STRESS tokenUTF16=\(w.input.utf16.count) claims=\(w.result?.claims.count ?? -1) elapsed=\(start.duration(to: .now)) heartbeatMax=\(gaps.max() ?? -1) nativeCells=\(all(NSTableCellView.self, host).count) peakBytes=\(usage.ru_maxrss)")
        try check(w.result?.claims.count == 12000 && gaps.count > 1, "large-tree-responsive-worker")
        if let table = all(NSTableView.self, host).first {
            table.scrollRowToVisible(11999); await settle(host, 200)
            try check(table.rows(in: table.visibleRect).location > 11900 && all(NSTableCellView.self, host).count < 100, "continuous-list-recycles-at-end")
        }
        try check(all(JSONNativeTextView.self, host).map(ObjectIdentifier.init) == ids, "stress-retains-native-editors")
        let fresh = JWTWorkspaceSession(repository: .init(defaults: defaults)); try check(fresh.input.isEmpty && fresh.result == nil, "new-session-empty")
        window.contentView = nil; window.close()
    }
}
