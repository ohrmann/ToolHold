import Foundation

enum DelimitedFormat: String, CaseIterable, Sendable {
    case csv = "CSV", tsv = "TSV"
    var separator: UInt16 { self == .csv ? 44 : 9 }
    var text: String { self == .csv ? "," : "\t" }
}
enum JSONCSVStatus: Equatable, Sendable { case success, invalid, unsupported, resourceLimit, cancelled }
struct DelimitedFailure: Error {
    let status: JSONCSVStatus
    let message: String
    let range: NSRange
    var related: [JSONRelatedLocation] = []
    var precision = JSONDiagnostic.Precision.exact
    var configuration = false
    static func invalid(_ message: String, _ range: NSRange, related: [JSONRelatedLocation] = [], precision: JSONDiagnostic.Precision = .exact) -> Self {
        Self(status: .invalid, message: message, range: range, related: related, precision: precision)
    }
    static func options(_ message: String) -> Self {
        Self(status: .unsupported, message: message, range: NSRange(location: 0, length: 0), precision: .region, configuration: true)
    }
    static func unsupported(_ message: String, _ range: NSRange) -> Self { Self(status: .unsupported, message: message, range: range) }
    static func limit(_ message: String) -> Self { Self(status: .resourceLimit, message: message, range: NSRange(location: 0, length: 0)) }
}

struct DelimitedCell: Sendable {
    let value: String
    let range: NSRange
    let quoted: Bool
}
struct DelimitedRecord: Sendable {
    let cells: Range<Int>
    let range: NSRange
}
/// Immutable memory-only table with source coordinates. No view/model objects per cell.
struct DelimitedDocument: Sendable {
    let source: String
    let cells: [DelimitedCell]
    let records: [DelimitedRecord]

    /// Decode doubled quotes while mapping an inner JSON diagnostic back to original CSV UTF-16.
    func sourceRange(_ decoded: NSRange, in cell: DelimitedCell) -> NSRange {
        guard cell.quoted else { return NSRange(location: cell.range.location + min(decoded.location, cell.range.length), length: min(decoded.length, max(0, cell.range.length - decoded.location))) }
        let raw = Array((source as NSString).substring(with: cell.range).utf16)
        var positions: [Int] = [], index = 1
        while index + 1 < raw.count {
            positions.append(cell.range.location + index)
            if raw[index] == 34, index + 1 < raw.count - 1, raw[index + 1] == 34 { index += 1 }
            index += 1
        }
        positions.append(cell.range.location + max(0, raw.count - 1))
        let start = positions[min(max(0, decoded.location), positions.count - 1)]
        let end = positions[min(max(0, NSMaxRange(decoded)), positions.count - 1)]
        return NSRange(location: start, length: max(0, end - start))
    }
}

enum DelimitedTextParser {
    /// RFC 4180 quote grammar; Unicode, BOM and LF/CR line endings are explicit extensions.
    /// TSV uses the same quoted-field dialect with TAB as delimiter (not backslash escapes).
    static func parse(_ source: String, format: DelimitedFormat) throws -> DelimitedDocument {
        let units = Array(source.utf16.prefix(JSONProcessor.maximumUTF16Length + 1))
        guard units.count <= JSONProcessor.maximumUTF16Length else { throw DelimitedFailure.limit("Input exceeds 262,144 UTF-16 code units.") }
        var cells: [DelimitedCell] = [], records: [DelimitedRecord] = []
        var index = units.first == 0xFEFF ? 1 : 0, recordStart = 0
        guard index < units.count else { return DelimitedDocument(source: source, cells: [], records: []) }
        while index < units.count {
            try Task.checkCancellation()
            recordStart = index
            let cellStart = cells.count
            while true {
                try Task.checkCancellation()
                let start = index, quoted = index < units.count && units[index] == 34
                let value: String
                if quoted {
                    index += 1
                    var decoded: [UInt16] = [], closed = false
                    while index < units.count {
                        if index & 255 == 0 { try Task.checkCancellation() }
                        if units[index] == 34 {
                            if index + 1 < units.count, units[index + 1] == 34 { decoded.append(34); index += 2 }
                            else { index += 1; closed = true; break }
                        } else { decoded.append(units[index]); index += 1 }
                    }
                    guard closed else {
                        throw DelimitedFailure.invalid("Unterminated quoted field; expected a closing double quote before end of input.", NSRange(location: units.count, length: 0), related: [.init(.stringStart, NSRange(location: start, length: 1))])
                    }
                    guard index == units.count || [format.separator, 10, 13].contains(units[index]) else {
                        throw DelimitedFailure.invalid("Expected a delimiter or line ending after the closing quote. Spaces after a quoted field are not discarded.", NSRange(location: index, length: 1))
                    }
                    value = String(decoding: decoded, as: UTF16.self)
                } else {
                    while index < units.count, ![format.separator, 10, 13].contains(units[index]) {
                        if index & 255 == 0 { try Task.checkCancellation() }
                        guard units[index] != 34 else { throw DelimitedFailure.invalid("A quote inside an unquoted field must be enclosed in double quotes and escaped as two double quotes.", NSRange(location: index, length: 1)) }
                        index += 1
                    }
                    value = String(decoding: units[start..<index], as: UTF16.self)
                }
                cells.append(DelimitedCell(value: value, range: NSRange(location: start, length: index - start), quoted: quoted))
                if index < units.count, units[index] == format.separator { index += 1; continue }
                records.append(DelimitedRecord(cells: cellStart..<cells.count, range: NSRange(location: recordStart, length: index - recordStart)))
                if index < units.count {
                    if units[index] == 13, index + 1 < units.count, units[index + 1] == 10 { index += 1 }
                    index += 1
                }
                break
            }
        }
        return DelimitedDocument(source: source, cells: cells, records: records)
    }
}

/// Shared JSON string escaping; values never pass through Foundation JSON dictionaries.
enum JSONTextEncoding {
    static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0...31, 0x7F...0x9F, 0x2028, 0x2029: result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
