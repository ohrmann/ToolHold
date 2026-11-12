import AppKit
import SwiftUI

@main struct CSVTableNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run() } catch { print("TABLE_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] { (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) } }
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw Failure.check(message) }; print("TABLE_NATIVE_OK \(message)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 80) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func run() async throws {
        let suite = "CSVTableNativeProbe.\(UUID())", defaults = UserDefaults(suiteName: "CSVTableNativeProbe.temporary")!
        defer { defaults.removePersistentDomain(forName: "CSVTableNativeProbe.temporary") }
        let workspace = CSVTableWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: CSVTableViewerView(workspace: workspace))
        let window = NSWindow(contentRect: .init(x: 40, y: 40, width: 1100, height: 800), styleMask: [.titled,.resizable,.closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 250)
        let input = try required(all(JSONNativeTextView.self, host).first)
        let identity = ObjectIdentifier(input)
        if ProcessInfo.processInfo.arguments.contains("--pan-only") {
            try await mousePan(workspace, host: host, window: window)
            window.contentView = nil; window.close(); return
        }
        if ProcessInfo.processInfo.arguments.contains("--scrollbars-only") {
            try await scrollbars(workspace, host: host)
            window.contentView = nil; window.close(); return
        }
        if ProcessInfo.processInfo.arguments.contains("--double-click-only") {
            try await doubleClickSource(workspace, host: host, window: window, input: input)
            window.contentView = nil; window.close(); return
        }
        let source = "name,value\nAda,9007199254740993\n\"quote\"\"name\",\"a,b\""
        window.makeFirstResponder(input); input.insertText(source, replacementRange: .init(location: 0, length: 0)); await settle(host)
        let caret = input.selectedRange()
        await workspace.build().value; await settle(host)
        try check(workspace.document?.rowCount == 2, "build-table")
        try check(input.selectedRange() == caret && window.firstResponder === input, "build-preserves-caret-focus")
        for _ in 0..<8 {
            input.insertText(" ", replacementRange: .init(location: input.string.utf16.count, length: 0)); await settle(host, 12)
            try check(input.adornments.coordinates != nil && !input.string.isEmpty, "editor-gutter-present-during-typing")
        }
        input.breakUndoCoalescing(); input.undoManager?.removeAllActions()
        input.insertText(" ", replacementRange: .init(location: input.string.utf16.count, length: 0)); input.breakUndoCoalescing()
        input.undoManager?.undo(); await settle(host)
        try check(workspace.input == source + String(repeating: " ", count: 8), "native-undo")
        input.undoManager?.redo(); await settle(host)
        try check(workspace.input == source + String(repeating: " ", count: 9), "native-redo")
        let savedClipboard = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type,$0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(savedClipboard.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data, forType: type) }; return item }) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("name,value\nAda,9007199254740993\nBen,2", forType: .string)
        input.selectAll(nil); input.paste(nil)
        for _ in 0..<50 { if workspace.document != nil { break }; await settle(host, 20) }
        try check(workspace.document?.rowCount == 2 && workspace.document?.cell(.init(row: 0, column: 1))?.value == "9007199254740993", "native-paste-build-exact-text")
        workspace.go(row: 0, column: 1); await settle(host)
        let firstGrid = try required(all(CSVGridHost.self, host).first)
        window.makeFirstResponder(firstGrid.scroll.documentView)
        let copyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        firstGrid.scroll.documentView?.keyDown(with: copyEvent)
        try check(NSPasteboard.general.string(forType: .string) == "9007199254740993", "grid-keyboard-copy-exact-cell")
        let downEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!
        firstGrid.scroll.documentView?.keyDown(with: downEvent); await settle(host)
        try check(workspace.selection == .init(row: 1, column: 1), "grid-arrow-navigation")
        let snapshot = workspace.document!.id
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 390, height: 850)); await settle(host, 250)
        try check(all(JSONNativeTextView.self, host).first.map(ObjectIdentifier.init) == identity && workspace.document?.id == snapshot, "theme-resize-preserves-editor-and-snapshot")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { workspace.inputCollapsed = true }
        var heights: [Int] = []
        for _ in 0..<14 { await settle(host, 20); heights.append(Int(input.enclosingScrollView?.bounds.height ?? -1)) }
        print("TABLE_NATIVE_COLLAPSE reduced=\(reduced) heights=\(heights)")
        try check(reduced ? Set(heights).count == 1 : Set(heights).count > 2, "smooth-input-collapse")
        workspace.inputCollapsed = false; window.setContentSize(.init(width: 1100, height: 800)); await settle(host, 250)
        workspace.input = "a,b\n" + Array(repeating: "1,2", count: 850).joined(separator: "\n") + "\n\"unfinished"
        await workspace.build().value
        var diagnosticHeights: [Int] = []
        for _ in 0..<14 { await settle(host, 20); diagnosticHeights.append(Int(input.enclosingScrollView?.bounds.height ?? -1)) }
        print("TABLE_NATIVE_DIAGNOSTICS reduced=\(reduced) heights=\(diagnosticHeights)")
        try check(reduced ? Set(diagnosticHeights).count == 1 : Set(diagnosticHeights).count > 2, "smooth-diagnostics-expansion")
        try check(workspace.result?.status == .invalid && workspace.document == nil, "invalid-has-no-stale-grid")
        let anchor = workspace.result!.diagnostics[0].range
        JSONEditorNavigation.jump(input, to: anchor.location, animated: !reduced, focus: false, highlight: anchor)
        var frames: [Int] = []
        for _ in 0..<25 { await settle(host, 20); frames.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("TABLE_NATIVE_SOURCE reduced=\(reduced) frames=\(frames)")
        try check(input.adornments.caretRect(at: anchor.location).map { input.visibleRect.intersects($0) } == true, "source-detection-visible")
        try check(reduced ? Set(frames).count == 1 : Set(frames).count > 2, "smooth-source-navigation")
        workspace.inputCollapsed = true; workspace.hasHeader = false
        workspace.input = Array(repeating: "1,2,3,4,5,6,7,8,9,10", count: 12000).joined(separator: "\n")
        let began = ProcessInfo.processInfo.systemUptime
        await workspace.build().value; await settle(host, 250)
        print("TABLE_NATIVE_LARGE utf16=\(workspace.input.utf16.count) rows=\(workspace.document?.rowCount ?? -1) buildAndLayout=\(ProcessInfo.processInfo.systemUptime-began)")
        let grid = try required(all(CSVGridHost.self, host).first)
        try check(workspace.document?.rowCount == 12000, "large-grid-loaded")
        func countViews(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + countViews($1) } }
        let nativeViews = countViews(grid)
        try check(nativeViews < 40, "viewport-native-view-count-bounded-\(nativeViews)")
        try check(workspace.go(row: 11999, column: 9), "go-to-offscreen-cell")
        var ys: [Int] = [], xs: [Int] = []
        for _ in 0..<25 { await settle(host, 20); ys.append(Int(grid.scroll.contentView.bounds.minY)); xs.append(Int(grid.scroll.contentView.bounds.minX)) }
        print("TABLE_NATIVE_GRID_SCROLL reduced=\(reduced) x=\(xs) y=\(ys)")
        try check((ys.last ?? 0) > 400000 && (xs.last ?? 0) > 300, "two-axis-target-visible")
        try check(reduced ? Set(ys).count == 1 : Set(ys).count > 2, "smooth-grid-scroll")
        workspace.go(row: 0, column: 0); await settle(host, 40); workspace.go(row: 6000, column: 5); await settle(host, 400)
        try check(grid.scroll.contentView.bounds.minY > 200000 && grid.scroll.contentView.bounds.minY < 300000, "latest-grid-navigation-wins")
        let y = grid.scroll.contentView.bounds.minY
        workspace.selection = .init(row: 6000, column: 4); await settle(host)
        try check(grid.scroll.contentView.bounds.minY == y, "selection-does-not-reset-viewport")
        workspace.go(row: 11999, column: 9); await settle(host, 35)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: grid.scroll)
        let stopped = grid.scroll.contentView.bounds.origin
        await settle(host, 300)
        try check(grid.scroll.contentView.bounds.origin == stopped, "native-live-scroll-cancels-programmatic-transition")
        workspace.query = "10"; await workspace.scheduleProjection()?.value; await settle(host)
        try check(workspace.projection?.rows.count == 12000, "filter-offscreen-data")
        workspace.query = ""
        for (name, source, row, column) in [
            ("max-tall", String(repeating: "\n", count: 262144), 262143, 0),
            ("max-wide", String(repeating: "x,", count: 131072), 0, 131072),
            ("ragged", String(repeating: ",", count: 10000) + String(repeating: "\nx", count: 10000), 10000, 0)
        ] {
            workspace.input = source
            let start = ProcessInfo.processInfo.systemUptime
            await workspace.build().value; await settle(host, 100)
            try check(workspace.document != nil && workspace.go(row: row, column: column), "\(name)-loaded")
            await settle(host, 400)
            print("TABLE_NATIVE_MAX \(name) utf16=\(source.utf16.count) rows=\(workspace.document!.rowCount) columns=\(workspace.document!.columnCount) buildLayoutScroll=\(ProcessInfo.processInfo.systemUptime-start) offset=\(grid.scroll.contentView.bounds.origin) views=\(countViews(grid))")
            try check(countViews(grid) < 40, "\(name)-bounded-native-views")
            if name == "max-tall" { try check(grid.scroll.contentView.bounds.minY > 10_000_000, "max-tall-last-row") }
            if name == "ragged" { try check(grid.scroll.contentView.bounds.minY > 390000, "ragged-last-row") }
            if name == "max-wide" { try check(grid.scroll.contentView.bounds.minX > 20_000_000, "max-wide-last-column") }
        }
        input.selectAll(nil); input.insertText("", replacementRange: input.selectedRange()); await settle(host)
        try check(workspace.document == nil && workspace.projection == nil, "clear-invalidates-snapshot")
        print("TABLE_NATIVE_END \(suite)")
        window.contentView = nil; window.close()
    }
    @MainActor static func doubleClickSource(_ workspace: CSVTableWorkspaceSession, host: NSView, window: NSWindow, input: JSONNativeTextView) async throws {
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        workspace.input = "name,value\n" + (0..<850).map { "\($0),value\($0)" }.joined(separator: "\n") + "\n\"😀é\",\"needle \"\"quoted\"\"\""
        await workspace.build().value
        workspace.query = "needle"; await workspace.scheduleProjection()?.value
        workspace.sort = .init(column: 1, ascending: false); await workspace.scheduleProjection()?.value
        workspace.inputCollapsed = true; await settle(host, 300)
        let grid = try required(all(CSVGridHost.self, host).first)
        let content = try required(grid.scroll.documentView)
        let target = CSVTableSelection(row: 850, column: 1)
        let range = try required(workspace.document?.cell(target)?.range)
        let identity = ObjectIdentifier(input), source = workspace.input
        func click(_ count: Int, column: Int = 1) {
            let point = content.convert(NSPoint(x: 54 + CGFloat(column) * 180 + 30, y: 60), to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1)!
            content.mouseDown(with: event)
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 0)!
            content.mouseUp(with: up)
        }
        click(1); await settle(host)
        try check(workspace.selection == target && workspace.inputCollapsed, "single-click-selects-without-source-navigation")
        // Activate a different cell directly, so deferred SwiftUI selection observers
        // must not cancel the source request issued in the same event.
        click(2, column: 0)
        var positions: [Int] = [], heights: [Int] = []
        for _ in 0..<45 { await settle(host, 20); positions.append(Int(input.enclosingScrollView!.contentView.bounds.minY)); heights.append(Int(input.enclosingScrollView!.bounds.height)) }
        let firstRange = try required(workspace.document?.cell(.init(row: 850, column: 0))?.range)
        try check(!workspace.inputCollapsed && input.adornments.navigationHighlight == firstRange, "double-click-opens-input-and-highlights-new-selection")
        try check(input.adornments.caretRect(at: firstRange.location).map { input.visibleRect.intersects($0) } == true, "filtered-sorted-source-target-visible")
        try check(window.firstResponder !== input && input.selectedRange().length == 0, "navigation-preserves-editor-focus-and-selection")
        print("TABLE_DOUBLE_CLICK reduced=\(reduced) heights=\(heights) y=\(positions)")
        try check(reduced ? Set(positions).count <= 2 : Set(positions).count > 2, "double-click-motion-policy")
        click(2)
        await settle(host, 500)
        try check(input.adornments.navigationHighlight == range, "double-click-quoted-value-exact-source-range")
        try check(workspace.input == source && ObjectIdentifier(input) == identity, "double-click-does-not-change-source-or-editor-identity")
        await settle(host, 2200)
        try check(input.adornments.navigationHighlight == nil, "source-highlight-expires")
        workspace.inputCollapsed = true; await settle(host, 250)
        click(2); workspace.input += "\nnew,record"; await settle(host, 600)
        try check(input.adornments.navigationHighlight == nil && workspace.document == nil, "source-edit-cancels-pending-double-click-jump")
    }
    @MainActor static func scrollbars(_ workspace: CSVTableWorkspaceSession, host: NSView) async throws {
        workspace.hasHeader = false
        workspace.inputCollapsed = true
        workspace.input = Array(repeating: Array(repeating: "value", count: 12).joined(separator: ","), count: 200).joined(separator: "\n")
        await workspace.build().value; await settle(host, 300)
        let grid = try required(all(CSVGridHost.self, host).first)
        let vertical = try required(grid.scroll.verticalScroller), horizontal = try required(grid.scroll.horizontalScroller)
        try check(grid.scroll.scrollerStyle == .legacy && !grid.scroll.autohidesScrollers, "persistent-native-scrollbars")
        for (name, scroller) in [("vertical", vertical), ("horizontal", horizontal)] {
            try check(!scroller.isHidden && scroller.isEnabled && !scroller.frame.isEmpty, "\(name)-scrollbar-visible-and-enabled")
            try check(scroller.knobProportion > 0 && scroller.knobProportion < 1, "\(name)-draggable-thumb")
            let center = grid.convert(NSPoint(x: scroller.bounds.midX, y: scroller.bounds.midY), from: scroller)
            try check(grid.hitTest(grid.convert(center, to: grid.superview)) === scroller, "\(name)-scrollbar-not-covered-by-grid-canvas")
        }
        workspace.go(row: 199, column: 11); await settle(host, 400)
        try check(vertical.doubleValue > 0.9 && horizontal.doubleValue > 0.9, "both-scrollbar-thumbs-follow-navigation")
        let source = workspace.input
        workspace.selection = .init(row: 199, column: 10); await settle(host)
        try check(workspace.input == source && grid.scroll.contentView.bounds.minY > 100, "selection-preserves-content-and-scroll")
    }
    @MainActor static func mousePan(_ workspace: CSVTableWorkspaceSession, host: NSView, window: NSWindow) async throws {
        workspace.hasHeader = false
        workspace.input = Array(repeating: Array(repeating: "value", count: 24).joined(separator: ","), count: 200).joined(separator: "\n")
        await workspace.build().value; await settle(host, 250)
        let grid = try required(all(CSVGridHost.self, host).first)
        let scroller = try required(grid.scroll.horizontalScroller)
        for (size, collapsed) in [(CGSize(width: 1100, height: 800), false), (CGSize(width: 700, height: 600), false), (CGSize(width: 700, height: 600), true)] {
            window.setContentSize(size); workspace.inputCollapsed = collapsed; await settle(host, 300)
            for row in [0, 199] {
                workspace.go(row: row, column: 0); await settle(host, 350)
                let frame = host.convert(scroller.bounds, from: scroller)
                let visible = host.visibleRect
                print("TABLE_PAN_GEOMETRY window=\(size) collapsed=\(collapsed) row=\(row) grid=\(grid.bounds) rail=\(frame) visible=\(visible)")
                try check(visible.contains(frame), "horizontal-scrollbar-within-window-at-row-\(row)")
            }
        }
        window.setContentSize(.init(width: 1100, height: 800)); workspace.inputCollapsed = true
        workspace.go(row: 0, column: 0); await settle(host, 400)
        let content = try required(grid.scroll.documentView)
        let source = workspace.input, identity = ObjectIdentifier(content), selection = workspace.selection
        let start = grid.convert(NSPoint(x: 550, y: 260), to: nil)
        func event(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        content.mouseDown(with: event(.leftMouseDown, start))
        var positions: [CGPoint] = []
        for step in 1...8 {
            content.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: start.x - CGFloat(step * 20), y: start.y + CGFloat(step * 15))))
            await settle(host, 10); positions.append(grid.scroll.contentView.bounds.origin)
        }
        content.mouseUp(with: event(.leftMouseUp, NSPoint(x: start.x - 160, y: start.y + 120)))
        await settle(host)
        print("TABLE_PAN_POSITIONS \(positions)")
        try check(abs(grid.scroll.contentView.bounds.minX - 160) < 2 && abs(grid.scroll.contentView.bounds.minY - 120) < 2, "drag-pans-both-axes-with-pointer")
        try check(Set(positions.map { Int($0.x) }).count == 8, "drag-publishes-intermediate-positions")
        try check(workspace.selection == selection && workspace.input == source && workspace.inputCollapsed, "pan-does-not-select-or-activate-cell")
        try check(ObjectIdentifier(content) == identity, "pan-preserves-native-grid-identity")
        // Jitter below the drag threshold still behaves as a click.
        let click = grid.convert(NSPoint(x: 100, y: grid.bounds.height - 90), to: nil)
        content.mouseDown(with: event(.leftMouseDown, click))
        content.mouseDragged(with: event(.leftMouseDragged, .init(x: click.x + 2, y: click.y + 1)))
        content.mouseUp(with: event(.leftMouseUp, .init(x: click.x + 2, y: click.y + 1)))
        await settle(host)
        try check(workspace.selection != selection, "small-pointer-jitter-remains-cell-selection")
        let before = grid.scroll.contentView.bounds.origin
        content.mouseDown(with: event(.leftMouseDown, start))
        content.mouseDragged(with: event(.leftMouseDragged, .init(x: start.x + 100000, y: start.y - 100000)))
        content.mouseUp(with: event(.leftMouseUp, start)); await settle(host)
        try check(grid.scroll.contentView.bounds.origin == .zero && before != .zero, "pan-clamps-to-document-edge")
    }
    static func required<T>(_ value: T?) throws -> T { guard let value else { throw Failure.check("missing-native-view") }; return value }
}
