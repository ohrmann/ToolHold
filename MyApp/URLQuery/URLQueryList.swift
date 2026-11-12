import SwiftUI

/// Native recycled rows: the logical query can contain hundreds of thousands of empty occurrences.
struct URLQueryList {
    let rows: [URLQueryRow]
    let revision: UUID
    let baseRevision: UUID?
    let change: URLQueryListChange
    let reduceMotion: Bool
    let selection: Int?
    let enabled: Bool
    let select: (Int) -> Void
    let move: (Int,Int) -> Void
    static func label(_ row: URLQueryRow) -> String {
        let name = row.rawName.isEmpty && row.changedName == nil ? "(empty name)" : URLQueryPresentation.safe(row.displayName)
        let value = row.displayValue.map { $0.isEmpty ? "(empty)" : URLQueryPresentation.safe($0) } ?? "(no '=')"
        if row.rawName.isEmpty && row.rawValue == nil && row.changedName == nil { return "Empty segment" }
        return name + "  =  " + value + (row.rawOnlyName || row.rawOnlyValue ? "  · Raw bytes" : "")
    }
}
#if os(macOS)
import AppKit
extension URLQueryList: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        let table = NSTableView(); table.headerView = nil; table.rowHeight = 38; table.usesAlternatingRowBackgroundColors = true
        let column = NSTableColumn(identifier:.init("parameter")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.registerForDraggedTypes([Coordinator.type]); table.setDraggingSourceOperationMask(.move,forLocal:true)
        table.setAccessibilityLabel("Query parameters"); table.identifier = .init("url-query-list")
        scroll.documentView = table; return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        let c = context.coordinator, table = view.documentView as! NSTableView
        let changed = c.parent.revision != revision, canPatch = c.parent.revision == baseRevision
        c.parent = self
        c.updating = true
        if changed {
            if !canPatch { table.reloadData() }
            else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = reduceMotion ? 0 : 0.2
                    context.allowsImplicitAnimation = !reduceMotion
                    switch change {
                    case .reload: table.reloadData()
                    case .update(let index): table.reloadData(forRowIndexes:IndexSet(integer:index),columnIndexes:IndexSet(integer:0))
                    case .insert(let index): table.insertRows(at:IndexSet(integer:index),withAnimation:reduceMotion ? [] : .slideDown)
                    case .remove(let index): table.removeRows(at:IndexSet(integer:index),withAnimation:reduceMotion ? [] : .slideUp)
                    case .move(let from,let to): table.beginUpdates(); table.moveRow(at:from,to:to); table.endUpdates()
                    }
                }
            }
        }
        let index = selection.flatMap { id in rows.firstIndex { $0.id == id } }
        c.updating = true
        if let index, table.selectedRow != index { table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false) }
        else if index == nil { table.deselectAll(nil) }
        c.updating = false
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let type = NSPasteboard.PasteboardType("developerToolbox.urlQuery.row")
        var parent: URLQueryList
        var updating = false
        init(_ parent: URLQueryList) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let key = NSUserInterfaceItemIdentifier("query-cell")
            let cell = (tableView.makeView(withIdentifier:key,owner:nil) as? NSTableCellView) ?? {
                let cell = NSTableCellView(); cell.identifier = key
                let text = NSTextField(labelWithString:""); text.font = .monospacedSystemFont(ofSize:12,weight:.regular)
                text.lineBreakMode = .byTruncatingTail; text.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(text); cell.textField = text
                NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),text.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
                return cell
            }()
            guard parent.rows.indices.contains(row) else { return cell }
            let text = "⠿  \(row+1)   " + URLQueryList.label(parent.rows[row])
            cell.textField?.stringValue = text
            cell.setAccessibilityLabel("Parameter \(row+1). " + URLQueryList.label(parent.rows[row]))
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView, parent.rows.indices.contains(table.selectedRow) else { return }
            parent.select(parent.rows[table.selectedRow].id)
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard parent.enabled, parent.rows.indices.contains(row) else { return nil }
            // Selection uses the body; only the narrow handle starts a drag.
            let point = tableView.convert(tableView.window?.mouseLocationOutsideOfEventStream ?? .zero,from:nil)
            guard point.x < 34 else { return nil }
            let item = NSPasteboardItem(); item.setString(String(parent.rows[row].id),forType:Self.type); return item
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard parent.enabled, info.draggingSource as? NSTableView === tableView else { return [] }
            tableView.setDropRow(row,dropOperation:.above); return .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard parent.enabled, info.draggingSource as? NSTableView === tableView,
                  let raw = info.draggingPasteboard.string(forType:Self.type), let id = Int(raw), let old = parent.rows.firstIndex(where:{$0.id == id}) else { return false }
            parent.move(id,max(0,row > old ? row-1 : row)); return true
        }
    }
}
#else
import UIKit
extension URLQueryList: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame:.zero,style:.plain)
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.register(UITableViewCell.self,forCellReuseIdentifier:"parameter")
        table.rowHeight = 48; table.isEditing = true; table.allowsSelectionDuringEditing = true
        table.accessibilityIdentifier = "url-query-list"; table.keyboardDismissMode = .interactive
        return table
    }
    func updateUIView(_ table: UITableView, context: Context) {
        let c = context.coordinator, changed = c.parent.revision != revision, canPatch = c.parent.revision == baseRevision
        c.parent = self
        if changed {
            if !canPatch || c.nativeMove { c.nativeMove = false; table.reloadData() }
            else {
                let update = {
                    switch change {
                    case .reload: table.reloadData()
                    case .update(let index): table.reloadRows(at:[IndexPath(row:index,section:0)],with:.none)
                    case .insert(let index): table.insertRows(at:[IndexPath(row:index,section:0)],with:reduceMotion ? .none : .automatic)
                    case .remove(let index): table.deleteRows(at:[IndexPath(row:index,section:0)],with:reduceMotion ? .none : .automatic)
                    case .move(let from,let to): table.moveRow(at:IndexPath(row:from,section:0),to:IndexPath(row:to,section:0))
                    }
                }
                if reduceMotion { UIView.performWithoutAnimation(update) } else { update() }
            }
        }
        table.isEditing = enabled
        if let index = selection.flatMap({ id in rows.firstIndex { $0.id == id } }) {
            if table.indexPathForSelectedRow?.row != index { table.selectRow(at:IndexPath(row:index,section:0),animated:false,scrollPosition:.none) }
        } else if let path = table.indexPathForSelectedRow { table.deselectRow(at:path,animated:false) }
    }
    @MainActor final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: URLQueryList
        var nativeMove = false
        init(_ parent: URLQueryList) { self.parent = parent }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { parent.rows.count }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier:"parameter",for:indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "\(indexPath.row+1)   " + URLQueryList.label(parent.rows[indexPath.row])
            content.textProperties.font = .monospacedSystemFont(ofSize:13,weight:.regular); content.textProperties.numberOfLines = 1
            cell.contentConfiguration = content; cell.showsReorderControl = true
            cell.accessibilityLabel = "Parameter \(indexPath.row+1). " + URLQueryList.label(parent.rows[indexPath.row])
            return cell
        }
        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { parent.select(parent.rows[indexPath.row].id) }
        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
        func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }
        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { parent.enabled }
        func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) { nativeMove = true; parent.move(parent.rows[source.row].id,destination.row) }
    }
}
#endif
