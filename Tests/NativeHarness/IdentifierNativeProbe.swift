import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

@main struct IdentifierNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in
            do { try await run(); print("T022_NATIVE_PASSED") } catch { print("T022_NATIVE_FAILURE \(error)"); exit(1) }
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
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws { guard condition() else { throw Failure.check(name) }; print("T022_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func run() async throws {
        let suite = "T022-native-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { entries in let item = NSPasteboardItem(); for (key, data) in entries { item.setData(data, forType: key) }; return item }) }
        let session = IdentifierWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: IdentifierGeneratorView(workspace: session))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1100, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 250)
        try check(session.batch == nil, "initial-empty")
        try press("identifier-generate", in: window)
        for _ in 0..<100 where session.busy { await settle(host, 10) }
        await settle(host)
        let first = session.batch!.values[0]
        try check(first.count == 36 && UUID(uuidString: first) != nil, "native-generate-v4")
        await settle(host, 300)
        try press("identifier-copy-row-0", in: window)
        try check(NSPasteboard.general.string(forType: .string) == first, "native-copy-exact-row")
        session.preferences.kind = .nanoID; session.preferences.nanoAlphabetPreset = .custom
        await settle(host, 250)
        guard let editor = all(NSTextView.self, host).first(where: { $0.accessibilityIdentifier() == "identifier-custom-alphabet" }) else { throw Failure.check("native-editor") }
        let identity = ObjectIdentifier(editor)
        window.makeFirstResponder(editor); editor.insertText("ab", replacementRange: .init(location: 0, length: 0)); await settle(host)
        try check(session.customAlphabet == "ab", "native-custom-input")
        editor.undoManager?.undo(); await settle(host)
        try check(session.customAlphabet.isEmpty, "native-undo")
        editor.undoManager?.redo(); await settle(host)
        try check(session.customAlphabet == "ab", "native-redo")
        let selection = editor.selectedRange()
        await session.run()?.value; await settle(host)
        try check(editor.selectedRange() == selection && window.firstResponder === editor, "generate-keeps-caret-focus")
        host.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 430, height: 850)); await settle(host, 280)
        try check(all(NSTextView.self, host).contains { ObjectIdentifier($0) == identity }, "resize-theme-keeps-editor-identity")
        try check(session.customAlphabet == "ab", "resize-keeps-draft")
        window.makeFirstResponder(editor); editor.setSelectedRange(.init(location: 0, length: editor.string.utf16.count))
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("a\tb", forType: .string); editor.paste(nil); await settle(host)
        try check(session.customAlphabet == "a\tb" && session.validationIssue != nil, "invalid-paste-not-sanitized")
        try press("identifier-clear", in: window); await settle(host)
        try check(!editor.undoManager!.canUndo && session.customAlphabet.isEmpty && session.batch == nil, "clear-removes-own-undo-and-results")
        window.setContentSize(NSSize(width: 1100, height: 800))
        session.preferences.kind = .uuidV7; session.countText = "10000"
        await session.run()?.value; await settle(host, 250)
        guard let table = all(NSTableView.self, host).first, let scroll = table.enclosingScrollView else { throw Failure.check("native-table") }
        try check(table.numberOfRows == 10_000 && scroll.hasVerticalScroller && !scroll.autohidesScrollers, "ten-thousand-rows-and-mouse-scrollbar")
        let cellCount = table.subviews.count
        try check(cellCount < 100, "bounded-native-row-views")
        print("T022_NATIVE_RENDERED_SUBVIEWS \(cellCount)")
        // Test the shared opt-in motion with a genuinely offscreen row and sampled native origins.
        let motion = NativeListScrollMotion(), reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        let target = table.rect(ofRow: 9999)
        motion.reveal(target, in: scroll, animated: !reduced)
        var samples = [Double]()
        for _ in 0..<12 { await settle(host, 20); samples.append(scroll.contentView.bounds.origin.y) }
        print("T022_MOTION \(samples)")
        let distinct = Set(samples.map { Int($0) })
        try check(reduced ? distinct.count == 1 : distinct.count > 3, "offscreen-motion-frames")
        try check(scroll.contentView.bounds.maxY >= target.maxY - 1, "last-row-visible")
        window.makeFirstResponder(table)
        session.selection = 9999
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8) { _ = table.performKeyEquivalent(with: event) }
        try check(NSPasteboard.general.string(forType: .string) == session.batch?.values.last, "focused-tree-copy-last-row")
        motion.reveal(table.rect(ofRow: 0), in: scroll, animated: !reduced); motion.cancel()
        let cancelledOrigin = scroll.contentView.bounds.origin.y
        await settle(host, 250)
        try check(scroll.contentView.bounds.origin.y == cancelledOrigin, "cancel-stops-old-scroll")
        if !ProcessInfo.processInfo.arguments.contains("--ui-only") {
        for kind in IdentifierKind.allCases {
            for count in [1, 1000, 10_000] {
                let start = ProcessInfo.processInfo.systemUptime
                let result = await IdentifierGenerator().generate(.init(kind: kind, count: count, nanoLength: 256))
                try check(result.batch?.values.count == count, "stress-\(kind)-\(count)")
                print("T022_STRESS kind=\(kind.rawValue) count=\(count) length=\(kind == .nanoID ? 256 : 0) ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
            }
        }
        let alphabet65 = IdentifierAlphabet.urlSafe.symbols + "!"
        let start = ProcessInfo.processInfo.systemUptime
        let custom = await IdentifierGenerator().generate(.init(kind: .nanoID, count: 10_000, nanoLength: 256, alphabet: .custom, customAlphabet: alphabet65))
        try check(custom.batch?.values.count == 10_000, "stress-custom65")
        print("T022_STRESS custom65 ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
        let copyStart = ProcessInfo.processInfo.systemUptime
        var copiedBytes = 0
        await session.copyAll(.json) { copiedBytes = $0.utf8.count }?.value
        print("T022_STRESS jsonCopyBytes=\(copiedBytes) ms=\((ProcessInfo.processInfo.systemUptime - copyStart) * 1000)")
        }
        // Frame samples measure actual details layout; observer identity remains stable.
        session.selection = 9999; session.showDetails = false; await settle(host, 250)
        session.showDetails = true
        var heights = [Double]()
        for _ in 0..<12 { await settle(host, 20); heights.append(Double(table.enclosingScrollView?.frame.height ?? 0)) }
        print("T022_DETAILS_HEIGHTS \(heights)")
        try check(reduced || Set(heights.map { Int($0) }).count > 2, "details-animation-samples")
        session.preferences.kind = .nanoID; session.preferences.nanoAlphabetPreset = .numeric; session.lengthText = "1"
        await settle(host, 250)
        await session.run()?.value
        var noteHeights = [Double]()
        for _ in 0..<12 { await settle(host, 20); noteHeights.append(Double(scroll.frame.height)) }
        print("T022_NOTE_HEIGHTS \(noteHeights)")
        try check(session.batch?.duplicateCount == 9990, "duplicate-note-no-filtering")
        try check(reduced ? Set(noteHeights.map { Int($0) }).count == 1 : Set(noteHeights.map { Int($0) }).count > 2, "notes-transition-samples")
        session.preferences.nanoAlphabetPreset = .urlSafe
        // Input heartbeat during the largest configured generation request.
        session.preferences.kind = .nanoID; session.lengthText = "256"
        var ticks = [Double](), running = true
        let heartbeat = Task { @MainActor in while running { ticks.append(ProcessInfo.processInfo.systemUptime); try? await Task.sleep(for: .milliseconds(5)) } }
        let publishStart = ProcessInfo.processInfo.systemUptime
        await session.run()?.value; running = false; await heartbeat.value
        let maxGap = zip(ticks.dropFirst(), ticks).map { ($0 - $1) * 1000 }.max() ?? 0
        print("T022_RESPONSIVENESS publicationMs=\((ProcessInfo.processInfo.systemUptime - publishStart) * 1000) heartbeatMaxGapMs=\(maxGap) ticks=\(ticks.count)")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage); print("T022_PEAK_BYTES \(usage.ru_maxrss)")
        if let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toolbox-t022-mac.png"))
        }
        window.close()
    }
}
