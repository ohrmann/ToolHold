import SwiftUI
#if SWIFT_PACKAGE
import JSONCore
#endif
#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
#endif

/// Native geometry is the only authority for soft wraps, glyphs, bidi and caret positions.
/// The overlay is hit-test transparent; none of these decorations enter the document.
@MainActor final class JSONEditorAdornments {
    private weak var editor: JSONNativeTextView?
    private(set) var coordinates: JSONSourceCoordinates?
    private(set) var diagnostic: JSONDiagnostic?
    private(set) var showsGutter = false
    private(set) var navigationHighlight: NSRange?
    private(set) var navigationHighlightOpacity: CGFloat = 0
    private var navigationHighlightTask: Task<Void, Never>?
    private var navigationHighlightID = UUID()
    private var matches: TextEditorHighlights?
    private var gutterWidth: CGFloat = 30
    private lazy var overlay = JSONAdornmentOverlay(adornments: self)
    #if os(macOS)
    private var ruler: JSONLineRuler?
    #endif
    init(editor: JSONNativeTextView) { self.editor = editor }

    /// Presentation-only decoration. No text attributes, selection or Undo changes.
    func showNavigationHighlight(_ range: NSRange, animated: Bool) {
        cancelNavigationHighlight()
        guard let editor, editor.window != nil else { return }
        #if os(macOS)
        let source = editor.string as NSString
        #else
        let source = (editor.text ?? "") as NSString
        #endif
        guard range.location >= 0, range.location <= source.length, range.length >= 0 else { return }
        let bounded = NSRange(location: range.location, length: min(80, min(range.length, source.length - range.location)))
        let composed: NSRange
        if bounded.length > 0 { composed = source.rangeOfComposedCharacterSequences(for: bounded) }
        else if bounded.location < source.length { composed = source.rangeOfComposedCharacterSequence(at: bounded.location) }
        else { composed = bounded }
        navigationHighlight = composed.length <= 128 ? composed : NSRange(location: composed.location, length: 0)
        navigationHighlightOpacity = animated ? 0 : 0.24
        redrawNavigationHighlight()
        let request = UUID(), start = ContinuousClock.now
        navigationHighlightID = request
        navigationHighlightTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.navigationHighlightID == request, self.editor?.window != nil else { break }
                let elapsed = start.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                guard seconds < 2 else { break }
                // Two quiet one-second pulses, beginning/ending transparent.
                if animated { self.navigationHighlightOpacity = 0.24 * pow(sin(.pi * seconds), 2) }
                self.redrawNavigationHighlight()
                do {
                    if animated { try await Task.sleep(for: .milliseconds(32)) }
                    else {
                        // Expire relative to presentation, even if this task starts late.
                        try await Task.sleep(until: start.advanced(by: .seconds(2)),
                                             tolerance: .milliseconds(10), clock: .continuous)
                    }
                } catch { break }
            }
            guard let self, self.navigationHighlightID == request else { return }
            self.cancelNavigationHighlight()
        }
    }
    func cancelNavigationHighlight() {
        guard navigationHighlight != nil || navigationHighlightTask != nil else { return }
        navigationHighlightID = UUID()
        navigationHighlightTask?.cancel(); navigationHighlightTask = nil
        navigationHighlight = nil; navigationHighlightOpacity = 0
        redrawNavigationHighlight()
    }
    private func redrawNavigationHighlight() {
        #if os(macOS)
        overlay.needsDisplay = true
        #else
        overlay.setNeedsDisplay()
        #endif
    }

    /// Visible native glyph rectangles, also used by focused geometry tests.
    func navigationHighlightRects() -> [CGRect] {
        guard let range = navigationHighlight else { return [] }
        return rectangles(for: range)
    }
    private func rectangles(for range: NSRange) -> [CGRect] {
        guard let editor else { return [] }
        #if os(macOS)
        guard !editor.hasMarkedText() else { return [] }
        let viewport = editor.visibleRect
        #else
        guard editor.markedTextRange == nil else { return [] }
        let viewport = editor.bounds
        #endif
        if range.length == 0 {
            guard let caret = caretRect(at: range.location), caret.intersects(viewport) else { return [] }
            return [CGRect(x: caret.minX, y: caret.minY, width: 6, height: caret.height)]
        }
        guard NSIntersectionRange(range, visibleOffsets).length > 0 else { return [] }
        var rects: [CGRect] = []
        #if os(macOS)
        guard let manager = editor.layoutManager, let container = editor.textContainer else { return [] }
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            rects.append(rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y))
        }
        #else
        guard let start = editor.position(from: editor.beginningOfDocument, offset: range.location),
              let end = editor.position(from: start, offset: range.length), let textRange = editor.textRange(from: start, to: end) else { return [] }
        rects = editor.selectionRects(for: textRange).map(\.rect)
        #endif
        return rects.compactMap { rect in
            guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite,
                  rect.minX.isFinite, rect.minY.isFinite, rect.intersects(viewport) else { return nil }
            return rect.intersection(viewport)
        }
    }
    private func drawNavigationHighlight() {
        guard navigationHighlightOpacity > 0, let editor, let context = currentContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        #if os(macOS)
        let color = NSColor.systemYellow
        context.clip(to: editor.visibleRect)
        #else
        let color = UIColor.systemYellow
        let viewport = editor.bounds, gutter = showsGutter ? gutterWidth + 2 : 0
        context.clip(to: CGRect(x: viewport.minX + gutter, y: viewport.minY,
                               width: max(0, viewport.width - gutter), height: viewport.height))
        #endif
        context.setFillColor(color.withAlphaComponent(navigationHighlightOpacity).cgColor)
        for rect in navigationHighlightRects() {
            // Filled geometry avoids wide-line strokes and never changes native text.
            let shape = CGPath(roundedRect: rect.insetBy(dx: -1, dy: 0), cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(shape); context.fillPath()
        }
    }

    func updateMatches(_ value: TextEditorHighlights?) {
        if matches?.id == value?.id { return }
        matches = value
        redrawNavigationHighlight()
    }
    private func drawMatches() {
        guard let matches, let editor, let context = currentContext else { return }
        #if os(macOS)
        let text = editor.string
        #else
        let text = editor.text ?? ""
        #endif
        guard text.utf16.elementsEqual(matches.source.utf16) else { return }
        let visible = visibleOffsets
        var lo = 0, hi = matches.ranges.count
        while lo < hi { let m = (lo + hi) / 2; if NSMaxRange(matches.ranges[m]) < visible.location { lo = m + 1 } else { hi = m } }
        func draw(_ range: NSRange, active: Bool) {
            guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= text.utf16.count else { return }
            let r = range.length == 0 ? range : (text as NSString).rangeOfComposedCharacterSequences(for: NSIntersectionRange(range, visible))
            context.setFillColor(PlatformColor.systemYellow.withAlphaComponent(active ? 0.35 : 0.14).cgColor)
            for rect in rectangles(for: r) { context.fill(rect); if active { context.setStrokeColor(PlatformColor.systemOrange.cgColor); context.stroke(rect, width: 1) } }
        }
        var i = lo
        while i < matches.ranges.count, matches.ranges[i].location <= NSMaxRange(visible) { draw(matches.ranges[i], active: matches.ranges[i] == matches.active); i += 1 }
        if let capture = matches.capture, capture.location <= NSMaxRange(visible), NSMaxRange(capture) >= visible.location { draw(capture, active: true) }
    }

    func install() {
        guard let editor else { return }
        #if os(macOS)
        editor.addSubview(overlay)
        #else
        overlay.isUserInteractionEnabled = false
        overlay.isAccessibilityElement = false
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        editor.addSubview(overlay)
        #endif
    }
    func update(diagnostic: JSONDiagnostic?, showsGutter: Bool) {
        self.diagnostic = diagnostic
        self.showsGutter = showsGutter
        updateViewport()
    }
    func setCoordinates(_ coordinates: JSONSourceCoordinates?) {
        self.coordinates = coordinates
        if let coordinates {
            let digits = String(coordinates.lineStarts.count).count
            gutterWidth = min(52, max(30, CGFloat(digits) * 7 + 15))
        }
        updateViewport()
    }
    func updateViewport() {
        guard let editor else { return }
        #if os(macOS)
        if let scroll = editor.enclosingScrollView {
            if showsGutter, ruler == nil {
                let ruler = JSONLineRuler(scrollView: scroll, adornments: self)
                self.ruler = ruler
                scroll.verticalRulerView = ruler
                scroll.hasVerticalRuler = true
            }
            if scroll.rulersVisible != showsGutter { scroll.rulersVisible = showsGutter }
            if ruler?.ruleThickness != gutterWidth { ruler?.ruleThickness = gutterWidth }
            ruler?.needsDisplay = true
        }
        overlay.frame = editor.visibleRect
        overlay.needsDisplay = true
        #else
        let inset = showsGutter ? gutterWidth + 8 : 8
        if editor.textContainerInset.left != inset {
            editor.textContainerInset.left = inset
        }
        overlay.frame = editor.bounds
        editor.bringSubviewToFront(overlay)
        overlay.setNeedsDisplay()
        #endif
    }

    func caretRect(at offset: Int) -> CGRect? {
        guard let editor, offset >= 0 else { return nil }
        #if os(macOS)
        guard offset <= (editor.textStorage?.length ?? 0), let window = editor.window else { return nil }
        let rect = editor.firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
        guard rect.height > 0, rect.width.isFinite, rect.minX.isFinite else { return nil }
        return editor.convert(window.convertFromScreen(rect), from: nil)
        #else
        guard let position = editor.position(from: editor.beginningOfDocument, offset: offset) else { return nil }
        let rect = editor.caretRect(for: position)
        return rect.height > 0 && rect.minX.isFinite ? rect : nil
        #endif
    }
    private var visibleOffsets: NSRange {
        guard let editor else { return NSRange(location: 0, length: 0) }
        #if os(macOS)
        guard let manager = editor.layoutManager, let container = editor.textContainer else { return NSRange(location: 0, length: 0) }
        let bounds = editor.visibleRect.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: bounds, in: container)
        return manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        #else
        let x = editor.contentOffset.x + editor.textContainerInset.left + 2
        let top = editor.closestPosition(to: CGPoint(x: x, y: editor.contentOffset.y)) ?? editor.beginningOfDocument
        let bottom = editor.closestPosition(to: CGPoint(x: editor.bounds.maxX - editor.textContainerInset.right,
                                                       y: editor.contentOffset.y + editor.bounds.height)) ?? editor.endOfDocument
        let start = editor.offset(from: editor.beginningOfDocument, to: top)
        let end = editor.offset(from: editor.beginningOfDocument, to: bottom)
        return NSRange(location: max(0, start), length: max(0, end - start))
        #endif
    }
    func drawGutter(convert: (CGRect) -> CGRect, width: CGFloat, bounds: CGRect) {
        guard showsGutter, let coordinates else { return }
        #if os(macOS)
        let background = NSColor.controlBackgroundColor
        let secondary = NSColor.secondaryLabelColor
        #else
        let background = UIColor.secondarySystemBackground
        let secondary = UIColor.secondaryLabel
        #endif
        background.setFill()
        #if os(macOS)
        NSBezierPath(rect: bounds).fill()
        #else
        UIBezierPath(rect: bounds).fill()
        #endif
        let visible = visibleOffsets
        let first = max(1, coordinates.location(at: visible.location).line)
        let last = min(coordinates.lineStarts.count, coordinates.location(at: NSMaxRange(visible)).line + 1)
        guard first <= last else { return }
        for line in first...min(last, first + 180) {
            guard let rect = caretRect(at: coordinates.lineStarts[line - 1]) else { continue }
            let local = convert(rect)
            guard local.maxY >= bounds.minY, local.minY <= bounds.maxY else { continue }
            let marked = diagnostic?.line == line
            let color: PlatformColor = marked ? (diagnostic?.severity == .warning ? .systemOrange : .systemRed) : secondary
            let label = String(line) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: PlatformFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: color]
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: bounds.minX + width - size.width - 5, y: local.minY + max(0, (local.height - size.height) / 2)), withAttributes: attributes)
            if marked { triangle(at: CGPoint(x: bounds.minX + 3, y: local.midY - 3), color: color) }
        }
        if let diagnostic, diagnostic.range.location >= visible.location,
           diagnostic.range.location <= NSMaxRange(visible) + 1,
           let rect = caretRect(at: diagnostic.range.location) {
            let local = convert(rect)
            if local.maxY >= bounds.minY, local.minY <= bounds.maxY {
                triangle(at: CGPoint(x: bounds.minX + 3, y: local.midY - 3),
                         color: diagnostic.severity == .warning ? .systemOrange : .systemRed)
            }
        }
    }
    func drawMarkers() {
        guard let editor, let diagnostic else { return }
        #if os(macOS)
        guard !editor.hasMarkedText() else { return }
        let viewport = editor.visibleRect
        #else
        guard editor.markedTextRange == nil else { return }
        let viewport = editor.bounds
        #endif
        let visible = visibleOffsets
        let position = diagnostic.range.location
        #if !os(macOS)
        // Draw diagnostic strokes independently of TextKit color presentation, from
        // native selection geometry without changing the actual selection.
        if diagnostic.range.length > 0, diagnostic.range.length <= 256,
           diagnostic.precision == .exact || diagnostic.range.length <= 64,
           NSIntersectionRange(diagnostic.range, visible).length > 0,
           let start = editor.position(from: editor.beginningOfDocument, offset: position),
           let end = editor.position(from: start, offset: diagnostic.range.length),
           let range = editor.textRange(from: start, to: end) {
            let context = currentContext
            context?.saveGState()
            context?.clip(to: CGRect(x: viewport.minX + (showsGutter ? gutterWidth + 2 : 0),
                                    y: viewport.minY, width: viewport.width - (showsGutter ? gutterWidth + 2 : 0), height: viewport.height))
            context?.setStrokeColor((diagnostic.severity == .warning ? UIColor.systemOrange : UIColor.systemRed).cgColor)
            context?.setLineWidth(1.5)
            context?.setLineDash(phase: 0, lengths: [2, 2])
            for selection in editor.selectionRects(for: range) where selection.rect.intersects(viewport) && selection.rect.width > 0 {
                let rect = selection.rect
                context?.move(to: CGPoint(x: rect.minX, y: rect.maxY - 2))
                context?.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2))
                context?.strokePath()
            }
            context?.restoreGState()
        }
        #endif
        // Never force layout of a far-away anchor merely to paint an offscreen marker.
        if diagnostic.range.length == 0, position >= visible.location, position <= NSMaxRange(visible) + 1,
           let rect = caretRect(at: position), rect.intersects(viewport.insetBy(dx: -4, dy: -4)) {
            let color: PlatformColor = diagnostic.severity == .warning ? .systemOrange : .systemRed
            let context = currentContext
            // Filled geometry avoids the Core Animation wide-line Metal path,
            // including degenerate strokes during scrolling/layout transitions.
            context?.setFillColor(color.cgColor)
            context?.fill(CGRect(x: rect.minX, y: rect.minY + 2, width: 1.5, height: max(1, rect.height - 4)))
            triangle(at: CGPoint(x: rect.minX - 3, y: rect.maxY - 4), color: color)
            if position == coordinates?.utf16Length {
                let x = rect.minX + 28 < viewport.maxX ? rect.minX + 4 : rect.minX - 24
                ("EOF" as NSString).draw(at: CGPoint(x: x, y: rect.minY), withAttributes: [.font: PlatformFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: color])
            }
        }
        for location in diagnostic.related.prefix(3) {
            let offset = location.range.location
            guard offset >= visible.location, offset <= NSMaxRange(visible),
                  let rect = caretRect(at: offset), rect.intersects(viewport) else { continue }
            #if os(macOS)
            let secondary = NSColor.secondaryLabelColor
            #else
            let secondary = UIColor.secondaryLabel
            #endif
            let box = CGRect(x: rect.minX - 2, y: rect.maxY - 4, width: 5, height: 3)
            currentContext?.setFillColor(secondary.cgColor)
            currentContext?.fill([CGRect(x: box.minX, y: box.minY, width: 5, height: 1),
                                  CGRect(x: box.minX, y: box.maxY - 1, width: 5, height: 1),
                                  CGRect(x: box.minX, y: box.minY, width: 1, height: 3),
                                  CGRect(x: box.maxX - 1, y: box.minY, width: 1, height: 3)])
        }
    }
    private var currentContext: CGContext? {
        #if os(macOS)
        NSGraphicsContext.current?.cgContext
        #else
        UIGraphicsGetCurrentContext()
        #endif
    }
    private func triangle(at point: CGPoint, color: PlatformColor) {
        guard let context = currentContext else { return }
        context.setFillColor(color.cgColor)
        context.move(to: point)
        context.addLine(to: CGPoint(x: point.x + 6, y: point.y))
        context.addLine(to: CGPoint(x: point.x + 3, y: point.y + 5))
        context.closePath(); context.fillPath()
    }
    func drawOverlay() {
        guard let editor else { return }
        #if os(macOS)
        let viewport = editor.visibleRect
        #else
        let viewport = editor.bounds
        #endif
        currentContext?.saveGState()
        currentContext?.translateBy(x: -viewport.minX, y: -viewport.minY)
        #if !os(macOS)
        drawGutter(convert: { $0 }, width: gutterWidth,
                   bounds: CGRect(x: viewport.minX, y: viewport.minY, width: showsGutter ? gutterWidth : 0, height: viewport.height))
        #endif
        drawMatches()
        drawNavigationHighlight()
        drawMarkers()
        currentContext?.restoreGState()
    }
}

#if os(macOS)
@MainActor private final class JSONAdornmentOverlay: NSView {
    weak var adornments: JSONEditorAdornments?
    init(adornments: JSONEditorAdornments) { self.adornments = adornments; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { adornments?.drawOverlay() }
}
@MainActor private final class JSONLineRuler: NSRulerView {
    weak var adornments: JSONEditorAdornments?
    init(scrollView: NSScrollView, adornments: JSONEditorAdornments) {
        self.adornments = adornments
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = scrollView.documentView
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let clientView else { return }
        adornments?.drawGutter(convert: { self.convert($0, from: clientView) }, width: ruleThickness, bounds: bounds)
    }
}
#else
@MainActor private final class JSONAdornmentOverlay: UIView {
    weak var adornments: JSONEditorAdornments?
    init(adornments: JSONEditorAdornments) { self.adornments = adornments; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ rect: CGRect) { adornments?.drawOverlay() }
}
#endif
