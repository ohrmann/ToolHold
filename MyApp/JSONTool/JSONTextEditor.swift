import SwiftUI
#if SWIFT_PACKAGE
import JSONCore
#endif

/// A native editing command, kept outside SwiftUI update callbacks to preserve Undo.
@MainActor final class JSONEditorCommands {
    var clear: (() -> Void)?
    var replace: ((NSRange, String) -> Void)?
    var purgeUndo: (() -> Void)?
    var resignFocus: (() -> Void)?
    var hasMarkedText: (() -> Bool)?
    var cancelNavigation: (() -> Void)?
}

/// Retains a source snapshot using String's copy-on-write storage. SwiftUI must
/// compare exact document content even when a constant Binding compares canonically equal.
private struct JSONEditorSourceSnapshot: Equatable {
    let text: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text.utf16.elementsEqual(rhs.text.utf16)
    }
}

struct JSONTextEditor {
    @Binding var text: String
    var privateUndo = false
    var usesPrivacyContainer = false
    var presentationHidden = false
    var editable = true
    var matchHighlights: TextEditorHighlights?
    var showsLineNumbers = true
    var diagnostic: JSONDiagnostic?
    var jumpTarget: NSRange?
    var jumpRequest = 0
    var animateJumps = false
    var highlightJumps = false
    var focusOnJump = true
    var onPaste: () -> Void = {}
    var commands: JSONEditorCommands?
    var options = JSONEditorOptions()
    var highlightingLimit = 262_144
    var placeholder: String?
    var contentName: String?
    var editorAccessibilityLabel: String { (contentName ?? options.syntax.name) + (editable ? " input" : " result") }

    private let sourceSnapshot: JSONEditorSourceSnapshot

    init(text: Binding<String>, editable: Bool = true, diagnostic: JSONDiagnostic? = nil,
         jumpTarget: NSRange? = nil, jumpRequest: Int = 0, animateJumps: Bool = false, highlightJumps: Bool = false, focusOnJump: Bool = true, onPaste: @escaping () -> Void = {},
         commands: JSONEditorCommands? = nil, options: JSONEditorOptions = JSONEditorOptions(),
         presentationHidden: Bool = false, usesPrivacyContainer: Bool = false, privateUndo: Bool = false, highlightingLimit: Int = 262_144, placeholder: String? = nil, contentName: String? = nil, showsLineNumbers: Bool = true, matchHighlights: TextEditorHighlights? = nil) {
        self.matchHighlights = matchHighlights
        self.privateUndo = privateUndo
        self.usesPrivacyContainer = usesPrivacyContainer
        self.presentationHidden = presentationHidden
        self._text = text
        self.sourceSnapshot = JSONEditorSourceSnapshot(text: text.wrappedValue)
        self.editable = editable; self.diagnostic = diagnostic
        self.showsLineNumbers = showsLineNumbers
        self.jumpTarget = jumpTarget; self.jumpRequest = jumpRequest
        self.animateJumps = animateJumps; self.highlightJumps = highlightJumps; self.focusOnJump = focusOnJump
        self.onPaste = onPaste; self.commands = commands; self.options = options
        self.highlightingLimit = highlightingLimit; self.placeholder = placeholder; self.contentName = contentName
    }
}

#if os(macOS)
import AppKit

extension JSONTextEditor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = JSONNativeTextView(frame: .zero)
        if privateUndo { editor.privateHistory = UndoManager() }
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor
        editor.didPaste = { [weak coordinator = context.coordinator, weak editor] in
            guard let coordinator, let editor else { return }
            coordinator.parent.text = editor.string
            coordinator.parent.onPaste()
        }
        commands?.clear = { [weak editor] in
            guard let editor else { return }
            editor.breakUndoCoalescing()
            editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            editor.breakUndoCoalescing()
        }
        commands?.purgeUndo = { [weak editor] in editor?.undoManager?.removeAllActions() }
        commands?.replace = { [weak editor] range, value in
            guard let editor, NSMaxRange(range) <= editor.string.utf16.count else { return }
            editor.breakUndoCoalescing(); editor.insertText(value, replacementRange: range); editor.breakUndoCoalescing()
        }
        commands?.resignFocus = { [weak editor] in
            if let editor, editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) }
        }
        commands?.cancelNavigation = { [weak editor] in if let editor { JSONEditorNavigation.cancel(editor) } }
        commands?.hasMarkedText = { [weak editor] in editor?.hasMarkedText() ?? false }
        editor.delegate = context.coordinator
        context.coordinator.highlighter.attach(editor)
        context.coordinator.highlighter.didUpdateCoordinates = { [weak editor] coordinates in
            editor?.adornments.setCoordinates(coordinates)
        }
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textColor = .textColor
        editor.insertionPointColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.isEditable = editable
        editor.allowsUndo = true
        editor.setAccessibilityLabel(editorAccessibilityLabel)
        editor.adornments.install()
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.viewportChanged(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let editor = scroll.documentView as! NSTextView
        context.coordinator.parent = self
        (editor as? JSONNativeTextView)?.privacyHidden = presentationHidden
        scroll.isHidden = presentationHidden
        editor.setAccessibilityElement(!presentationHidden)
        editor.setAccessibilityLabel(editorAccessibilityLabel)
        context.coordinator.diagnosticSource = text
        if editor.isEditable != editable { editor.isEditable = editable }
        if !editor.hasMarkedText(), !editor.string.utf16.elementsEqual(text.utf16) {
            JSONEditorNavigation.cancel(editor)
            editor.string = text
        }
        context.coordinator.configureWrap(editor, scroll: scroll)
        if let native = editor as? JSONNativeTextView {
            native.presentationLimit = highlightingLimit
            native.wrapIndentation.update()
        }
        context.coordinator.refresh(editor)
        (editor as? JSONNativeTextView)?.adornments.updateMatches(matchHighlights)
        (editor as? JSONNativeTextView)?.placeholder.update(text: placeholder)
        if context.coordinator.lastJump != jumpRequest {
            context.coordinator.lastJump = jumpRequest
            if let target = jumpTarget, target.location <= text.utf16.count {
                JSONEditorNavigation.jump(editor, to: target.location, animated: animateJumps, focus: focusOnJump,
                                          highlight: highlightJumps ? target : nil)
            }
        }
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.highlighter.stop()
        if let editor = view.documentView as? JSONNativeTextView {
            JSONEditorNavigation.cancel(editor)
            editor.privateHistory?.removeAllActions()
        }
        NotificationCenter.default.removeObserver(coordinator)
    }
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONTextEditor
        var lastJump = 0
        var wrapping: Bool?
        var diagnosticSource = ""
        let highlighter = JSONEditorHighlighter()
        init(_ parent: JSONTextEditor) { self.parent = parent }
        @objc func viewportChanged(_ notification: Notification) {
            ((notification.object as? NSClipView)?.documentView as? JSONNativeTextView)?.adornments.updateViewport()
        }
        func refresh(_ editor: NSTextView) {
            (editor as? JSONNativeTextView)?.wrapIndentation.update()
            (editor as? JSONNativeTextView)?.placeholder.update(text: parent.placeholder)
            let diagnostic = editor.string.utf16.elementsEqual(diagnosticSource.utf16) ? parent.diagnostic : nil
            (editor as? JSONNativeTextView)?.adornments.update(diagnostic: diagnostic, showsGutter: parent.editable && parent.showsLineNumbers)
            highlighter.update(source: editor.string, options: parent.options,
                               diagnostic: diagnostic, limit: parent.highlightingLimit, needsCoordinates: (parent.editable && parent.showsLineNumbers) || diagnostic != nil)
        }
        func configureWrap(_ editor: NSTextView, scroll: NSScrollView) {
            let wrap = parent.options.wordWrap
            if wrapping != wrap {
                wrapping = wrap
                scroll.hasHorizontalScroller = !wrap
                editor.isHorizontallyResizable = !wrap
                editor.autoresizingMask = wrap ? [.width] : []
                editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                editor.textContainer?.widthTracksTextView = wrap
                editor.textContainer?.containerSize = NSSize(width: wrap ? scroll.contentSize.width : CGFloat.greatestFiniteMagnitude,
                                                            height: CGFloat.greatestFiniteMagnitude)
                if wrap { editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: editor.frame.height)) }
            }
            if !wrap {
                editor.minSize = NSSize(width: scroll.contentSize.width, height: 0)
                editor.sizeToFit()
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { refresh(editor) }
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            JSONEditorNavigation.cancel(editor)
            parent.text = editor.string
            refresh(editor)
        }
    }
}
/// All AppKit paste actions flow through the same completion hook, once per paste.
final class JSONNativeTextView: NSTextView {
    var privateHistory: UndoManager?
    override var undoManager: UndoManager? { privateHistory ?? super.undoManager }
    var privacyHidden = false
    override func accessibilityValue() -> String? { privacyHidden ? nil : super.accessibilityValue() }
    override func copy(_ sender: Any?) { if !privacyHidden { super.copy(sender) } }
    override func cut(_ sender: Any?) { if !privacyHidden { super.cut(sender) } }
    var navigationAnimation: Task<Void, Never>?
    var navigationAnimationID = UUID()
    lazy var adornments = JSONEditorAdornments(editor: self)
    lazy var wrapIndentation = JSONWrapIndentation(editor: self)
    lazy var placeholder = JSONEditorPlaceholder(editor: self)
    var presentationLimit = 262_144
    override func becomeFirstResponder() -> Bool {
        guard !privacyHidden else { return false }
        let became = super.becomeFirstResponder()
        placeholder.update(focused: became ? true : nil)
        return became
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        placeholder.update(focused: resigned ? false : nil)
        return resigned
    }
    override func layout() {
        super.layout()
        wrapIndentation.update()
        adornments.updateViewport()
        placeholder.update()
    }
    var didPaste: (() -> Void)?
    private var pasteDepth = 0
    private func performingPaste(_ action: () -> Void) {
        guard !privacyHidden else { return }
        pasteDepth += 1
        action()
        pasteDepth -= 1
        if pasteDepth == 0 { didPaste?() }
    }
    override func paste(_ sender: Any?) { performingPaste { super.paste(sender) } }
    override func pasteAsPlainText(_ sender: Any?) { performingPaste { super.pasteAsPlainText(sender) } }
    override func pasteAsRichText(_ sender: Any?) { performingPaste { super.pasteAsRichText(sender) } }
}
#else
import UIKit

extension JSONTextEditor: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        // Stay on TextKit 2; never access UITextView.layoutManager (which forces fallback).
        let editor = JSONNativeTextView(usingTextLayoutManager: true)
        context.coordinator.highlighter.attach(editor)
        context.coordinator.highlighter.didUpdateCoordinates = { [weak editor] coordinates in
            editor?.adornments.setCoordinates(coordinates)
        }
        editor.pasteDelegate = context.coordinator
        commands?.clear = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.replace(editor.textRange(from: editor.beginningOfDocument, to: editor.endOfDocument)!, withText: "")
            coordinator?.parent.text = editor.text
        }
        commands?.purgeUndo = { [weak editor] in editor?.undoManager?.removeAllActions() }
        commands?.replace = { [weak editor, weak coordinator = context.coordinator] range, value in
            guard let editor, NSMaxRange(range) <= editor.text.utf16.count,
                  let start = editor.position(from: editor.beginningOfDocument, offset: range.location),
                  let end = editor.position(from: start, offset: range.length),
                  let selection = editor.textRange(from: start, to: end) else { return }
            editor.replace(selection, withText: value)
            coordinator?.parent.text = editor.text
        }
        commands?.resignFocus = { [weak editor] in
            if editor?.isFirstResponder == true { _ = editor?.resignFirstResponder() }
        }
        commands?.cancelNavigation = { [weak editor] in if let editor { JSONEditorNavigation.cancel(editor) } }
        commands?.hasMarkedText = { [weak editor] in editor?.markedTextRange != nil }
        editor.delegate = context.coordinator
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.autocorrectionType = .no
        editor.autocapitalizationType = .none
        editor.smartQuotesType = .no
        editor.smartDashesType = .no
        editor.smartInsertDeleteType = .no
        editor.spellCheckingType = .no
        editor.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        editor.isEditable = editable
        editor.accessibilityLabel = editorAccessibilityLabel
        editor.adornments.install()
        return usesPrivacyContainer ? JSONEditorPrivacyContainer(editor: editor) : editor
    }
    func updateUIView(_ view: UIView, context: Context) {
        let editor = (view as? JSONEditorPrivacyContainer)?.editor ?? (view as! UITextView)
        context.coordinator.parent = self
        (editor as? JSONNativeTextView)?.privacyHidden = presentationHidden
        (view as? JSONEditorPrivacyContainer)?.setHidden(presentationHidden)
        editor.isHidden = presentationHidden
        editor.accessibilityElementsHidden = presentationHidden
        editor.isAccessibilityElement = !presentationHidden
        editor.accessibilityLabel = editorAccessibilityLabel
        context.coordinator.diagnosticSource = text
        if editor.isEditable != editable { editor.isEditable = editable }
        if editor.markedTextRange == nil, !editor.text.utf16.elementsEqual(text.utf16) {
            JSONEditorNavigation.cancel(editor)
            editor.text = text
        }
        context.coordinator.highlighter.attach(editor)
        context.coordinator.configureWrap(editor)
        if let native = editor as? JSONNativeTextView {
            native.presentationLimit = highlightingLimit
            native.wrapIndentation.update()
        }
        context.coordinator.refresh(editor)
        (editor as? JSONNativeTextView)?.adornments.updateMatches(matchHighlights)
        (editor as? JSONNativeTextView)?.placeholder.update(text: placeholder)
        if context.coordinator.lastJump != jumpRequest {
            context.coordinator.lastJump = jumpRequest
            if let target = jumpTarget, target.location <= text.utf16.count {
                // An explicit jump can also reveal/reparent a collapsed SwiftUI panel.
                // Wait until that update transaction completes before entering UIKit's
                // responder chain; synchronous becomeFirstResponder can re-enter layout.
                let request = jumpRequest
                let source = text
                DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
                    guard let editor, let coordinator, coordinator.parent.jumpRequest == request,
                          !coordinator.parent.presentationHidden, editor.window != nil, editor.text.utf16.elementsEqual(source.utf16),
                          target.location <= editor.text.utf16.count else { return }
                    JSONEditorNavigation.jump(editor, to: target.location,
                                              animated: coordinator.parent.animateJumps, focus: coordinator.parent.focusOnJump,
                                              highlight: coordinator.parent.highlightJumps ? target : nil)
                }
            }
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        let editor = (view as? JSONEditorPrivacyContainer)?.editor ?? (view as! UITextView)
        JSONEditorNavigation.cancel(editor)
        if coordinator.parent.privateUndo { editor.undoManager?.removeAllActions() }
        coordinator.highlighter.stop()
    }
    @MainActor class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: JSONTextEditor
        var lastJump = 0
        var wrapping: Bool?
        var diagnosticSource = ""
        let highlighter = JSONEditorHighlighter()
        init(_ parent: JSONTextEditor) { self.parent = parent }
        func refresh(_ editor: UITextView) {
            (editor as? JSONNativeTextView)?.wrapIndentation.update()
            (editor as? JSONNativeTextView)?.placeholder.update(text: parent.placeholder)
            let diagnostic = editor.text.utf16.elementsEqual(diagnosticSource.utf16) ? parent.diagnostic : nil
            (editor as? JSONNativeTextView)?.adornments.update(diagnostic: diagnostic, showsGutter: parent.editable && parent.showsLineNumbers)
            highlighter.update(source: editor.text, options: parent.options,
                               diagnostic: diagnostic, limit: parent.highlightingLimit, needsCoordinates: (parent.editable && parent.showsLineNumbers) || diagnostic != nil)
        }
        func configureWrap(_ editor: UITextView) {
            let wrap = parent.options.wordWrap
            guard wrapping != wrap else { return }
            wrapping = wrap
            editor.textContainer.widthTracksTextView = wrap
            editor.textContainer.size = CGSize(width: wrap ? max(1, editor.bounds.width - editor.textContainerInset.left - editor.textContainerInset.right) : CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude)
            editor.showsHorizontalScrollIndicator = !wrap
            editor.alwaysBounceHorizontal = !wrap
            if wrap { editor.setContentOffset(CGPoint(x: 0, y: editor.contentOffset.y), animated: false) }
            editor.setNeedsLayout()
        }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            (scrollView as? JSONNativeTextView)?.finishNavigation?()
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if let editor = scrollView as? UITextView { JSONEditorNavigation.cancel(editor) }
        }
        func textViewDidChange(_ textView: UITextView) {
            JSONEditorNavigation.cancel(textView)
            parent.text = textView.text
            refresh(textView)
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            refresh(textView)
        }

        // UIKit calls this after asynchronous item-provider loading has completed.
        // replace(_:withText:) uses native text editing/Undo; no clipboard polling.
        func textPasteConfigurationSupporting(_ supporting: any UITextPasteConfigurationSupporting,
            performPasteOf attributedString: NSAttributedString, to textRange: UITextRange) -> UITextRange {
            guard let editor = supporting as? UITextView, editor.isEditable else { return textRange }
            editor.replace(textRange, withText: attributedString.string)
            parent.text = editor.text
            refresh(editor)
            parent.onPaste()
            return editor.selectedTextRange ?? textRange
        }
    }
}
/// Opt-in for sensitive workspaces. The same text view/Undo storage is retained,
/// but a masked editor is absent from UIKit's active accessibility hierarchy.
final class JSONEditorPrivacyContainer: UIView {
    let editor: UITextView
    private var concealed = false
    private var presentationRevision = 0
    init(editor: UITextView) {
        self.editor = editor
        super.init(frame: .zero)
        addSubview(editor)
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    required init?(coder: NSCoder) { fatalError("Not archived") }
    func setHidden(_ hidden: Bool) {
        concealed = hidden; presentationRevision += 1
        accessibilityElementsHidden = hidden
        if (hidden && editor.superview != nil) || (!hidden && editor.superview == nil) {
            // Both removal and reattachment can enter SwiftUI's keyboard/focus graph
            // (UIKit restores a previously focused editor on attachment). Do neither
            // inside updateUIView. Pixels/accessibility are concealed synchronously.
            let revision = presentationRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, presentationRevision == revision else { return }
                if concealed {
                    if editor.isFirstResponder { _ = editor.resignFirstResponder() }
                    editor.removeFromSuperview()
                } else if editor.superview == nil { addSubview(editor); editor.frame = bounds }
            }
        }
    }
    override func layoutSubviews() { super.layoutSubviews(); if editor.superview != nil { editor.frame = bounds } }
}
final class JSONNativeTextView: UITextView {
    var privacyHidden = false
    override var accessibilityValue: String? {
        get { privacyHidden ? nil : super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { !privacyHidden && super.canPerformAction(action, withSender: sender) }
    override var canBecomeFirstResponder: Bool { !privacyHidden && super.canBecomeFirstResponder }
    override func copy(_ sender: Any?) { if !privacyHidden { super.copy(sender) } }
    override func cut(_ sender: Any?) { if !privacyHidden { super.cut(sender) } }
    override func paste(_ sender: Any?) { if !privacyHidden { super.paste(sender) } }
    var finishNavigation: (() -> Void)?
    lazy var adornments = JSONEditorAdornments(editor: self)
    lazy var wrapIndentation = JSONWrapIndentation(editor: self)
    lazy var placeholder = JSONEditorPlaceholder(editor: self)
    var presentationLimit = 262_144
    override func becomeFirstResponder() -> Bool {
        guard !privacyHidden else { return false }
        let became = super.becomeFirstResponder()
        placeholder.update(focused: became ? true : nil)
        return became
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        placeholder.update(focused: resigned ? false : nil)
        return resigned
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        wrapIndentation.update()
        adornments.updateViewport()
        placeholder.update()
    }
}
#endif

/// Native scrolling is opt-in; existing Formatter/Tree navigation keeps its defaults.
@MainActor enum JSONEditorNavigation {
    #if os(macOS)
    static func cancel(_ editor: NSTextView) {
        guard let native = editor as? JSONNativeTextView else { return }
        native.navigationAnimation?.cancel(); native.navigationAnimation = nil
        native.navigationAnimationID = UUID()
        native.adornments.cancelNavigationHighlight()
    }
    static func jump(_ editor: NSTextView, to offset: Int, animated: Bool, focus: Bool, highlight: NSRange? = nil) {
        cancel(editor)
        let caret = NSRange(location: offset, length: 0)
        guard animated, let native = editor as? JSONNativeTextView, let scroll = editor.enclosingScrollView else {
            editor.setSelectedRange(caret); editor.scrollRangeToVisible(caret)
            if focus { editor.window?.makeFirstResponder(editor) }
            if let highlight { (editor as? JSONNativeTextView)?.adornments.showNavigationHighlight(highlight, animated: animated) }
            return
        }
        let initialSelection = editor.selectedRange()
        guard let rect = scrollTarget(editor, at: offset) else {
            editor.setSelectedRange(caret); editor.scrollRangeToVisible(caret)
            if focus { editor.window?.makeFirstResponder(editor) }
            if let highlight { native.adornments.showNavigationHighlight(highlight, animated: animated) }
            return
        }
        let clip = scroll.contentView
        let viewport = clip.bounds
        var origin = viewport.origin
        if rect.minY < viewport.minY + 16 || rect.maxY > viewport.maxY - 16 { origin.y = rect.midY - viewport.height / 2 }
        if rect.minX < viewport.minX + 16 || rect.maxX > viewport.maxX - 16 { origin.x = rect.midX - viewport.width / 2 }
        let destination = clip.constrainBoundsRect(CGRect(origin: origin, size: viewport.size)).origin
        let source = editor.string, request = UUID()
        native.navigationAnimationID = request
        let start = viewport.origin, clock = ContinuousClock.now
        // Offscreen anchors need layout geometry, not firstRect's visible-range fallback.
        // Commit selection after scrolling so native caret reveal cannot jump ahead.
        native.navigationAnimation = Task { @MainActor [weak native, weak scroll, weak clip] in
            var expected = start
            while !Task.isCancelled {
                guard let native, let scroll, let clip, native.window != nil,
                      native.navigationAnimationID == request,
                      native.selectedRange() == initialSelection,
                      native.string.utf16.elementsEqual(source.utf16),
                      abs(clip.bounds.minX - expected.x) < 1, abs(clip.bounds.minY - expected.y) < 1 else { break }
                let elapsed = clock.duration(to: .now).components
                let progress = min(1, (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) / 0.22)
                let ease = progress * progress * (3 - 2 * progress)
                clip.scroll(to: CGPoint(x: start.x + (destination.x - start.x) * ease,
                                        y: start.y + (destination.y - start.y) * ease))
                scroll.reflectScrolledClipView(clip)
                expected = clip.bounds.origin
                if progress >= 1 {
                    native.setSelectedRange(caret)
                    if focus { native.window?.makeFirstResponder(native) }
                    if let highlight { native.adornments.showNavigationHighlight(highlight, animated: animated) }
                    break
                }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
            }
            if let native, native.navigationAnimationID == request { native.navigationAnimation = nil }
        }
    }
    private static func scrollTarget(_ editor: NSTextView, at offset: Int) -> CGRect? {
        guard let manager = editor.layoutManager, let container = editor.textContainer else { return nil }
        manager.ensureLayout(for: container)
        let count = editor.textStorage?.length ?? 0
        var rect: CGRect
        if offset < count {
            let glyph = manager.glyphIndexForCharacter(at: offset)
            guard glyph < manager.numberOfGlyphs else { return nil }
            rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        } else if manager.extraLineFragmentRect.height > 0 {
            rect = manager.extraLineFragmentRect
        } else if manager.numberOfGlyphs > 0 {
            rect = manager.boundingRect(forGlyphRange: NSRange(location: manager.numberOfGlyphs - 1, length: 1), in: container)
            rect.origin.x = rect.maxX
        } else { return nil }
        rect.size.width = 1
        return rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    }
    #else
    static func cancel(_ editor: UITextView) {
        guard let native = editor as? JSONNativeTextView else { return }
        native.finishNavigation = nil
        native.adornments.cancelNavigationHighlight()
    }
    static func jump(_ editor: UITextView, to offset: Int, animated: Bool, focus: Bool, highlight: NSRange? = nil) {
        cancel(editor)
        let native = editor as? JSONNativeTextView
        let start = editor.contentOffset
        editor.setContentOffset(start, animated: false)
        let caret = NSRange(location: offset, length: 0)
        guard animated, let native, let position = editor.position(from: editor.beginningOfDocument, offset: offset) else {
            if focus, !editor.isFirstResponder { editor.becomeFirstResponder() }
            editor.selectedRange = caret; editor.scrollRangeToVisible(caret)
            if let highlight { native?.adornments.showNavigationHighlight(highlight, animated: animated) }
            return
        }
        let initialSelection = editor.selectedRange, source = editor.text ?? ""
        editor.layoutIfNeeded()
        let rect = editor.caretRect(for: position)
        guard rect.minX.isFinite, rect.minY.isFinite else { return }
        let insets = editor.adjustedContentInset
        let width = max(1, editor.bounds.width - insets.left - insets.right)
        let height = max(1, editor.bounds.height - insets.top - insets.bottom)
        var destination = start
        if rect.minY < start.y + insets.top + 16 || rect.maxY > start.y + insets.top + height - 16 {
            destination.y = rect.midY - height / 2 - insets.top
        }
        if rect.minX < start.x + insets.left + 16 || rect.maxX > start.x + insets.left + width - 16 {
            destination.x = rect.midX - width / 2 - insets.left
        }
        destination.x = min(max(-insets.left, destination.x), max(-insets.left, editor.contentSize.width - editor.bounds.width + insets.right))
        destination.y = min(max(-insets.top, destination.y), max(-insets.top, editor.contentSize.height - editor.bounds.height + insets.bottom))
        native.finishNavigation = { [weak native] in
            guard let native else { return }
            guard native.window != nil, native.text.utf16.elementsEqual(source.utf16), native.selectedRange == initialSelection else {
                native.finishNavigation = nil; return
            }
            guard abs(native.contentOffset.x - destination.x) < 2, abs(native.contentOffset.y - destination.y) < 2 else { return }
            native.finishNavigation = nil
            native.selectedRange = caret
            if focus, !native.isFirstResponder { native.becomeFirstResponder() }
            if let highlight { native.adornments.showNavigationHighlight(highlight, animated: animated) }
        }
        if abs(start.x - destination.x) < 1 && abs(start.y - destination.y) < 1 { native.finishNavigation?() }
        else { editor.setContentOffset(destination, animated: true) }
    }
    #endif
}
