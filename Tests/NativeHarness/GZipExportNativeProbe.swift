import AppKit
import SwiftUI
@testable import Developer_Toolbox

/// Real first sheet presentation: do not edit the filename to refresh stale SwiftUI state.
@main struct GZipExportNativeProbe {
    enum Failure:Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        NSApp.accessibilitySetValue(true, forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        Task { @MainActor in
            do { try await run(); print("T019_EXPORT_NATIVE_PASSED") }
            catch { print("T019_EXPORT_NATIVE_FAILURE \(error)"); exit(1) }; exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func objectValue(_ element:NSObject,_ key:String) -> AnyObject? {
        let selector = NSSelectorFromString(key)
        return element.responds(to:selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }
    @MainActor static func boolValue(_ element:NSObject,_ key:String) -> Bool {
        let selector = NSSelectorFromString(key)
        guard element.responds(to:selector) else { return false }
        typealias Getter = @convention(c) (AnyObject,Selector) -> Bool
        return unsafeBitCast(element.method(for:selector),to:Getter.self)(element,selector)
    }
    @MainActor static func elements(_ root:Any,_ seen:inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let element = root as? NSObject, seen.insert(ObjectIdentifier(element)).inserted else { return [] }
        return [element] + ((objectValue(element,"accessibilityChildren") as? [Any]) ?? []).flatMap { elements($0,&seen) }
    }
    @MainActor static func find(_ identifier:String) -> NSObject? {
        var seen:Set<ObjectIdentifier> = []
        return NSApp.windows.flatMap { elements($0,&seen) }.first { objectValue($0,"accessibilityIdentifier") as? String == identifier }
    }
    @MainActor static func check(_ value:Bool,_ label:String) throws {
        guard value else { throw Failure.check(label) }; print("T019_EXPORT_NATIVE_OK \(label)")
    }
    @MainActor static func settle(_ host:NSView) async {
        try? await Task.sleep(for:.milliseconds(250)); host.layoutSubtreeIfNeeded()
    }
    @MainActor static func run() async throws {
        let suite = "GZipExportProbe."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let workspace = GZipWorkspaceSession(repository:.init(defaults:defaults))
        let host = NSHostingView(rootView:GZipView(workspace:workspace))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1100,height:800),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        await settle(host)
        workspace.input = "hello"; await workspace.run().value; await settle(host)
        try check(workspace.canExport,"valid-result-can-export")
        guard let export = find("gzip-export") else { throw Failure.check("export-accessibility-element") }
        try check(boolValue(export,"isAccessibilityEnabled") && boolValue(export,"accessibilityPerformPress"),"open-export-sheet")
        await settle(host)
        guard let confirm = find("gzip-export-confirm") else { throw Failure.check("choose-folder-element") }
        print("T019_EXPORT_NATIVE_INITIAL enabled=\(boolValue(confirm,"isAccessibilityEnabled")) defaultName=\(find("gzip-export-name").flatMap { objectValue($0,"accessibilityValue") } ?? "nil" as NSString)")
        try check(boolValue(confirm,"isAccessibilityEnabled"),"choose-folder-enabled-without-editing-name")
        guard let cancel = find("gzip-export-cancel") else { throw Failure.check("cancel-element") }
        try check(boolValue(cancel,"accessibilityPerformPress"),"cancel-export-sheet")
        await settle(host)
        workspace.preferences.direction = .decompress
        workspace.input = "H4sIAAAAAAAC/8tIzcnJ5wIAIDA6NgYAAAA="
        await workspace.run().value; await settle(host)
        guard let nextExport = find("gzip-export") else { throw Failure.check("next-export-element") }
        try check(boolValue(nextExport,"accessibilityPerformPress"),"open-decompress-export")
        await settle(host)
        try check(find("gzip-export-name").flatMap { objectValue($0,"accessibilityValue") as? String } == "decompressed.bin","current-default-filename-on-reopen")
        try check(find("gzip-export-confirm").map { boolValue($0,"isAccessibilityEnabled") } == true,"reopened-choose-folder-enabled")
        workspace.input = "changed"; await settle(host)
        try check(!workspace.canExport && find("gzip-export-confirm") == nil,"source-edit-dismisses-stale-export-sheet")
        window.contentView = nil; window.close()
    }
}
