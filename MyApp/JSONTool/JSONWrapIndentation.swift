import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Native soft-wrap layout: Output, and Input containing physical line breaks.
/// Never inserts characters; composition and the native text undo history are protected.
@MainActor final class JSONWrapIndentation {
    private weak var editor: JSONNativeTextView?
    private var source: String?
    private var width: CGFloat?
    private var spaceWidth: CGFloat?
    private var applied = false
    private var updating = false

    init(editor: JSONNativeTextView) { self.editor = editor }

    func update() {
        guard !updating, let editor, let font = editor.font else { return }
        #if os(macOS)
        guard !editor.hasMarkedText() else { return }
        #else
        guard editor.markedTextRange == nil else { return }
        #endif
        let storage: NSTextStorage? = editor.textStorage
        guard let storage else { return }
        #if os(macOS)
        let wraps = editor.textContainer?.widthTracksTextView == true
        let available = (editor.enclosingScrollView?.contentSize.width ?? editor.bounds.width)
            - 2 * editor.textContainerInset.width - 2 * (editor.textContainer?.lineFragmentPadding ?? 5)
        #else
        let wraps = editor.textContainer.widthTracksTextView
        let available = editor.bounds.width - editor.textContainerInset.left - editor.textContainerInset.right
            - 2 * editor.textContainer.lineFragmentPadding
        #endif
        let text = storage.string
        guard wraps, storage.length <= editor.presentationLimit,
              !editor.isEditable || text.contains("\n") || text.contains("\r") else {
            if applied {
                applied = false; source = nil; width = nil
                updateLayoutAttributes(editor, storage: storage) {
                    storage.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: storage.length))
                }
            }
            return
        }
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        let availableWidth = max(0, available)
        guard text != source || width != availableWidth || spaceWidth != space else { return }
        source = text; width = availableWidth; spaceWidth = space
        let original = text as NSString
        var offset = 0
        var styles: [String: NSParagraphStyle] = [:]
        updateLayoutAttributes(editor, storage: storage) {
            while offset < original.length {
                let paragraph = original.paragraphRange(for: NSRange(location: offset, length: 0))
                var position = offset
                while position < NSMaxRange(paragraph) {
                    let unit = original.character(at: position)
                    guard unit == 32 || unit == 9 else { break }
                    position += 1
                }
                let leading = original.substring(with: NSRange(location: offset, length: position - offset))
                let style: NSParagraphStyle
                if let cached = styles[leading] { style = cached }
                else {
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.firstLineHeadIndent = 0 // actual leading whitespace already exists
                    let leadingWidth = (leading as NSString).size(withAttributes: [.font: font, .paragraphStyle: paragraphStyle]).width
                    paragraphStyle.headIndent = min(leadingWidth + 2 * space, availableWidth * 0.5)
                    style = paragraphStyle.copy() as! NSParagraphStyle
                    styles[leading] = style
                }
                var effective = NSRange()
                let current = storage.attribute(.paragraphStyle, at: offset, longestEffectiveRange: &effective, in: paragraph) as? NSParagraphStyle
                if current?.isEqual(style) != true || NSMaxRange(effective) < NSMaxRange(paragraph) {
                    storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
                }
                offset = NSMaxRange(paragraph)
            }
        }
        applied = true
    }

    private func updateLayoutAttributes(_ editor: JSONNativeTextView, storage: NSTextStorage, changes: () -> Void) {
        updating = true
        defer { updating = false }
        let undo = editor.undoManager
        let protectUndo = editor.isEditable && undo?.isUndoRegistrationEnabled == true
        if protectUndo { undo?.disableUndoRegistration() }
        defer { if protectUndo { undo?.enableUndoRegistration() } }

        // Native selection can inherit our paragraph style. Do not carry its hanging
        // indent into newly typed paragraphs or back into a single-line document.
        var typing = editor.typingAttributes
        if let paragraph = typing[.paragraphStyle] as? NSParagraphStyle, paragraph.headIndent > 0 {
            let plain = paragraph.mutableCopy() as! NSMutableParagraphStyle
            plain.headIndent = 0
            typing[.paragraphStyle] = plain.copy() as! NSParagraphStyle
        }
        storage.beginEditing()
        changes()
        storage.endEditing()
        if editor.isEditable { editor.typingAttributes = typing }
    }
}
