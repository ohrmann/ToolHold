import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Synthetic, memory-only UI/native checks. File export is exercised in a private test folder.
@main struct Base64FileNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(); print("T013_NATIVE_PASSED") } catch { print("T013_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type,$0) }
    }
    @MainActor static func check(_ test: @autoclosure () -> Bool, _ label: String) throws {
        guard test() else { throw Failure.check(label) }; print("T013_NATIVE_OK \(label)")
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 80) async {
        try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor static func run() async throws {
        let suite = "T013Native." + UUID().uuidString, directory = FileManager.default.temporaryDirectory.appendingPathComponent("T013Native-" + UUID().uuidString)
        let defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let session = Base64FileWorkspaceSession(repository: .init(defaults: defaults))
        session.preferences.direction = .decode
        let host = NSHostingView(rootView: Base64FileView(workspace: session))
        let window = NSWindow(contentRect: .init(x:40,y:40,width:1100,height:800),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        await settle(host,300)
        let editors = all(JSONNativeTextView.self,host)
        try check(editors.count == 2,"two-native-editors")
        let input = editors[0], output = editors[1], identity = editors.map(ObjectIdentifier.init)
        window.makeFirstResponder(input); input.insertText("YQ==",replacementRange:.init(location:0,length:0)); await settle(host)
        let caret = input.selectedRange()
        await session.run().value; await settle(host)
        try check(session.artifact?.imageBytes == Data([97]) && output.string.contains("61") && !output.isEditable,"decode-bytes-readonly-output")
        try check(input.selectedRange() == caret && window.firstResponder === input,"operation-keeps-native-caret-focus")
        await session.run(.check).value
        try check(session.artifact?.imageBytes == Data([97]),"check-preserves-current-artifact")
        input.breakUndoCoalescing(); input.undoManager?.removeAllActions()
        input.insertText("!",replacementRange:.init(location:4,length:0)); input.breakUndoCoalescing(); await settle(host)
        try check(session.artifact == nil && session.result == nil && input.adornments.coordinates != nil,"edit-invalidates-without-gutter-flicker")
        input.undoManager?.undo(); await settle(host); try check(session.input == "YQ==","native-undo")
        input.undoManager?.redo(); await settle(host); try check(session.input == "YQ==!","native-redo")
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType,Data)? in item.data(forType:type).map { (type,$0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item }) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("8J+YgA==",forType:.string)
        window.makeFirstResponder(input); input.selectAll(nil); input.paste(nil)
        for _ in 0..<50 { if session.result != nil { break }; await settle(host,20) }
        try check(session.result?.status == .success && session.artifact == nil,"system-paste-check-only")
        await session.run().value
        for _ in 0..<8 {
            input.insertText(" ",replacementRange:.init(location:input.string.utf16.count,length:0)); await settle(host,12)
            try check(input.adornments.coordinates != nil && session.result == nil && !session.busy,"rapid-typing-retains-gutter-no-auto-parse")
        }
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        let oldHeight = input.enclosingScrollView!.frame.height
        session.inputCollapsed = true
        var heights:[Int] = []
        for _ in 0..<14 { await settle(host,18); heights.append(Int(input.enclosingScrollView!.frame.height)) }
        print("T013_NATIVE_COLLAPSE reduced=\(reduced) before=\(oldHeight) frames=\(heights)")
        try check(reduced ? Set(heights).count == 1 : Set(heights).count > 2,"smooth-input-collapse")
        session.inputCollapsed = false; await settle(host,260)
        session.preferences.decodeMode = .forgiving
        session.input = String(repeating:"YWFh\n",count:600) + "!"
        let beforeDiagnostic = input.enclosingScrollView!.frame.height
        await session.run(.check).value
        var diagnosticHeights:[Int] = []
        for _ in 0..<14 { await settle(host,18); diagnosticHeights.append(Int(input.enclosingScrollView!.frame.height)) }
        print("T013_NATIVE_DIAGNOSTICS reduced=\(reduced) before=\(beforeDiagnostic) frames=\(diagnosticHeights)")
        try check(session.result?.failure?.textRange?.location == 3000 && input.adornments.diagnostic?.range.location == 3000,"native-error-marker")
        let anchor = session.result!.failure!.textRange!
        JSONEditorNavigation.jump(input,to:anchor.location,animated:!reduced,focus:false,highlight:anchor)
        var vertical:[Int] = []
        for _ in 0..<28 { await settle(host,20); vertical.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("T013_NATIVE_VERTICAL reduced=\(reduced) frames=\(vertical)")
        try check(input.adornments.caretRect(at:anchor.location).map { input.visibleRect.intersects($0) } == true,"detection-target-visible")
        try check(reduced ? Set(vertical).count == 1 : Set(vertical).count > 2,"smooth-source-navigation")
        session.preferences.wordWrap = false; session.input = String(repeating:"YWFh",count:5000) + "A"
        await session.run(.check).value; await settle(host,200)
        let eof = session.result!.failure!.textRange!
        try check(eof == .init(location:20_001,length:0),"exact-eof-marker")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false,highlight:eof)
        var horizontal:[Int] = []
        for _ in 0..<28 { await settle(host,20); horizontal.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("T013_NATIVE_HORIZONTAL reduced=\(reduced) frames=\(horizontal)")
        try check(reduced ? Set(horizontal).count == 1 : Set(horizontal).count > 2,"smooth-horizontal-navigation")
        JSONEditorNavigation.jump(input,to:eof.location,animated:!reduced,focus:false)
        JSONEditorNavigation.jump(input,to:0,animated:!reduced,focus:false); await settle(host,600)
        try check(input.enclosingScrollView!.contentView.bounds.minX < 30,"new-jump-cancels-old")
        host.appearance = NSAppearance(named:.darkAqua); window.setContentSize(.init(width:390,height:850)); await settle(host,250)
        try check(all(JSONNativeTextView.self,host).map(ObjectIdentifier.init) == identity && session.input.utf16.count == 20_001,"theme-axis-native-identity-and-data")
        session.input = "YQ=="; await session.run(destination:.init(directory:directory,name:"decoded.bin")).value
        try check(session.exportMessage != nil && (try? Data(contentsOf:directory.appendingPathComponent("decoded.bin"))) == Data([97]),"session-export-exact-bytes")
        let source = directory.appendingPathComponent("source.bin"); try Data([0,255,42]).write(to:source)
        session.preferences.direction = .encode; await session.select(source).value
        try check(session.result == nil && session.selectedFile?.size == 3,"file-selection-metadata-only")
        await session.run().value; await settle(host)
        try check(session.artifact?.copyText == "AP8q" && session.canCopy && window.firstResponder !== input,"file-encode-complete-copy")
        let imageData = NSMutableData()
        let cg = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:3,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        imageData.append(cg.representation(using:.png,properties:[:])!)
        let preview = await Task.detached { Base64FileImagePreview.make(imageData as Data,declared:"image/jpeg") }.value
        try check(preview.image?.width == 2 && preview.message.contains("differs"),"bounded-image-and-mime-mismatch")
        let svg = Base64FileImagePreview.make(Data("<svg/>".utf8),declared:"image/svg+xml")
        try check(svg.image == nil,"svg-never-rendered")
        let fresh = Base64FileWorkspaceSession(repository:.init(defaults:defaults))
        try check(fresh.input.isEmpty && fresh.encodeFile == nil && fresh.decodeFile == nil && fresh.result == nil,"new-session-private")
        window.contentView = nil; window.close()
    }
}
