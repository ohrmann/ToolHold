// Compile with JSONCore/*.swift, JSONTool/*.swift (except JSONFormatterView),
// JSONTreeTable.swift and JSONDiff/*.swift. No app preferences or working data are saved.
import AppKit
import SwiftUI
import Darwin

@main struct JSONDiffNativeProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run() }
            catch { print("DIFF_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        app.run()
    }
    enum Failure: Error { case check(String) }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        if !condition() { throw Failure.check(label) }
        print("DIFF_NATIVE_PASS \(label)")
    }
    @MainActor static func descendants<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, $0) }
    }
    @MainActor static func settle(_ host: NSView, milliseconds: Int = 100) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(milliseconds))
        host.layoutSubtreeIfNeeded()
    }
    @MainActor static func screenshot(_ host: NSView, _ name: String) throws {
        if let window = host.window {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/toolbox-diff-\(name).png"]
            try capture.run(); capture.waitUntilExit()
            if capture.terminationStatus == 0 { return }
        }
        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toolbox-diff-\(name).png"))
    }
    @MainActor static func run() async throws {
        let domain = "developerToolbox.diff.native.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = JSONDiffWorkspaceSession(repository: .init(defaults: defaults))
        let reduced = CommandLine.arguments.contains("--reduce-motion")
        let host = NSHostingView(rootView: JSONDiffView(workspace: session).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; host.appearance = NSAppearance(named: .aqua); window.makeKeyAndOrderFront(nil)
        await settle(host)
        let editors = descendants(JSONNativeTextView.self, host)
        try check(editors.count == 2, "two-native-editors")
        let identities = Set(editors.map(ObjectIdentifier.init))
        let a = #"{"price":1,"user":{"name":"é😀"},"removed":true}"#
        let b = #"{"price":1.0,"user":{"name":"e\u0301😀"},"added":[1,2]}"#
        for (editor, text) in zip(editors, [a,b]) {
            window.makeFirstResponder(editor)
            editor.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        }
        await settle(host)
        try check(session.before.source == a && session.after.source == b, "native-input-bindings")
        let caret = editors[1].selectedRange()
        await session.compare().value; await settle(host)
        try check(session.result?.changes.count == 4, "compare-four-changes")
        try check(editors[1].selectedRange() == caret, "compare-preserves-caret")
        try screenshot(host, "native-light")
        host.appearance = NSAppearance(named: .darkAqua); await settle(host)
        try screenshot(host, "native-dark")
        try check(Set(descendants(JSONNativeTextView.self, host).map(ObjectIdentifier.init)) == identities, "appearance-editor-identities")
        let initialHeight = editors[0].enclosingScrollView?.frame.height ?? 0
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { session.inputsCollapsed = true }
        var frames: [Int] = []
        for _ in 0..<12 {
            await settle(host, milliseconds: 20)
            frames.append(Int(editors[0].enclosingScrollView?.frame.height ?? -1))
        }
        print("DIFF_NATIVE_COLLAPSE reduced=\(reduced) initial=\(initialHeight) heights=\(frames)")
        try check(frames.last == 0 && (reduced || Set(frames).count > 2), "smooth-collapse-or-reduced-motion")
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { session.inputsCollapsed = false }
        await settle(host, milliseconds: 300)
        window.setContentSize(NSSize(width: 390, height: 760)); await settle(host)
        try check(Set(descendants(JSONNativeTextView.self, host).map(ObjectIdentifier.init)) == identities, "compact-editor-identities")
        try check(session.before.source == a && session.after.source == b && session.result?.changes.count == 4, "resize-retains-input-result")
        try screenshot(host, "native-compact")
        window.setContentSize(NSSize(width: 1100, height: 780)); await settle(host)
        // Actual native typing/Undo/Paste and retained colors/gutter, not simulated source changes.
        let editor = editors[0]
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.insertText(" ", replacementRange: editor.selectedRange())
        try check(session.result == nil && session.rows.isEmpty, "edit-removes-stale-diff")
        editor.undoManager?.undo(); await settle(host)
        try check(editor.string == a && session.before.source == a, "native-undo")
        // Invalid snapshot and detection/related native navigation uses the same editor.
        session.before.source = #"{"a":[1,]}"#
        await session.compare().value; await settle(host)
        try check(session.before.result?.status == .invalid && session.after.document != nil && session.result == nil, "side-specific-invalid")
        try screenshot(host, "native-invalid")
        window.setContentSize(NSSize(width: 390, height: 760)); await settle(host, milliseconds: 300)
        try check((editors[0].enclosingScrollView?.frame.height ?? 0) >= 64, "invalid-compact-input-stays-editable")
        try screenshot(host, "native-invalid-compact")
        window.setContentSize(NSSize(width: 1100, height: 780)); await settle(host)
        let beforePane = editors[0]
        let pasteFixture = "[1,2]"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pasteFixture, forType: .string)
        window.makeFirstResponder(beforePane); beforePane.selectAll(nil); beforePane.paste(nil)
        for _ in 0..<30 {
            if session.before.document != nil { break }
            await settle(host, milliseconds: 20)
        }
        try check(session.before.document?.source == pasteFixture && session.result == nil, "system-paste-capture-without-auto-diff")
        // A genuine double click on a previously unselected row reveals both editors.
        let fields = (0..<900).map { "\"k\($0)\":0" }.joined(separator: ",\n")
        session.before.source = "{\n" + fields + ",\n\"x\":1,\n\"y\":1\n}"
        session.after.source = "{\n" + fields + ",\n\"x\":2,\n\"y\":2\n}"
        await session.compare().value
        session.inputsCollapsed = true
        await settle(host, milliseconds: 300)
        let resultTable = descendants(NSTableView.self, host).first!
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        await settle(host)
        let row = resultTable.rect(ofRow: 1)
        let location = resultTable.convert(NSPoint(x: 100, y: row.midY), to: nil)
        for count in [1, 2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: count, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
                await settle(host, milliseconds: 10)
            }
            await settle(host, milliseconds: 40)
        }
        var scrollFrames: [Int] = []
        for _ in 0..<30 {
            await settle(host, milliseconds: 20)
            scrollFrames.append(Int(editors[0].enclosingScrollView?.contentView.bounds.minY ?? -1))
        }
        print("DIFF_NATIVE_CLICK collapsed=\(session.inputsCollapsed) selected=\(String(describing: session.selection)) location=\(location)")
        try check(!session.inputsCollapsed && session.selection == 1, "double-click-reveals-both")
        let diff = session.result!, selected = diff.changes[1]
        try check(editors[0].selectedRange().location == diff.before.nodes[selected.before!].range.location &&
                  editors[1].selectedRange().location == diff.after.nodes[selected.after!].range.location, "both-source-anchors")
        for editor in editors {
            let caret = editor.adornments.caretRect(at: editor.selectedRange().location)!
            try check(editor.visibleRect.intersects(caret), "paired-target-visible")
        }
        print("DIFF_NATIVE_PAIRED_SCROLL reduced=\(reduced) frames=\(scrollFrames)")
        try check(reduced || Set(scrollFrames.filter { $0 > 0 }).count > 2, "smooth-paired-scroll")
        try check(window.firstResponder !== editors[0] && window.firstResponder !== editors[1], "paired-jump-keeps-result-focus")
        // Maximum permitted arrays, with every value changed. No artificial paging.
        session.before.source = "[" + Array(repeating: "0", count: 131_071).joined(separator: ",") + "]"
        session.after.source = "[" + Array(repeating: "1", count: 131_071).joined(separator: ",") + "]"
        session.inputsCollapsed = true
        await session.compare().value; await settle(host, milliseconds: 200)
        let table = descendants(NSTableView.self, host).first!
        try check(table.numberOfRows == 131_071, "continuous-maximum-rows")
        let clock = ContinuousClock.now
        session.move(131_071); await settle(host, milliseconds: 100)
        try check(table.rows(in: table.visibleRect).contains(131_070), "scroll-to-last-change")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        func viewCount(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + viewCount($1) } }
        print("DIFF_NATIVE_STRESS utf16_per_input=262143 rows=\(table.numberOfRows) live_views=\(viewCount(host)) scroll_duration=\(clock.duration(to: .now)) peak_bytes=\(usage.ru_maxrss)")
        try screenshot(host, "native-stress")
        window.contentView = nil; window.close()
    }
}
