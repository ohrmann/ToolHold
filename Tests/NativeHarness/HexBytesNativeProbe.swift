import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

/// Focused native TextKit/List runtime evidence; synthetic data, isolated defaults, restored clipboard.
@main struct HexBytesNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(); print("T018_NATIVE_PASSED") }
            catch { print("T018_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type,$0) }
    }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw Failure.check(name) }; print("T018_NATIVE_OK \(name)")
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 80) async {
        try? await Task.sleep(for:.milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor static func run() async throws {
        let suite = "HexBytesNativeProbe."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let workspace = HexBytesWorkspaceSession(repository:.init(defaults:defaults))
        let host = NSHostingView(rootView:HexBytesView(workspace:workspace))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1100,height:800),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.contentView=host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        await settle(host,250)
        let editors = all(JSONNativeTextView.self,host)
        try check(editors.count==2,"two-native-editors")
        let input=editors[0], output=editors[1], identity=editors.map(ObjectIdentifier.init)
        window.makeFirstResponder(input); input.insertText("4142",replacementRange:.init(location:0,length:0)); await settle(host)
        let caret=input.selectedRange(); await workspace.run().value
        for _ in 0..<20 { if output.string=="AB" { break }; await settle(host,20) }
        try check(output.string=="AB" && !output.isEditable && workspace.canCopyText,"convert-readonly-output")
        try check(window.firstResponder === input && input.selectedRange()==caret,"operation-keeps-focus-caret")
        let id=workspace.artifact!.id; await workspace.run(.check).value
        try check(workspace.artifact?.id==id,"check-keeps-artifact")
        let work=workspace.run(); workspace.cancel(); await work.value
        try check(workspace.wasCancelled && workspace.artifact?.id==id,"cancel-keeps-artifact")
        input.undoManager?.removeAllActions(); input.breakUndoCoalescing()
        input.insertText(" ",replacementRange:.init(location:input.string.utf16.count,length:0)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.artifact==nil && input.adornments.coordinates != nil,"edit-invalidates-without-gutter-flash")
        input.undoManager?.undo(); await settle(host); try check(workspace.input=="4142","native-undo")
        input.undoManager?.redo(); await settle(host); try check(workspace.input=="4142 ","native-redo")
        let clipboard=NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(clipboard.map { entries in let item=NSPasteboardItem(); for (type,data) in entries { item.setData(data,forType:type) }; return item })
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("F0 9F 98 80",forType:.string)
        input.setSelectedRange(.init(location:0,length:input.string.utf16.count)); input.paste(nil); await settle(host,250)
        try check(workspace.result?.status == .success && workspace.artifact==nil,"system-paste-check-only")
        let pasted=workspace.input
        for _ in 0..<8 {
            input.insertText(" ",replacementRange:.init(location:input.string.utf16.count,length:0)); await settle(host,12)
            try check(input.adornments.coordinates != nil && workspace.result==nil && !workspace.busy,"rapid-typing-stable-no-validation")
        }
        input.insertText("",replacementRange:.init(location:pasted.utf16.count,length:8)); await workspace.run().value; await settle(host)
        workspace.preferences.preferredOutputView = .bytes; await settle(host,200)
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init)==identity,"bytes-view-keeps-native-editor-identity")
        workspace.preferences.preferredOutputView = .text
        host.appearance=NSAppearance(named:.darkAqua); window.setContentSize(.init(width:390,height:850)); await settle(host,250)
        try check(workspace.output=="😀" && workspace.input==pasted && all(JSONNativeTextView.self,host).map(ObjectIdentifier.init)==identity,"theme-layout-keeps-data-and-editors")
        let reduced=ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        withAnimation(reduced ? nil : .easeInOut(duration:0.2)) { workspace.outputCollapsed=true }
        var heights=[Int](); for _ in 0..<14 { await settle(host,20); heights.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("T018_NATIVE_COLLAPSE reduced=\(reduced) frames=\(heights)")
        try check(reduced ? Set(heights).count==1 : Set(heights).count>2,"smooth-collapse-policy")
        workspace.outputCollapsed=false; window.setContentSize(.init(width:1100,height:800)); await settle(host,250)
        workspace.input=String(repeating:"41\n",count:850)+"4G"; await settle(host,250); await workspace.run().value
        var diagnosticFrames=[Int](); for _ in 0..<14 { await settle(host,20); diagnosticFrames.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("T018_NATIVE_DIAGNOSTICS reduced=\(reduced) frames=\(diagnosticFrames)")
        try check(reduced ? Set(diagnosticFrames).count==1 : Set(diagnosticFrames).count>2,"smooth-diagnostic-policy")
        let anchor=workspace.result!.issues[0].range!
        try check(input.adornments.diagnostic?.range==anchor,"native-underline-exact")
        JSONEditorNavigation.jump(input,to:anchor.location,animated:!reduced,focus:false,highlight:anchor)
        var vertical=[Int](); for _ in 0..<28 { await settle(host,20); vertical.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("T018_NATIVE_VERTICAL reduced=\(reduced) frames=\(vertical)")
        try check(reduced ? Set(vertical).count==1 : Set(vertical).count>2,"smooth-offscreen-navigation")
        try check(input.adornments.caretRect(at:anchor.location).map { input.visibleRect.intersects($0) }==true,"source-target-visible")
        workspace.preferences.wordWrap=false; workspace.input=String(repeating:"41",count:10_000)+"F0 9F 98"
        await workspace.run().value; await settle(host,250)
        let eof=workspace.result!.issues[0].range!
        try check(eof.location==20_008 && eof.length==0 && input.adornments.diagnostic?.range==eof,"utf8-eof-marker")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false,highlight:eof)
        var horizontal=[Int](); for _ in 0..<28 { await settle(host,20); horizontal.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("T018_NATIVE_HORIZONTAL reduced=\(reduced) frames=\(horizontal)")
        try check(reduced ? Set(horizontal).count==1 : Set(horizontal).count>2,"smooth-horizontal-eof")
        try check(input.adornments.caretRect(at:eof.location).map { input.visibleRect.intersects($0) }==true,"horizontal-eof-visible")
        let related=workspace.result!.issues[0].related!
        JSONEditorNavigation.jump(input,to:related.location,animated:!reduced,focus:false,highlight:related)
        JSONEditorNavigation.jump(input,to:0,animated:!reduced,focus:false); await settle(host,600)
        try check(input.enclosingScrollView!.contentView.bounds.minX<30,"new-jump-cancels-old")
        workspace.preferences.wordWrap=true; workspace.preferences.preferredOutputView = .text
        workspace.input="61 00 62 0D 0A E2 80 AE 63 EF BB BF"; await workspace.run().value; await settle(host)
        let exact="a\u{0}b\r\n\u{202E}c\u{FEFF}"
        try check(output.string.utf16.elementsEqual(exact.utf16),"nul-crlf-bidi-native-exact")
        let copy=await workspace.prepareCopy(.text).value!
        try check(workspace.isCurrent(copy),"prepared-copy-current")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(copy.text,forType:.string)
        try check(NSPasteboard.general.string(forType:.string)?.utf16.elementsEqual(exact.utf16)==true,"exact-native-clipboard")
        workspace.input=String(repeating:"41",count:131_072)
        let start=ContinuousClock.now; await workspace.run().value
        workspace.preferences.preferredOutputView = .bytes; await settle(host,300)
        var usage=rusage(); getrusage(RUSAGE_SELF,&usage)
        let tables=all(NSTableView.self,host), collections=all(NSCollectionView.self,host)
        print("T018_NATIVE_LARGE inputUTF16=262144 bytes=131072 rows=8192 readyIncluding300ms=\(start.duration(to:.now)) peakBytes=\(usage.ru_maxrss) nativeTables=\(tables.map { $0.numberOfRows }) nativeCollections=\(collections.count)")
        if let table=tables.first {
            let visible=table.rows(in:table.visibleRect), rowViews=all(NSTableRowView.self,table).count
            print("T018_NATIVE_LIST rows=\(table.numberOfRows) visibleRows=\(visible) createdRowViews=\(rowViews)")
            try check(table.numberOfRows==8192 && rowViews < 200,"native-list-virtualization")
            table.scrollRowToVisible(8191); await settle(host,250)
            try check(NSMaxRange(table.rows(in:table.visibleRect))==8192,"continuous-scroll-last-byte")
            window.setContentSize(.init(width:390,height:850)); await settle(host,300)
            print("T018_NATIVE_LIST_RESIZE rows=\(table.numberOfRows) visibleRows=\(table.rows(in:table.visibleRect))")
            try check(table.numberOfRows == 16384 && table.rows(in:table.visibleRect).location > 16000,"resize-keeps-byte-anchor")
        } else {
            try check(!collections.isEmpty,"native-list-backing-present")
        }
        workspace.preferences.preferredOutputView = .text; await settle(host)
        input.undoManager?.removeAllActions(); input.breakUndoCoalescing(); window.makeFirstResponder(input)
        input.insertText("",replacementRange:.init(location:0,length:input.string.utf16.count)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.input.isEmpty && workspace.artifact==nil,"clear-invalidates")
        input.undoManager?.undo(); await settle(host); try check(workspace.input.utf16.count==262_144,"undo-clear-restores")
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init)==identity,"final-native-editor-identities")
        let fresh=HexBytesWorkspaceSession(repository:.init(defaults:defaults))
        try check(fresh.input.isEmpty && fresh.artifact==nil,"new-session-private")
        window.contentView=nil; window.close()
    }
}
