import SwiftUI

@MainActor final class DigestEditorCommands { var clear: (() -> Void)?; var resignFocus: (() -> Void)?; var showRange: ((NSRange) -> Bool)? }

/// Small plain native editor: exact Paste (including invalid whitespace), native Undo,
/// and a private undo manager so Clear cannot resurrect working input.
private struct DigestEditorSource: Equatable {
    let text: String
    static func ==(l: Self, r: Self) -> Bool { l.text.utf16.elementsEqual(r.text.utf16) }
}
struct DigestNativeEditor {
    @Binding var text: String
    let commands: DigestEditorCommands
    var visible: Bool
    var fieldLabel: String
    var fieldIdentifier: String
    private let source: DigestEditorSource
    init(text: Binding<String>, commands: DigestEditorCommands, visible: Bool = true, fieldLabel: String = "Input", fieldIdentifier: String = "digest-input") {
        _text = text; self.commands = commands; self.visible = visible; self.fieldLabel = fieldLabel; self.fieldIdentifier = fieldIdentifier
        source = .init(text: text.wrappedValue)
    }
}
#if os(macOS)
import AppKit
private final class DigestPlainTextView: NSTextView {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
}
extension DigestNativeEditor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); let editor = DigestPlainTextView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        editor.isRichText = false; editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textColor = .textColor; editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator; editor.string = text
        editor.setAccessibilityLabel(fieldLabel); editor.setAccessibilityIdentifier(fieldIdentifier)
        scroll.documentView = editor
        context.coordinator.editor = editor
        commands.resignFocus = { [weak editor] in if let editor, editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) } }
        commands.clear = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.breakUndoCoalescing(); editor.history.removeAllActions()
            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator?.parent.text = ""
        }
        commands.showRange = { [weak editor, weak coordinator = context.coordinator] range in
            guard let editor, editor.window != nil, range.location <= editor.string.utf16.count else { return false }
            editor.window?.makeFirstResponder(editor); editor.setSelectedRange(range)
            guard let layout = editor.layoutManager, let container = editor.textContainer, let scroll = editor.enclosingScrollView else { return false }
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            if range.length == 0 {
                if range.location == editor.string.utf16.count && layout.extraLineFragmentTextContainer === container {
                    rect = layout.extraLineFragmentRect
                } else if range.location > 0 {
                    let previous = layout.glyphRange(forCharacterRange: .init(location: range.location - 1, length: 1), actualCharacterRange: nil)
                    rect = layout.boundingRect(forGlyphRange: previous, in: container)
                    rect.origin.x = rect.maxX; rect.size.width = 2
                }
            }
            rect.origin.y += editor.textContainerOrigin.y
            if rect.height < 1 { rect.size.height = editor.font?.pointSize ?? 16 }
            coordinator?.motion.reveal(rect, in: scroll, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
            return true
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        scroll.setAccessibilityHidden(!visible)
        guard let editor = context.coordinator.editor else { return }
        if visible && scroll.documentView !== editor { scroll.documentView = editor }
        else if !visible && scroll.documentView != nil { scroll.documentView = nil }
        editor.setAccessibilityHidden(!visible)
        if !editor.string.utf8.elementsEqual(text.utf8) && !editor.hasMarkedText() { editor.string = text }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.motion.cancel()
        coordinator.editor?.history.removeAllActions()
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        fileprivate var editor: DigestPlainTextView?
        let motion = NativeListScrollMotion()
        var parent: DigestNativeEditor
        init(_ parent: DigestNativeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { motion.cancel(); if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}
#else
import UIKit
private final class DigestPlainTextView: UITextView {
    private struct Snapshot { let text: String; let selection: NSRange }
    let history: UndoManager = { let value = UndoManager(); value.levelsOfUndo = 50; value.groupsByEvent = false; return value }()
    private var committed = Snapshot(text: "", selection: .init(location: 0, length: 0))
    private var restoring = false
    override var undoManager: UndoManager? { history }
    // The bridged UIKit control does not populate a substituted manager on its
    // own. Register committed plain-text snapshots, like the existing credential field.
    func reset(_ value: String) {
        text = value; selectedRange = .init(location: 0, length: 0)
        history.removeAllActions(); committed = .init(text: value, selection: selectedRange)
    }
    func selectionChanged() {
        if markedTextRange == nil && text.utf8.elementsEqual(committed.text.utf8) { committed = .init(text: text, selection: selectedRange) }
    }
    func commitChange() {
        guard !restoring, markedTextRange == nil, !text.utf8.elementsEqual(committed.text.utf8) else { return }
        remember(committed); committed = .init(text: text, selection: selectedRange)
    }
    private func remember(_ snapshot: Snapshot) {
        let group = !history.isUndoing && !history.isRedoing
        if group { history.beginUndoGrouping() }
        history.registerUndo(withTarget: self) { $0.restore(snapshot) }
        if group { history.endUndoGrouping() }
    }
    private func restore(_ snapshot: Snapshot) {
        let previous = Snapshot(text: text, selection: selectedRange)
        restoring = true
        text = snapshot.text; selectedRange = snapshot.selection; committed = snapshot
        remember(previous)
        delegate?.textViewDidChange?(self)
        restoring = false
    }
}
extension DigestNativeEditor: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let editor = DigestPlainTextView()
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.adjustsFontForContentSizeCategory = true; editor.textColor = .label; editor.backgroundColor = .secondarySystemBackground
        editor.textContainerInset = .init(top: 6, left: 6, bottom: 6, right: 6)
        editor.autocorrectionType = .no; editor.autocapitalizationType = .none
        editor.smartQuotesType = .no; editor.smartDashesType = .no; editor.spellCheckingType = .no
        editor.smartInsertDeleteType = .no; editor.keyboardType = .default
        editor.delegate = context.coordinator; editor.reset(text)
        editor.accessibilityLabel = fieldLabel; editor.accessibilityIdentifier = fieldIdentifier
        commands.resignFocus = { [weak editor] in if editor?.isFirstResponder == true { editor?.resignFirstResponder() } }
        commands.clear = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.reset("")
            coordinator?.parent.text = ""
        }
        commands.showRange = { [weak editor] range in
            guard let editor, editor.window != nil, range.location <= editor.text.utf16.count else { return false }
            editor.becomeFirstResponder(); editor.selectedRange = range; editor.layoutIfNeeded()
            if let position = editor.position(from: editor.beginningOfDocument, offset: range.location) {
                var rect = editor.caretRect(for: position); rect = rect.insetBy(dx: -8, dy: -16)
                editor.scrollRectToVisible(rect, animated: !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
            }
            return true
        }
        let container = DigestEditorContainer(editor: editor); container.setVisible(visible); return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        guard let container = view as? DigestEditorContainer else { return }
        let editor = container.editor
        container.setVisible(visible)
        if !editor.text.utf8.elementsEqual(text.utf8) && editor.markedTextRange == nil { editor.reset(text) }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { (view as? DigestEditorContainer)?.editor.history.removeAllActions() }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DigestNativeEditor
        init(_ parent: DigestNativeEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { (textView as? DigestPlainTextView)?.commitChange(); parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { (textView as? DigestPlainTextView)?.selectionChanged() }
    }
}
private final class DigestEditorContainer: UIView {
    let editor: DigestPlainTextView
    init(editor: DigestPlainTextView) { self.editor = editor; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Not archived") }
    func setVisible(_ visible: Bool) {
        // Retain the native editor and its Undo, but keep hidden input out of UIKit AX.
        if visible && editor.superview == nil { addSubview(editor); setNeedsLayout() }
        else if !visible && editor.superview != nil { editor.removeFromSuperview() }
        accessibilityElementsHidden = !visible
    }
    override func layoutSubviews() { super.layoutSubviews(); editor.frame = bounds }
}
#endif
