import SwiftUI

@MainActor final class IdentifierAlphabetCommands { var clear: (() -> Void)?; var resignFocus: (() -> Void)? }

/// Small plain native editor: exact Paste (including invalid whitespace), native Undo,
/// and a private undo manager so Clear cannot resurrect the custom alphabet.
struct IdentifierAlphabetEditor {
    @Binding var text: String
    let commands: IdentifierAlphabetCommands
    var visible = true
    var fieldLabel = "Custom alphabet"
    var fieldIdentifier = "identifier-custom-alphabet"
}
#if os(macOS)
import AppKit
private final class AlphabetTextView: NSTextView {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
}
extension IdentifierAlphabetEditor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); let editor = AlphabetTextView()
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
        commands.resignFocus = { [weak editor] in if let editor, editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) } }
        commands.clear = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.breakUndoCoalescing(); editor.history.removeAllActions()
            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator?.parent.text = ""
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        scroll.setAccessibilityHidden(!visible)
        guard let editor = scroll.documentView as? AlphabetTextView else { return }
        editor.setAccessibilityHidden(!visible)
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? AlphabetTextView)?.history.removeAllActions()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IdentifierAlphabetEditor
        init(_ parent: IdentifierAlphabetEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}
#else
import UIKit
private final class AlphabetTextView: UITextView {
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
        if markedTextRange == nil && text == committed.text { committed = .init(text: text, selection: selectedRange) }
    }
    func commitChange() {
        guard !restoring, markedTextRange == nil, text != committed.text else { return }
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
extension IdentifierAlphabetEditor: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let editor = AlphabetTextView()
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.adjustsFontForContentSizeCategory = true; editor.textColor = .label; editor.backgroundColor = .secondarySystemBackground
        editor.textContainerInset = .init(top: 6, left: 6, bottom: 6, right: 6)
        editor.autocorrectionType = .no; editor.autocapitalizationType = .none
        editor.smartQuotesType = .no; editor.smartDashesType = .no; editor.spellCheckingType = .no
        editor.smartInsertDeleteType = .no; editor.keyboardType = .asciiCapable
        editor.delegate = context.coordinator; editor.reset(text)
        editor.accessibilityLabel = fieldLabel; editor.accessibilityIdentifier = fieldIdentifier
        commands.resignFocus = { [weak editor] in if editor?.isFirstResponder == true { editor?.resignFirstResponder() } }
        commands.clear = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.reset("")
            coordinator?.parent.text = ""
        }
        let container = AlphabetContainer(editor: editor); container.setVisible(visible); return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        guard let container = view as? AlphabetContainer else { return }
        let editor = container.editor
        container.setVisible(visible)
        if editor.text != text && editor.markedTextRange == nil { editor.reset(text) }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { (view as? AlphabetContainer)?.editor.history.removeAllActions() }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IdentifierAlphabetEditor
        init(_ parent: IdentifierAlphabetEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { (textView as? AlphabetTextView)?.commitChange(); parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { (textView as? AlphabetTextView)?.selectionChanged() }
    }
}
private final class AlphabetContainer: UIView {
    let editor: AlphabetTextView
    init(editor: AlphabetTextView) { self.editor = editor; super.init(frame: .zero) }
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
