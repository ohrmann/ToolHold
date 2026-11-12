import AppKit
import SwiftUI

@main struct JSONSchemaNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run() } catch { print("SCHEMA_NATIVE_FAILURE \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type: T.Type, _ root: NSView) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { all(type, $0) }
    }
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw Failure.check(message) }; print("SCHEMA_NATIVE_PASS \(message)")
    }
    @MainActor static func settle(_ host: NSView, _ ms: Int = 60) async {
        host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(ms)); host.layoutSubtreeIfNeeded()
    }
    @MainActor static func run() async throws {
        let domain = "toolbox.schema.probe.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = JSONSchemaWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: JSONSchemaValidatorView(workspace: workspace))
        let window = NSWindow(contentRect: .init(x: 80, y: 80, width: 1100, height: 820), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        await settle(host)
        let editors = all(JSONNativeTextView.self, host)
        try check(editors.count == 2, "two-native-editors")
        let input = editors[0], schema = editors[1]
        let identities = editors.map(ObjectIdentifier.init)
        let source = #"{"age":"bad"}"#
        let rules = #"{"properties":{"age":{"type":"integer"}}}"#
        window.makeFirstResponder(input); input.insertText(source, replacementRange: .init(location: 0, length: 0))
        window.makeFirstResponder(schema); schema.insertText(rules, replacementRange: .init(location: 0, length: 0))
        let selection = schema.selectedRange()
        await workspace.validate().value; await settle(host)
        try check(workspace.report?.status == .nonconforming, "native-validation")
        try check(schema.selectedRange() == selection && window.firstResponder === schema, "validation-preserves-caret-focus")
        let table = all(NSTableView.self, host).first!
        try check(table.numberOfRows == workspace.rows.count && table.numberOfRows > 0, "native-issue-table")
        host.appearance = NSAppearance(named: .darkAqua); await settle(host)
        window.setContentSize(.init(width: 390, height: 840)); await settle(host)
        try check(all(JSONNativeTextView.self, host).map(ObjectIdentifier.init) == identities, "theme-resize-native-identity")
        try check(workspace.instance.source == source && workspace.schema.source == rules, "theme-resize-source-retained")
        window.setContentSize(.init(width: 1100, height: 820)); await settle(host)
        window.makeFirstResponder(input); input.breakUndoCoalescing()
        input.insertText(" ", replacementRange: .init(location: source.utf16.count, length: 0)); input.breakUndoCoalescing()
        try check(workspace.report == nil, "edit-invalidates-report")
        input.undoManager?.undo(); await settle(host)
        try check(workspace.instance.source == source, "native-undo")
        input.undoManager?.redo(); await settle(host)
        try check(workspace.instance.source == source + " ", "native-redo")
        let savedClipboard = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(savedClipboard.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data, forType: type) }; return item })
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("{\"age\":12}", forType: .string)
        input.selectAll(nil); input.paste(nil)
        for _ in 0..<30 { if workspace.instance.document != nil { break }; await settle(host, 20) }
        try check(workspace.instance.document != nil && workspace.report == nil, "system-paste-syntax-only")
        let reduced = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        window.makeFirstResponder(table)
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { workspace.instanceCollapsed = true; workspace.schemaCollapsed = true }
        var heights: [Int] = []
        for _ in 0..<14 { await settle(host, 20); heights.append(Int(input.enclosingScrollView?.bounds.height ?? -1)) }
        print("SCHEMA_NATIVE_COLLAPSE reduced=\(reduced) heights=\(heights)")
        try check(reduced || Set(heights).count > 2, "smooth-collapse")
        workspace.instance.source = "{\n" + (0..<850).map { "\"k\($0)\":0" }.joined(separator: ",\n") + ",\n\"target\":\"wrong\"\n}"
        workspace.schema.source = "{\n" + (0..<850).map { "\"x-\($0)\":null" }.joined(separator: ",\n") + ",\n\"properties\":{\"target\":{\"type\":\"integer\"}}\n}"
        await workspace.validate().value; await settle(host)
        try check(workspace.report?.status == .nonconforming, "offscreen-pair-validation")
        let point = table.convert(NSPoint(x: 130, y: table.rect(ofRow: 0).midY), to: nil)
        for count in [1,2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false); await settle(host, 12)
            }
            await settle(host, 30)
        }
        var y: [Int] = [], ruleY: [Int] = []
        for _ in 0..<32 {
            await settle(host, 20)
            y.append(Int(input.enclosingScrollView?.contentView.bounds.minY ?? -1))
            ruleY.append(Int(schema.enclosingScrollView?.contentView.bounds.minY ?? -1))
        }
        print("SCHEMA_NATIVE_SCROLL reduced=\(reduced) json=\(y) schema=\(ruleY)")
        try check(!workspace.instanceCollapsed && !workspace.schemaCollapsed, "actual-double-click-reveals-both")
        let issue = workspace.selectedIssue!
        let dataRange = workspace.sourceRange(issue, schemaSide: false)!, ruleRange = workspace.sourceRange(issue, schemaSide: true)!
        try check(input.selectedRange().location == dataRange.location && schema.selectedRange().location == ruleRange.location, "both-source-anchors")
        try check(input.adornments.caretRect(at: dataRange.location).map { input.visibleRect.intersects($0) } == true, "json-offscreen-visible")
        try check(schema.adornments.caretRect(at: ruleRange.location).map { schema.visibleRect.intersects($0) } == true, "schema-offscreen-visible")
        try check(reduced || (Set(y.filter { $0 > 0 }).count > 2 && Set(ruleY.filter { $0 > 0 }).count > 2), "both-scrolls-animate")
        try check(window.firstResponder !== input && window.firstResponder !== schema, "source-navigation-does-not-steal-focus")
        try check(input.adornments.navigationHighlight != nil && schema.adornments.navigationHighlight != nil, "both-attention-markers")
        workspace.instance.source = "[1,]"; await workspace.validate().value; await settle(host)
        try check(workspace.instance.result?.status == .invalid && workspace.report == nil, "invalid-json-diagnostics")
        workspace.instanceCollapsed = true; workspace.schemaCollapsed = true
        workspace.instance.source = "[" + Array(repeating: "0", count: 24_000).joined(separator: ",") + "]"
        workspace.schema.source = #"{"items":{"type":"string"}}"#
        let started = ContinuousClock.now
        await workspace.validate().value; await settle(host)
        print("SCHEMA_STRESS_DIAGNOSTIC status=\(String(describing: workspace.report?.status)) issues=\(workspace.report?.issues.count ?? -1) rows=\(table.numberOfRows) busy=\(workspace.busy)")
        try check(workspace.report?.status == .nonconforming && table.numberOfRows == 1000, "large-issue-list-report-cap")
        workspace.selection = workspace.rows.last; workspace.move(0); await settle(host)
        try check(table.rows(in: table.visibleRect).contains(999), "continuous-last-issue-reachable")
        func countViews(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + countViews($1) } }
        print("SCHEMA_NATIVE_STRESS utf16=48001 violations=24000 rendered_rows=1000 live_views=\(countViews(host)) wall_with_settle=\(started.duration(to: .now))")
        let usage = getUsage()
        print("SCHEMA_NATIVE_MEMORY peak_bytes=\(usage)")
        // Extended profiles and explicit imported-resource source navigation.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("schema-probe-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resourceURL = directory.appendingPathComponent("rules.json")
        try Data(("{\n" + (0..<700).map { "\"x-\($0)\":null" }.joined(separator: ",\n") + ",\n\"type\":\"integer\"\n}").utf8).write(to: resourceURL)
        workspace.instance.source = #""wrong""#
        workspace.schema.source = #"{"$ref":"rules.json"}"#
        await workspace.importResources([resourceURL]).value
        await workspace.validate().value; await settle(host)
        try check(workspace.report?.status == .nonconforming, "imported-schema-validation")
        let importedIssue = workspace.selectedIssue!
        let originalSchemaIdentity = ObjectIdentifier(schema)
        let originalSchemaViewport = schema.enclosingScrollView!.contentView.bounds.origin
        workspace.instanceCollapsed = false; workspace.schemaCollapsed = false
        // Actual issue double-click triggers Show Both and activates the referenced source.
        await settle(host, reduced ? 80 : 240)
        let resourcePoint = table.convert(NSPoint(x: 130, y: table.rect(ofRow: 0).midY), to: nil)
        for count in [1,2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: resourcePoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1)!
                NSApp.postEvent(event, atStart: false); await settle(host, 12)
            }
            await settle(host, 30)
        }
        var importedY: [Int] = []
        for _ in 0..<28 {
            await settle(host, 20)
            if let imported = all(JSONNativeTextView.self, host).first(where: { !$0.isEditable }) {
                importedY.append(Int(imported.enclosingScrollView!.contentView.bounds.minY))
            }
        }
        try check(workspace.activeResource == importedIssue.schemaDocumentID && workspace.activeResource != nil, "show-imported-schema")
        let imported = all(JSONNativeTextView.self, host).first { !$0.isEditable }!
        let importedRange = workspace.sourceRange(importedIssue, schemaSide: true)!
        try check(imported.adornments.caretRect(at: importedRange.location).map { imported.visibleRect.intersects($0) } == true, "imported-rule-visible")
        print("SCHEMA_IMPORTED_SCROLL reduced=\(reduced) offsets=\(importedY)")
        try check(reduced || Set(importedY.filter { $0 > 0 }).count > 2, "imported-rule-smooth-navigation")
        try check(all(JSONNativeTextView.self, host).contains { ObjectIdentifier($0) == originalSchemaIdentity }, "primary-editor-remains-mounted")
        workspace.activeResource = nil; await settle(host)
        try check(schema.string == #"{"$ref":"rules.json"}"# && schema.enclosingScrollView!.contentView.bounds.origin == originalSchemaViewport, "primary-source-viewport-preserved")
        workspace.schema.source = #"{"format":"email"}"#
        workspace.instance.source = #""bad-email""#
        await workspace.validate().value
        try check(workspace.report?.status == .valid, "format-annotation-default")
        workspace.validateFormats = true
        try check(workspace.report == nil, "format-switch-invalidates-report")
        await workspace.validate().value
        try check(workspace.report?.status == .nonconforming, "format-validation-enabled")
        workspace.validateFormats = false
        workspace.assumedDialect = .draft7
        workspace.schema.source = #"{"items":[{"type":"integer"}],"additionalItems":false}"#
        workspace.instance.source = "[1,2]"
        await workspace.validate().value
        try check(workspace.report?.status == .nonconforming && workspace.report!.profile.contains("Draft-07"), "draft7-native-workspace")
        window.contentView = nil; window.close()
    }
    static func getUsage() -> Int { var r = rusage(); getrusage(RUSAGE_SELF, &r); return Int(r.ru_maxrss) }
}
