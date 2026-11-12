#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import JSONEditor
@testable import JSONCore

@MainActor @Suite(.serialized)
struct JSONNativeEditorTests {
    private final class State {
        var text = ""
        var pastes = 0
    }
    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }

    @Test func lineNumberVisibilityPreservesNativeEditing() throws {
        _ = NSApplication.shared
        let state = State(); state.text = "first line\nsecond line"
        func root(_ numbers: Bool) -> JSONTextEditor {
            JSONTextEditor(text:Binding(get:{state.text},set:{state.text=$0}),privateUndo:true,showsLineNumbers:numbers)
        }
        let host=NSHostingView(rootView:root(false))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:240),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.contentView=host
        defer { window.contentView=nil }
        host.layoutSubtreeIfNeeded()
        let editor=try #require(descendant(JSONNativeTextView.self,in:host))
        #expect(!editor.adornments.showsGutter && editor.enclosingScrollView?.rulersVisible != true)
        editor.setSelectedRange(NSRange(location:5,length:0))
        editor.insertText("!",replacementRange:editor.selectedRange())
        let selection=editor.selectedRange()
        for numbers in [true,false,true,false] {
            host.rootView=root(numbers); host.layoutSubtreeIfNeeded()
            #expect(descendant(JSONNativeTextView.self,in:host) === editor)
            #expect(editor.adornments.showsGutter == numbers)
            #expect(editor.enclosingScrollView?.rulersVisible == numbers)
            #expect(editor.selectedRange() == selection && state.text == "first! line\nsecond line")
        }
        editor.undoManager?.undo()
        #expect(state.text == "first line\nsecond line")
        editor.undoManager?.redo()
        #expect(state.text == "first! line\nsecond line")
    }

    @Test(arguments: [true,false])
    func baseTextColorsFollowAppearanceWithoutReplacingEditor(plain: Bool) throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView:JSONTextEditor(text:.constant("visible text"),options:.init(syntax:plain ? .plainText : .json,syntaxHighlighting:false,rainbowBrackets:false,matchingBrackets:false,wordWrap:true)))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:240),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(NSTextView.self,in:host))
        let identity = ObjectIdentifier(editor), original = editor.string
        for (appearance,dark) in [(NSAppearance.Name.darkAqua,true),(.aqua,false)] {
            window.appearance = NSAppearance(named:appearance)
            host.layoutSubtreeIfNeeded()
            let foreground = try #require(editor.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor ?? editor.textColor)
            var text = 0.0, background = 0.0
            editor.effectiveAppearance.performAsCurrentDrawingAppearance {
                text = Double(foreground.usingColorSpace(.sRGB)?.redComponent ?? -1)
                background = Double(editor.backgroundColor.usingColorSpace(.sRGB)?.redComponent ?? -1)
            }
            #expect(dark ? text > 0.7 && background < 0.3 : text < 0.3 && background > 0.7)
            #expect(ObjectIdentifier(editor) == identity && editor.string == original)
        }
    }

    @Test(arguments: [true, false])
    func exactUnicodeSnapshotsReachNativeEditor(editable: Bool) throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: JSONTextEditor(text: .constant(""), editable: editable))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        for (first, second) in [("\u{00E9}", "e\u{0301}"), ("\u{00C5}", "\u{212B}"),
                                ("\u{AC00}", "\u{1100}\u{1161}")] {
            let source = "\"👩🏽‍💻\(first)\"", edited = "\"👩🏽‍💻\(second)\""
            #expect(source == edited && !source.utf16.elementsEqual(edited.utf16))
            for snapshot in [source, edited, source] {
                host.rootView = JSONTextEditor(text: .constant(snapshot), editable: editable)
                host.layoutSubtreeIfNeeded()
                #expect(descendant(JSONNativeTextView.self, in: host) === editor)
                #expect(editor.string.utf16.elementsEqual(snapshot.utf16))
            }
        }
        #expect(editor.undoManager?.canUndo != true) // Presentation sync isn't a user edit.
    }

    @Test(arguments: [true, false])
    func animatedJumpPreservesEditorAndDoesNotStealFocus(wrap: Bool) async throws {
        _ = NSApplication.shared
        let source = wrap ? "[\n" + Array(repeating: "123,", count: 1000).joined(separator: "\n") + "0\n]"
                          : "[" + Array(repeating: "123,", count: 1000).joined() + "0]"
        let target = source.utf16.count - 2
        func root(_ offset: Int?, request: Int, animated: Bool) -> JSONTextEditor {
            JSONTextEditor(text: .constant(source), jumpTarget: offset.map { NSRange(location: $0, length: 0) },
                jumpRequest: request, animateJumps: animated, focusOnJump: false, options: JSONEditorOptions(wordWrap: wrap))
        }
        let host = NSHostingView(rootView: root(nil, request: 0, animated: false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        window.makeFirstResponder(nil)
        host.rootView = root(target, request: 1, animated: true)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        #expect(editor === descendant(JSONNativeTextView.self, in: host))
        #expect(editor.string.utf16.elementsEqual(source.utf16))
        #expect(editor.selectedRange() == NSRange(location: target, length: 0))
        let caret = try #require(editor.adornments.caretRect(at: target))
        #expect(editor.visibleRect.insetBy(dx: -2, dy: -2).intersects(caret))
        #expect(window.firstResponder !== editor && editor.undoManager?.canUndo != true)
        host.rootView = root(0, request: 2, animated: false)
        host.layoutSubtreeIfNeeded()
        let start = try #require(editor.adornments.caretRect(at: 0))
        #expect(editor.visibleRect.insetBy(dx: -2, dy: -2).intersects(start))
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test(arguments: [true, false])
    func jumpHighlightStartsAfterScrollPulsesAndExpires(wrap: Bool) async throws {
        _ = NSApplication.shared
        let source = wrap ? "[\n" + Array(repeating: "123,", count: 400).joined(separator: "\n") + "42\n]"
                          : "[" + Array(repeating: "123,", count: 400).joined() + "42]"
        let range = (source as NSString).range(of: "42")
        let host = NSHostingView(rootView: JSONTextEditor(text: .constant(source), options: JSONEditorOptions(wordWrap: wrap)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        defer { JSONEditorNavigation.cancel(editor); window.contentView = nil }
        window.makeFirstResponder(nil)
        JSONEditorNavigation.jump(editor, to: range.location, animated: true, focus: false, highlight: range)
        try await Task.sleep(for: .milliseconds(80))
        #expect(editor.adornments.navigationHighlight == nil, "No attention marker before scroll completes")
        try await Task.sleep(for: .milliseconds(280))
        #expect(editor.adornments.navigationHighlight == range)
        #expect(!editor.adornments.navigationHighlightRects().isEmpty)
        #expect(editor.selectedRange() == NSRange(location: range.location, length: 0))
        let selection = editor.selectedRange()
        var opacity: [CGFloat] = []
        for _ in 0..<13 {
            opacity.append(editor.adornments.navigationHighlightOpacity)
            host.displayIfNeeded()
            #expect(editor.selectedRange() == selection && editor.string.utf16.elementsEqual(source.utf16))
            #expect(window.firstResponder !== editor && editor.undoManager?.canUndo != true)
            try await Task.sleep(for: .milliseconds(150))
        }
        let high = opacity.map { $0 > 0.15 }
        let peaks = high.enumerated().filter { $0.element && ($0.offset == 0 || !high[$0.offset - 1]) }.count
        #expect(peaks == 2, "Two gentle pulses: \(opacity)")
        #expect(editor.adornments.navigationHighlight == nil && editor.adornments.navigationHighlightOpacity == 0)
    }

    @Test func reducedJumpHighlightIsStaticAndCancelsOnEditOrReplacement() async throws {
        _ = NSApplication.shared
        let state = State(); state.text = #"{"value":"e\u0301😀","n":42}"#
        let commands = JSONEditorCommands()
        func root() -> JSONTextEditor {
            JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }), commands: commands)
        }
        let host = NSHostingView(rootView: root())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        defer { JSONEditorNavigation.cancel(editor); window.contentView = nil }
        let source = state.text
        let range = (source as NSString).range(of: "42")
        editor.setSelectedRange(NSRange(location: 2, length: 3))
        let selection = editor.selectedRange()
        editor.adornments.showNavigationHighlight(range, animated: false)
        #expect(editor.selectedRange() == selection)
        try await Task.sleep(for: .milliseconds(1_750))
        #expect(editor.adornments.navigationHighlight == range && editor.adornments.navigationHighlightOpacity == 0.24)
        JSONEditorNavigation.jump(editor, to: 0, animated: false, focus: false, highlight: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(350))
        #expect(editor.adornments.navigationHighlight == NSRange(location: 0, length: 1), "Old expiry must not erase a newer highlight")
        #expect(editor.adornments.navigationHighlightOpacity == 0.24 && editor.string == source)
        commands.cancelNavigation?()
        #expect(editor.adornments.navigationHighlight == nil)
        editor.adornments.showNavigationHighlight(range, animated: true)
        editor.breakUndoCoalescing()
        editor.insertText(" ", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        editor.breakUndoCoalescing()
        #expect(editor.adornments.navigationHighlight == nil)
        editor.undoManager?.undo()
        #expect(editor.string == source && state.text == source)
        editor.adornments.showNavigationHighlight(range, animated: false)
        state.text = "[]"; host.rootView = root(); host.layoutSubtreeIfNeeded()
        #expect(editor.adornments.navigationHighlight == nil && editor.string == "[]")
        editor.adornments.showNavigationHighlight(NSRange(location: 99, length: 1), animated: true)
        #expect(editor.adornments.navigationHighlight == nil)
        editor.adornments.showNavigationHighlight(NSRange(location: 2, length: 0), animated: false)
        #expect(editor.adornments.navigationHighlight == NSRange(location: 2, length: 0))
        #expect(!editor.adornments.navigationHighlightRects().isEmpty)
        try await Task.sleep(for: .milliseconds(2_100))
        #expect(editor.adornments.navigationHighlight == nil)
    }

    @Test func emptyPlaceholderTracksNativeTextOriginAndFocus() throws {
        _ = NSApplication.shared
        let state = State()
        func root(_ hint: String) -> JSONTextEditor {
            JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }), placeholder: hint)
        }
        let host = NSHostingView(rootView: root("Paste or type JSON, then Build Tree."))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        window.makeFirstResponder(nil)
        editor.placeholder.update()
        let hint = try #require(editor.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(!hint.isHidden)
        let expectedX = editor.textContainerOrigin.x + (editor.textContainer?.lineFragmentPadding ?? 0)
        #expect(abs(hint.frame.minX - expectedX) < 1)
        #expect(hint.hitTest(NSPoint(x: 2, y: 2)) == nil)
        window.makeFirstResponder(editor)
        #expect(hint.isHidden)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        let caret = try #require(editor.adornments.caretRect(at: 0))
        #expect(abs(caret.minX - expectedX) < 1)
        // Changing the hint or panel width doesn't move the native insertion column.
        host.rootView = root("Paste or type JSON. Processing stays on this device.")
        host.setFrameSize(NSSize(width: 320, height: 300))
        host.layoutSubtreeIfNeeded()
        #expect(descendant(JSONNativeTextView.self, in: host) === editor)
        #expect(hint.isHidden)
        window.makeFirstResponder(nil)
        #expect(!hint.isHidden)
        #expect(hint.stringValue == "Paste or type JSON. Processing stays on this device.")
        window.makeFirstResponder(editor)
        editor.insertText("[]", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        window.makeFirstResponder(nil)
        #expect(hint.isHidden)
        window.makeFirstResponder(editor)
        #expect(editor.selectedRange() == NSRange(location: 1, length: 0))
        #expect(state.text == "[]")
    }

    @Test func emptyInputDropsInheritedParagraphIndentWithoutEditingText() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: JSONTextEditor(text: .constant(""), placeholder: "Enter JSON"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        let inherited = NSMutableParagraphStyle()
        inherited.alignment = .center
        inherited.firstLineHeadIndent = 100
        inherited.headIndent = 120
        editor.typingAttributes[.paragraphStyle] = inherited
        editor.placeholder.update()
        let plain = try #require(editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(plain.alignment == .left && plain.firstLineHeadIndent == 0 && plain.headIndent == 0)
        #expect(editor.string.isEmpty && editor.selectedRange().location == 0)
        #expect(editor.undoManager?.canUndo != true)
    }

    @Test func typingNeverPublishesBlankGutterOrClearsExistingColors() async throws {
        _ = NSApplication.shared
        let editor = JSONNativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        let scroll = NSScrollView(frame: editor.frame)
        scroll.documentView = editor
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil }
        editor.string = #"{"key":123}"#
        let highlighter = JSONEditorHighlighter()
        highlighter.attach(editor)
        var coordinateUpdates: [JSONSourceCoordinates?] = []
        highlighter.didUpdateCoordinates = { coordinateUpdates.append($0) }
        highlighter.update(source: editor.string, options: JSONEditorOptions(), diagnostic: nil, limit: 262_144, needsCoordinates: true)
        func color() -> NSColor? { editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor }
        for _ in 0..<100 {
            if color() != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(color() != nil)
        // All edits happen before the debounced lexer can run again.
        for _ in 0..<12 {
            editor.insertText("\n", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            let selection = editor.selectedRange()
            highlighter.update(source: editor.string, options: JSONEditorOptions(), diagnostic: nil, limit: 262_144, needsCoordinates: true)
            #expect(color() != nil) // No plain-text frame between typed characters.
            #expect((coordinateUpdates.last ?? nil)?.lineStarts.count == editor.string.filter { $0 == "\n" }.count + 1)
            #expect(editor.selectedRange() == selection)
        }
        #expect(coordinateUpdates.allSatisfy { $0 != nil })
        try await Task.sleep(for: .milliseconds(100))
        #expect(color() != nil)
        highlighter.stop()
    }

    @Test func nativePasteClearUndoAndOrdinaryTyping() throws {
        _ = NSApplication.shared
        let state = State()
        let commands = JSONEditorCommands()
        func panels(horizontal: Bool) -> some View {
            JSONPanelLayout(horizontal: horizontal, fraction: 0.5, collapsed: false) {
                JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }),
                               onPaste: { state.pastes += 1 }, commands: commands)
                Color.clear
                JSONTextEditor(text: .constant("readonly output"), editable: false)
            }
        }
        let host = NSHostingView(rootView: panels(horizontal: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(NSTextView.self, in: host))
        window.makeFirstResponder(editor)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        func event(_ action: () -> Void) {
            undo.beginUndoGrouping()
            action()
            undo.endUndoGrouping()
        }
        let clipboard = NSPasteboard.general
        let saved: [NSPasteboardItem] = clipboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        defer {
            clipboard.clearContents()
            clipboard.writeObjects(saved)
            window.contentView = nil
        }
        clipboard.clearContents()
        clipboard.setString(#"{"n":123}"#, forType: .string)
        event { editor.paste(nil) }
        #expect(state.text == #"{"n":123}"#)
        #expect(state.pastes == 1)
        event { commands.clear?() }
        #expect(state.text.isEmpty)
        #expect(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        #expect(state.text == #"{"n":123}"#)
        editor.undoManager?.redo()
        #expect(state.text.isEmpty)
        event { editor.insertText("[]", replacementRange: NSRange(location: 0, length: 0)) }
        #expect(state.text == "[]")
        #expect(state.pastes == 1) // ordinary edits and Undo/Redo are not paste events
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        event { editor.pasteAsPlainText(nil) }
        #expect(state.text == #"{"n":123}"#)
        #expect(state.pastes == 2)
        // A root-size change must keep the editor instance and its text/undo stack.
        host.rootView = panels(horizontal: false)
        host.appearance = NSAppearance(named: .darkAqua)
        host.setFrameSize(NSSize(width: 320, height: 500))
        host.layoutSubtreeIfNeeded()
        #expect(descendant(NSTextView.self, in: host) === editor)
        #expect(state.text == #"{"n":123}"#)
        #expect(editor.string == state.text)
        #expect(state.pastes == 2)
        // Programmatic binding synchronization is not an explicit Paste.
        state.text = "{}"
        host.rootView = panels(horizontal: false)
        host.layoutSubtreeIfNeeded()
        #expect(editor.string == "{}")
        #expect(state.pastes == 2)
        let multiline = "{\n    \"n\":\"" + String(repeating: "long value 😀 ", count: 30) + "\"\n}"
        clipboard.clearContents()
        clipboard.setString(multiline, forType: .string)
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        event { editor.paste(nil) }
        #expect(state.text == multiline && state.pastes == 3)
        let paragraph = editor.textStorage?.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
        #expect((paragraph?.headIndent ?? 0) > 0)
        undo.undo()
        #expect(editor.string == "{}" && state.pastes == 3)
        undo.redo()
        #expect(editor.string == multiline && state.pastes == 3)
    }

    @Test func highlightingWrapAndUndoDoNotEditDocument() async throws {
        _ = NSApplication.shared
        let state = State()
        let source = #"{"😀":"["# + String(repeating: "text é ", count: 500) + #"]","n":9007199254740993 "bad":true}"#
        state.text = source // invalid JSON: missing comma, still independently highlighted
        var bindingWrites = 0
        func root(_ options: JSONEditorOptions, editable: Bool = true) -> JSONTextEditor {
            JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0; bindingWrites += 1 }),
                           editable: editable, options: options)
        }
        let host = NSHostingView(rootView: root(JSONEditorOptions(syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(NSTextView.self, in: host))
        let scroll = try #require(editor.enclosingScrollView)
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        func foreground(_ position: Int) -> NSColor? {
            manager.temporaryAttribute(.foregroundColor, atCharacterIndex: position, effectiveRange: nil) as? NSColor
        }
        let native = try #require(editor as? JSONNativeTextView)
        for _ in 0..<100 {
            if native.adornments.coordinates != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(native.adornments.coordinates != nil)
        #expect(foreground(1) == nil)
        host.rootView = root(JSONEditorOptions()) // enable colors after gutter-only pass, with no source edit
        host.layoutSubtreeIfNeeded()
        for _ in 0..<100 {
            if foreground(1) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let keyColor = try #require(foreground(1))
        let stringColor = try #require(foreground(6))
        #expect(keyColor != stringColor)
        #expect(editor.string == source)
        #expect(bindingWrites == 0)
        manager.ensureLayout(for: container)
        let wrappedHeight = manager.usedRect(for: container).height
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        let caret = editor.selectedRange()
        #expect(manager.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) != nil)
        #expect(manager.temporaryAttribute(.underlineStyle, atCharacterIndex: source.utf16.count - 1, effectiveRange: nil) != nil)
        var settings = JSONEditorOptions()
        settings.wordWrap = false
        host.rootView = root(settings)
        host.layoutSubtreeIfNeeded()
        manager.ensureLayout(for: container)
        #expect(descendant(NSTextView.self, in: host) === editor)
        #expect(scroll.hasHorizontalScroller)
        #expect(manager.usedRect(for: container).width > scroll.contentSize.width)
        #expect(manager.usedRect(for: container).height < wrappedHeight)
        #expect(editor.selectedRange() == caret)
        #expect(editor.string == source)
        #expect(bindingWrites == 0)
        settings.wordWrap = true
        host.rootView = root(settings)
        host.layoutSubtreeIfNeeded()
        #expect(!scroll.hasHorizontalScroller)
        #expect(editor.selectedRange() == caret)
        #expect(editor.string == source)
        settings.syntaxHighlighting = false
        settings.rainbowBrackets = false
        settings.matchingBrackets = false
        host.rootView = root(settings)
        host.layoutSubtreeIfNeeded()
        #expect(foreground(1) == nil)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.insertText(" ", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        undo.endUndoGrouping()
        settings.syntaxHighlighting = true
        settings.rainbowBrackets = true
        host.rootView = root(settings)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<100 {
            if foreground(1) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(editor.string == source + " ")
        undo.undo()
        #expect(editor.string == source)
        undo.redo()
        #expect(editor.string == source + " ")
        // Read-only output receives exactly the same render-only coloring.
        host.rootView = root(settings, editable: false)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<100 {
            if foreground(1) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!editor.isEditable)
        #expect(editor.string == source + " ")
        #expect(foreground(1) != nil)
    }

    @Test(arguments: [2, 4], [false, true])
    func outputContinuationUsesLogicalLineIndent(_ indentation: Int, unbroken: Bool) throws {
        _ = NSApplication.shared
        let leading = String(repeating: " ", count: indentation * 2)
        let source = "{\n" + leading + #""description": ""#
            + String(repeating: unbroken ? "https://example.com/abcdefgh😀é" : "long value 😀é ", count: 60) + "\"\n}"
        var options = JSONEditorOptions()
        func root() -> JSONTextEditor { JSONTextEditor(text: .constant(source), editable: false, options: options) }
        let host = NSHostingView(rootView: root())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        manager.ensureLayout(for: container)
        let key = (source as NSString).range(of: "\"description\"").location
        let glyph = manager.glyphIndexForCharacter(at: key)
        var firstLine = NSRange()
        let first = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &firstLine)
        let nextGlyph = NSMaxRange(firstLine)
        #expect(nextGlyph < manager.numberOfGlyphs)
        let continuation = manager.lineFragmentUsedRect(forGlyphAt: nextGlyph, effectiveRange: nil)
        let keyRect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        #expect(continuation.minY > first.minY)
        #expect(continuation.minX > keyRect.minX)
        #expect(continuation.minX - keyRect.minX < 30)
        #expect(editor.string == source)
        #expect(!editor.isEditable)
        let selected = NSRange(location: key, length: 13)
        editor.setSelectedRange(selected)
        options.wordWrap = false
        host.rootView = root()
        host.layoutSubtreeIfNeeded()
        manager.ensureLayout(for: container)
        #expect(editor.selectedRange() == selected)
        #expect(editor.string == source)
        #expect(manager.usedRect(for: container).width > 360)
        options.wordWrap = true
        host.rootView = root()
        host.setFrameSize(NSSize(width: 160, height: 400))
        host.layoutSubtreeIfNeeded()
        manager.ensureLayout(for: container)
        let style = editor.textStorage?.attribute(.paragraphStyle, at: key, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.headIndent ?? .infinity) < 80) // narrow panes retain room for actual text
        #expect(editor.string == source)
        #expect(editor.selectedRange() == selected)
    }

    @Test(arguments: ["\n", "\r\n", "\r"], ["    ", "\t"])
    func multilineInputWrapPreservesEditing(_ newline: String, leading: String) throws {
        _ = NSApplication.shared
        let state = State()
        let source = "{" + newline + leading + #""description": ""#
            + String(repeating: "long value 😀é ", count: 60) + "\"" + newline + "}"
        state.text = source
        var writes = 0
        func root() -> JSONTextEditor {
            JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0; writes += 1 }))
        }
        let host = NSHostingView(rootView: root())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        manager.ensureLayout(for: container)
        let key = (source as NSString).range(of: "\"description\"").location
        let glyph = manager.glyphIndexForCharacter(at: key)
        var firstLine = NSRange()
        let first = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &firstLine)
        let continuation = manager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(firstLine), effectiveRange: nil)
        let keyRect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        #expect(continuation.minY > first.minY)
        #expect(continuation.minX > keyRect.minX)
        #expect(continuation.minX - keyRect.minX < 30)
        #expect(editor.string == source && state.text == source)
        #expect(writes == 0) // layout must never publish a text edit

        window.makeFirstResponder(editor)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        let cursor = (source as NSString).range(of: "long").location
        editor.setSelectedRange(NSRange(location: cursor, length: 0))
        undo.beginUndoGrouping()
        editor.insertText("X", replacementRange: NSRange(location: cursor, length: 0))
        undo.endUndoGrouping()
        let edited = editor.string
        #expect(edited != source && state.text == edited)
        #expect(editor.selectedRange() == NSRange(location: cursor + 1, length: 0))
        undo.undo()
        #expect(editor.string == source && state.text == source)
        undo.redo()
        #expect(editor.string == edited && state.text == edited)
        undo.undo()
        #expect(editor.string == source)

        undo.disableUndoRegistration()
        host.setFrameSize(NSSize(width: 280, height: 400))
        host.layoutSubtreeIfNeeded()
        #expect(!undo.isUndoRegistrationEnabled)
        undo.enableUndoRegistration()

        // A literal JSON escape is not a physical line break. No inherited hanging
        // indent may survive after the multiline document becomes a single line.
        let single = #"{"a":"\n"}"#
        undo.beginUndoGrouping()
        editor.insertText(single, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        undo.endUndoGrouping()
        editor.wrapIndentation.update()
        #expect(editor.string == single && state.text == single)
        let style = editor.textStorage?.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as? NSParagraphStyle
        #expect(style == nil || style?.headIndent == 0)
        let typing = editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(typing == nil || typing?.headIndent == 0)
        undo.undo()
        editor.wrapIndentation.update()
        #expect(editor.string == source && state.text == source)
        let restored = editor.textStorage?.attribute(.paragraphStyle, at: key, effectiveRange: nil) as? NSParagraphStyle
        #expect((restored?.headIndent ?? 0) > 0)
    }

    @Test func markedTextIsNotOverwrittenBySwiftUIUpdate() async throws {
        _ = NSApplication.shared
        let state = State()
        state.text = "{\n  \"a\":\"" + String(repeating: "long value ", count: 20) + "\"\n}"
        func root() -> JSONTextEditor {
            JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }))
        }
        let host = NSHostingView(rootView: root())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(NSTextView.self, in: host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let text = editor.string
        let selection = editor.selectedRange()
        let marked = editor.markedRange()
        #expect(editor.hasMarkedText())
        // The offscreen host has no real input method session. Check synchronization while
        // composition is active, then commit through the native text-input protocol.
        host.rootView = root()
        host.layoutSubtreeIfNeeded()
        #expect(editor.string == text)
        #expect(editor.selectedRange() == selection)
        #expect(editor.markedRange() == marked)
        editor.insertText("日本", replacementRange: editor.markedRange())
        #expect(!editor.hasMarkedText())
        #expect(state.text == text)
        try await Task.sleep(for: .milliseconds(120))
        #expect(editor.string == text)
    }

    @Test func relatedNavigationUsesSolidMarkersWithoutChangingSource() async throws {
        _ = NSApplication.shared
        let state = State()
        var request = 0
        let host = NSHostingView(rootView: JSONTextEditor(text: .constant("")))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        let sources = ["{\"a\":[1,2", "{\"a\":\"unterminated", "{\"a\":1,}",
                       "{\r\n  \"👩🏽‍💻é\": [1,2\r\n}"]
        for source in sources {
            state.text = source
            let diagnostic = try #require(JSONProcessor.process(source, operation: .validate).diagnostics.first)
            #expect(!diagnostic.related.isEmpty)
            for related in diagnostic.related {
                request += 1
                host.rootView = JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }),
                                              diagnostic: diagnostic, jumpTarget: related.range, jumpRequest: request)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                let editor = try #require(descendant(JSONNativeTextView.self, in: host))
                #expect(editor.selectedRange() == NSRange(location: related.range.location, length: 0))
                #expect(editor.string.utf16.elementsEqual(source.utf16))
                let manager = try #require(editor.layoutManager)
                for anchor in diagnostic.related where anchor.range.length > 0 && anchor.range.length <= 32 {
                    let style = manager.temporaryAttribute(.underlineStyle, atCharacterIndex: anchor.range.location, effectiveRange: nil) as? Int
                    #expect(style == NSUnderlineStyle.single.rawValue)
                }
                // Exercise native marker drawing as well as navigation/attributes.
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                }
                #expect(editor.undoManager?.canUndo != true)
            }
        }
    }

    @Test func diagnosticMarkersGutterNavigationAndStaleRemoval() async throws {
        _ = NSApplication.shared
        let state = State()
        state.text = "[" + Array(repeating: "123", count: 1800).joined(separator: ",")
        let eof = try #require(JSONProcessor.process(state.text, operation: .validate).diagnostics.last)
        func root(_ diagnostic: JSONDiagnostic?, wrap: Bool, jump: NSRange? = nil, request: Int = 0) -> JSONTextEditor {
            JSONTextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }),
                           diagnostic: diagnostic, jumpTarget: jump, jumpRequest: request,
                           options: JSONEditorOptions(wordWrap: wrap))
        }
        let host = NSHostingView(rootView: root(eof, wrap: false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendant(JSONNativeTextView.self, in: host))
        for _ in 0..<100 {
            if editor.adornments.coordinates != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(editor.adornments.coordinates?.lineStarts.count == 1)
        #expect(editor.enclosingScrollView?.rulersVisible == true)
        let count = state.text.utf16.count
        let manager = try #require(editor.layoutManager)
        #expect(manager.temporaryAttribute(.underlineColor, atCharacterIndex: count - 1, effectiveRange: nil) == nil)
        host.rootView = root(eof, wrap: false, jump: eof.range, request: 1)
        host.layoutSubtreeIfNeeded()
        #expect(editor.selectedRange() == NSRange(location: count, length: 0))
        #expect(editor.visibleRect.minX > 0)
        let rect = try #require(editor.adornments.caretRect(at: count))
        #expect(rect.insetBy(dx: -2, dy: -2).intersects(editor.visibleRect))
        host.rootView = root(eof, wrap: true, jump: eof.range, request: 2)
        host.layoutSubtreeIfNeeded()
        #expect(editor.visibleRect.minY > 0)
        #expect(editor.selectedRange().length == 0)
        #expect(editor.adornments.coordinates?.lineStarts.count == 1) // soft wraps are not logical lines
        state.text = #"{"a":1 "b":2}"#
        let error = try #require(JSONProcessor.process(state.text, operation: .validate).diagnostics.last)
        host.rootView = root(error, wrap: true, jump: error.range, request: 3)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<100 {
            if manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 7, effectiveRange: nil) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(manager.temporaryAttribute(.underlineColor, atCharacterIndex: 7, effectiveRange: nil) != nil)
        #expect(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 7, effectiveRange: nil) != nil)
        #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: 7, effectiveRange: nil) == nil)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.insertText(" ", replacementRange: NSRange(location: state.text.utf16.count, length: 0))
        undo.endUndoGrouping()
        #expect(editor.adornments.diagnostic == nil) // no old diagnostic between native edit and SwiftUI refresh
        undo.undo()
        #expect(state.text == #"{"a":1 "b":2}"#)
    }

}
#endif

#if os(macOS)
@MainActor @Suite(.serialized)
struct TextMatchAdornmentTests {
  private final class Storage {var text="a😀e\u{301}\nline"}
  private func find(_ view:NSView)->JSONNativeTextView?{if let v=view as? JSONNativeTextView{return v};for child in view.subviews{if let v=find(child){return v}};return nil}
  @Test func overlaysPreserveDocumentSelectionUndoAndIdentity() throws {
    _=NSApplication.shared
    let state=Storage(),commands=JSONEditorCommands()
    var payload:TextEditorHighlights?=nil
    func root()->JSONTextEditor{JSONTextEditor(text:Binding(get:{state.text},set:{state.text=$0}),commands:commands,options:.init(syntax:.plainText,syntaxHighlighting:false),privateUndo:true,matchHighlights:payload)}
    let host=NSHostingView(rootView:root())
    let window=NSWindow(contentRect:.init(x:0,y:0,width:500,height:250),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;defer{window.contentView=nil}
    host.layoutSubtreeIfNeeded();let editor=try #require(find(host));editor.setSelectedRange(.init(location:3,length:0))
    for mode in [true,false,true]{
      payload=mode ? .init(id:UUID(),source:state.text,ranges:[.init(location:1,length:2),.init(location:state.text.utf16.count,length:0)],active:.init(location:1,length:2)):nil
      host.rootView=root();host.layoutSubtreeIfNeeded();host.displayIfNeeded()
      #expect(find(host) === editor);#expect(editor.string.utf16.elementsEqual(state.text.utf16));#expect(editor.selectedRange()==NSRange(location:3,length:0))
    }
    commands.replace?(.init(location:0,length:state.text.utf16.count),"replacement")
    #expect(state.text=="replacement")
    editor.undoManager?.undo();#expect(state.text=="a😀e\u{301}\nline")
    editor.undoManager?.redo();#expect(state.text=="replacement")
  }
}
#endif
