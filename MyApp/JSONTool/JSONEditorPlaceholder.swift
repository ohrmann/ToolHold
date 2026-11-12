import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Presentation only. Uses the editor's text origin, so gutter/insets stay aligned.
/// Native responder changes hide the hint without moving selection or SwiftUI focus.
@MainActor final class JSONEditorPlaceholder {
    private weak var editor: JSONNativeTextView?
    private var text: String?
    #if os(macOS)
    private var label: JSONPlaceholderLabel?
    #else
    private var label: UILabel?
    #endif
    init(editor: JSONNativeTextView) { self.editor = editor }

    func update(text: String?) { self.text = text; update() }

    func update(focused focusOverride: Bool? = nil) {
        guard let editor else { return }
        #if os(macOS)
        let empty = editor.string.isEmpty
        let focused = focusOverride ?? (editor.window?.firstResponder === editor)
        let composing = editor.hasMarkedText()
        #else
        let empty = editor.text?.isEmpty != false
        let focused = focusOverride ?? editor.isFirstResponder
        let composing = editor.markedTextRange != nil
        #endif
        if empty, editor.isEditable, !composing { resetEmptyTypingStyle(editor) }
        guard let text, !text.isEmpty, empty, !(editor.isEditable && focused) else {
            label?.isHidden = true
            return
        }
        #if os(macOS)
        if label == nil {
            let hint = JSONPlaceholderLabel(labelWithString: text)
            hint.setAccessibilityElement(false)
            hint.textColor = .placeholderTextColor
            hint.font = .systemFont(ofSize: editor.font?.pointSize ?? 14)
            hint.cell?.wraps = true
            hint.cell?.isScrollable = false
            editor.addSubview(hint)
            label = hint
        }
        guard let label else { return }
        if label.stringValue != text { label.stringValue = text }
        let origin = editor.textContainerOrigin
        let x = origin.x + (editor.textContainer?.lineFragmentPadding ?? 0)
        let width = max(0, editor.bounds.width - x - editor.textContainerInset.width)
        let height = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 20
        label.frame = NSRect(x: x, y: origin.y, width: width, height: height)
        #else
        if label == nil {
            let hint = UILabel()
            hint.textColor = .placeholderText
            hint.font = .systemFont(ofSize: editor.font?.pointSize ?? 14)
            hint.numberOfLines = 0
            hint.isUserInteractionEnabled = false
            hint.isAccessibilityElement = false
            editor.addSubview(hint)
            label = hint
        }
        guard let label else { return }
        if label.text != text { label.text = text }
        let x = editor.textContainerInset.left + editor.textContainer.lineFragmentPadding
        let width = max(0, editor.bounds.width - x - editor.textContainerInset.right)
        let height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        label.frame = CGRect(x: x, y: editor.textContainerInset.top, width: width, height: height)
        #endif
        label.isHidden = false
    }

    private func resetEmptyTypingStyle(_ editor: JSONNativeTextView) {
        // Clearing formatted/multiline text can leave a hanging indent in typing
        // attributes. Empty JSON always starts at the first text column.
        let existing = editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        guard existing?.alignment != .left || existing?.firstLineHeadIndent != 0
                || existing?.headIndent != 0 || existing?.tailIndent != 0
                || existing?.baseWritingDirection != .leftToRight else { return }
        let plain = NSMutableParagraphStyle()
        plain.alignment = .left
        plain.baseWritingDirection = .leftToRight
        var attributes = editor.typingAttributes
        attributes[.paragraphStyle] = plain.copy() as! NSParagraphStyle
        editor.typingAttributes = attributes
    }
}

#if os(macOS)
@MainActor private final class JSONPlaceholderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
