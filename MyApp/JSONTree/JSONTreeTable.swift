import SwiftUI

/// A flat, reusable native table. The strict document and projection stay in JSONCore;
/// only requested rows acquire hosting views. No per-node view graph or paging.
struct JSONTreeTable {
    let rows: [Int]
    let rowNumbers: [Int: Int]
    let version: Int
    let rowsVersion: Int
    let changes: JSONTreeRowChanges?
    let animate: Bool
    let selection: Int?
    let scrollRequest: Int
    let scrollTarget: Int?
    let row: (Int) -> AnyView
    let select: (Int) -> Void
    let key: (TreeKey) -> Void
    var preferredRowHeight: CGFloat? = nil
    var tableIdentifier = "json-tree"
    var suppressSoftwareKeyboard = false
    /// Optional actual point heights; callers handle Dynamic Type. Default keeps existing tools uniform.
    var heightForID: ((Int) -> CGFloat)? = nil
    // Opt-in behavior for simple generated lists; existing tools keep their defaults.
    var smoothScrolling = false
    var fadeReplacements = false
    var alwaysShowScrollers = false
    var accessibilityScrollName = "JSON tree"
    /// Secret lists also clear retained offscreen hosting views when their presentation changes.
    var clearsOffscreenRowContent = false
    enum TreeKey { case up, down, left, right, copy }
}

#if os(macOS)
import AppKit
extension JSONTreeTable: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = TreeNativeTable()
        table.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = preferredRowHeight ?? 48; table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.keyAction = { [weak coordinator = context.coordinator] key in coordinator?.parent.key(key) }
        table.setAccessibilityIdentifier(tableIdentifier)
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        if alwaysShowScrollers { scroll.autohidesScrollers = false; scroll.scrollerStyle = .legacy }
        scroll.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let previousRowsVersion = coordinator.parent.rowsVersion
        let previousRows = coordinator.parent.rows
        let initial = coordinator.version == -1
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        let heightChanged = table.rowHeight != (preferredRowHeight ?? 48)
        table.rowHeight = preferredRowHeight ?? 48
        if heightChanged, heightForID != nil { table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count)) }
        coordinator.updating = true
        let selectionChanged = coordinator.selected != selection
        if coordinator.version != version {
            if clearsOffscreenRowContent { coordinator.clearTransition(); coordinator.clearOffscreenContent(table, count: previousRows.count) }
            coordinator.version = version
            if initial || previousRowsVersion != rowsVersion {
                if !initial, !fadeReplacements { coordinator.refreshSurvivingVisible(table, oldRows: previousRows) }
                coordinator.scrollMotion.cancel()
                if !initial, fadeReplacements, animate { coordinator.crossfade(table, in: scroll) }
                else if !initial, animate, !coordinator.animatingRows, let changes, changes.baseVersion == previousRowsVersion, changes.count > 0 {
                    if changes.count <= 200 {
                        coordinator.animatingRows = true
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.2
                            table.beginUpdates()
                            table.removeRows(at: changes.removed, withAnimation: .slideUp)
                            table.insertRows(at: changes.inserted, withAnimation: .slideDown)
                            table.endUpdates()
                        } completionHandler: { [weak coordinator, weak table] in
                            guard let coordinator, let table else { return }
                            coordinator.animatingRows = false
                            coordinator.refreshVisible(table)
                        }
                    } else { coordinator.crossfade(table, in: scroll) }
                } else { coordinator.clearTransition(); table.reloadData() }
            }
            if !coordinator.animatingRows { coordinator.refreshVisible(table) }
        } else if selectionChanged {
            // Native selection has a separate color, so refresh only the old/new visible rows.
            for id in [coordinator.selected, selection].compactMap({ $0 }) {
                if let number = rowNumbers[id], let cell = table.view(atColumn: 0, row: number - 1, makeIfNecessary: false) as? TreeHostingCell {
                    cell.host.rootView = coordinator.hosted(id, table: table)
                }
            }
        }
        coordinator.selected = selection
        coordinator.updating = true
        if let selection, let number = rowNumbers[selection] { table.selectRowIndexes(IndexSet(integer: number - 1), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        coordinator.updating = false
        if coordinator.scrollRequest != scrollRequest {
            coordinator.scrollRequest = scrollRequest
            if let scrollTarget, let number = rowNumbers[scrollTarget] {
                if smoothScrolling { coordinator.scrollMotion.reveal(table.rect(ofRow: number - 1), in: scroll, animated: animate) }
                else { table.scrollRowToVisible(number - 1) }
            }
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.scrollMotion.cancel(); coordinator.clearTransition() }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: JSONTreeTable
        @MainActor lazy var scrollMotion = NativeListScrollMotion()
        weak var table: NSTableView?
        var version = -1
        var selected: Int?
        var scrollRequest = -1
        var updating = false
        init(_ parent: JSONTreeTable) { self.parent = parent }
        override func responds(to selector: Selector!) -> Bool {
            if selector == #selector(NSTableViewDelegate.tableView(_:heightOfRow:)), parent.heightForID == nil { return false }
            return super.responds(to: selector)
        }
        var animatingRows = false
        private var fading: NSView?
        func clearTransition() { fading?.removeFromSuperview(); fading = nil }
        func refreshSurvivingVisible(_ table: NSTableView, oldRows: [Int]) {
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            for index in visible.location..<min(NSMaxRange(visible), oldRows.count) {
                let id = oldRows[index]
                if parent.rowNumbers[id] != nil,
                   let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? TreeHostingCell {
                    cell.host.rootView = hosted(id, table: table)
                }
            }
        }
        func clearOffscreenContent(_ table: NSTableView, count: Int) {
            let visible = table.rows(in: table.visibleRect)
            for index in 0..<count where visible.location == NSNotFound || !NSLocationInRange(index, visible) {
                if let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? TreeHostingCell {
                    cell.host.rootView = index < parent.rows.count ? hosted(parent.rows[index], table: table) : AnyView(EmptyView())
                }
            }
        }
        func refreshVisible(_ table: NSTableView) {
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            for row in visible.location..<min(NSMaxRange(visible), parent.rows.count) {
                if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TreeHostingCell {
                    cell.host.rootView = hosted(parent.rows[row], table: table)
                }
            }
        }
        func crossfade(_ table: NSTableView, in scroll: NSScrollView) {
            fading?.removeFromSuperview()
            let rect = table.visibleRect
            let bitmap = rect.isEmpty ? nil : table.bitmapImageRepForCachingDisplay(in: rect)
            if let bitmap { table.cacheDisplay(in: rect, to: bitmap) }
            table.reloadData()
            guard let bitmap else { return }
            let image = NSImage(size: rect.size); image.addRepresentation(bitmap)
            let overlay = TreeFadeImage(frame: scroll.contentView.bounds)
            overlay.image = image; overlay.imageScaling = .scaleAxesIndependently
            scroll.contentView.addSubview(overlay); fading = overlay
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                overlay.animator().alphaValue = 0
            } completionHandler: { [weak overlay] in overlay?.removeFromSuperview() }
        }
        func hosted(_ id: Int, table: NSTableView) -> AnyView {
            AnyView(parent.row(id).simultaneousGesture(TapGesture().onEnded { [weak table] in
                if let table { table.window?.makeFirstResponder(table) }
            }))
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard parent.rows.indices.contains(row), let height = parent.heightForID else { return tableView.rowHeight }
            return height(parent.rows[row])
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.rows.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("tree-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? TreeHostingCell ?? TreeHostingCell()
            cell.identifier = identifier
            cell.host.rootView = hosted(parent.rows[row], table: tableView)
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table, parent.rows.indices.contains(table.selectedRow) else { return }
            parent.select(parent.rows[table.selectedRow])
        }
    }
}
private final class TreeFadeImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}
private final class TreeHostingCell: NSTableCellView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Not archived") }
    override func layout() { super.layout(); host.frame = bounds }
}
private final class TreeNativeTable: NSTableView {
    var keyAction: ((JSONTreeTable.TreeKey) -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: keyAction?(.up)
        case 125: keyAction?(.down)
        case 123: keyAction?(.left)
        case 124: keyAction?(.right)
        default: super.keyDown(with: event)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            keyAction?(.copy); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
#else
import UIKit
extension JSONTreeTable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITableView {
        let table = TreeNativeTable(frame: .zero, style: .plain)
        table.backgroundColor = .clear; table.separatorStyle = .none
        table.allowsSelection = false // Selection is the row action; folding never selects.
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.register(UITableViewCell.self, forCellReuseIdentifier: "tree")
        table.keyboardDismissMode = .interactive
        table.accessibilityIdentifier = tableIdentifier
        table.suppressSoftwareKeyboard = suppressSoftwareKeyboard
        table.scrollName = accessibilityScrollName
        table.keyAction = { [weak coordinator = context.coordinator] key in coordinator?.parent.key(key) }
        return table
    }
    func updateUIView(_ table: UITableView, context: Context) {
        let coordinator = context.coordinator
        let previousRowsVersion = coordinator.parent.rowsVersion
        let previousRows = coordinator.parent.rows
        let initial = coordinator.version == -1
        coordinator.parent = self
        let previousHeight = table.rowHeight
        table.rowHeight = heightForID == nil
            ? max(UIFontMetrics.default.scaledValue(for: preferredRowHeight ?? 44), UIFont.preferredFont(forTextStyle: .body).lineHeight * 2 + 8)
            : preferredRowHeight ?? 44
        if heightForID != nil, table.rowHeight != previousHeight { UIView.performWithoutAnimation { table.reloadData() } }
        if coordinator.version != version {
            if clearsOffscreenRowContent { coordinator.clearTransition() }
            coordinator.version = version
            if initial || previousRowsVersion != rowsVersion {
                if !initial, !fadeReplacements { coordinator.refreshSurvivingVisible(table, oldRows: previousRows) }
                if !initial, fadeReplacements, animate { coordinator.crossfade(table) }
                else if !initial, animate, !coordinator.animatingRows, let changes, changes.baseVersion == previousRowsVersion, changes.count > 0 {
                    if changes.count <= 200 {
                        coordinator.animatingRows = true
                        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { [coordinator, table] in
                            table.performBatchUpdates {
                                table.deleteRows(at: changes.removed.map { IndexPath(row: $0, section: 0) }, with: .top)
                                table.insertRows(at: changes.inserted.map { IndexPath(row: $0, section: 0) }, with: .top)
                            } completion: { [weak coordinator, weak table] _ in
                                guard let coordinator, let table else { return }
                                coordinator.animatingRows = false
                                coordinator.refreshVisible(table)
                            }
                        }
                    } else { coordinator.crossfade(table) }
                } else { coordinator.clearTransition(); UIView.performWithoutAnimation { table.reloadData() } }
            }
            if !coordinator.animatingRows { coordinator.refreshVisible(table) }
        } else if coordinator.selected != selection {
            for id in [coordinator.selected, selection].compactMap({ $0 }) {
                if let number = rowNumbers[id], let cell = table.cellForRow(at: IndexPath(row: number - 1, section: 0)) {
                    cell.contentConfiguration = coordinator.hosted(id, table: table)
                }
            }
        }
        coordinator.selected = selection
        if coordinator.scrollRequest != scrollRequest {
            coordinator.scrollRequest = scrollRequest
            if let scrollTarget, let number = rowNumbers[scrollTarget] {
                table.scrollToRow(at: IndexPath(row: number - 1, section: 0), at: .middle, animated: smoothScrolling && animate)
            }
        }
    }
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: JSONTreeTable
        var version = -1
        var selected: Int?
        var scrollRequest = -1
        init(_ parent: JSONTreeTable) { self.parent = parent }
        override func responds(to selector: Selector!) -> Bool {
            if selector == #selector(UITableViewDelegate.tableView(_:heightForRowAt:)), parent.heightForID == nil { return false }
            return super.responds(to: selector)
        }
        var animatingRows = false
        private var fading: UIView?
        func clearTransition() { fading?.removeFromSuperview(); fading = nil }
        func refreshSurvivingVisible(_ table: UITableView, oldRows: [Int]) {
            for index in table.indexPathsForVisibleRows ?? [] where oldRows.indices.contains(index.row) {
                let id = oldRows[index.row]
                if parent.rowNumbers[id] != nil, let cell = table.cellForRow(at: index) {
                    cell.contentConfiguration = hosted(id, table: table)
                }
            }
        }
        func refreshVisible(_ table: UITableView) {
            for index in table.indexPathsForVisibleRows ?? [] where parent.rows.indices.contains(index.row) {
                if let cell = table.cellForRow(at: index) { cell.contentConfiguration = hosted(parent.rows[index.row], table: table) }
            }
        }
        func crossfade(_ table: UITableView) {
            fading?.removeFromSuperview()
            let snapshot = table.snapshotView(afterScreenUpdates: false)
            table.reloadData(); table.layoutIfNeeded()
            guard let snapshot, let host = table.superview else { return }
            snapshot.frame = table.frame; snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            host.addSubview(snapshot); fading = snapshot
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                snapshot.alpha = 0
            } completion: { _ in snapshot.removeFromSuperview() }
        }
        func hosted(_ id: Int, table: UITableView) -> UIContentConfiguration {
            let render = parent.row
            return UIHostingConfiguration {
                render(id).simultaneousGesture(TapGesture().onEnded { [weak table] in table?.becomeFirstResponder() })
            }.margins(.all, 0)
        }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { parent.rows.count }
        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            guard parent.rows.indices.contains(indexPath.row), let height = parent.heightForID else { return tableView.rowHeight }
            return height(parent.rows[indexPath.row])
        }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "tree", for: indexPath)
            cell.backgroundColor = .clear; cell.selectionStyle = .none
            guard parent.rows.indices.contains(indexPath.row) else {
                cell.contentConfiguration = nil
                return cell
            }
            cell.contentConfiguration = hosted(parent.rows[indexPath.row], table: tableView)
            return cell
        }
        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            parent.select(parent.rows[indexPath.row]); tableView.becomeFirstResponder()
        }
    }
}
private final class TreeNativeTable: UITableView {
    // UITableView's default accessibility enumerator can materialize offscreen
    // hosting configurations for every row during an AX snapshot. Expose the
    // recycled cells, and retain native continuous accessibility scrolling.
    override var accessibilityElements: [Any]? {
        get { visibleCells }
        set { }
    }
    override func accessibilityElementCount() -> Int { visibleCells.count }
    override func accessibilityElement(at index: Int) -> Any? {
        let cells = visibleCells
        return cells.indices.contains(index) ? cells[index] : nil
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        guard let cell = element as? UITableViewCell else { return NSNotFound }
        return visibleCells.firstIndex(of: cell) ?? NSNotFound
    }
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard direction == .up || direction == .down else { return super.accessibilityScroll(direction) }
        let delta = (direction == .down ? 1.0 : -1.0) * max(rowHeight, bounds.height - rowHeight)
        let offset = min(max(-adjustedContentInset.top, contentOffset.y + delta), max(0, contentSize.height - bounds.height + adjustedContentInset.bottom))
        guard offset != contentOffset.y else { return false }
        setContentOffset(CGPoint(x: contentOffset.x, y: offset), animated: false)
        UIAccessibility.post(notification: .pageScrolled, argument: "Scrolled \(scrollName)")
        return true
    }

    var keyAction: ((JSONTreeTable.TreeKey) -> Void)?
    var suppressSoftwareKeyboard = false
    var scrollName = "JSON tree"
    private lazy var emptyInputView = UIView(frame: .zero)
    override var inputView: UIView? { suppressSoftwareKeyboard ? emptyInputView : super.inputView }
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(up)),
         UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(down)),
         UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(left)),
         UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(right)),
         UIKeyCommand(input: "c", modifierFlags: .command, action: #selector(copyFragment))]
    }
    @objc private func up() { keyAction?(.up) }
    @objc private func down() { keyAction?(.down) }
    @objc private func left() { keyAction?(.left) }
    @objc private func right() { keyAction?(.right) }
    @objc private func copyFragment() { keyAction?(.copy) }
}
#endif
