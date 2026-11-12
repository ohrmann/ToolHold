import AppKit
import SwiftUI
import CoreImage
@testable import Developer_Toolbox

@main struct QRCodeDecoderNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func check(_ condition: @autoclosure () -> Bool,_ name: String) throws {
        guard condition() else { throw Failure.check(name) }; print("T029_NATIVE_OK \(name)")
    }
    @MainActor static func views<T:NSView>(_ type:T.Type,_ root:NSView) -> [T] { var list:[T] = []; if let match=root as? T { list.append(match) }; for child in root.subviews { list += views(type,child) };return list }
    @MainActor static func settle(_ host:NSView,_ ms:Int=80) async { try? await Task.sleep(for:.milliseconds(ms));host.layoutSubtreeIfNeeded();host.displayIfNeeded() }
    static func fixture() throws -> Data {
        let path=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/QRCodeCoreTests/DecoderFixtures/utf8-eci.png")
        return try Data(contentsOf:path)
    }
    @MainActor static func ready(_ session:QRCodeDecoderWorkspaceSession,_ host:NSView) async throws {
        for _ in 0..<500 where session.busy { await settle(host,10) }
        try check(!session.busy,"worker-completed")
    }
    @MainActor static func main() {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run();print("T029_NATIVE_PASSED");exit(0) } catch { print("T029_NATIVE_FAILED \(error)");exit(1) }
        };NSApplication.shared.run()
    }
    @MainActor static func run() async throws {
        let s=QRCodeDecoderWorkspaceSession()
        let host=NSHostingView(rootView:QRCodeDecoderView(workspace:s))
        let window=NSWindow(contentRect:NSRect(x:50,y:50,width:1100,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        await settle(host,200)
        try check(s.source == nil,"first-open-empty")
        let board=NSPasteboard.general
        let saved=board.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        defer {
            board.clearContents()
            for values in saved { let item=NSPasteboardItem();for(type,data) in values { item.setData(data,forType:type) };board.writeObjects([item]) }
        }
        board.clearContents();board.setData(try fixture(),forType:.png)
        QRDecodedClipboard.paste(into:s)
        try await ready(s,host);await settle(host,200)
        try check(s.selected?.text == "👩🏽‍💻 e\u{301} 中文","real-image-paste-text")
        guard let editor=views(NSTextView.self,host).first,let viewport=views(QRDecoderScrollView.self,host).first else { throw Failure.check("native-views") }
        let identity=ObjectIdentifier(editor)
        try check(!editor.isEditable && editor.isSelectable,"readonly-selectable-native-output")
        try check(editor.string == s.selected?.text.map(QRDecodedPresentation.safeText),"full-text-output")
        editor.setSelectedRange(NSRange(location:0,length:2))
        let range=editor.selectedRange()
        let sourceID=s.source?.id
        window.appearance=NSAppearance(named:.darkAqua);await settle(host,150)
        try check(views(NSTextView.self,host).contains { ObjectIdentifier($0)==identity },"theme-preserves-editor")
        try check(s.source?.id==sourceID && s.canOutput,"theme-keeps-current-snapshot")
        try check(editor.selectedRange() == range,"theme-preserves-selection")
        let value=try s.selected.unwrap("selected")
        QRDecodedClipboard.copy(QRDecodedPresentation.copy(value,as:.text)!)
        try check(board.string(forType:.string) == value.text,"copy-exact-text")
        let nul = "a\0b\0"
        QRDecodedClipboard.copy(nul)
        try check(board.data(forType:.string) == Data(nul.utf8),"clipboard-preserves-nul-bytes")
        try check(board.string(forType:.string)?.utf8.elementsEqual(nul.utf8) == true,"clipboard-preserves-nul-text")
        let export=try QRDecodedExport(item:value,text:false).unwrap("export")
        let file=URL(fileURLWithPath:"/tmp/t029-native-payload.bin");try export.data.write(to:file)
        let readback = try Data(contentsOf:file)
        try check(readback == value.bytes,"byte-export-readback")
        let initial=viewport.magnification
        viewport.perform(.zoomIn,reduced:ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
        var samples:[CGFloat]=[initial]
        for _ in 0..<15 { await settle(host,20);samples.append(viewport.magnification) }
        print("T029_ZOOM_SAMPLES \(samples)")
        try check(samples.last! > initial,"zoom-in")
        if !ProcessInfo.processInfo.arguments.contains("--reduce-motion") { try check(samples.dropFirst().dropLast().contains { $0>initial && $0<samples.last! },"zoom-intermediate-frames") }
        viewport.perform(.reveal(value.bounds),reduced:true);await settle(host)
        try check(viewport.documentVisibleRect.intersects(value.bounds),"reveal-visible")
        try check(viewport.hasHorizontalScroller && viewport.hasVerticalScroller,"visible-native-scrollbars")
        window.setContentSize(NSSize(width:390,height:850));await settle(host,250)
        try check(s.source?.id==sourceID,"narrow-retains-data")
        try check(views(NSTextView.self,host).contains { ObjectIdentifier($0)==identity },"resize-preserves-editor")
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let png=bitmap.representation(using:.png,properties:[:]) { try png.write(to:URL(fileURLWithPath:"/tmp/t029-mac-narrow.png")) }
        }
        window.setContentSize(NSSize(width:1100,height:800));await settle(host,250)
        s.scanAgain();s.cancel();try check(s.canOutput,"cancel-keeps-current-result")
        s.clear();await settle(host);try check(s.source==nil && s.snapshot==nil,"clear-removes-image-and-content")
        try check(views(NSTextView.self,host).first?.string == "","clear-removes-native-text")
        try check(QRCodeDecoderWorkspaceSession().snapshot==nil,"new-session-empty")
        window.close()
    }
}
extension Optional {
    func unwrap(_ name:String) throws -> Wrapped { guard let self else { throw QRCodeDecoderNativeProbe.Failure.check(name) };return self }
}
