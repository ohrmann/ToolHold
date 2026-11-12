#if os(macOS)
import AppKit
import SwiftUI

/// AppKit recycling avoids SwiftUI List's reentrant NSTableView layout on this SDK.
/// One native cell per visible row; row text is bounded to 16 bytes.
struct HexBytesNativeList: NSViewRepresentable {
    let artifact: HexBytesArtifact
    let hexCase: HexBytesCase
    let fontSize: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Scroll {
        let scroll = Scroll(), table = NSTableView()
        table.headerView = nil; table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false; table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero; table.columnAutoresizingStyle = .noColumnAutoresizing
        let column = NSTableColumn(identifier: .init("bytes")); column.minWidth = 1; column.maxWidth = 10_000
        table.addTableColumn(column); table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.setAccessibilityLabel("Bytes inspector. Byte offsets are hexadecimal, not source line numbers.")
        table.setAccessibilityIdentifier("hex-bytes-inspector")
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
        scroll.drawsBackground = false; scroll.documentView = table
        context.coordinator.table = table; context.coordinator.scroll = scroll
        scroll.didLayout = { [weak coordinator = context.coordinator] in coordinator?.schedule() }
        return scroll
    }
    func updateNSView(_ view: Scroll, context: Context) {
        context.coordinator.update(artifact, hexCase: hexCase, fontSize: fontSize)
    }
    final class Scroll: NSScrollView {
        var didLayout: (() -> Void)?
        override func layout() { super.layout(); didLayout?() }
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        weak var scroll: NSScrollView?
        private var artifact: HexBytesArtifact?
        private var hexCase = HexBytesCase.uppercase
        private var fontSize: CGFloat = 12
        private var columns = 16
        private var ascii = true
        private var pending = false
        private var reload = false
        private var newSnapshot = false
        func update(_ artifact: HexBytesArtifact, hexCase: HexBytesCase, fontSize: CGFloat) {
            if self.artifact?.id != artifact.id { self.artifact = artifact; newSnapshot = true; reload = true }
            if self.hexCase != hexCase || self.fontSize != fontSize { self.hexCase = hexCase; self.fontSize = fontSize; reload = true }
            schedule()
        }
        func schedule() {
            guard !pending else { return }; pending = true
            // Geometry/reload must run after native/SwiftUI layout and delegate callbacks return.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
        private func apply() {
            pending = false
            guard let table, let scroll, let artifact else { return }
            let width = scroll.contentSize.width
            guard width > 0 else { return }
            let next = width >= fontSize * 37 ? 16 : width >= fontSize * 23 ? 8 : 4
            let nextASCII = width >= fontSize * (12 + CGFloat(next) * 2.6)
            let visible = table.rows(in: table.visibleRect)
            let first = newSnapshot || visible.location == NSNotFound ? 0 : visible.location * columns
            let geometryChanged = next != columns || nextASCII != ascii
            columns = next; ascii = nextASCII
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
            let chars = 8 + 3 + columns * 3 - 1 + (ascii ? 3 + columns : 0)
            let rowWidth = max(width, ceil(CGFloat(chars) * charWidth + 16))
            table.rowHeight = max(28, ceil(fontSize * 2.4))
            if table.tableColumns[0].width != rowWidth { table.tableColumns[0].width = rowWidth }
            if reload || geometryChanged {
                table.reloadData()
                if !artifact.bytes.isEmpty {
                    let row = min(max(0, first / columns), numberOfRows(in: table) - 1)
                    let y = table.rect(ofRow: row).minY
                    scroll.contentView.scroll(to: .init(x: scroll.contentView.bounds.minX, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
                }
                reload = false; newSnapshot = false
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { ((artifact?.bytes.count ?? 0) + columns - 1) / columns }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let artifact else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("hex-byte-row")
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView { cell = existing }
            else {
                cell = NSTableCellView(); cell.identifier = identifier
                let field = NSTextField(labelWithString: ""); field.translatesAutoresizingMaskIntoConstraints = false
                field.lineBreakMode = .byClipping; field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                cell.addSubview(field); cell.textField = field
                NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            let start = row * columns, value = HexBytesRow(bytes: artifact.bytes, start: start, count: columns, hexCase: hexCase)
            let text = value.offset + "   " + value.hex.padding(toLength: columns * 3 - 1, withPad: " ", startingAt: 0) + (ascii ? "   " + value.ascii : "")
            cell.textField?.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            cell.textField?.textColor = .labelColor; cell.textField?.stringValue = text
            cell.textField?.setAccessibilityLabel("Byte offset \(start), hexadecimal \(value.offset). \(value.hex). ASCII \(value.ascii)")
            cell.setAccessibilityIdentifier("hex-bytes-row-\(start)")
            return cell
        }
    }
}
#endif
