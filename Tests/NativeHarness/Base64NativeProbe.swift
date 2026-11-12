import AppKit
import SwiftUI

/// Focused real AppKit/TextKit checks; synthetic data only. No production defaults touched.
@main struct Base64NativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(); print("BASE64_NATIVE_PASSED") } catch { print("BASE64_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) }
    }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw Failure.check(label) }; print("BASE64_NATIVE_OK \(label)")
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 80) async {
        try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor static func run() async throws {
        let suite = "Base64NativeProbe." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = Base64WorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: Base64TextView(workspace: workspace))
        let window = NSWindow(contentRect: .init(x: 40, y: 40, width: 1100, height: 800), styleMask: [.titled,.resizable,.closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 250)
        let editors = all(JSONNativeTextView.self, host)
        try check(editors.count == 2, "two-native-editors")
        let input = editors[0], output = editors[1], identity = editors.map(ObjectIdentifier.init)
        window.makeFirstResponder(input); input.insertText("YQ==", replacementRange: .init(location: 0, length: 0)); await settle(host)
        let caret = input.selectedRange()
        await workspace.run().value; await settle(host)
        try check(workspace.output == "a" && output.string == "a" && !output.isEditable, "decode-readonly-output")
        try check(window.firstResponder === input && input.selectedRange() == caret, "operation-keeps-focus-caret")
        await workspace.run(.check).value; try check(workspace.output == "a", "check-keeps-output")
        let repeated = workspace.run(); workspace.cancel(); await repeated.value
        try check(workspace.wasCancelled && workspace.output == "a", "cancel-keeps-output")
        input.breakUndoCoalescing(); input.undoManager?.removeAllActions()
        input.insertText("!", replacementRange: .init(location: 4, length: 0)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.output == nil && workspace.result == nil && input.adornments.coordinates != nil, "edit-invalidates-with-stable-gutter")
        input.undoManager?.undo(); await settle(host)
        try check(workspace.input == "YQ==", "native-undo")
        input.undoManager?.redo(); await settle(host)
        try check(workspace.input == "YQ==!", "native-redo")
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType,Data)? in item.data(forType: type).map { (type,$0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item }) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("8J+YgA==",forType:.string)
        input.selectAll(nil); input.paste(nil)
        for _ in 0..<50 { if workspace.result != nil { break }; await settle(host, 20) }
        try check(workspace.result?.status == .success && workspace.output == nil, "system-paste-check-only")
        await workspace.run().value; await settle(host)
        try check(workspace.output == "😀", "unicode-output")
        let pasted = workspace.input
        for _ in 0..<8 {
            input.insertText(" ", replacementRange: .init(location: input.string.utf16.count, length: 0))
            await settle(host, 12)
            try check(input.adornments.coordinates != nil && workspace.result == nil && !workspace.busy,
                      "rapid-typing-retains-gutter-without-validation")
        }
        input.insertText("", replacementRange: .init(location: pasted.utf16.count, length: 8))
        await workspace.run().value; await settle(host)
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 390,height: 850)); await settle(host,250)
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init) == identity && workspace.input == pasted && workspace.output == "😀", "theme-axis-native-identity-data")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { workspace.outputCollapsed = true }
        var heights: [Int] = []
        for _ in 0..<14 { await settle(host,20); heights.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("BASE64_NATIVE_COLLAPSE reduced=\(reduced) frames=\(heights)")
        try check(reduced ? Set(heights).count == 1 : Set(heights).count > 2, "smooth-collapse-policy")
        workspace.outputCollapsed = false; window.setContentSize(.init(width: 1100,height: 800)); await settle(host,250)
        workspace.preferences.decodeMode = .forgiving
        workspace.input = String(repeating: "YWFh\n",count: 850) + "!"
        await settle(host,250); await workspace.run().value
        var diagnostics: [Int] = []
        for _ in 0..<14 { await settle(host,20); diagnostics.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("BASE64_NATIVE_DIAGNOSTICS reduced=\(reduced) frames=\(diagnostics)")
        try check(reduced ? Set(diagnostics).count == 1 : Set(diagnostics).count > 2, "smooth-diagnostic-policy")
        let anchor = workspace.result!.issues[0].range!
        try check(input.adornments.diagnostic?.range == anchor, "native-underline-anchor")
        JSONEditorNavigation.jump(input,to:anchor.location,animated:!reduced,focus:false,highlight:anchor)
        var vertical: [Int] = []
        for _ in 0..<28 { await settle(host,20); vertical.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("BASE64_NATIVE_VERTICAL reduced=\(reduced) frames=\(vertical)")
        try check(input.adornments.caretRect(at: anchor.location).map { input.visibleRect.intersects($0) } == true, "source-target-visible")
        try check(reduced ? Set(vertical).count == 1 : Set(vertical).count > 2, "smooth-source-policy")
        workspace.preferences.wordWrap = false
        workspace.input = String(repeating: "YWFh",count: 5_000) + "A"
        await workspace.run().value; await settle(host,250)
        let eof = workspace.result!.issues[0].range!
        try check(eof.length == 0 && eof.location == 20_001 && input.adornments.diagnostic?.range == eof, "eof-exact-marker")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false,highlight:eof)
        var horizontal: [Int] = []
        for _ in 0..<28 { await settle(host,20); horizontal.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("BASE64_NATIVE_HORIZONTAL reduced=\(reduced) frames=\(horizontal)")
        try check(reduced ? Set(horizontal).count == 1 : Set(horizontal).count > 2, "smooth-horizontal-policy")
        try check(input.adornments.caretRect(at:eof.location).map { input.visibleRect.intersects($0) } == true, "horizontal-eof-visible")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false)
        JSONEditorNavigation.jump(input,to:0,animated:!reduced,focus:false)
        await settle(host,600)
        try check(input.enclosingScrollView!.contentView.bounds.minX < 30, "new-jump-cancels-old")
        workspace.preferences.direction = .encode
        workspace.input = "a\0b\u{202E}c"
        await workspace.run().value; await settle(host)
        try check(workspace.result?.issues.contains { $0.code == .controls } == true, "control-notice")
        workspace.preferences.direction = .decode
        workspace.input = "YQBi4oCuYw=="
        await workspace.run().value; await settle(host)
        try check(workspace.output?.utf16.elementsEqual("a\0b\u{202E}c".utf16) == true, "nul-bidi-exact-output")
        try check(output.string.utf16.elementsEqual(workspace.output!.utf16), "nul-bidi-native-render-source")
        workspace.preferences.direction = .encode; workspace.input = String(repeating: "a",count:196_608)
        let start = ContinuousClock.now
        await workspace.run().value; await settle(host,300)
        let elapsed = start.duration(to:.now)
        try check(output.string.utf16.count == 262_144 && workspace.canCopy, "maximum-output-native-layout")
        print("BASE64_NATIVE_MAX_OUTPUT duration=\(elapsed)")
        // Earlier stress fixtures replace the model programmatically, outside native Undo.
        // Start an independent Undo baseline; otherwise a retained Paste from the first
        // fixture can join this synthetic run-loop group and edit the new large fixture.
        input.undoManager?.removeAllActions()
        // Re-establish a key native editing session after external Simulator UI automation.
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input)
        print("BASE64_NATIVE_CLEAR before=\(input.string.utf16.count) model=\(workspace.input.utf16.count) undo=\(input.undoManager?.canUndo ?? false)")
        input.breakUndoCoalescing(); input.insertText("",replacementRange:.init(location:0,length:input.string.utf16.count)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.input.isEmpty && workspace.output == nil, "clear-invalidates")
        window.makeFirstResponder(input); input.undoManager?.undo(); await settle(host)
        print("BASE64_NATIVE_UNDO_CLEAR native=\(input.string.utf16.count) model=\(workspace.input.utf16.count) canUndo=\(input.undoManager?.canUndo ?? false) canRedo=\(input.undoManager?.canRedo ?? false)")
        try check(workspace.input.utf16.count == 196_608, "undo-clear-restores")
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init) == identity, "final-native-identity")
        let fresh = Base64WorkspaceSession(repository:.init(defaults:defaults))
        try check(fresh.input.isEmpty && fresh.artifact == nil, "new-session-private")
        window.contentView = nil; window.close()
    }
}
