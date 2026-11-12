import Foundation

enum JSONCSVDirection: String, CaseIterable, Sendable {
    case toDelimited = "JSON → Table", toJSON = "Table → JSON"
}
enum JSONCSVRowShape: String, CaseIterable, Sendable { case objects = "Objects", arrays = "Arrays" }
enum JSONCSVCellMode: String, CaseIterable, Sendable {
    case text = "Text cells", json = "JSON cells", flatten = "Flatten objects"
}
enum JSONCSVEmptyCell: String, CaseIterable, Sendable { case string = "Empty string", null = "Null", omit = "Omit field" }
enum DelimitedLineEnding: String, CaseIterable, Sendable {
    case crlf = "CRLF", lf = "LF"
    var text: String { self == .crlf ? "\r\n" : "\n" }
}
struct JSONCSVOptions: Equatable, Sendable {
    var format = DelimitedFormat.csv
    var shape = JSONCSVRowShape.objects
    var hasHeader = true
    var cells = JSONCSVCellMode.text
    var empty = JSONCSVEmptyCell.string
    var inferScalars = false
    var protectFormulas = false
    var lineEnding = DelimitedLineEnding.crlf
    var summary: String {
        let header = hasHeader ? "Header row" : "No header"
        return "\(format.rawValue) · \(shape.rawValue) · \(header) · \(cells.rawValue)"
    }
}
struct JSONCSVResult: Sendable {
    let status: JSONCSVStatus
    var output: String?
    var diagnostics: [JSONDiagnostic] = []
    var notes: [String] = []
    var rowCount = 0
    var columnCount = 0
    var suggestedFormat: DelimitedFormat?
}

enum JSONCSVConverter {
    static func process(_ source: String, direction: JSONCSVDirection, options: JSONCSVOptions = .init(),
                        indentation: JSONIndentation = .two, produceOutput: Bool = true) -> JSONCSVResult {
        do {
            try Task.checkCancellation()
            guard source.utf16.count <= JSONProcessor.maximumUTF16Length else { throw DelimitedFailure.limit("Input exceeds 262,144 UTF-16 code units.") }
            guard !source.isEmpty else { throw DelimitedFailure.invalid("Enter JSON or delimited text before converting.", NSRange(location: 0, length: 0)) }
            guard options.cells != .flatten || (options.shape == .objects && options.hasHeader) else {
                throw DelimitedFailure.options("Flatten objects requires object rows and a header row containing JSON Pointer paths.")
            }
            if direction == .toDelimited {
                let parsed = JSONProcessor.inspectStructure(source)
                guard let document = parsed.document else {
                    let status: JSONCSVStatus
                    switch parsed.result.status { case .cancelled: status = .cancelled; case .resourceLimit: status = .resourceLimit; default: status = .invalid }
                    return JSONCSVResult(status: status, diagnostics: parsed.result.diagnostics)
                }
                return try export(document, options: options, produceOutput: produceOutput)
            } else {
                var result = try importTable(source, options: options, indentation: indentation, produceOutput: produceOutput)
                if result.columnCount == 1 { result.suggestedFormat = suggestedFormat(source, options: options) }
                try Task.checkCancellation()
                return result
            }
        } catch is CancellationError { return JSONCSVResult(status: .cancelled) }
        catch let failure as DelimitedFailure {
            let length = source.utf16.count, offset = min(length, max(0, failure.range.location))
            let coordinates = offset == 0 ? (line: 1, column: 1) : JSONSourceCoordinates(source).location(at: offset)
            let diagnostic = JSONDiagnostic(severity: .error,
                code: failure.configuration ? "TABLE-OPTIONS" : failure.status == .resourceLimit ? "TABLE-LIMIT" : failure.status == .unsupported ? "TABLE-MAPPING" : "TABLE-SYNTAX",
                message: failure.message, range: NSRange(location: offset, length: min(max(0, failure.range.length), length - offset)),
                line: coordinates.line, column: coordinates.column, related: failure.related, precision: failure.precision)
            let suggestion = direction == .toJSON && failure.status == .invalid ? suggestedFormat(source, options: options) : nil
            if Task.isCancelled { return JSONCSVResult(status: .cancelled) }
            return JSONCSVResult(status: failure.status, diagnostics: [diagnostic], suggestedFormat: suggestion)
        } catch {
            return JSONCSVResult(status: .unsupported, diagnostics: [JSONDiagnostic(severity: .error, code: "TABLE-FAILED",
                message: "Conversion could not be completed. No partial output was published.", range: NSRange(location: 0, length: 0), line: 1, column: 1, precision: .region)])
        }
    }

    /// Advisory only: never changes the selected dialect or the validity of that dialect.
    /// Require a real multi-column TSV header/first record and consistent records, allowing
    /// the common extra terminal TAB that the normal width diagnostic explains separately.
    private static func suggestedFormat(_ source: String, options: JSONCSVOptions) -> DelimitedFormat? {
        guard options.format == .csv, source.utf16.contains(9),
              let table = try? DelimitedTextParser.parse(source, format: .tsv),
              table.records.count > 1, let first = table.records.first, first.cells.count > 1 else { return nil }
        for record in table.records.dropFirst() {
            if Task.isCancelled { return nil }
            guard record.cells.count == first.cells.count || hasExtraTrailingEmptyField(record, columns: first.cells.count, table: table) else { return nil }
        }
        return .tsv
    }

    private static func hasExtraTrailingEmptyField(_ record: DelimitedRecord, columns: Int, table: DelimitedDocument) -> Bool {
        guard record.cells.count == columns + 1 else { return false }
        let last = table.cells[record.cells.upperBound - 1]
        // An unquoted zero-length final field is created by a terminal delimiter.
        // A quoted empty value or an empty field inside the record is not this case.
        return !last.quoted && last.range.length == 0 && last.value.isEmpty
    }

    private struct Writer {
        var text = "", length = 0, steps = 0
        mutating func append(_ value: String) throws {
            let size = value.utf16.count
            guard size <= JSONProcessor.maximumUTF16Length - length else { throw DelimitedFailure.limit("Converted output exceeds 262,144 UTF-16 code units. No partial result was published.") }
            text += value; length += size
        }
        mutating func tick() throws {
            steps += 1
            if steps & 255 == 0 { try Task.checkCancellation() }
            guard steps <= 2_000_000 else { throw DelimitedFailure.limit("Table conversion work budget reached.") }
        }
        mutating func cell(_ value: String, format: DelimitedFormat) throws {
            // Always quote empty fields, too: an empty final record remains an actual record.
            if value.isEmpty || value.utf16.contains(where: { [format.separator, 34, 10, 13].contains($0) }) {
                try append("\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            } else { try append(value) }
        }
    }
    private static func key(_ value: String) -> Data { Data(value.utf8) }
    private static func pointerSegment(_ value: String) -> String { value.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
    private static func formula(_ text: String) -> Bool {
        if text.first == "\t" || text.first == "\r" || text.first == "\n" { return true }
        return text.first(where: { !$0.isWhitespace }).map { "=+-@".contains($0) } ?? false
    }

    private static func export(_ document: JSONStructureDocument, options: JSONCSVOptions, produceOutput: Bool) throws -> JSONCSVResult {
        let root = document.nodes[0]
        guard root.kind == .array else { throw DelimitedFailure.unsupported("JSON must be an array of object rows or array rows. Choose the row shape explicitly.", root.range) }
        var columns: [String] = [], columnSources: [NSRange] = [], headerLength = 0, columnIndex: [Data: Int] = [:], rows: [[Int: Int]] = []
        var writer = Writer()
        func addColumn(_ name: String, source: NSRange) throws -> Int {
            let identity = key(name)
            if let index = columnIndex[identity] { return index }
            headerLength += name.utf16.count
            guard headerLength <= JSONProcessor.maximumUTF16Length else { throw DelimitedFailure.limit("Column names exceed the bounded output budget.") }
            let index = columns.count; columns.append(name); columnSources.append(source); columnIndex[identity] = index; return index
        }
        for rowID in root.children {
            try writer.tick()
            let row = document.nodes[rowID]
            guard row.kind == (options.shape == .objects ? .object : .array) else {
                throw DelimitedFailure.unsupported("Each JSON row must match the selected \(options.shape.rawValue.lowercased()) shape; mixed rows are not converted implicitly.", row.range)
            }
            var values: [Int: Int] = [:]
            if options.shape == .arrays {
                if rows.isEmpty { columns = row.children.indices.map { "column\($0 + 1)" } }
                guard row.children.count == columns.count else { throw DelimitedFailure.unsupported("Array rows must have the same number of cells. Ragged rows are not padded or truncated.", row.range) }
                for (index,id) in row.children.enumerated() { values[index] = id }
            } else if options.cells == .flatten {
                var stack = row.children.reversed().map { ($0, "/" + pointerSegment(document.nodes[$0].key!)) }
                while let (id, path) = stack.popLast() {
                    try writer.tick()
                    let node = document.nodes[id]
                    guard node.occurrences == 1 else { throw DelimitedFailure.unsupported("Duplicate object keys cannot become unique table columns.", node.keyRange ?? node.range) }
                    if node.kind == .object, !node.children.isEmpty {
                        stack.append(contentsOf: node.children.reversed().map { ($0, path + "/" + pointerSegment(document.nodes[$0].key!)) })
                    } else { values[try addColumn(path, source: node.keyRange ?? node.range)] = id }
                }
            } else {
                for id in row.children {
                    try writer.tick()
                    let node = document.nodes[id]
                    guard node.occurrences == 1 else { throw DelimitedFailure.unsupported("Duplicate object keys cannot become unique table columns.", node.keyRange ?? node.range) }
                    values[try addColumn(node.key!, source: node.keyRange ?? node.range)] = id
                }
            }
            rows.append(values)
        }
        guard rows.isEmpty || !columns.isEmpty else { throw DelimitedFailure.unsupported("Zero-column rows cannot be represented as CSV/TSV records.", root.range) }
        if options.cells == .flatten {
            let identities = Set(columns.map(key))
            for (index,path) in columns.enumerated() {
                let bytes = Array(path.utf8)
                for slash in bytes.indices.dropFirst() where bytes[slash] == 47 {
                    try writer.tick()
                    if identities.contains(Data(bytes[..<slash])) {
                        throw DelimitedFailure.unsupported("Rows produce conflicting leaf and parent paths. Use JSON cells instead of flattening these mixed structures.", columnSources[index])
                    }
                }
            }
        }
        var warningRange: NSRange?, protected = false
        func spreadsheetValue(_ value: String, range: NSRange) -> String {
            guard formula(value) else { return value }
            if warningRange == nil { warningRange = range }
            if options.protectFormulas { protected = true; return "'" + value }
            return value
        }
        if options.hasHeader, !columns.isEmpty {
            for (index,name) in columns.enumerated() {
                try writer.tick(); if index > 0 { try writer.append(options.format.text) }
                try writer.cell(spreadsheetValue(name, range: index < columnSources.count ? columnSources[index] : root.range), format: options.format)
            }
            try writer.append(options.lineEnding.text)
        }
        for row in rows {
            for column in columns.indices {
                try writer.tick()
                if column > 0 { try writer.append(options.format.text) }
                var value = ""
                if let id = row[column] {
                    let node = document.nodes[id]
                    if options.cells != .text { value = document.fragment(id) }
                    else {
                        switch node.kind {
                        case .object, .array: throw DelimitedFailure.unsupported("Nested values need an explicit choice: JSON cells or Flatten objects in Conversion Settings.", node.range)
                        case .string: value = spreadsheetValue(node.scalar ?? "", range: node.range)
                        case .null: value = ""
                        default: value = node.scalar ?? ""
                        }
                    }
                }
                try writer.cell(value, format: options.format)
            }
            try writer.append(options.lineEnding.text)
        }
        var notes = options.cells == .text ? ["Text cells do not retain JSON types: null, missing fields and empty strings can share an empty cell. Choose JSON cells for typed round trips."] : ["Each non-empty cell is a complete JSON value; blank object cells mean a missing field. No type guessing."]
        if !options.hasHeader, options.shape == .objects { notes.append("Field names are not exported without a header; import generates column1, column2, … .") }
        if options.cells == .flatten { notes.append("Headers are JSON Pointers into each row object. Arrays and empty objects remain JSON cells; no array expansion.") }
        var diagnostics: [JSONDiagnostic] = []
        if let range = warningRange {
            let point = JSONSourceCoordinates(document.source).location(at: range.location)
            diagnostics.append(JSONDiagnostic(severity: .warning, code: "CSV-SPREADSHEET",
                message: protected ? "Spreadsheet protection added an apostrophe to affected text cells or headers. Exported text has changed; protection is not universal across spreadsheet apps." : "Some text cells or headers may be interpreted as formulas by spreadsheet apps. Review the output or enable Spreadsheet protection before using it there.",
                range: NSRange(location: range.location, length: min(1, range.length)), line: point.line, column: point.column))
        }
        try Task.checkCancellation()
        return JSONCSVResult(status: .success, output: produceOutput ? writer.text : nil, diagnostics: diagnostics, notes: notes, rowCount: rows.count, columnCount: columns.count)
    }

    private struct PathNode {
        var name: String
        var children: [Int] = []
        var indices: [Data: Int] = [:]
        var column: Int?
    }
    private static func paths(_ names: [String], table: DelimitedDocument, header: DelimitedRecord) throws -> [PathNode] {
        var trie = [PathNode(name: "")]
        for (column,name) in names.enumerated() {
            try Task.checkCancellation()
            let anchor = table.cells[header.cells.lowerBound + column].range
            guard name.hasPrefix("/") else { throw DelimitedFailure.unsupported("Flatten headers must be non-root JSON Pointers starting with '/'.", anchor) }
            let segments = name.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count <= JSONProcessor.maximumDepth - 1 else { throw DelimitedFailure.limit("Flattened object paths exceed the JSON nesting limit.") }
            var parent = 0
            for raw in segments {
                let units = Array(raw.utf16); var decoded: [UInt16] = [], i = 0
                while i < units.count {
                    if units[i] == 126 {
                        guard i + 1 < units.count, units[i + 1] == 48 || units[i + 1] == 49 else { throw DelimitedFailure.invalid("Invalid JSON Pointer escape in header; use '~0' for '~' and '~1' for '/'.", anchor) }
                        decoded.append(units[i + 1] == 48 ? 126 : 47); i += 2
                    } else { decoded.append(units[i]); i += 1 }
                }
                let segment = String(decoding: decoded, as: UTF16.self)
                guard trie[parent].column == nil else { throw DelimitedFailure.unsupported("Flatten headers contain conflicting leaf and parent paths.", anchor) }
                if let child = trie[parent].indices[key(segment)] { parent = child }
                else {
                    let id = trie.count; trie.append(PathNode(name: segment))
                    trie[parent].indices[key(segment)] = id; trie[parent].children.append(id); parent = id
                }
            }
            guard trie[parent].column == nil, trie[parent].children.isEmpty else { throw DelimitedFailure.unsupported("Flatten headers contain duplicate or conflicting paths.", anchor) }
            trie[parent].column = column
        }
        return trie
    }

    private static func importTable(_ source: String, options: JSONCSVOptions, indentation: JSONIndentation, produceOutput: Bool) throws -> JSONCSVResult {
        let table = try DelimitedTextParser.parse(source, format: options.format)
        guard let first = table.records.first else { throw DelimitedFailure.invalid("No table records were found.", NSRange(location: source.utf16.count, length: 0)) }
        let columns = first.cells.count
        let names = options.hasHeader ? first.cells.map { table.cells[$0].value } : (0..<columns).map { "column\($0 + 1)" }
        if options.shape == .objects {
            var seen: Set<Data> = []
            for (index,name) in names.enumerated() {
                guard seen.insert(key(name)).inserted else { throw DelimitedFailure.unsupported("Duplicate header names cannot become unique JSON object keys. Choose array rows or supply unique headers.", table.cells[first.cells.lowerBound + index].range) }
            }
        }
        let trie = options.cells == .flatten ? try paths(names, table: table, header: first) : []
        let records = options.hasHeader ? Array(table.records.dropFirst()) : table.records
        var writer = Writer()
        try writer.append("[")
        for (rowIndex,record) in records.enumerated() {
            try writer.tick()
            guard record.cells.count == columns else {
                let number = rowIndex + (options.hasHeader ? 2 : 1)
                if hasExtraTrailingEmptyField(record, columns: columns, table: table) {
                    let delimiter = options.format == .tsv ? "TAB" : "comma"
                    let basis = options.hasHeader ? "the header has" : "the first record has"
                    throw DelimitedFailure.invalid("Record \(number) has \(record.cells.count) fields; \(basis) \(columns). A trailing \(delimiter) creates an extra empty field. Remove it, or add a column if intentional.",
                        NSRange(location: NSMaxRange(record.range) - 1, length: 1), related: [.init(.fieldName, first.range)])
                }
                let range = record.cells.count > columns ? table.cells[record.cells.lowerBound + columns].range : NSRange(location: NSMaxRange(record.range), length: 0)
                throw DelimitedFailure.invalid("Record \(rowIndex + (options.hasHeader ? 2 : 1)) has \(record.cells.count) fields; expected \(columns). Ragged records are not padded or truncated.", range, related: [.init(.fieldName, first.range)])
            }
            if rowIndex > 0 { try writer.append(",") }
            try writer.append("\n" + indentation.spaces)
            var values: [String?] = []
            for cellID in record.cells {
                try writer.tick()
                let cell = table.cells[cellID]
                if options.cells != .text {
                    if cell.value.isEmpty {
                        guard options.shape == .objects else { throw DelimitedFailure.invalid("An array cell must contain a JSON value. Use null or \"\" explicitly.", cell.range) }
                        values.append(nil); continue
                    }
                    let parsed = JSONProcessor.process(cell.value, operation: .minify)
                    guard parsed.isValid, let output = parsed.output else {
                        if case .cancelled = parsed.status { throw CancellationError() }
                        if case .resourceLimit = parsed.status { throw DelimitedFailure.limit("A JSON cell exceeds the existing JSON processing limits.") }
                        let issue = parsed.diagnostics.first { $0.severity == .error }
                        throw DelimitedFailure.invalid("Invalid JSON cell. " + (issue?.message ?? "A complete JSON value is required."), table.sourceRange(issue?.range ?? NSRange(location: 0, length: 0), in: cell),
                            related: issue?.related.map { JSONRelatedLocation($0.role, table.sourceRange($0.range, in: cell)) } ?? [], precision: issue?.precision ?? .region)
                    }
                    values.append(output)
                } else if cell.value.isEmpty {
                    switch options.empty {
                    case .string: values.append("\"\"")
                    case .null: values.append("null")
                    case .omit:
                        guard options.shape == .objects else { throw DelimitedFailure.unsupported("Omit field is available only for object rows; array positions cannot be omitted.", cell.range) }
                        values.append(nil)
                    }
                } else if options.inferScalars {
                    let parsed = JSONProcessor.inspectStructure(cell.value)
                    if let doc = parsed.document, [.number, .boolean, .null].contains(doc.nodes[0].kind),
                       cell.value.utf16.elementsEqual(cell.value.trimmingCharacters(in: .whitespacesAndNewlines).utf16) { values.append(cell.value) }
                    else { values.append(JSONTextEncoding.quote(cell.value)) }
                } else { values.append(JSONTextEncoding.quote(cell.value)) }
            }
            if options.cells == .flatten {
                // Sparse selected trie: never generate absent parent objects or a Cartesian row matrix.
                var present: Set<Int> = []
                for id in trie.indices.reversed() {
                    try writer.tick()
                    if let column = trie[id].column { if values[column] != nil { present.insert(id) } }
                    else if trie[id].children.contains(where: { present.contains($0) }) { present.insert(id) }
                }
                func emit(_ id: Int, depth: Int, writer: inout Writer) throws {
                    try writer.tick()
                    if let column = trie[id].column { try writer.append(values[column]!); return }
                    try writer.append("{")
                    let children = trie[id].children.filter { present.contains($0) }
                    for (index,child) in children.enumerated() {
                        if index > 0 { try writer.append(",") }
                        try writer.append("\n" + String(repeating: indentation.spaces, count: depth + 1) + JSONTextEncoding.quote(trie[child].name) + ": ")
                        try emit(child, depth: depth + 1, writer: &writer)
                    }
                    if !children.isEmpty { try writer.append("\n" + String(repeating: indentation.spaces, count: depth)) }
                    try writer.append("}")
                }
                try emit(0, depth: 1, writer: &writer)
            } else {
                try writer.append(options.shape == .objects ? "{" : "[")
                var printed = 0
                for (column,value) in values.enumerated() {
                    try writer.tick()
                    guard let value else { continue }
                    if printed > 0 { try writer.append(",") }; printed += 1
                    try writer.append("\n" + indentation.spaces + indentation.spaces)
                    if options.shape == .objects { try writer.append(JSONTextEncoding.quote(names[column]) + ": ") }
                    try writer.append(value)
                }
                if printed > 0 { try writer.append("\n" + indentation.spaces) }
                try writer.append(options.shape == .objects ? "}" : "]")
            }
        }
        if !records.isEmpty { try writer.append("\n") }
        try writer.append("]")
        // Existing strict parser verifies aggregate depth (root/row + JSON cell), not a new grammar.
        let check = JSONProcessor.process(writer.text, operation: .validate)
        if case .cancelled = check.status { throw CancellationError() }
        guard check.isValid else { throw DelimitedFailure.limit("The combined JSON document exceeds the existing nesting or output limits.") }
        var notes = [options.cells == .text ? (options.inferScalars ? "Only exact JSON number/boolean/null literals are inferred. Other cells remain strings; spaces are preserved." : "Every non-empty cell remains a string; no numeric or date inference.") : "JSON cells preserve value types; empty object cells are omitted, distinct from null and the JSON string \"\"."]
        if options.shape == .arrays, options.hasHeader { notes.append("The first record is treated as a header and excluded from the JSON arrays.") }
        if options.cells == .flatten { notes.append("JSON Pointer segments create objects, including numeric names. Arrays are stored inside JSON cells.") }
        return JSONCSVResult(status: .success, output: produceOutput ? writer.text : nil, notes: notes, rowCount: records.count, columnCount: columns)
    }
}
