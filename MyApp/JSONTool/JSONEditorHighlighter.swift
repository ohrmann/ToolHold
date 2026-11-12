import SwiftUI
#if SWIFT_PACKAGE
import JSONCore
#endif

#if os(macOS)
import AppKit
private typealias EditorView = NSTextView
private typealias EditorColor = NSColor
#else
import UIKit
private typealias EditorView = UITextView
private typealias EditorColor = UIColor
#endif

private enum JSONEditorPalette {
    private static func color(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> EditorColor {
        #if os(macOS)
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let contrast = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let c = isDark ? dark : light
            let mix = contrast ? 0.2 : 0.0
            let target = isDark ? 1.0 : 0.0
            return NSColor(srgbRed: c.0 * (1 - mix) + target * mix,
                           green: c.1 * (1 - mix) + target * mix,
                           blue: c.2 * (1 - mix) + target * mix, alpha: 1)
        }
        #else
        return UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let c = isDark ? dark : light
            let mix = traits.accessibilityContrast == .high ? 0.2 : 0.0
            let target = isDark ? 1.0 : 0.0
            return UIColor(red: c.0 * (1 - mix) + target * mix,
                           green: c.1 * (1 - mix) + target * mix,
                           blue: c.2 * (1 - mix) + target * mix, alpha: 1)
        }
        #endif
    }
    static let blue = color((0.10, 0.32, 0.64), (0.56, 0.73, 0.97))
    static let green = color((0.16, 0.40, 0.25), (0.56, 0.78, 0.62))
    static let brown = color((0.49, 0.30, 0.08), (0.87, 0.72, 0.48))
    static let purple = color((0.42, 0.28, 0.63), (0.74, 0.65, 0.89))
    static let teal = color((0.10, 0.40, 0.44), (0.53, 0.78, 0.81))
    static let rose = color((0.55, 0.26, 0.24), (0.86, 0.61, 0.57))
    static let rainbow = [blue, purple, teal, brown, rose, green]
    static var base: EditorColor {
        #if os(macOS)
        .textColor
        #else
        .label
        #endif
    }
    static var separator: EditorColor { color((0.30, 0.32, 0.34), (0.75, 0.77, 0.79)) }
    static var match: EditorColor { blue.withAlphaComponent(0.17) }
    static var error: EditorColor { EditorColor.systemRed.withAlphaComponent(0.23) }
    static func foreground(_ token: JSONSyntaxToken, options: JSONEditorOptions) -> EditorColor? {
        if token.kind == .bracket, options.rainbowBrackets, let depth = token.depth {
            return rainbow[depth % rainbow.count]
        }
        guard options.syntaxHighlighting else { return nil }
        switch token.kind {
        case .key: return blue
        case .string: return green
        case .number: return brown
        case .literal: return purple
        case .bracket: return base
        case .separator: return separator
        case .comment: return separator
        }
    }
}

/// Render-only decorations: never changes text storage, typing attributes, Undo or selection.
@MainActor final class JSONEditorHighlighter {
    private weak var editor: EditorView?
    private var source: String?
    private var options = JSONEditorOptions()
    private var snapshot: JSONSyntaxSnapshot?
    private var presentationSnapshot: JSONSyntaxSnapshot?
    private var paintedSelection = NSRange(location: NSNotFound, length: 0)
    private var diagnostic: JSONDiagnostic?
    private var relatedRanges: [NSRange] = []
    var didUpdateCoordinates: ((JSONSourceCoordinates?) -> Void)?
    private var visibleDiagnostic: NSRange?
    private var selection = NSRange(location: 0, length: 0)
    private var attempted = false
    private var limit = 262_144
    private var revision = UUID()
    private var work: Task<Void, Never>?
    private var coloring: Task<Void, Never>?
    private var backgroundRanges: [NSRange] = []
    private var wasComposing = false

    #if os(macOS)
    func attach(_ editor: NSTextView) { self.editor = editor }
    #else
    func attach(_ editor: UITextView) {
        guard self.editor !== editor else { return }
        self.editor = editor
        editor.textLayoutManager?.renderingAttributesValidator = { [weak self] manager, fragment in
            self?.render(fragment: fragment, manager: manager)
        }
    }
    #endif

    func update(source: String, options: JSONEditorOptions, diagnostic: JSONDiagnostic?, limit: Int, needsCoordinates: Bool = false) {
        guard let editor else { return }
        let changed = (self.source.map { !$0.utf16.elementsEqual(source.utf16) } ?? true) || self.limit != limit
        let optionsChanged = self.options != options
        let tokensEnabled = (options.needsTokens && !self.options.needsTokens) || options.syntax != self.options.syntax
        let diagnosticChanged = self.diagnostic != diagnostic
        self.options = options
        self.diagnostic = diagnostic
        if changed || diagnosticChanged {
            visibleDiagnostic = Self.displayRange(diagnostic, source: source)
            relatedRanges = diagnostic?.related.compactMap { location in
                guard location.range.length > 0, location.range.length <= 32,
                      NSMaxRange(location.range) <= (source as NSString).length else { return nil }
                return (source as NSString).rangeOfComposedCharacterSequences(for: location.range)
            } ?? []
        }
        self.limit = limit
        #if os(macOS)
        let composing = editor.hasMarkedText()
        #else
        let composing = editor.markedTextRange != nil
        #endif
        let compositionEnded = wasComposing && !composing
        wasComposing = composing
        if tokensEnabled {
            // A coordinates-only pass must not prevent enabling colors without an edit.
            work?.cancel(); work = nil
            attempted = false
        }
        if optionsChanged, !options.needsTokens {
            work?.cancel(); work = nil; coloring?.cancel()
            revision = UUID(); snapshot = nil; presentationSnapshot = nil
            clearPresentation()
        }
        if changed || composing || compositionEnded {
            work?.cancel(); work = nil
            coloring?.cancel()
            revision = UUID()
            self.source = source
            snapshot = nil
            attempted = false
            // Never publish a blank gutter during the lexer debounce. This bounded
            // O(source length) coordinate pass is independent of syntax coloring.
            if changed || compositionEnded {
                didUpdateCoordinates?(needsCoordinates && source.utf16.count <= limit ? JSONSourceCoordinates(source) : nil)
            }
            // Native attributes already track edits. Retain the last colors while
            // scanning, but never use the old snapshot for matching/diagnostics.
            if !composing, source.isEmpty || source.utf16.count > limit {
                presentationSnapshot = nil
                clearPresentation()
            }
        }
        guard !composing else { return }
        readSelection()
        if options.needsTokens, !attempted, work == nil {
            attempted = true
            let request = revision
            work = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                let worker = Task.detached(priority: .userInitiated) {
                    let snapshot = options.needsTokens ? (options.syntax == .json ? JSONSyntaxLexer.scan(source, maximumUTF16Length: limit) : options.syntax == .yaml ? YAMLSyntaxLexer.scan(source, limit: limit) : MarkupSyntaxLexer.scan(source, syntax: options.syntax, limit: limit)) : nil
                    return snapshot
                }
                let parsed = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self, self.revision == request else { return }
                self.work = nil
                self.snapshot = parsed
                self.presentationSnapshot = parsed
                self.paint(recolor: true)
            }
        }
        let selectionChanged = selection != paintedSelection
        if changed || optionsChanged || diagnosticChanged || selectionChanged || compositionEnded {
            // Text edits wait for the complete replacement colors, not a plain frame.
            paint(recolor: optionsChanged && !changed, resetDecorations: changed)
            paintedSelection = selection
        }
    }

    private func readSelection() {
        guard let editor else { return }
        #if os(macOS)
        selection = editor.window?.firstResponder === editor ? editor.selectedRange() : NSRange(location: NSNotFound, length: 0)
        guard !editor.hasMarkedText() else { return }
        #else
        selection = editor.isFirstResponder ? editor.selectedRange : NSRange(location: NSNotFound, length: 0)
        guard editor.markedTextRange == nil else { return }
        #endif
    }

    func stop() {
        work?.cancel(); coloring?.cancel()
        revision = UUID()
    }

    private var matches: [NSRange] {
        options.matchingBrackets ? snapshot?.matchingRanges(at: selection) ?? [] : []
    }
    private static func displayRange(_ diagnostic: JSONDiagnostic?, source: String) -> NSRange? {
        guard let diagnostic, !source.isEmpty else { return nil }
        let range = diagnostic.range
        guard range.location >= 0, range.length > 0,
              diagnostic.precision == .exact || range.length <= 64,
              NSMaxRange(range) <= (source as NSString).length else { return nil }
        // EOF/insertion anchors are drawn at the native caret rect, never on a preceding glyph.
        return (source as NSString).rangeOfComposedCharacterSequences(for: range)
    }

    private func clearPresentation() {
        guard let editor else { return }
        #if os(macOS)
        let range = NSRange(location: 0, length: editor.textStorage?.length ?? 0)
        editor.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        editor.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        editor.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
        editor.layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
        backgroundRanges = []
        #else
        if let manager = editor.textLayoutManager, let content = manager.textContentManager {
            manager.invalidateRenderingAttributes(for: content.documentRange)
        }
        editor.setNeedsLayout()
        editor.setNeedsDisplay()
        #endif
    }

    private func paint(recolor: Bool, resetDecorations: Bool = false) {
        guard let editor else { return }
        #if os(macOS)
        guard !editor.hasMarkedText() else { return }
        guard let manager = editor.layoutManager else { return }
        if recolor {
            coloring?.cancel()
            let all = NSRange(location: 0, length: editor.textStorage?.length ?? 0)
            let tokens = snapshot?.tokens ?? []
            let settings = options
            if tokens.isEmpty { manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all) }
            coloring = Task { [weak self, weak manager] in
                for start in stride(from: 0, to: tokens.count, by: 384) {
                    guard !Task.isCancelled, let self, let manager,
                          self.editor?.hasMarkedText() == false else { return }
                    let chunk = tokens[start..<min(start + 384, tokens.count)]
                    let lower = start == 0 ? 0 : tokens[start].range.location
                    let upper = start + 384 >= tokens.count ? all.length : tokens[start + 384].range.location
                    manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: lower, length: upper - lower))
                    for token in chunk {
                        if let color = JSONEditorPalette.foreground(token, options: settings) {
                            manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
                        }
                    }
                    await Task.yield()
                }
            }
        }
        let length = editor.textStorage?.length ?? 0
        if resetDecorations {
            let all = NSRange(location: 0, length: length)
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            manager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
            manager.removeTemporaryAttribute(.underlineColor, forCharacterRange: all)
            backgroundRanges = []
        }
        for range in backgroundRanges where NSMaxRange(range) <= length {
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            manager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
            manager.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
        }
        backgroundRanges = matches + relatedRanges
        // Short dashed/dotted strokes can produce an empty instanced draw in
        // Core Animation on macOS with Metal validation. Solid underlines retain
        // the semantic/color distinction without that fragile stroke path.
        for range in relatedRanges {
            manager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
            manager.addTemporaryAttribute(.underlineColor, value: NSColor.secondaryLabelColor, forCharacterRange: range)
        }
        for range in matches {
            manager.addTemporaryAttribute(.backgroundColor, value: JSONEditorPalette.match, forCharacterRange: range)
            manager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
        }
        if let range = visibleDiagnostic {
            manager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
            manager.addTemporaryAttribute(.underlineColor, value: diagnostic?.severity == .warning ? NSColor.systemOrange : NSColor.systemRed, forCharacterRange: range)
            backgroundRanges.append(range)
        }
        #else
        guard editor.markedTextRange == nil else { return }
        if let manager = editor.textLayoutManager, let content = manager.textContentManager {
            manager.invalidateRenderingAttributes(for: content.documentRange)
            if options.validateVisibleRendering {
                // UIKit can retain laid-out fragments without calling its validator again.
                // Apply render-only colors to the existing viewport, without invalidating
                // document storage, selection, undo or the entire document's layout.
                let visible = manager.textViewportLayoutController.viewportRange ?? content.documentRange
                manager.enumerateTextLayoutFragments(from: visible.location, options: []) { [weak self] fragment in
                    guard fragment.rangeInElement.location.compare(visible.endLocation) == .orderedAscending else {return false}
                    self?.render(fragment: fragment, manager: manager)
                    return true
                }
            }
        }
        editor.setNeedsLayout()
        editor.setNeedsDisplay()
        #endif
    }

    #if !os(macOS)
    private func render(fragment: NSTextLayoutFragment, manager: NSTextLayoutManager) {
        guard let editor, editor.markedTextRange == nil, let content = manager.textContentManager else { return }
        let range = fragment.rangeInElement
        let start = content.offset(from: content.documentRange.location, to: range.location)
        let end = content.offset(from: content.documentRange.location, to: range.endLocation)
        guard start >= 0, end >= start else { return }
        let fragmentRange = NSRange(location: start, length: end - start)
        // Rendering attributes belong to TextKit, not the document's attributed string.
        manager.setRenderingAttributes([.foregroundColor: JSONEditorPalette.base], for: range)
        func textRange(_ nsRange: NSRange) -> NSTextRange? {
            let clipped = NSIntersectionRange(nsRange, fragmentRange)
            guard clipped.length > 0,
                  let from = content.location(content.documentRange.location, offsetBy: clipped.location),
                  let to = content.location(from, offsetBy: clipped.length) else { return nil }
            return NSTextRange(location: from, end: to)
        }
        if let snapshot = presentationSnapshot {
            for index in snapshot.tokenIndices(intersecting: fragmentRange) {
                let token = snapshot.tokens[index]
                if let color = JSONEditorPalette.foreground(token, options: options), let range = textRange(token.range) {
                    manager.setRenderingAttributes([.foregroundColor: color], for: range)
                }
            }
        }
        for related in relatedRanges {
            if let range = textRange(related) {
                manager.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, for: range)
                manager.addRenderingAttribute(.underlineColor, value: UIColor.secondaryLabel, for: range)
            }
        }
        for match in matches {
            if let range = textRange(match) {
                manager.addRenderingAttribute(.backgroundColor, value: JSONEditorPalette.match, for: range)
                manager.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, for: range)
            }
        }
        if let display = visibleDiagnostic, let range = textRange(display) {
            manager.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, for: range)
            manager.addRenderingAttribute(.underlineColor, value: diagnostic?.severity == .warning ? UIColor.systemOrange : UIColor.systemRed, for: range)
        }
    }
    #endif
}
