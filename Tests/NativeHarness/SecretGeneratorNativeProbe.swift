import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

@main struct SecretGeneratorNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in
            do { try await run(); print("T023_T024_NATIVE_PASSED") } catch { print("T023_T024_NATIVE_FAILED \(error)"); exit(1) }
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
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("SECRET_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func run() async throws {
        let suite = "Secrets-native-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { entries in let item = NSPasteboardItem(); for (key, data) in entries { item.setData(data, forType: key) }; return item }) }
        let session = SecretGeneratorWorkspaceSession(kind: .password, repository: .init(kind: .password, defaults: defaults))
        let host = NSHostingView(rootView: PasswordGeneratorView(workspace: session))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1100, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 250)
        try check(session.batch == nil && session.lengthText == "13", "initial-empty-default13")
        try press("secret-generate", in: window)
        for _ in 0..<100 where session.busy { await settle(host, 10) }
        await settle(host)
        let first = try require(session.batch?.values.first, "generated")
        try check(first.utf8.count == 13, "generate13")
        try press("secret-copy-single", in: window)
        try check(NSPasteboard.general.string(forType: .string) == first, "copy-exact-single")
        try press("secret-visibility", in: window); await settle(host)
        let axText = ax(window).flatMap { [value($0, "accessibilityLabel") as? String, value($0, "accessibilityValue") as? String].compactMap { $0 } }.joined(separator: "|")
        try check(session.hidden && !axText.contains(first), "hidden-ax-has-no-secret")
        try press("secret-visibility", in: window)
        session.advanced = true; session.mode = .custom; await settle(host, 250)
        guard let editor = all(NSTextView.self, host).first(where: { $0.accessibilityIdentifier() == "secret-custom-alphabet" }) else { throw Failure.check("custom-editor") }
        let identity = ObjectIdentifier(editor)
        window.makeFirstResponder(editor); editor.insertText("ab", replacementRange: .init(location: 0, length: 0)); await settle(host)
        try check(session.customAlphabet == "ab", "custom-input")
        editor.undoManager?.undo(); await settle(host); try check(session.customAlphabet.isEmpty, "undo")
        editor.undoManager?.redo(); await settle(host); try check(session.customAlphabet == "ab", "redo")
        let caret = editor.selectedRange()
        await session.run()?.value; await settle(host)
        try check(editor.selectedRange() == caret && window.firstResponder === editor, "generate-keeps-caret-focus")
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 390, height: 850)); await settle(host, 250)
        try check(all(NSTextView.self, host).contains { ObjectIdentifier($0) == identity }, "narrow-dark-stable-editor")
        try check(session.batch != nil && session.customAlphabet == "ab", "resize-keeps-results-draft")
        try press("secret-clear", in: window); await settle(host)
        try check(session.batch == nil && session.customAlphabet.isEmpty && !editor.undoManager!.canUndo, "clear-purges-custom-undo")
        window.setContentSize(.init(width: 1100, height: 800)); session.advanced = false
        session.countText = "1000"; session.lengthText = "128"
        var ticks = [Double](), running = true
        let heartbeat = Task { @MainActor in while running { ticks.append(ProcessInfo.processInfo.systemUptime); try? await Task.sleep(for: .milliseconds(5)) } }
        let start = ProcessInfo.processInfo.systemUptime
        await session.run()?.value; running = false; await heartbeat.value
        let publicationMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
        await settle(host, 250)
        try check(session.batch?.values.count == 1000, "maximum-password-batch")
        print("SECRET_DEBUG_BATCH_MS \(publicationMs) heartbeatMaxGapMs=\(zip(ticks.dropFirst(), ticks).map { ($0 - $1) * 1000 }.max() ?? 0)")
        guard let table = all(NSTableView.self, host).first, let scroll = table.enclosingScrollView else { throw Failure.check("table") }
        try check(table.numberOfRows == 1000 && table.subviews.count < 100 && !scroll.autohidesScrollers, "virtualized-thousand-rows-scrollbar")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion"), motion = NativeListScrollMotion()
        motion.reveal(table.rect(ofRow: 999), in: scroll, animated: !reduced)
        var samples = [Double]()
        for _ in 0..<15 { await settle(host, 20); samples.append(scroll.contentView.bounds.origin.y) }
        print("SECRET_SCROLL_FRAMES \(samples)")
        try check(reduced ? Set(samples.map(Int.init)).count == 1 : Set(samples.map(Int.init)).count > 3, "offscreen-scroll-motion")
        try check(scroll.contentView.bounds.maxY >= table.rect(ofRow: 999).maxY - 1, "last-row-visible")
        session.selection = 999; await settle(host)
        session.showDetails = true
        var heights = [Double]()
        for _ in 0..<15 { await settle(host, 20); heights.append(Double(scroll.frame.height)) }
        print("SECRET_DETAILS_FRAMES \(heights)")
        try check(reduced ? Set(heights.map(Int.init)).count == 1 : Set(heights.map(Int.init)).count > 2, "details-motion")
        try press("secret-copy-selected", in: window)
        try check(NSPasteboard.general.string(forType: .string) == session.batch?.values.last, "selected-full-copy")
        session.concealSecrets(); await settle(host)
        let last = session.batch!.values.last!
        let concealed = ax(window).flatMap { [value($0, "accessibilityLabel") as? String, value($0, "accessibilityValue") as? String].compactMap { $0 } }.joined(separator: "|")
        if concealed.contains(last) {
            for object in ax(window) {
                if [value(object, "accessibilityLabel") as? String, value(object, "accessibilityValue") as? String].compactMap({ $0 }).contains(where: { $0.contains(last) }) {
                    print("SECRET_AX_LEAK_CLASS \(type(of: object)) id=\(value(object, "accessibilityIdentifier") as? String ?? "none")")
                }
            }
        }
        try check(!concealed.contains(last), "batch-details-ax-masked")
        session.toggleVisibility(); await settle(host)
        await session.run()?.value; await settle(host, 5)
        session.concealSecrets(); await settle(host, 20)
        try check(!all(NSImageView.self, host).contains { String(describing: type(of: $0)).contains("TreeFadeImage") }, "conceal-cancels-replacement-snapshot")
        let phrase = SecretGeneratorWorkspaceSession(kind: .passphrase, repository: .init(kind: .passphrase, defaults: defaults))
        let phraseHost = NSHostingView(rootView: PassphraseGeneratorView(workspace: phrase))
        window.contentView = phraseHost; await settle(phraseHost, 250)
        try press("secret-generate", in: window)
        for _ in 0..<100 where phrase.busy { await settle(phraseHost, 10) }
        await settle(phraseHost)
        try check(phrase.batch?.dictionaryVersion != nil && phrase.batch!.values[0].count > 10, "app-bundled-wordlist-generation")
        try press("secret-copy-single", in: window)
        try check(NSPasteboard.general.string(forType: .string) == phrase.batch!.values[0], "phrase-exact-copy")
        phrase.preferences.separator = .space; phrase.preferences.appendDigit = true; phrase.preferences.letterCase = .titleCase
        try check(phrase.settingsDiffer && phrase.batch != nil, "phrase-settings-do-not-regenerate")
        await phrase.run()?.value; await settle(phraseHost)
        try check(phrase.batch!.values[0].split(separator: " ").count == 7, "phrase-options-applied")
        window.setContentSize(.init(width: 390, height: 700)); phraseHost.appearance = NSAppearance(named: .aqua); await settle(phraseHost, 250)
        try check(phrase.batch != nil, "phrase-narrow-light-preserved")
        let fresh = SecretGeneratorWorkspaceSession(kind: .password, repository: .init(kind: .password, defaults: defaults))
        try check(fresh.batch == nil && fresh.customAlphabet.isEmpty, "new-session-private")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage); print("SECRET_NATIVE_PEAK_BYTES \(usage.ru_maxrss)")
        window.orderOut(nil)
    }
    @MainActor static func require<T>(_ value: T?, _ name: String) throws -> T { guard let value else { throw Failure.check(name) }; return value }
}
