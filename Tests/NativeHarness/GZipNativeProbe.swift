import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

/// Synthetic focused native evidence. No production data; clipboard restored afterwards.
@main struct GZipNativeProbe {
    enum Failure:Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { if ProcessInfo.processInfo.arguments.contains("--stress-only") { try await stress() } else { try await run() }; print("T019_NATIVE_PASSED") }
            catch { print("T019_NATIVE_FAILURE \(error)"); exit(1) }; exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T:NSView>(_ type:T.Type,_ view:NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type,$0) }
    }
    @MainActor static func check(_ value:@autoclosure () -> Bool,_ name:String) throws {
        guard value() else { throw Failure.check(name) }; print("T019_NATIVE_OK \(name)")
    }
    @MainActor static func settle(_ host:NSView,_ ms:Int = 80) async {
        try? await Task.sleep(for:.milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor static func stress() async throws {
        let suite = "GZipStressProbe."+UUID().uuidString, dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let source = dir.appendingPathComponent("zeros.bin")
        FileManager.default.createFile(atPath:source.path,contents:nil)
        let file = try FileHandle(forWritingTo:source); try file.truncate(atOffset:256 * 1_024 * 1_024); try file.close()
        let workspace = GZipWorkspaceSession(repository:.init(defaults:defaults)), host = NSHostingView(rootView:GZipView(workspace:workspace))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1100,height:800),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); await settle(host,200)
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage); let baseline = usage.ru_maxrss
        workspace.usesFile = true; await workspace.select(source).value
        let start = ContinuousClock.now, work = workspace.run()
        var last = ProcessInfo.processInfo.systemUptime, gaps:[Double] = []
        while workspace.busy {
            await settle(host,10); let now = ProcessInfo.processInfo.systemUptime; gaps.append(now-last); last = now
        }; await work.value
        getrusage(RUSAGE_SELF,&usage)
        print("T019_NATIVE_STRESS inputBytes=268435456 outputBytes=\(workspace.result?.outputBytes ?? -1) elapsed=\(start.duration(to:.now)) heartbeatMax=\(gaps.max() ?? -1) samples=\(gaps.count) baselinePeakBytes=\(baseline) peakBytes=\(usage.ru_maxrss)")
        try check(workspace.result?.status == .success && gaps.count > 10,"large-worker-main-actor-responsive")
        try check(all(JSONNativeTextView.self,host).allSatisfy { $0.string.utf16.count <= 262_144 },"large-file-bounded-native-editors")
        window.contentView = nil; window.close()
    }
    @MainActor static func run() async throws {
        let suite = "GZipProbe."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let workspace = GZipWorkspaceSession(repository:.init(defaults:defaults))
        let host = NSHostingView(rootView:GZipView(workspace:workspace))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1100,height:800),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        await settle(host,250)
        let editors = all(JSONNativeTextView.self,host), identities = editors.map(ObjectIdentifier.init)
        try check(editors.count == 2,"two-native-editors")
        let input = editors[0], output = editors[1]
        window.makeFirstResponder(input); input.insertText("hello\r\n",replacementRange:.init(location:0,length:0)); await settle(host)
        let caret = input.selectedRange(); await workspace.run().value; await settle(host)
        try check(!output.isEditable && workspace.copyText(.base64) == output.string,"compress-readonly-base64")
        try check(input.selectedRange() == caret && window.firstResponder === input,"convert-keeps-caret-focus")
        let encoded = workspace.copyText(.base64)!, id = workspace.artifact!.id
        await workspace.run(.check).value; try check(workspace.artifact?.id == id,"check-keeps-artifact")
        let cancelled = workspace.run(); workspace.cancel(); await cancelled.value
        try check(workspace.wasCancelled && workspace.artifact?.id == id,"cancel-keeps-artifact")
        workspace.preferences.direction = .decompress; workspace.input = encoded; await workspace.run().value; await settle(host)
        try check(output.string == "hello\r\n" && workspace.copyText(.text) == "hello\r\n","exact-decompressed-text")
        input.undoManager?.removeAllActions(); input.breakUndoCoalescing()
        input.insertText("A",replacementRange:.init(location:input.string.utf16.count,length:0)); input.breakUndoCoalescing(); await settle(host)
        try check(workspace.artifact == nil && input.adornments.coordinates != nil,"edit-invalidates-no-gutter-flash")
        input.undoManager?.undo(); await settle(host); try check(workspace.input == encoded,"native-undo")
        input.undoManager?.redo(); await settle(host); try check(workspace.input == encoded + "A","native-redo")
        let clipboard = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        defer {
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(clipboard.map { entries in
                let item = NSPasteboardItem(); for (type,data) in entries { item.setData(data,forType:type) }; return item
            })
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(encoded,forType:.string)
        input.setSelectedRange(.init(location:0,length:input.string.utf16.count)); input.paste(nil); await settle(host,250)
        try check(workspace.result?.status == .success && workspace.artifact == nil,"native-paste-check-only")
        for _ in 0..<8 {
            input.insertText("A",replacementRange:.init(location:input.string.utf16.count,length:0)); await settle(host,12)
            try check(workspace.result == nil && !workspace.busy && input.adornments.coordinates != nil,"typing-no-check-no-flicker")
        }
        workspace.input = encoded; await workspace.run().value; await settle(host)
        host.appearance = NSAppearance(named:.darkAqua); window.setContentSize(.init(width:390,height:850)); await settle(host,250)
        try check(workspace.copyText(.text) == "hello\r\n" && all(JSONNativeTextView.self,host).map(ObjectIdentifier.init) == identities,"theme-resize-keeps-data-editors")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        workspace.outputCollapsed = true
        var frames:[Int] = []
        for _ in 0..<15 { await settle(host,20); frames.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("T019_COLLAPSE reduced=\(reduced) frames=\(frames)")
        try check(reduced ? Set(frames).count == 1 : Set(frames).count > 2,"smooth-collapse")
        workspace.outputCollapsed = false; window.setContentSize(.init(width:1100,height:800)); await settle(host,250)
        workspace.preferences.base64Mode = .forgiving
        workspace.input = String(repeating:"AAAA\n",count:850)+"A"; await settle(host,250); await workspace.run().value
        var errors:[Int] = []
        for _ in 0..<15 { await settle(host,20); errors.append(Int(input.enclosingScrollView!.bounds.height)) }
        print("T019_DIAGNOSTICS reduced=\(reduced) frames=\(errors)")
        try check(reduced ? Set(errors).count == 1 : Set(errors).count > 2,"smooth-diagnostics")
        let anchor = workspace.result!.failure!.textRange!
        try check(input.adornments.diagnostic?.range == anchor && anchor.length == 0,"eof-native-marker")
        JSONEditorNavigation.jump(input,to:anchor.location,animated:!reduced,focus:false,highlight:anchor)
        var vertical:[Int] = []
        for _ in 0..<28 { await settle(host,20); vertical.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("T019_VERTICAL reduced=\(reduced) frames=\(vertical)")
        try check(reduced ? Set(vertical).count == 1 : Set(vertical).count > 2,"smooth-offscreen-source-navigation")
        try check(input.adornments.caretRect(at:anchor.location).map { input.visibleRect.intersects($0) } == true,"source-anchor-visible")
        workspace.preferences.wordWrap = false; workspace.input = String(repeating:"A",count:20_001); await workspace.run().value; await settle(host,250)
        let eof = workspace.result!.failure!.textRange!
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false,highlight:eof)
        var horizontal:[Int] = []
        for _ in 0..<28 { await settle(host,20); horizontal.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("T019_HORIZONTAL reduced=\(reduced) frames=\(horizontal)")
        try check(reduced ? Set(horizontal).count == 1 : Set(horizontal).count > 2,"smooth-horizontal-eof")
        try check(input.adornments.caretRect(at:eof.location).map { input.visibleRect.intersects($0) } == true,"horizontal-anchor-visible")
        JSONEditorNavigation.jump(input,to:0,animated:!reduced,focus:false); await settle(host,600)
        try check(input.enclosingScrollView!.contentView.bounds.minX < 30,"new-jump-replaces-old")
        // Switching source kind preserves the editable native role; UI resigns before invoking this mutation.
        window.makeFirstResponder(nil); workspace.usesFile = true; await settle(host); workspace.usesFile = false; await settle(host)
        try check(input.isEditable && !output.isEditable && all(JSONNativeTextView.self,host).map(ObjectIdentifier.init) == identities,"file-switch-stable-editor-role")
        let fresh = GZipWorkspaceSession(repository:.init(defaults:defaults))
        try check(fresh.input.isEmpty && fresh.result == nil && fresh.artifact == nil && fresh.selectedFile == nil,"new-session-empty")
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage); print("T019_NATIVE_PEAK bytes=\(usage.ru_maxrss)")
        window.contentView = nil; window.close()
    }
}
