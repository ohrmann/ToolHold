import AppKit
import SwiftUI
import Darwin
@testable import Developer_Toolbox

/// Focused runtime evidence against the real Debug app UI, using synthetic content only.
@main struct QRCodeNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func all<T: NSView>(_ type: T.Type,_ view: NSView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type,$0) } }
    @MainActor static func value(_ object: NSObject,_ key: String) -> AnyObject? {
        let selector = NSSelectorFromString(key); return object.responds(to:selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }
    @MainActor static func elements(_ root: Any,_ seen: inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let object = root as? NSObject,seen.insert(ObjectIdentifier(object)).inserted else { return [] }
        return [object] + ["accessibilityChildren","accessibilityRows","accessibilityContents"].flatMap { value(object,$0) as? [Any] ?? [] }.flatMap { elements($0,&seen) }
    }
    @MainActor static func ax(_ window: NSWindow) -> [NSObject] { var seen:Set<ObjectIdentifier> = []; return elements(window,&seen) + (window.contentView.map { all(NSView.self,$0).flatMap { elements($0,&seen) } } ?? []) }
    @MainActor static func object(_ id: String,_ window: NSWindow) -> NSObject? { ax(window).first { value($0,"accessibilityIdentifier") as? String == id } }
    @MainActor static func pressObject(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        typealias Call = @convention(c) (AnyObject,Selector) -> Bool
        return object.responds(to:selector) && unsafeBitCast(object.method(for:selector),to:Call.self)(object,selector)
    }
    @MainActor static func press(_ id: String,_ window: NSWindow) throws {
        guard let o = object(id,window), pressObject(o) else { throw Failure.check("press "+id) }
    }
    @MainActor static func check(_ value: @autoclosure () -> Bool,_ name: String) throws { guard value() else { throw Failure.check(name) }; print("QR_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host: NSView,_ ms: Int = 100) async { try? await Task.sleep(for:.milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func ready(_ s: QRCodeWorkspaceSession,_ host: NSView) async throws {
        for _ in 0..<500 where s.busy || s.preparing || s.loadingLogo { await settle(host,10) }
        try check(!s.busy && !s.preparing && !s.loadingLogo,"worker-finished")
    }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true,forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        Task { @MainActor in
            do { if ProcessInfo.processInfo.arguments.contains("--polish") { try await polish() } else { try await run() }; print("T028_NATIVE_PASSED") } catch { print("T028_NATIVE_FAILED \(error)"); exit(1) }; exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func polish() async throws {
        let name="qr-polish-"+UUID().uuidString, defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let s=QRCodeWorkspaceSession(defaults:defaults)
        s.input="Readable in dark mode"
        let host=NSHostingView(rootView:QRCodeGeneratorView(workspace:s))
        let window=NSWindow(contentRect:NSRect(x:40,y:40,width:1100,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.appearance=NSAppearance(named:.darkAqua); window.contentView=host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        await settle(host,300); try await ready(s,host)
        guard let editor=all(NSTextView.self,host).first else { throw Failure.check("dark-input") }
        let identity=ObjectIdentifier(editor)
        func red(_ color:NSColor) -> Double {
            var red=0.0
            editor.effectiveAppearance.performAsCurrentDrawingAppearance { red = Double(color.usingColorSpace(.sRGB)?.redComponent ?? -1) }
            return red
        }
        let text=(editor.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor) ?? editor.textColor!
        print("QR_DARK_NATIVE_COLORS text=\(red(text)) background=\(red(editor.backgroundColor))")
        try check(red(text)>0.7 && red(editor.backgroundColor)<0.3,"dark-text-and-background-contrast")
        window.makeFirstResponder(editor); editor.insertText("!",replacementRange:editor.selectedRange()); await settle(host)
        editor.undoManager?.undo(); await settle(host); try check(s.input=="Readable in dark mode","theme-fix-preserves-undo")
        if ProcessInfo.processInfo.arguments.contains("--logo-only") {
            s.input=String(repeating:"x",count:110); s.preferences.style = .rounded
            s.preferences.logoSize=0.2; s.preferences.logoExpanded=true
            let c=CGContext(data:nil,width:128,height:64,bitsPerComponent:8,bytesPerRow:512,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.clear(CGRect(x:0,y:0,width:128,height:64))
            c.setFillColor(QRColor(0.15,0.35,0.7).cg()); c.fill(CGRect(x:16,y:8,width:96,height:48))
            let image=c.makeImage()!
            s.setLogo(QRLogo(image:image,png:try QRCodeRenderer.png(image)))
            await settle(host,350); try await ready(s,host)
            try check(s.canOutput && s.artifact?.logoMoved == true,"safe-near-center-logo-is-readable")
            let text=editor.string, selection=editor.selectedRange()
            guard let slider=object("qr-logo-opacity",window) else { throw Failure.check("logo-opacity-slider") }
            let decrement=NSSelectorFromString("accessibilityPerformDecrement")
            typealias Action = @convention(c) (AnyObject,Selector) -> Bool
            guard slider.responds(to:decrement),unsafeBitCast(slider.method(for:decrement),to:Action.self)(slider,decrement) else { throw Failure.check("decrement-logo-opacity") }
            await settle(host,350); try await ready(s,host)
            try check(s.preferences.logoBackgroundOpacity < 1 && s.preferences.logoBackgroundOpacity > 0,"real-opacity-control-updates-preferences")
            try check(s.canOutput && editor.string==text && editor.selectedRange()==selection && all(NSTextView.self,host).first === editor,"logo-opacity-keeps-input-and-editor")
            for opacity in [0.0,0.5,1.0] {
                s.preferences.logoBackgroundOpacity=opacity; await settle(host,300); try await ready(s,host)
                try check(s.canOutput,"logo-readable-opacity-\(opacity)")
            }
            if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
                host.cacheDisplay(in:host.bounds,to:bitmap)
                if let data=bitmap.representation(using:.png,properties:[:]) { try data.write(to:URL(fileURLWithPath:"/tmp/t028-logo-workspace.png")) }
            }
            window.contentView=nil; window.close(); return
        }
        if ProcessInfo.processInfo.arguments.contains("--gutter-only") {
            try check(editor.enclosingScrollView?.rulersVisible != true && all(NSRulerView.self,host).isEmpty,"free-text-has-no-ruler-or-separator")
            try check(all(NSTextView.self,host).first === editor,"gutter-fix-retains-editor")
            if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
                host.cacheDisplay(in:host.bounds,to:bitmap)
                if let data=bitmap.representation(using:.png,properties:[:]) { try data.write(to:URL(fileURLWithPath:"/tmp/t028-gutter-fixed.png")) }
            }
            window.contentView=nil; window.close(); return
        }
        let beforeString=editor.string, beforeSelection=editor.selectedRange()
        let beforeTyping=editor.typingAttributes[.foregroundColor] as? NSColor
        let beforeStorage=editor.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor
        try press("qr-foreground",window); await settle(host,250)
        guard let paletteWindow=NSApp.windows.first(where:{object("qr-foreground-swatch-10",$0) != nil}) else { throw Failure.check("palette-popover") }
        try check(!NSColorPanel.shared.isVisible,"no-shared-color-panel")
        try press("qr-foreground-swatch-10",paletteWindow); await settle(host,200)
        print("QR_PALETTE_SELECTED \(s.preferences.foreground.hex)")
        try check(s.preferences.foreground.hex == "#1F52A6","palette-blue-updates-only-qr-color")
        try check(editor.string==beforeString && editor.selectedRange()==beforeSelection,"palette-keeps-input-and-selection")
        try check(editor.typingAttributes[.foregroundColor] as? NSColor == beforeTyping && editor.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == beforeStorage,"palette-does-not-recolor-input")
        // Render the real palette in both appearances and check the colored swatch
        // row directly. This catches the reported all-black grid, unlike binding tests.
        for appearance in [NSAppearance.Name.darkAqua,.aqua] {
            let palette=NSHostingView(rootView:QRCodeColorPalette(color:Binding(get:{s.preferences.foreground},set:{s.preferences.foreground=$0}),label:"Pattern color",identifier:"probe-palette"))
            let panel=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:360),styleMask:[.titled],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed=false
            panel.appearance=NSAppearance(named:appearance); panel.contentView=palette; panel.makeKeyAndOrderFront(nil); await settle(palette,200)
            guard let bitmap=palette.bitmapImageRepForCachingDisplay(in:palette.bounds) else { throw Failure.check("palette-bitmap") }
            palette.cacheDisplay(in:palette.bounds,to:bitmap)
            guard let raster=bitmap.cgImage else { throw Failure.check("palette-cgimage") }
            var pixels=[UInt8](repeating:0,count:raster.width*raster.height*4)
            pixels.withUnsafeMutableBytes { bytes in
                let c=CGContext(data:bytes.baseAddress,width:raster.width,height:raster.height,bitsPerComponent:8,bytesPerRow:raster.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
                c.draw(raster,in:CGRect(x:0,y:0,width:raster.width,height:raster.height))
            }
            var redPixels=0,greenPixels=0,bluePixels=0
            for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3]>200 {
                if pixels[i]>153 && pixels[i+1]<64 && pixels[i+2]<77 { redPixels += 1 }
                if pixels[i+1]>115 && pixels[i]<64 && pixels[i+2]<102 { greenPixels += 1 }
                if pixels[i+2]>140 && pixels[i]<64 && pixels[i+1]<102 { bluePixels += 1 }
            }
            print("QR_PALETTE_PIXELS \(appearance.rawValue) red=\(redPixels) green=\(greenPixels) blue=\(bluePixels)")
            if let data=bitmap.representation(using:.png,properties:[:]) { try data.write(to:URL(fileURLWithPath:"/tmp/t028-d103-palette-\(appearance.rawValue).png")) }
            try check(min(redPixels,greenPixels,bluePixels)>300,"palette-colored-grid-\(appearance.rawValue)")
            panel.close()
        }
        paletteWindow.orderOut(nil); window.makeKeyAndOrderFront(nil)
        try check(all(NSTextView.self,host).contains { ObjectIdentifier($0)==identity },"color-change-retains-native-editor")
        // Wide preview should use a compact sidebar instead of most of the workspace.
        let selector=NSSelectorFromString("accessibilityFrame")
        if let p=object("qr-preview",window),p.responds(to:selector) {
            typealias Getter = @convention(c) (AnyObject,Selector) -> NSRect
            let frame=unsafeBitCast(p.method(for:selector),to:Getter.self)(p,selector); print("QR_PREVIEW_FRAME \(frame)")
            try check(frame.width <= 340 && frame.height <= 300,"compact-preview-bounds")
        } else { print("QR_NATIVE_UNVERIFIED preview AX frame unavailable") }
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let data=bitmap.representation(using:.png,properties:[:]) { try data.write(to:URL(fileURLWithPath:"/tmp/t028-d103-workspace.png")) }
        }
        for kind in [QRContentKind.url,.contact,.wifi,.email,.phone,.sms,.freeText] {
            window.makeFirstResponder(nil); s.contentKind=kind; await settle(host,250)
            try check(all(NSTextView.self,host).contains { ObjectIdentifier($0)==identity },"mode-keeps-original-free-text-editor-\(kind.rawValue)")
        }
        try check(s.input=="Readable in dark mode","content-mode-switch-retains-free-draft")
        window.appearance=NSAppearance(named:.aqua); await settle(host,150)
        try check(red(text)<0.3 && red(editor.backgroundColor)>0.7,"light-theme-contrast-restored")
        window.close()
    }
    @MainActor static func run() async throws {
        let suite = "QR-native-"+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let saved = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved.map { entries in let item=NSPasteboardItem(); for (type,data) in entries { item.setData(data,forType:type) }; return item }) }
        let session = QRCodeWorkspaceSession(defaults:defaults)
        let host = NSHostingView(rootView:QRCodeGeneratorView(workspace:session))
        let window = NSWindow(contentRect:NSRect(x:40,y:40,width:1100,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.contentView=host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); await settle(host,250)
        let editor = try all(NSTextView.self,host).first.unwrap("input")
        let identity = ObjectIdentifier(editor)
        window.makeFirstResponder(editor)
        editor.insertText("https://example.com/native",replacementRange:NSRange(location:0,length:0))
        await settle(host,50)
        try check(session.input == "https://example.com/native","native-input")
        editor.undoManager?.undo(); await settle(host); try check(session.input.isEmpty,"native-undo")
        editor.undoManager?.redo(); await settle(host); try check(session.input == "https://example.com/native","native-redo")
        let selection = editor.selectedRange()
        try press("qr-generate",window); try await ready(session,host)
        try check(session.canOutput,"native-qr-readable")
        try check(editor.selectedRange()==selection && window.firstResponder === editor,"generate-keeps-caret-focus")
        try press("qr-copy",window); try await ready(session,host)
        try check(NSPasteboard.general.data(forType:.png)?.starts(with:[137,80,78,71]) == true,"copy-real-png")
        // Actual native Paste; background generation must not move the caret.
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(" 🌍",forType:.string)
        editor.paste(nil); let pastedSelection = editor.selectedRange(); await settle(host,300); try await ready(session,host)
        try check(session.input.hasSuffix(" 🌍") && session.canOutput && editor.selectedRange()==pastedSelection,"native-paste-live-generation")
        for style in QRModuleStyle.allCases { session.preferences.style=style; try await ready(session,host); try check(session.canOutput,"style-\(style.rawValue)") }
        // Observe the actual layout transition, not merely presence of withAnimation.
        var frames:[Double]=[]
        session.preferences.appearanceExpanded=false
        for _ in 0..<18 { await settle(host,16); if let scroll = all(NSScrollView.self,host).first(where:{ !($0.documentView is NSTextView) }), let document = scroll.documentView { frames.append(document.frame.height) } }
        print("QR_DISCLOSURE_FRAMES \(frames)")
        let reduced=ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        try check(reduced || Set(frames.map { Int($0.rounded()) }).count > 2,"disclosure-intermediate-motion")
        session.preferences.appearanceExpanded=true; session.preferences.logoExpanded=true; await settle(host,250)
        let c=CGContext(data:nil,width:128,height:64,bitsPerComponent:8,bytesPerRow:512,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(QRColor(0.2,0.3,0.8).cg()); c.fill(CGRect(x:0,y:0,width:128,height:64))
        let logoURL=URL(fileURLWithPath:"/tmp/t028-synthetic-logo.png")
        try QRCodeRenderer.png(c.makeImage()!).write(to:logoURL)
        defer { try? FileManager.default.removeItem(at:logoURL) }
        session.loadLogo(logoURL); try await ready(session,host)
        try check(session.logo != nil && session.artifact?.matrix.correction == .h && session.canOutput,"file-logo-h-readable")
        session.preferences.opacity=0; try await ready(session,host)
        try check(session.artifact?.verification == .readable(conditional:true),"transparent-conditional-check")
        let same=editor.string
        window.appearance=NSAppearance(named:.darkAqua); window.setContentSize(NSSize(width:390,height:820)); await settle(host,300)
        try check(all(NSTextView.self,host).contains { ObjectIdentifier($0)==identity } && editor.string==same,"dark-narrow-stable-editor")
        window.appearance=NSAppearance(named:.aqua); window.setContentSize(NSSize(width:1100,height:850)); await settle(host,250)
        // Exercise the real first exporter. The native panel must have a usable Save action.
        session.preferences.format = .png
        try press("qr-export",window); try await ready(session,host); await settle(host,400)
        print("QR_EXPORT_WINDOWS \(NSApp.windows.map { String(describing:type(of:$0)) })")
        if let panel = NSApp.windows.compactMap({$0 as? NSSavePanel}).first {
            let folder=URL(fileURLWithPath:"/tmp/t028-native-export",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            print("QR_SAVE_BEFORE_DIRECTORY"); panel.directoryURL=folder; print("QR_SAVE_AFTER_DIRECTORY"); panel.nameFieldStringValue="qr-native.png"; await settle(host,200)
            let controls = ax(panel)
            print("QR_SAVE_CONTROLS",controls.compactMap { value($0,"accessibilityLabel") as? String })
            // macOS 27 hosts the real controls in the remote Save service. This in-process
            // probe cannot press them; do not call NSSavePanel.ok (not implemented there).
            print("QR_NATIVE_UNVERIFIED remote-Mac-Save-confirmation; picker presented")
            panel.orderOut(nil)
        } else { throw Failure.check("native-save-panel-not-found") }
        // Save a synthetic runtime screenshot for visual review.
        if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) { host.cacheDisplay(in:host.bounds,to:rep); try rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:reduced ? "/tmp/t028-mac-reduced.png" : "/tmp/t028-mac-light.png")) }
        try press("qr-clear",window); await settle(host)
        try check(session.input.isEmpty && !session.canOutput && editor.undoManager?.canUndo == false,"clear-purges-working-input-undo")
        let new=QRCodeWorkspaceSession(defaults:defaults)
        try check(new.input.isEmpty && new.logo==nil && new.artifact==nil,"fresh-session-private")
        window.close()
    }
}
private extension Optional {
    func unwrap(_ name:String) throws -> Wrapped { guard let self else { throw QRCodeNativeProbe.Failure.check(name) }; return self }
}
