import AppKit
import SwiftUI

@main struct JSONTOMLNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run() } catch { print("TOML_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] { (view as? T).map { [$0] } ?? view.subviews.flatMap { all(type, $0) } }
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw Failure.check(message) }; print("TOML_NATIVE_OK \(message)") }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 80) async { try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    @MainActor static func run() async throws {
        let suite = "TOMLNativeProbe.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = JSONTOMLWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: JSONTOMLConverterView(workspace: workspace))
        let window = NSWindow(contentRect: .init(x: 40, y: 40, width: 1100, height: 800), styleMask: [.titled,.resizable,.closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host, 250)
        let editors = all(JSONNativeTextView.self, host)
        try check(editors.count == 2, "two-native-editors")
        let input = editors[0], output = editors[1], identity = editors.map(ObjectIdentifier.init)
        let source = #"{"root":{"number":9007199254740993,"text":"yes"}}"#
        window.makeFirstResponder(input); input.insertText(source, replacementRange: .init(location: 0, length: 0)); await settle(host)
        let caret = input.selectedRange()
        await workspace.run().value; await settle(host)
        try check(workspace.output?.contains("9007199254740993") == true && !output.isEditable, "convert-exact-number-readonly-output")
        try check(input.selectedRange() == caret && window.firstResponder === input, "conversion-preserves-caret-focus")
        await workspace.run(convert: false).value
        try check(workspace.output != nil, "check-preserves-output")
        for _ in 0..<8 {
            input.insertText(" ", replacementRange: .init(location: input.string.utf16.count, length: 0)); await settle(host, 12)
            try check(input.adornments.coordinates != nil, "gutter-present-during-typing")
        }
        input.breakUndoCoalescing(); input.undoManager?.removeAllActions()
        input.insertText(" ", replacementRange: .init(location: input.string.utf16.count, length: 0)); input.breakUndoCoalescing()
        window.makeFirstResponder(input)
        input.undoManager?.undo(); await settle(host)
        print("TOML_NATIVE_UNDO actualLength=\(workspace.input.utf16.count) expectedLength=\(source.utf16.count+8) nativeLength=\(input.string.utf16.count) canUndo=\(input.undoManager?.canUndo ?? false) canRedo=\(input.undoManager?.canRedo ?? false)")
        try check(workspace.input == source + String(repeating: " ", count: 8), "native-undo")
        input.undoManager?.redo(); await settle(host)
        try check(workspace.input == source + String(repeating: " ", count: 9), "native-redo")
        let savedClipboard = NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type,$0) } } } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(savedClipboard.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data, forType: type) }; return item }) }
        workspace.direction = .tomlToJSON
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("emoji=\"😀\"\nnumber=9007199254740993", forType: .string)
        input.selectAll(nil); input.paste(nil)
        for _ in 0..<30 { if workspace.result != nil { break }; await settle(host, 20) }
        try check(workspace.result?.status == .success && workspace.output == nil, "system-paste-check-only")
        let pasted = workspace.input
        await workspace.run().value; await settle(host)
        host.appearance = NSAppearance(named: .darkAqua); window.setContentSize(.init(width: 390, height: 850)); await settle(host, 250)
        try check(all(JSONNativeTextView.self, host).map(ObjectIdentifier.init) == identity, "dark-resize-preserves-native-identity")
        try check(workspace.input == pasted && workspace.output != nil, "theme-resize-retains-working-data")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { workspace.outputCollapsed = true }
        var heights: [Int] = []
        for _ in 0..<14 { await settle(host, 20); heights.append(Int(input.enclosingScrollView?.bounds.height ?? -1)) }
        print("TOML_NATIVE_COLLAPSE reduced=\(reduced) heights=\(heights)")
        try check(reduced ? Set(heights).count == 1 : Set(heights).count > 2, "smooth-collapse")
        workspace.outputCollapsed = false; window.setContentSize(.init(width: 1100, height: 800)); await settle(host, 250)
        workspace.input = "values=[\n" + Array(repeating: "1,", count: 850).joined(separator: "\n") + "\nunfinished"
        await settle(host, 250)
        await workspace.run().value
        var diagnosticHeights: [Int] = []
        for _ in 0..<14 { await settle(host, 20); diagnosticHeights.append(Int(input.enclosingScrollView?.bounds.height ?? -1)) }
        print("TOML_NATIVE_DIAGNOSTICS reduced=\(reduced) heights=\(diagnosticHeights)")
        try check(reduced ? Set(diagnosticHeights).count == 1 : Set(diagnosticHeights).count > 2, "smooth-diagnostics-expansion")
        try check(workspace.result?.status == .invalid && workspace.context != nil, "toml-diagnostics")
        let before = input.enclosingScrollView!.contentView.bounds.minY
        let anchor = workspace.result!.diagnostics[0].range
        // iPhone/iPad XCTest exercises the actual Show Detection button. Here sample
        // the same shared native navigation path, independently of SwiftUI AX wrappers.
        JSONEditorNavigation.jump(input, to: anchor.location, animated: !reduced, focus: false, highlight: anchor)
        var frames: [Int] = []
        for _ in 0..<30 { await settle(host, 20); frames.append(Int(input.enclosingScrollView!.contentView.bounds.minY)) }
        print("TOML_NATIVE_SCROLL reduced=\(reduced) start=\(before) frames=\(frames)")
        try check(input.adornments.caretRect(at: anchor.location).map { input.visibleRect.intersects($0) } == true, "offscreen-detection-visible")
        try check(reduced ? Set(frames).count == 1 : Set(frames).count > 2, "smooth-detection-navigation")
        try check(input.selectedRange().length == 0, "no-whole-line-selection")
        workspace.preferences.wordWrap = false
        workspace.direction = .jsonToTOML
        workspace.input = "{\"root\":\"" + String(repeating: "x", count: 20_000)
        await workspace.run().value; await settle(host, 300)
        let horizontalAnchor = workspace.result!.diagnostics[0].range
        JSONEditorNavigation.jump(input, to: horizontalAnchor.location, animated: !reduced, focus: false, highlight: horizontalAnchor)
        var horizontal: [Int] = []
        for _ in 0..<25 { await settle(host, 20); horizontal.append(Int(input.enclosingScrollView!.contentView.bounds.minX)) }
        print("TOML_NATIVE_HORIZONTAL reduced=\(reduced) frames=\(horizontal)")
        try check((horizontal.last ?? 0) > 1000, "wrap-off-horizontal-navigation")
        try check(reduced ? Set(horizontal).count == 1 : Set(horizontal).count > 2, "horizontal-motion-policy")
        try check(input.adornments.caretRect(at: horizontalAnchor.location).map { input.visibleRect.intersects($0) } == true, "horizontal-target-visible")
        // A new jump cancels the previous one; it must not return to the old EOF target.
        let related = workspace.result!.diagnostics[0].related[0].range
        JSONEditorNavigation.jump(input, to: horizontalAnchor.location, animated: !reduced, focus: false)
        JSONEditorNavigation.jump(input, to: related.location, animated: !reduced, focus: false)
        await settle(host, 600)
        try check(input.enclosingScrollView!.contentView.bounds.minX < 30, "new-jump-replaces-old-target")
        commandsClear(input); await settle(host)
        try check(workspace.input.isEmpty && workspace.output == nil && workspace.result == nil, "clear-invalidates-all")
        window.makeFirstResponder(input)
        input.undoManager?.undo(); await settle(host)
        try check(!workspace.input.isEmpty, "undo-clear-restores-input")
        window.contentView = nil; window.close()
    }
    @MainActor static func commandsClear(_ input: NSTextView) { input.breakUndoCoalescing(); input.insertText("", replacementRange: .init(location: 0, length: input.string.utf16.count)); input.breakUndoCoalescing() }
}
