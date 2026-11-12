#if os(macOS)
  import AppKit
  import SwiftUI

  /// A small fixed-row AppKit table avoids SwiftUI List's reentrant NSTableView measurement on macOS 27.
  struct NativeReferenceList: NSViewRepresentable {
    let rows: [CalculationRow]
    @Binding var selected: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
      let scroll = NSScrollView()
      scroll.hasVerticalScroller = true
      scroll.autohidesScrollers = false
      let table = NSTableView()
      table.headerView = nil
      table.rowHeight = 54
      table.usesAlternatingRowBackgroundColors = true
      table.addTableColumn(NSTableColumn(identifier: .init("reference")))
      table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
      table.delegate = context.coordinator
      table.dataSource = context.coordinator
      table.allowsEmptySelection = true
      table.setAccessibilityLabel("Reference entries")
      scroll.documentView = table
      context.coordinator.table = table
      return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
      let c = context.coordinator
      c.parent = self
      guard let table = c.table else { return }
      c.updating = true
      if c.rows != rows {
        c.rows = rows
        table.reloadData()
      }
      let index = selected.flatMap { id in rows.firstIndex { $0.id == id } }
      if table.selectedRow != (index ?? -1) {
        if let index {
          table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
          table.deselectAll(nil)
        }
      }
      c.updating = false
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
      var parent: NativeReferenceList
      var rows: [CalculationRow] = []
      weak var table: NSTableView?
      var updating = false
      init(_ parent: NativeReferenceList) { self.parent = parent }
      func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
      func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
      {
        guard rows.indices.contains(row) else { return nil }
        let cell =
          tableView.makeView(withIdentifier: .init("entry"), owner: self) as? ReferenceCell
          ?? ReferenceCell()
        let data = rows[row]
        cell.title.stringValue = data.label
        cell.subtitle.stringValue = data.value
        cell.setAccessibilityLabel(data.label + ", " + data.value)
        return cell
      }
      func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, let table else { return }
        let id = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        DispatchQueue.main.async { [weak self] in
          guard let self, let table = self.table else { return }
          let current =
            self.rows.indices.contains(table.selectedRow) ? self.rows[table.selectedRow].id : nil
          if current == id { self.parent.selected = id }
        }
      }
    }
    final class ReferenceCell: NSTableCellView {
      let title = NSTextField(labelWithString: ""), subtitle = NSTextField(labelWithString: "")
      init() {
        super.init(frame: .zero)
        identifier = .init("entry")
        title.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        for field in [title, subtitle] {
          field.lineBreakMode = .byTruncatingTail
          field.maximumNumberOfLines = 1
          field.translatesAutoresizingMaskIntoConstraints = false
          addSubview(field)
        }
        textField = title
        NSLayoutConstraint.activate([
          title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
          title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
          title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
          subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
          subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
          subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
        ])
      }
      required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }
  }
#endif
