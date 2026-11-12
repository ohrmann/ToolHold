import SwiftUI
#if os(macOS)
import AppKit
private typealias GridColor = NSColor
private typealias GridFont = NSFont
#else
import UIKit
private typealias GridColor = UIColor
private typealias GridFont = UIFont
#endif

private func gridFill(_ rect: CGRect) {
    #if os(macOS)
    rect.fill()
    #else
    UIRectFill(rect)
    #endif
}

/// A viewport-sized native drawing surface over a native two-axis scroll view.
/// Work and accessibility elements are bounded by the viewport, never rows × columns.
@MainActor final class CSVGridState {
    var document: CSVTableDocument?
    var projection: CSVTableProjection?
    var selection: CSVTableSelection?
    var width: CGFloat = 180
    var rowHeight: CGFloat = 40
    let gutter: CGFloat = 54
    var select: (CSVTableSelection) -> Void = { _ in }
    var activate: (CSVTableSelection) -> Void = { _ in }
    var sort: (Int) -> Void = { _ in }
    var key: (String) -> Void = { _ in }
    var scrollRequest = 0
    var reduced = false
    var contentSize: CGSize {
        .init(width: gutter + CGFloat(document?.columnCount ?? 0) * width,
              height: CGFloat((projection?.rows.count ?? 0) + 1) * rowHeight)
    }
    func hit(_ point: CGPoint, offset: CGPoint, activate: Bool = false) {
        guard let document, let projection, point.x >= gutter else { return }
        let column = Int((point.x + offset.x - gutter) / width)
        guard column >= 0, column < document.columnCount else { return }
        if point.y < rowHeight { if !activate { sort(column) }; return }
        let displayRow = Int((point.y + offset.y) / rowHeight) - 1
        guard displayRow >= 0, displayRow < projection.rows.count else { return }
        let selection = CSVTableSelection(row: projection.rows[displayRow], column: column)
        if document.cellIndex(selection) != nil {
            select(selection)
            if activate { self.activate(selection) }
        }
    }
    func target(viewport: CGSize, current: CGPoint) -> CGPoint? {
        guard let selection, let projection, selection.row < projection.positions.count else { return nil }
        let position = projection.positions[selection.row]
        guard position >= 0 else { return nil }
        let rect = CGRect(x: gutter + CGFloat(selection.column) * width, y: CGFloat(position + 1) * rowHeight, width: width, height: rowHeight)
        var target = current
        if rect.minX < current.x + gutter { target.x = rect.minX - gutter }
        else if rect.maxX > current.x + viewport.width { target.x = rect.maxX - viewport.width }
        if rect.minY < current.y + rowHeight { target.y = rect.minY - rowHeight }
        else if rect.maxY > current.y + viewport.height { target.y = rect.maxY - viewport.height }
        target.x = min(max(0, contentSize.width - viewport.width), max(0, target.x))
        target.y = min(max(0, contentSize.height - viewport.height), max(0, target.y))
        return target
    }
    struct VisibleCell { let rect: CGRect; let label: String; let row: Int?; let column: Int }
    @discardableResult func draw(_ bounds: CGRect, offset: CGPoint) -> [VisibleCell] {
        #if os(macOS)
        let background = GridColor.textBackgroundColor, header = GridColor.controlBackgroundColor
        let foreground = GridColor.labelColor, secondary = GridColor.secondaryLabelColor, line = GridColor.separatorColor
        #else
        let background = GridColor.systemBackground, header = GridColor.secondarySystemBackground
        let foreground = GridColor.label, secondary = GridColor.secondaryLabel, line = GridColor.separator
        #endif
        background.setFill(); gridFill(bounds)
        guard let document, let projection, bounds.width > gutter, bounds.height > 0 else { return [] }
        let font = GridFont.monospacedSystemFont(ofSize: max(12, min(20, rowHeight * 0.34)), weight: .regular)
        let headerFont = GridFont.systemFont(ofSize: font.pointSize, weight: .medium)
        let firstColumn = max(0, Int(offset.x / width))
        let lastColumn = min(document.columnCount, Int((offset.x + bounds.width - gutter) / width) + 1)
        let firstRow = max(0, Int(offset.y / rowHeight))
        let lastRow = min(projection.rows.count, Int((offset.y + bounds.height) / rowHeight) + 1)
        var accessible: [VisibleCell] = []
        func paint(_ rect: CGRect, _ text: String, heading: Bool = false, selected: Bool = false, matches: [NSRange] = [], muted: Bool = false) {
            (selected ? GridColor.systemGreen.withAlphaComponent(0.17) : heading ? header : background).setFill(); gridFill(rect)
            line.withAlphaComponent(0.5).setFill()
            gridFill(CGRect(x: rect.maxX - 0.5, y: rect.minY, width: 0.5, height: rect.height))
            gridFill(CGRect(x: rect.minX, y: rect.maxY - 0.5, width: rect.width, height: 0.5))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let attributed = NSMutableAttributedString(string: text, attributes: [.font: heading ? headerFont : font, .foregroundColor: muted ? secondary : foreground, .paragraphStyle: paragraph])
            for range in matches where NSMaxRange(range) <= attributed.length {
                attributed.addAttributes([.backgroundColor: GridColor.systemYellow.withAlphaComponent(0.3), .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            }
            let height = font.pointSize + 5
            attributed.draw(in: rect.insetBy(dx: 9, dy: max(4, (rect.height - height) / 2)))
        }
        if firstRow < lastRow, firstColumn < lastColumn {
            for displayRow in firstRow..<lastRow {
                let row = projection.rows[displayRow], record = document.record(row)
                let y = CGFloat(displayRow + 1) * rowHeight - offset.y
                for column in firstColumn..<lastColumn {
                    let rect = CGRect(x: gutter + CGFloat(column) * width - offset.x, y: y, width: width, height: rowHeight)
                    let selection = CSVTableSelection(row: row, column: column)
                    if let index = document.cellIndex(selection) {
                        let preview = projection.previews[index] ?? document.previews[index]
                        let text = preview.text.isEmpty ? "∅ empty" : preview.text
                        paint(rect, text, selected: self.selection == selection, matches: preview.matches, muted: preview.text.isEmpty)
                        accessible.append(.init(rect: rect, label: "Data row \(row + 1), column \(column + 1), \(document.header(column)), \(text)", row: row, column: column))
                    } else {
                        paint(rect, "— missing", muted: true)
                    }
                }
                // Pinned data-record ordinal, independent of filtering/sorting and source lines.
                let rect = CGRect(x: 0, y: y, width: gutter, height: rowHeight)
                paint(rect, "\(row + 1)\(record.cells.count == document.columnCount ? "" : " !")", heading: true)
            }
        }
        if firstColumn < lastColumn {
            for column in firstColumn..<lastColumn {
                let rect = CGRect(x: gutter + CGFloat(column) * width - offset.x, y: 0, width: width, height: rowHeight)
                let indicator = projection.sort?.column == column ? (projection.sort?.ascending == true ? " ↑" : " ↓") : ""
                paint(rect, document.header(column) + indicator, heading: true)
                accessible.append(.init(rect: rect, label: "Column \(column + 1), \(document.header(column)). Sort as text\(indicator)", row: nil, column: column))
            }
        }
        paint(CGRect(x: 0, y: 0, width: gutter, height: rowHeight), "Row", heading: true)
        return accessible
    }
}

#if os(macOS)
final class CSVGridScrollView: NSScrollView {
    var onInteraction: (() -> Void)?
    override func scrollWheel(with event: NSEvent) { onInteraction?(); super.scrollWheel(with: event) }
}
private final class CSVGridDocumentView: NSView {
    weak var host: CSVGridHost?
    private struct MouseGesture {
        let location: NSPoint
        let offset: CGPoint
        let viewportPoint: CGPoint
        let document: UUID
        let projection: UUID
        let clicks: Int
        var panning = false
    }
    private var mouseGesture: MouseGesture?
    private var handCursor = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        cancelPan()
        guard let host else { return }
        window?.makeFirstResponder(self)
        host.stopAnimation()
        let point = convert(event.locationInWindow, from: nil)
        let offset = host.scroll.contentView.bounds.origin
        let viewport = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
        guard viewport.x >= host.state.gutter, viewport.y >= host.state.rowHeight,
              let document = host.state.document, let projection = host.state.projection else {
            host.state.hit(viewport, offset: offset, activate: event.clickCount == 2)
            return
        }
        mouseGesture = .init(location: event.locationInWindow, offset: offset, viewportPoint: viewport,
                             document: document.id, projection: projection.id, clicks: event.clickCount)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let host, var gesture = mouseGesture else { return }
        guard host.state.document?.id == gesture.document, host.state.projection?.id == gesture.projection else { cancelPan(); return }
        let dx = event.locationInWindow.x - gesture.location.x
        let dy = event.locationInWindow.y - gesture.location.y
        guard gesture.panning || hypot(dx, dy) >= 5 else { return }
        if !gesture.panning {
            gesture.panning = true; mouseGesture = gesture
            NSCursor.closedHand.push(); handCursor = true
        }
        // Window coordinates increase upwards; the document's vertical axis points down.
        host.pan(to: .init(x: gesture.offset.x - dx, y: gesture.offset.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        guard let host, let gesture = mouseGesture else { return }
        cancelPan()
        guard !gesture.panning, host.state.document?.id == gesture.document,
              host.state.projection?.id == gesture.projection else { return }
        host.state.hit(gesture.viewportPoint, offset: gesture.offset, activate: gesture.clicks == 2)
    }
    func cancelPan() {
        mouseGesture = nil
        if handCursor { NSCursor.pop(); handCursor = false }
    }
    override func cancelOperation(_ sender: Any?) { cancelPan(); host?.stopAnimation() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelPan() }
    }
    override func keyDown(with event: NSEvent) {
        cancelPan()
        let key: String?
        switch event.keyCode { case 123: key = "left"; case 124: key = "right"; case 125: key = "down"; case 126: key = "up"; default: key = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" ? "copy" : nil }
        if let key { host?.state.key(key) } else { super.keyDown(with: event) }
    }
}
private final class CSVGridAXCell: NSAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { action?(); return true }
}
private final class CSVGridCanvas: NSView {
    weak var host: CSVGridHost?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let host else { return }
        let cells = host.state.draw(bounds, offset: host.scroll.contentView.bounds.origin)
        setAccessibilityChildren(cells.filter { $0.rect.intersects(bounds) }.map { cell in
            let element = CSVGridAXCell()
            element.setAccessibilityRole(cell.row == nil ? .button : .cell)
            element.setAccessibilityLabel(cell.label); element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(cell.rect, to: nil)) ?? .zero)
            element.action = { [weak host] in
                if let row = cell.row { host?.state.select(.init(row: row, column: cell.column)) }
                else { host?.state.sort(cell.column) }
            }
            return element
        })
    }
}
final class CSVGridHost: NSView {
    fileprivate let state = CSVGridState()
    let scroll = CSVGridScrollView()
    private let content = CSVGridDocumentView()
    private let canvas = CSVGridCanvas()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        // Reserve native mouse-draggable rails instead of transient overlay indicators.
        scroll.scrollerStyle = .legacy; scroll.autohidesScrollers = false
        scroll.drawsBackground = false; scroll.documentView = content
        scroll.contentView.postsBoundsChangedNotifications = true
        content.host = self; canvas.host = self; canvas.setAccessibilityElement(false)
        addSubview(scroll); addSubview(canvas)
        scroll.onInteraction = { [weak self] in self?.content.cancelPan(); self?.stopAnimation() }
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.canvas.needsDisplay = true }
        })
        // Native live-scroll notifications describe user interaction; ordinary bounds
        // notifications are also posted asynchronously by AppKit during our own animation.
        observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.content.cancelPan(); self?.stopAnimation() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? NSWindow) === self.window else { return }
                self.content.cancelPan(); self.stopAnimation()
            }
        })
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) }; timer?.invalidate() }
    override func layout() {
        super.layout(); scroll.frame = bounds; canvas.frame = scroll.contentView.convert(scroll.contentView.bounds, to: self)
        content.setFrameSize(CGSize(width: max(scroll.contentSize.width, state.contentSize.width), height: max(scroll.contentSize.height, state.contentSize.height)))
        canvas.needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) { content.cancelPan(); stopAnimation(); super.scrollWheel(with: event) }
    fileprivate func cancelPan() { content.cancelPan() }
    fileprivate func pan(to point: CGPoint) {
        stopAnimation()
        let size = scroll.contentSize
        setOffset(.init(x: min(max(0, state.contentSize.width - size.width), max(0, point.x)),
                        y: min(max(0, state.contentSize.height - size.height), max(0, point.y))))
    }
    func refresh(scrollToSelection: Bool) {
        needsLayout = true; layoutSubtreeIfNeeded(); canvas.needsDisplay = true
        let point = scroll.contentView.bounds.origin
        let clamped = CGPoint(x: max(0, min(point.x, state.contentSize.width - scroll.contentSize.width)), y: max(0, min(point.y, state.contentSize.height - scroll.contentSize.height)))
        if clamped != point { setOffset(clamped) }
        if scrollToSelection, let target = state.target(viewport: scroll.contentSize, current: scroll.contentView.bounds.origin) { animate(to: target) }
    }
    private func setOffset(_ point: CGPoint) {
        scroll.contentView.scroll(to: point); scroll.reflectScrolledClipView(scroll.contentView)
        canvas.needsDisplay = true
    }
    fileprivate func stopAnimation() { timer?.invalidate(); timer = nil }
    private func animate(to target: CGPoint) {
        stopAnimation()
        let start = scroll.contentView.bounds.origin
        guard !state.reduced, start != target else { setOffset(target); return }
        let began = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.22), p = t * t * (3 - 2 * t)
                self.setOffset(.init(x: start.x + (target.x - start.x) * p, y: start.y + (target.y - start.y) * p))
                if t == 1 { self.stopAnimation() }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
}
struct CSVTableGrid: NSViewRepresentable {
    let document: CSVTableDocument?
    let projection: CSVTableProjection?
    let selection: CSVTableSelection?
    let columnWidth: Double
    let scrollRequest: Int
    let reduced: Bool
    let onSelect: (CSVTableSelection) -> Void
    let onActivate: (CSVTableSelection) -> Void
    let onSort: (Int) -> Void
    let onKey: (String) -> Void
    func makeNSView(context: Context) -> CSVGridHost { CSVGridHost() }
    func updateNSView(_ view: CSVGridHost, context: Context) {
        let sourceChanged = view.state.document?.id != document?.id
        let requestChanged = view.state.scrollRequest != scrollRequest
        if sourceChanged || view.state.projection?.id != projection?.id || requestChanged { view.cancelPan(); view.stopAnimation() }
        view.state.document = document; view.state.projection = projection; view.state.selection = selection
        view.state.width = columnWidth; view.state.reduced = reduced; view.state.scrollRequest = scrollRequest
        view.state.select = onSelect; view.state.activate = onActivate; view.state.sort = onSort; view.state.key = onKey
        if sourceChanged { view.scroll.contentView.scroll(to: .zero) }
        view.refresh(scrollToSelection: requestChanged)
    }
}
#else
private final class CSVGridAXCell: UIAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityActivate() -> Bool { action?(); return true }
}
private final class CSVGridCanvas: UIView {
    weak var host: CSVGridHost?
    override func draw(_ rect: CGRect) {
        guard let host else { return }
        let cells = host.state.draw(bounds, offset: host.scroll.contentOffset)
        accessibilityElements = cells.filter { $0.rect.intersects(bounds) }.map { cell in
            let element = CSVGridAXCell(accessibilityContainer: self)
            element.accessibilityLabel = cell.label
            element.accessibilityTraits = cell.row == nil ? .button : .staticText
            element.accessibilityFrameInContainerSpace = cell.rect.intersection(bounds)
            element.action = { [weak host] in
                if let row = cell.row { host?.state.select(.init(row: row, column: cell.column)) }
                else { host?.state.sort(cell.column) }
            }
            return element
        }
    }
}
final class CSVGridHost: UIView, UIScrollViewDelegate {
    fileprivate let state = CSVGridState()
    let scroll = UIScrollView()
    private let canvas = CSVGridCanvas()
    override var canBecomeFirstResponder: Bool { true }
    override init(frame: CGRect) {
        super.init(frame: frame); scroll.delegate = self; scroll.alwaysBounceVertical = false
        scroll.keyboardDismissMode = .onDrag
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        scroll.addGestureRecognizer(singleTap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)
        canvas.host = self; canvas.isUserInteractionEnabled = false; canvas.isAccessibilityElement = false
        addSubview(scroll); addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); scroll.frame = bounds; canvas.frame = bounds; scroll.contentSize = state.contentSize; canvas.setNeedsDisplay() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { canvas.setNeedsDisplay() }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { scroll.setContentOffset(scroll.contentOffset, animated: false) }
    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        becomeFirstResponder()
        let point = recognizer.location(in: scroll)
        state.hit(CGPoint(x: point.x - scroll.contentOffset.x, y: point.y - scroll.contentOffset.y), offset: scroll.contentOffset, activate: recognizer.numberOfTapsRequired == 2)
    }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow, UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].map { UIKeyCommand(input: $0, modifierFlags: [], action: #selector(arrow(_:))) } + [UIKeyCommand(input: "c", modifierFlags: .command, action: #selector(copyCell))]
    }
    @objc private func arrow(_ command: UIKeyCommand) {
        let keys = [UIKeyCommand.inputUpArrow: "up", UIKeyCommand.inputDownArrow: "down", UIKeyCommand.inputLeftArrow: "left", UIKeyCommand.inputRightArrow: "right"]
        if let key = keys[command.input ?? ""] { state.key(key) }
    }
    @objc private func copyCell() { state.key("copy") }
    func refresh(scrollToSelection: Bool) {
        setNeedsLayout(); layoutIfNeeded(); canvas.setNeedsDisplay()
        let current = scroll.contentOffset
        let clamped = CGPoint(x: max(0, min(current.x, state.contentSize.width - bounds.width)), y: max(0, min(current.y, state.contentSize.height - bounds.height)))
        if current != clamped { scroll.setContentOffset(clamped, animated: false) }
        if scrollToSelection, let target = state.target(viewport: bounds.size, current: scroll.contentOffset) { scroll.setContentOffset(target, animated: !state.reduced) }
    }
}
struct CSVTableGrid: UIViewRepresentable {
    let document: CSVTableDocument?
    let projection: CSVTableProjection?
    let selection: CSVTableSelection?
    let columnWidth: Double
    let scrollRequest: Int
    let reduced: Bool
    let onSelect: (CSVTableSelection) -> Void
    let onActivate: (CSVTableSelection) -> Void
    let onSort: (Int) -> Void
    let onKey: (String) -> Void
    func makeUIView(context: Context) -> CSVGridHost { CSVGridHost() }
    func updateUIView(_ view: CSVGridHost, context: Context) {
        let sourceChanged = view.state.document?.id != document?.id
        let requestChanged = view.state.scrollRequest != scrollRequest
        if sourceChanged || view.state.projection?.id != projection?.id { view.scroll.setContentOffset(view.scroll.contentOffset, animated: false) }
        view.state.document = document; view.state.projection = projection; view.state.selection = selection
        view.state.width = columnWidth; view.state.rowHeight = max(44, min(64, UIFont.preferredFont(forTextStyle: .body).lineHeight + 20))
        view.state.reduced = reduced; view.state.scrollRequest = scrollRequest
        view.state.select = onSelect; view.state.activate = onActivate; view.state.sort = onSort; view.state.key = onKey
        if sourceChanged { view.scroll.setContentOffset(.zero, animated: false) }
        view.refresh(scrollToSelection: requestChanged)
    }
}
#endif
