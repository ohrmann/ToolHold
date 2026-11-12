import SwiftUI
import AppKit
import Darwin
@main struct Harness {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let session = JSONTreeWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: "tree-runtime-harness")!))
        let view = NSHostingView(rootView: JSONTreeViewerView(workspace: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = view; window.makeKeyAndOrderFront(nil)
        var heartbeatMax = Duration.zero
        let heartbeat = Task { @MainActor in
            var previous = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                heartbeatMax = max(heartbeatMax, previous.duration(to: now)); previous = now
            }
        }
        let started = ContinuousClock.now
        session.input = "[" + Array(repeating: "0", count: 131_070).joined(separator: ",") + ",9]"
        await session.build().value
        print("MAC_TREE parse_publish \(started.duration(to: .now)) rows=\(session.visible.count)")
        session.inputCollapsed = true
        try? await Task.sleep(for: .seconds(2))
        func count(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + count($1) } }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("MAC_TREE initial_views=\(count(view)) peak_bytes=\(usage.ru_maxrss)")
        func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
            (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, type) }
        }
        let scrollStart = ContinuousClock.now
        if let table = descendants(view, NSTableView.self).first {
            for row in stride(from: 0, to: 131_072, by: 5000) {
                table.scrollRowToVisible(row)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        print("MAC_TREE scroll_27_jumps \(scrollStart.duration(to: .now)) views=\(count(view)) heartbeat_max=\(heartbeatMax)")
        let search = ContinuousClock.now
        session.query = "9"
        await session.scheduleSearch()?.value
        try? await Task.sleep(for: .milliseconds(500))
        print("MAC_TREE search_scroll \(search.duration(to: .now)) selection=\(session.selection ?? -1) views=\(count(view))")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toolbox-tree-mac-stress.png"))
        }
        let fold = ContinuousClock.now
        await session.collapseAll()?.value; await session.expandAll()?.value
        print("MAC_TREE collapse_expand \(fold.duration(to: .now)) rows=\(session.visible.count)")
        try? await Task.sleep(for: .milliseconds(500))
        getrusage(RUSAGE_SELF, &usage)
        print("MAC_TREE final_views=\(count(view)) peak_bytes=\(usage.ru_maxrss)")
        session.input = #"{"user":{"name":"Alice","roles":["admin","editor"]},"enabled":true,"balance":12345678901234567890,"items":[]}"#
        await session.build().value; session.query = "admin"; await session.scheduleSearch()?.value
        // Record the actual presentation of an unchanged sibling while its
        // preceding subtree collapses. Several intermediate positions mean the
        // native row transition moves continuously instead of jumping.
        try? await Task.sleep(for: .milliseconds(300))
        if let table = descendants(view, NSTableView.self).first,
           let ordinal = session.rowNumbers[6],
           let row = table.rowView(atRow: ordinal - 1, makeIfNecessary: false) {
            row.wantsLayer = true
            var positions = [row.frame.minY]
            await session.toggle(1)?.value
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(16))
                positions.append(row.layer?.presentation()?.frame.minY ?? row.frame.minY)
            }
            print("MAC_TREE animated_sibling_y=\(positions)")
            await session.toggle(1)?.value
        }
        session.inputCollapsed = false
        try? await Task.sleep(for: .milliseconds(300))
        let editor = descendants(view, JSONNativeTextView.self).first
        editor?.setSelectedRange(NSRange(location: 3, length: 0))
        window.setContentSize(NSSize(width: 620, height: 700))
        session.inputCollapsed = true
        try? await Task.sleep(for: .milliseconds(100))
        session.inputCollapsed = false
        try? await Task.sleep(for: .milliseconds(100))
        print("MAC_TREE editor_identity=\(editor === descendants(view, JSONNativeTextView.self).first) caret=\(editor?.selectedRange().location ?? -1) source_preserved=\(session.input.contains("12345678901234567890"))")
        window.setContentSize(NSSize(width: 1050, height: 780))
        try? await Task.sleep(for: .milliseconds(600))
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .milliseconds(250))
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toolbox-tree-mac-\(theme).png"))
            }
        }
        // Measure the real native viewport during Ready -> Invalid expansion.
        for reduced in [ProcessInfo.processInfo.arguments.contains("--reduce-motion")] {
            session.query = ""; session.input = "[1,]"
            try? await Task.sleep(for: .milliseconds(300))
            let editor = descendants(view, JSONNativeTextView.self).first
            let scroll = editor?.enclosingScrollView
            var heights = [scroll?.frame.height ?? 0]
            await session.build().value
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(16))
                heights.append(scroll?.frame.height ?? 0)
            }
            print("MAC_TREE diagnostic_heights reduceMotion=\(reduced) \(heights) editor_identity=\(editor === descendants(view, JSONNativeTextView.self).first)")
        }
        heartbeat.cancel()
        print("MAC_TREE heartbeat_max=\(heartbeatMax)")
        app.terminate(nil)
    }
}
