// Compile with JSONCore/**/*.swift, JSONTool except FormatterView, JSONTreeTable,
// JSONTreeNodeDetails and JSONPath/*.swift. Uses only synthetic, memory-only input.
import AppKit
import SwiftUI
import Darwin

@main struct JSONPathNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run() } catch { print("PATH_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        app.run()
    }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw Failure.check(name) }
        print("PATH_NATIVE_PASS \(name)")
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) }
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 100) async {
        host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded()
    }
    @MainActor static func screenshot(_ window: NSWindow, _ name: String) throws {
        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/toolbox-path-\(name).png"]
        try capture.run(); capture.waitUntilExit()
        if capture.terminationStatus != 0, let host = window.contentView,
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toolbox-path-\(name)-layout-only.png"))
        }
    }
    @MainActor static func run() async throws {
        let domain = "developerToolbox.path.native.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = JSONPathWorkspaceSession(repository: .init(defaults: defaults))
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        let host = NSHostingView(rootView: JSONPathExplorerView(workspace: session))
        let window = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 1100, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host)
        let editor = all(JSONNativeTextView.self, host).first!
        let identity = ObjectIdentifier(editor)
        let source = #"{"users":[{"name":"Ada","active":true},{"name":"Bob","active":false}]}"#
        window.makeFirstResponder(editor)
        editor.insertText(source, replacementRange: NSRange(location: 0, length: 0))
        await settle(host)
        try check(session.input == source, "native-input-binding")
        session.query = "$.users[?@.active == true].name"
        let caret = editor.selectedRange()
        await session.run().value; await settle(host)
        try check(session.rows.count == 1 && editor.selectedRange() == caret, "run-preserves-caret")
        let table = all(NSTableView.self, host).first!
        try check(table.numberOfRows == 1, "native-result-row")
        try screenshot(window, "native-light")
        host.appearance = NSAppearance(named: .darkAqua); await settle(host)
        try screenshot(window, "native-dark")
        try check(ObjectIdentifier(all(JSONNativeTextView.self, host).first!) == identity && session.result != nil, "theme-retains-editor-data-results")
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { session.inputCollapsed = true }
        var heights: [Int] = []
        for _ in 0..<14 { await settle(host, 20); heights.append(Int(editor.enclosingScrollView?.frame.width ?? -1)) }
        print("PATH_NATIVE_COLLAPSE reduced=\(reduced) widths=\(heights)")
        try check((heights.last ?? 999) <= 32 && session.inputCollapsed && (reduced || Set(heights).count > 2), "smooth-collapse")
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { session.inputCollapsed = false }
        await settle(host, 280)
        window.setContentSize(NSSize(width: 390, height: 760)); await settle(host)
        try check(ObjectIdentifier(all(JSONNativeTextView.self, host).first!) == identity && session.input == source, "compact-layout-editor-identity")
        try screenshot(window, "native-compact")
        window.setContentSize(NSSize(width: 1100, height: 780)); await settle(host)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.breakUndoCoalescing()
        editor.insertText(" ", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        try check(session.result == nil && session.rows.isEmpty, "edit-removes-stale-results")
        editor.undoManager?.undo(); await settle(host)
        try check(session.input == source && editor.string == source, "native-undo")
        editor.undoManager?.redo(); await settle(host)
        try check(session.input == source + " ", "native-redo")
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        defer {
            pasteboard.clearContents()
            if let previous { pasteboard.writeObjects(previous.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }) }
        }
        pasteboard.clearContents(); pasteboard.setString("[1,2]", forType: .string)
        window.makeFirstResponder(editor); editor.selectAll(nil); editor.paste(nil)
        for _ in 0..<30 { if session.document != nil { break }; await settle(host, 20) }
        try check(session.document?.source == "[1,2]" && session.result == nil, "system-paste-checks-without-auto-query")
        // Offscreen source jump from an actual double click in the results table.
        session.input = "{\n" + (0..<900).map { "\"k\($0)\":0" }.joined(separator: ",\n") + ",\n\"target\":42\n}"
        session.query = "$.target"
        await session.run().value; session.inputCollapsed = true; await settle(host, 300)
        window.makeFirstResponder(table)
        let row = table.rect(ofRow: 0), point = table.convert(NSPoint(x: 120, y: row.midY), to: nil)
        for count in [1,2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false); await settle(host, 10)
            }
            await settle(host, 40)
        }
        var scroll: [Int] = [], pulse: [Int] = []
        for _ in 0..<30 {
            await settle(host, 20)
            scroll.append(Int(editor.enclosingScrollView?.contentView.bounds.minY ?? -1))
            pulse.append(Int(editor.adornments.navigationHighlightOpacity * 1000))
        }
        print("PATH_NATIVE_SOURCE_SCROLL reduced=\(reduced) positions=\(scroll)")
        print("PATH_NATIVE_CLICK collapsed=\(session.inputCollapsed) selected=\(String(describing: session.selection)) point=\(point) tableInWindow=\(table.window != nil)")
        let node = session.document!.nodes[session.result!.nodeIDs[0]]
        try check(!session.inputCollapsed && editor.selectedRange().location == node.range.location, "double-click-source-anchor")
        try check(editor.adornments.caretRect(at: node.range.location).map { editor.visibleRect.intersects($0) } == true, "offscreen-source-visible")
        try check(reduced || Set(scroll.filter { $0 > 0 }).count > 2, "smooth-source-scroll")
        try check(window.firstResponder !== editor, "source-jump-does-not-steal-focus")
        let pulseSelection = editor.selectedRange(), pulseSource = session.input
        try check(editor.adornments.navigationHighlight == node.range && !editor.adornments.navigationHighlightRects().isEmpty, "source-attention-marker-visible")
        try screenshot(window, reduced ? "pulse-reduced" : "pulse")
        for _ in 0..<80 {
            await settle(host, 30)
            pulse.append(Int(editor.adornments.navigationHighlightOpacity * 1000))
        }
        print("PATH_NATIVE_PULSE reduced=\(reduced) opacity_milli=\(pulse)")
        let high = pulse.map { $0 > 150 }
        let peaks = high.enumerated().filter { $0.element && ($0.offset == 0 || !high[$0.offset - 1]) }.count
        try check(reduced ? pulse.filter { $0 > 0 }.allSatisfy { $0 == 240 } : peaks == 2, "two-pulses-or-static-reduced-motion")
        try check(editor.adornments.navigationHighlight == nil && editor.adornments.navigationHighlightOpacity == 0, "attention-marker-expires")
        try check(editor.selectedRange() == pulseSelection && session.input == pulseSource && window.firstResponder !== editor, "pulse-preserves-source-selection-focus")
        // Maximum permitted short-value array with continuous native virtualization.
        session.input = "[" + Array(repeating: "0", count: 131_071).joined(separator: ",") + "]"
        session.query = "$[*]"; session.inputCollapsed = true
        let started = ContinuousClock.now
        await session.run().value; await settle(host, 150)
        try check(table.numberOfRows == 131_071, "continuous-maximum-results")
        session.moveSelection(131_071); await settle(host)
        try check(table.rows(in: table.visibleRect).contains(131_070), "last-result-reachable")
        func views(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + views($1) } }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("PATH_NATIVE_STRESS utf16=262143 rows=\(table.numberOfRows) live_views=\(views(host)) wall_with_settle=\(started.duration(to: .now)) peak_bytes=\(usage.ru_maxrss)")
        try screenshot(window, "native-stress")
        session.input = "[1,]"; session.query = "$"; session.inputCollapsed = false
        await session.run().value; await settle(host)
        try check(session.status == .invalidJSON && session.context != nil && session.rows.isEmpty, "invalid-json-diagnostics")
        try screenshot(window, "native-invalid")
        window.contentView = nil; window.close()
    }
}
