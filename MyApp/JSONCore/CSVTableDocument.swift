import Foundation

struct CSVTableSelection: Equatable, Sendable { let row: Int; let column: Int }
struct CSVTableSort: Equatable, Sendable { let column: Int; let ascending: Bool }
struct CSVTableCellPreview: Sendable {
    let text: String
    var matches: [NSRange] = []
}
/// Lossless delimited snapshot. Row IDs are source data-record ordinals, not display positions.
struct CSVTableDocument: Sendable {
    let id = UUID()
    let table: DelimitedDocument
    let format: DelimitedFormat
    let hasHeader: Bool
    let columnCount: Int
    let previews: [CSVTableCellPreview]
    var headerOffset: Int { hasHeader && !table.records.isEmpty ? 1 : 0 }
    var rowCount: Int { table.records.count - headerOffset }
    func record(_ row: Int) -> DelimitedRecord { table.records[row + headerOffset] }
    func cellIndex(_ selection: CSVTableSelection) -> Int? {
        guard selection.row >= 0, selection.row < rowCount, selection.column >= 0 else { return nil }
        let range = record(selection.row).cells
        return selection.column < range.count ? range.lowerBound + selection.column : nil
    }
    func cell(_ selection: CSVTableSelection) -> DelimitedCell? { cellIndex(selection).map { table.cells[$0] } }
    func header(_ column: Int) -> String {
        guard hasHeader, let first = table.records.first, column < first.cells.count else { return "Column \(column + 1)" }
        let value = previews[first.cells.lowerBound + column].text
        return value.isEmpty ? "Column \(column + 1) · empty header" : value
    }
    func fragment(_ row: Int) -> String { (table.source as NSString).substring(with: record(row).range) }
}
struct CSVTableResult: Sendable {
    let status: JSONCSVStatus
    var document: CSVTableDocument?
    var diagnostics: [JSONDiagnostic] = []
}
struct CSVTableProjection: Sendable {
    let id = UUID()
    let documentID: UUID
    let rows: [Int]
    let positions: [Int]
    let query: String
    let sort: CSVTableSort?
    let previews: [Int: CSVTableCellPreview]
}

enum CSVTableProcessor {
    static func build(_ source: String, format: DelimitedFormat = .csv, hasHeader: Bool = true) -> CSVTableResult {
        do {
            let table = try DelimitedTextParser.parse(source, format: format)
            var previews: [CSVTableCellPreview] = []
            previews.reserveCapacity(table.cells.count)
            for (index, cell) in table.cells.enumerated() {
                if index & 255 == 0 { try Task.checkCancellation() }
                previews.append(.init(text: JSONTreePreview.make(cell.value, budget: 120).text))
            }
            let columns = table.records.map(\.cells.count).max() ?? 0
            let document = CSVTableDocument(table: table, format: format, hasHeader: hasHeader, columnCount: columns, previews: previews)
            var diagnostics: [JSONDiagnostic] = []
            if let first = table.records.first, let mismatch = table.records.dropFirst().first(where: { $0.cells.count != first.cells.count }) {
                let range = mismatch.cells.count > first.cells.count ? table.cells[mismatch.cells.lowerBound + first.cells.count].range : NSRange(location: NSMaxRange(mismatch.range), length: 0)
                let location = JSONSourceCoordinates(source).location(at: range.location)
                diagnostics.append(.init(severity: .warning, code: "TABLE-RAGGED", message: "Records have different field counts (\(first.cells.count) and \(mismatch.cells.count)). All fields are preserved; missing cells are marked separately from empty values.", range: range, line: location.line, column: location.column, related: [.init(.fieldName, first.range)]))
            }
            try Task.checkCancellation()
            return .init(status: .success, document: document, diagnostics: diagnostics)
        } catch is CancellationError { return .init(status: .cancelled) }
        catch let failure as DelimitedFailure {
            let offset = min(source.utf16.count, max(0, failure.range.location))
            let location = JSONSourceCoordinates(source).location(at: offset)
            return .init(status: failure.status, diagnostics: [.init(severity: .error, code: failure.status == .resourceLimit ? "TABLE-LIMIT" : "TABLE-SYNTAX", message: failure.message, range: failure.range, line: location.line, column: location.column, related: failure.related, precision: failure.precision)])
        } catch { return .init(status: .cancelled) }
    }
    /// Literal filtering and stable text sorting. Never coerces dates, amounts or identifiers.
    static func project(_ document: CSVTableDocument, query: String = "", sort: CSVTableSort? = nil) throws -> CSVTableProjection {
        var rows: [Int] = [], previews: [Int: CSVTableCellPreview] = [:]
        for row in 0..<document.rowCount {
            if row & 255 == 0 { try Task.checkCancellation() }
            var found = query.isEmpty
            if !query.isEmpty {
                for index in document.record(row).cells {
                    let value = document.table.cells[index].value as NSString
                    let match = value.range(of: query, options: [.literal, .caseInsensitive])
                    guard match.location != NSNotFound else { continue }
                    found = true
                    let preview = JSONTreePreview.make(value as String, around: match, budget: 120)
                    // Map all occurrences within the bounded source window only.
                    var ranges: [NSRange] = []
                    if let first = preview.spans.first, let last = preview.spans.last {
                        var cursor = first.source.location
                        let end = min(value.length, NSMaxRange(last.source))
                        while cursor < end {
                            let occurrence = value.range(of: query, options: [.literal, .caseInsensitive], range: NSRange(location: cursor, length: end - cursor))
                            if occurrence.location == NSNotFound || occurrence.length == 0 { break }
                            let pieces = preview.displayRanges(for: occurrence)
                            if let first = pieces.first, let last = pieces.last { ranges.append(NSRange(location: first.location, length: NSMaxRange(last) - first.location)) }
                            cursor = NSMaxRange(occurrence)
                        }
                    }
                    previews[index] = .init(text: preview.text, matches: ranges)
                }
            }
            if found { rows.append(row) }
        }
        if let sort, sort.column >= 0, sort.column < document.columnCount {
            // Bottom-up merge sort permits cancellation without an inconsistent comparator.
            var buffer = rows, width = 1
            func value(_ row: Int) -> String { document.cell(.init(row: row, column: sort.column))?.value ?? "" }
            while width < rows.count {
                try Task.checkCancellation()
                var start = 0
                while start < rows.count {
                    if start & 255 == 0 { try Task.checkCancellation() }
                    let middle = min(start + width, rows.count), end = min(start + width * 2, rows.count)
                    var a = start, b = middle
                    for target in start..<end {
                        let takeLeft: Bool
                        if a == middle { takeLeft = false }
                        else if b == end { takeLeft = true }
                        else {
                            let comparison = (value(rows[a]) as NSString).compare(value(rows[b]), options: .literal)
                            takeLeft = comparison == .orderedSame ? rows[a] < rows[b] : (sort.ascending ? comparison == .orderedAscending : comparison == .orderedDescending)
                        }
                        buffer[target] = takeLeft ? rows[a] : rows[b]
                        if takeLeft { a += 1 } else { b += 1 }
                    }
                    start = end
                }
                swap(&rows, &buffer); width *= 2
            }
        }
        var positions = Array(repeating: -1, count: document.rowCount)
        for (offset, row) in rows.enumerated() { positions[row] = offset }
        try Task.checkCancellation()
        return .init(documentID: document.id, rows: rows, positions: positions, query: query, sort: sort, previews: previews)
    }
}
