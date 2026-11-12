import AppKit
import SwiftUI
@testable import Developer_Toolbox

/// Real AppKit/TextKit probe, synthetic fixtures and isolated preferences. Linked against the Debug app objects.
@main struct URLQueryNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(); print("T015_NATIVE_PASSED") } catch { print("T015_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func views<T: NSView>(_ type: T.Type, _ parent: NSView) -> [T] {
        (parent as? T).map { [$0] } ?? parent.subviews.flatMap { views(type,$0) }
    }
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
        guard value() else { throw Failure.check(name) }; print("T015_NATIVE_OK \(name)")
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 70) async {
        try? await Task.sleep(for:.milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor static func run() async throws {
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        let suite = "URLQueryNativeProbe."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let s = URLQueryWorkspaceSession(repository:.init(defaults:defaults))
        let host = NSHostingView(rootView:URLQueryView(workspace:s))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1200,height:900),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        defer { window.close() }
        await settle(host,250)
        let editors = views(JSONNativeTextView.self,host)
        try check(editors.count == 2,"stable-two-editors")
        let input = editors[0], output = editors[1], identity = editors.map(ObjectIdentifier.init)
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType,Data)? in item.data(forType:type).map{(type,$0)} } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item }) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("https://例え.テスト/путь?tag=one&tag=two#😀",forType:.string)
        window.makeFirstResponder(input); input.paste(nil)
        for _ in 0..<60 { if s.snapshot != nil { break }; await settle(host,20) }
        try check(s.rows.count == 2 && s.artifact == nil,"system-paste-parse-without-build")
        let caret = input.selectedRange()
        await s.build()?.value; await settle(host,250)
        try check(output.string == s.input && !output.isEditable,"preserve-readonly-result")
        try check(window.firstResponder === input && input.selectedRange() == caret,"parse-build-keeps-caret-focus")
        s.outputForm = .ascii; await settle(host)
        try check(output.string.contains("xn--r8jz45g.xn--zckzah") && output.string.contains("%F0%9F%98%80"),"ascii-idna-output")
        s.selectedID = 1; s.beginEdit(1); s.editValue = "value +"; try check(s.applyEdit(),"apply-query-edit")
        await settle(host)
        let smallTable = views(NSTableView.self,host).first!
        let moving = smallTable.rowView(atRow:1,makeIfNecessary:true)!
        s.move(1,to:0)
        var positions: [Int] = []
        for _ in 0..<15 { await settle(host,20); positions.append(Int(moving.layer?.presentation()?.frame.minY ?? moving.frame.minY)) }
        print("T015_REORDER reduced=\(reduced) frames=\(positions)")
        try check(reduced ? Set(positions).count == 1 : Set(positions).count > 2,"query-reorder-motion")
        await s.build()?.value; await settle(host)
        try check(s.artifact?.preserve.contains("?tag=value%20%2B&tag=one#😀") == true,"ordered-duplicate-edit")
        s.undo(); s.undo(); await s.build()?.value; try check(s.artifact?.preserve == s.input,"query-undo")
        input.breakUndoCoalescing(); input.undoManager?.removeAllActions()
        input.insertText("!",replacementRange:.init(location:input.string.utf16.count,length:0)); input.breakUndoCoalescing(); await settle(host)
        try check(s.snapshot == nil && s.output == nil && input.adornments.coordinates != nil,"input-invalidates-without-gutter-flicker")
        input.undoManager?.undo(); await settle(host); try check(!s.input.hasSuffix("!"),"native-input-undo")
        input.undoManager?.redo(); await settle(host); try check(s.input.hasSuffix("!"),"native-input-redo")
        await s.parse().value; await s.build()?.value
        host.appearance = NSAppearance(named:.darkAqua); window.setContentSize(.init(width:410,height:900)); await settle(host,250)
        try check(views(JSONNativeTextView.self,host).map(ObjectIdentifier.init) == identity && s.snapshot != nil && s.output != nil,"theme-axis-keeps-identities-data")
        commandsResign(input)
        withAnimation(reduced ? nil : .easeInOut(duration:0.2)) { s.inputCollapsed = true }
        var heights: [Int] = []
        for _ in 0..<15 { await settle(host,20); heights.append(Int(input.enclosingScrollView!.frame.height)) }
        print("T015_COLLAPSE reduced=\(reduced) frames=\(heights)")
        try check(reduced ? Set(heights).count == 1 : Set(heights).count > 2,"input-collapse-motion")
        s.inputCollapsed = false; window.setContentSize(.init(width:1200,height:900)); await settle(host,250)
        s.setWordWrap(false); s.input = "?a="+String(repeating:"a",count:20_000)+"%"
        await settle(host,150); await s.parse().value; await settle(host,250)
        let anchor = s.issues.first!.range!
        try check(anchor.length == 0 && anchor.location == 20_004 && input.adornments.diagnostic?.range == anchor,"exact-eof-native-marker")
        JSONEditorNavigation.jump(input,to:anchor.location,animated:!reduced,focus:false,highlight:anchor)
        var offsets: [Int] = []
        for _ in 0..<28 { await settle(host,20); offsets.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("T015_SOURCE reduced=\(reduced) frames=\(offsets)")
        try check(input.adornments.caretRect(at:anchor.location).map { input.visibleRect.intersects($0) } == true,"eof-target-visible")
        try check(reduced ? Set(offsets).count == 1 : Set(offsets).count > 2,"source-navigation-motion")
        s.input = "?"+String(repeating:"&",count:262_143); s.inputCollapsed = true
        let start = ContinuousClock.now; await s.parse().value; await settle(host,250)
        let table = views(NSTableView.self,host).first!
        try check(table.numberOfRows == 262_144,"max-empty-query-rows")
        try check(views(NSTableRowView.self,table).count < 100,"native-recycled-rows")
        let endStart = ContinuousClock.now; table.scrollRowToVisible(262_143); await settle(host,120)
        try check(table.rows(in:table.visibleRect).contains(262_143),"continuous-scroll-to-last-row")
        table.selectRowIndexes(IndexSet(integer:262_143),byExtendingSelection:false); await settle(host)
        try check(s.selectedID == 262_143,"last-row-selection")
        print("T015_TABLE rows=\(table.numberOfRows) mountedRows=\(views(NSTableRowView.self,table).count) parsePublishLayout=\(start.duration(to:.now)) scrollSelect=\(endStart.duration(to:.now))")
        let largeMoveStart = ContinuousClock.now
        s.move(262_143,to:0); await settle(host,260)
        try check(s.rows.first?.id == 262_143 && table.numberOfRows == 262_144 && views(NSTableRowView.self,table).count < 100,"large-native-move-remains-recycled")
        print("T015_LARGE_MOVE elapsed=\(largeMoveStart.duration(to:.now)) mountedRows=\(views(NSTableRowView.self,table).count)")
        s.clear(); await settle(host)
        try check(s.input.isEmpty && s.snapshot == nil && table.numberOfRows == 0,"clear-invalidates-table")
        try check(URLQueryWorkspaceSession(repository:.init(defaults:defaults)).input.isEmpty,"new-session-empty")
    }
    @MainActor static func commandsResign(_ input: NSTextView) { input.window?.makeFirstResponder(nil) }
}
