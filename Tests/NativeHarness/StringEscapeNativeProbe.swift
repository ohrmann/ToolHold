import AppKit
import SwiftUI
@testable import Developer_Toolbox

/// Focused real AppKit/TextKit checks with isolated defaults and synthetic fixtures only.
@main struct StringEscapeNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(); print("T017_NATIVE_PASSED") }
            catch { print("T017_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type,$0) }
    }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw Failure.check(name) }; print("T017_NATIVE_OK \(name)")
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 80) async {
        try? await Task.sleep(for:.milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor static func run() async throws {
        let suite = "StringEscapeNativeProbe." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let workspace = StringEscapeWorkspaceSession(repository:.init(defaults:defaults))
        workspace.preferences.direction = .unescape
        let host = NSHostingView(rootView:StringEscapeView(workspace:workspace))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1100,height:800),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.contentView=host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        await settle(host,250)
        let editors = all(JSONNativeTextView.self,host)
        try check(editors.count==2,"two-native-editors")
        let input=editors[0], output=editors[1], identity=editors.map(ObjectIdentifier.init)
        window.makeFirstResponder(input)
        input.insertText(#""\u0041""#,replacementRange:.init(location:0,length:0)); await settle(host)
        let caret=input.selectedRange()
        await workspace.run().value
        for _ in 0..<20 { if output.string == "A" { break }; await settle(host,20) }
        print("T017_NATIVE_FIRST inputUnits=\(workspace.input.utf16.count) nativeUnits=\(input.string.utf16.count) result=\(String(describing:workspace.result?.status)) artifactUnits=\(workspace.output?.utf16.count ?? -1) outputNativeUnits=\(output.string.utf16.count) editable=\(input.isEditable)/\(output.isEditable)")
        try check(workspace.output=="A" && output.string=="A" && !output.isEditable,"unescape-readonly-output")
        try check(window.firstResponder === input && input.selectedRange()==caret,"operation-keeps-focus-selection")
        await workspace.run(.check).value; try check(workspace.output=="A","check-keeps-output")
        let work=workspace.run(); workspace.cancel(); await work.value
        try check(workspace.wasCancelled && workspace.output=="A","cancel-keeps-output")
        input.breakUndoCoalescing(); input.undoManager?.removeAllActions()
        input.insertText(" ",replacementRange:.init(location:input.string.utf16.count,length:0)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.output==nil && workspace.result==nil && input.adornments.coordinates != nil,"edit-invalidates-stable-gutter")
        input.undoManager?.undo(); await settle(host)
        try check(workspace.input == #""\u0041""#,"native-undo")
        input.undoManager?.redo(); await settle(host)
        try check(workspace.input.hasSuffix(" "),"native-redo")
        let clipboard=NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        defer {
            NSPasteboard.general.clearContents()
            let items=clipboard.map { entries in let item=NSPasteboardItem(); for (type,data) in entries { item.setData(data,forType:type) }; return item }
            NSPasteboard.general.writeObjects(items)
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(#""\uD83D\uDE00""#,forType:.string)
        input.setSelectedRange(.init(location:0,length:input.string.utf16.count)); input.paste(nil); await settle(host,250)
        try check(workspace.result?.status == .success && workspace.output==nil,"system-paste-check-only")
        let pasted=workspace.input
        for _ in 0..<8 {
            input.insertText(" ",replacementRange:.init(location:input.string.utf16.count,length:0)); await settle(host,12)
            try check(input.adornments.coordinates != nil && workspace.result==nil && !workspace.busy,"rapid-typing-stable-gutter-no-validation")
        }
        input.insertText("",replacementRange:.init(location:pasted.utf16.count,length:8))
        await workspace.run().value; await settle(host)
        host.appearance=NSAppearance(named:.darkAqua); window.setContentSize(.init(width:390,height:850)); await settle(host,250)
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init)==identity && workspace.input==pasted && workspace.output=="😀","theme-axis-native-identity-data")
        let reduced=ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        withAnimation(reduced ? nil : .easeInOut(duration:0.2)) { workspace.outputCollapsed=true }
        var heights:[Int]=[]
        for _ in 0..<14 { await settle(host,20); heights.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("T017_NATIVE_COLLAPSE reduced=\(reduced) frames=\(heights)")
        try check(reduced ? Set(heights).count==1 : Set(heights).count>2,"smooth-collapse-policy")
        workspace.outputCollapsed=false; window.setContentSize(.init(width:1100,height:800)); await settle(host,250)
        workspace.preferences.language = .javascript; workspace.preferences.representation = .contents
        workspace.input=String(repeating:"abc\\\n",count:850)+#"\xG0"#
        await settle(host,250); await workspace.run().value
        var diagnostics:[Int]=[]
        for _ in 0..<14 { await settle(host,20); diagnostics.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("T017_NATIVE_DIAGNOSTICS reduced=\(reduced) frames=\(diagnostics)")
        try check(reduced ? Set(diagnostics).count==1 : Set(diagnostics).count>2,"smooth-diagnostic-policy")
        let anchor=workspace.result!.issues.first { $0.severity == .error }!.range!
        try check(input.adornments.diagnostic?.range==anchor,"native-underline-anchor")
        JSONEditorNavigation.jump(input,to:anchor.location,animated:!reduced,focus:false,highlight:anchor)
        var vertical:[Int]=[]
        for _ in 0..<28 { await settle(host,20); vertical.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("T017_NATIVE_VERTICAL reduced=\(reduced) frames=\(vertical)")
        try check(input.adornments.caretRect(at:anchor.location).map { input.visibleRect.intersects($0) }==true,"source-target-visible")
        try check(reduced ? Set(vertical).count==1 : Set(vertical).count>2,"smooth-source-policy")
        workspace.preferences.wordWrap=false; workspace.preferences.language = .json; workspace.preferences.representation = .quoted
        workspace.input="\""+String(repeating:"a",count:20_000)+#"\u12"#
        await workspace.run().value; await settle(host,250)
        let eof=workspace.result!.issues[0].range!
        try check(eof.length==0 && eof.location==20_005 && input.adornments.diagnostic?.range==eof,"eof-exact-marker")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false,highlight:eof)
        var horizontal:[Int]=[]
        for _ in 0..<28 { await settle(host,20); horizontal.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("T017_NATIVE_HORIZONTAL reduced=\(reduced) frames=\(horizontal)")
        try check(reduced ? Set(horizontal).count==1 : Set(horizontal).count>2,"smooth-horizontal-policy")
        try check(input.adornments.caretRect(at:eof.location).map { input.visibleRect.intersects($0) }==true,"horizontal-eof-visible")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false)
        JSONEditorNavigation.jump(input,to:0,animated:!reduced,focus:false); await settle(host,600)
        try check(input.enclosingScrollView!.contentView.bounds.minX<30,"new-jump-cancels-old")
        workspace.preferences.representation = .quoted
        workspace.input = #""a\u0000b\r\n\u202Ec""#
        await workspace.run().value; await settle(host)
        let exact="a\u{0}b\r\n\u{202E}c"
        try check(workspace.output?.utf16.elementsEqual(exact.utf16)==true,"nul-crlf-bidi-exact-output")
        try check(output.string.utf16.elementsEqual(exact.utf16),"nul-crlf-bidi-native-readonly")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(workspace.output!,forType:.string)
        try check(NSPasteboard.general.string(forType:.string)?.utf16.elementsEqual(exact.utf16)==true,"nul-crlf-bidi-clipboard-exact")
        workspace.preferences.direction = .escape; workspace.preferences.representation = .contents
        workspace.input=String(repeating:"a",count:262_144)
        let start=ContinuousClock.now; await workspace.run().value; await settle(host,300)
        try check(output.string.utf16.count==262_144 && workspace.canCopy,"maximum-output-native-layout")
        print("T017_NATIVE_MAX_OUTPUT duration=\(start.duration(to:.now))")
        input.undoManager?.removeAllActions(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input)
        input.breakUndoCoalescing(); input.insertText("",replacementRange:.init(location:0,length:input.string.utf16.count)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.input.isEmpty && workspace.output==nil,"clear-invalidates")
        input.undoManager?.undo(); await settle(host)
        try check(workspace.input.utf16.count==262_144,"undo-clear-restores")
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init)==identity,"final-native-identity")
        let fresh=StringEscapeWorkspaceSession(repository:.init(defaults:defaults))
        try check(fresh.input.isEmpty && fresh.artifact==nil,"new-session-private")
        window.contentView=nil; window.close()
    }
}
