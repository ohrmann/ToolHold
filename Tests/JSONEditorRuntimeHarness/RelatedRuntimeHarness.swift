import AppKit
import SwiftUI
import QuartzCore

/// Standalone AppKit rendering probe; run with MTL_DEBUG_LAYER=1. No XCTest UI runner.
@main struct RelatedRuntimeHarness {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "related-runtime-harness")!
        let session = JSONWorkspaceSession(repository: .init(defaults: defaults))
        let host = NSHostingView(rootView: JSONFormatterView(workspace: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; defaults.removePersistentDomain(forName: "related-runtime-harness") }
        func editors(_ view: NSView) -> [JSONNativeTextView] {
            (view as? JSONNativeTextView).map { [$0] } ?? view.subviews.flatMap { editors($0) }
        }
        let sources = [#"{"a":[1,2"#, #"{"a":"unterminated"#, #"{"a":1,}"#, "[1 2]",
                       "{\r\n  \"emoji\": \"👩🏽‍💻\",\r\n  \"items\": [1,2\r\n}",
                       "[" + Array(repeating: "123", count: 1800).joined(separator: ",")]
        var jumps = 0
        for wrap in [true, false] {
            session.preferences.wordWrap = wrap
            for source in sources {
                session.input = source
                await session.run(.validate).value
                try? await Task.sleep(for: .milliseconds(250))
                guard let diagnostic = session.result?.diagnostics.first else { fatalError("No diagnostic") }
                for related in diagnostic.related {
                    guard let editor = editors(host).first(where: { $0.isEditable }) else { fatalError("No input") }
                    // First visit detection/EOF, then the related anchor, exercising both scroll directions.
                    for range in [diagnostic.range, related.range] {
                        editor.setSelectedRange(NSRange(location: range.location, length: 0))
                        editor.scrollRangeToVisible(editor.selectedRange())
                        window.makeFirstResponder(editor)
                        editor.needsDisplay = true
                        host.displayIfNeeded()
                        CATransaction.flush()
                        try? await Task.sleep(for: .milliseconds(100))
                        precondition(editor.string.utf16.elementsEqual(source.utf16))
                        precondition(editor.selectedRange() == NSRange(location: range.location, length: 0))
                        jumps += 1
                    }
                }
            }
        }
        print("RELATED_RUNTIME passed: 6 fixtures, wrap ON/OFF, \(jumps) detection/related jumps; source/caret intact")
    }
}
