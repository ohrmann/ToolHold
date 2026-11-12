import Foundation
import CToml

enum JSONTOMLDirection: String, CaseIterable, Sendable {
    case jsonToTOML = "JSON → TOML", tomlToJSON = "TOML → JSON"
    var inputName: String { self == .jsonToTOML ? "JSON" : "TOML" }
    var outputName: String { self == .jsonToTOML ? "TOML" : "JSON" }
}
enum JSONTOMLTableStyle: String, CaseIterable, Sendable { case sections = "Sections", inline = "Inline tables" }
struct JSONTOMLOptions: Equatable, Sendable {
    var tables = JSONTOMLTableStyle.sections
    var datesAsStrings = true
}
enum JSONTOMLStatus: Equatable, Sendable { case success, invalid, unsupported, resourceLimit, cancelled }
struct JSONTOMLResult: Sendable {
    let status: JSONTOMLStatus
    var output: String?
    var diagnostics: [JSONDiagnostic] = []
    var notes: [String] = []
}
private struct TOMLFailure: Error {
    let status: JSONTOMLStatus
    let message: String
    var range = NSRange(location: 0, length: 0)
    var precision = JSONDiagnostic.Precision.exact
}

/// Only the pinned C parser owns TOML grammar. Its numeric values are never
/// serialized through Double; original token spans are retained by a small adapter.
enum JSONTOMLConverter {
    static let conversionNote = "TOML 1.1 · signed 64-bit integers · no null. Comments, formatting and key escape spelling are not retained."
    static func process(_ source: String, direction: JSONTOMLDirection, options: JSONTOMLOptions = .init(),
                        indentation: JSONIndentation = .two, produceOutput: Bool = true) -> JSONTOMLResult {
        do {
            try Task.checkCancellation()
            guard source.utf16.count <= JSONProcessor.maximumUTF16Length else {
                throw TOMLFailure(status: .resourceLimit, message: "Input exceeds 262,144 UTF-16 code units.")
            }
            var writer = TOMLWriter(), notes = [conversionNote]
            var diagnostics: [JSONDiagnostic] = []
            if direction == .jsonToTOML {
                let parsed = JSONProcessor.inspectStructure(source)
                guard let document = parsed.document else {
                    let status: JSONTOMLStatus
                    switch parsed.result.status { case .cancelled: status = .cancelled; case .resourceLimit: status = .resourceLimit; default: status = .invalid }
                    return .init(status: status, diagnostics: parsed.result.diagnostics)
                }
                guard document.nodes[0].kind == .object else {
                    throw TOMLFailure(status: .unsupported, message: "TOML documents need an object root. Arrays and primitive roots are not wrapped automatically.", range: document.nodes[0].range)
                }
                for node in document.nodes {
                    try Task.checkCancellation()
                    if node.occurrences > 1 { throw TOMLFailure(status: .unsupported, message: "Duplicate JSON keys cannot become a TOML table without losing identity.", range: node.keyRange ?? node.range) }
                    if node.kind == .null { throw TOMLFailure(status: .unsupported, message: "TOML has no null value. Null is not removed, renamed or converted into a string automatically.", range: node.range) }
                    if node.kind == .number {
                        let token = node.scalar ?? document.fragment(node.id)
                        if token.contains(".") || token.contains("e") || token.contains("E") {
                            let mantissa = token.utf8.prefix { $0 != 101 && $0 != 69 }
                            let nonzero = mantissa.contains { (49...57).contains($0) }
                            guard let binary = Double(token), binary.isFinite, binary != 0 || !nonzero else {
                                throw TOMLFailure(status: .unsupported, message: "This number is outside the finite binary64 range supported by the TOML parser. No rounding, overflow or underflow substitution was performed.", range: node.range)
                            }
                        } else if Int64(token) == nil {
                            throw TOMLFailure(status: .unsupported, message: "TOML integers must fit signed 64-bit range. Large JSON integers are not converted into floating point or strings.", range: node.range)
                        }
                    }
                }
                if options.tables == .sections { try emitSection(document, id: 0, path: [], header: nil, writer: &writer) }
                else {
                    for id in document.nodes[0].children {
                        try writer.append(JSONTextEncoding.quote(document.nodes[id].key!) + " = ")
                        try emitInline(document, id: id, writer: &writer)
                        try writer.append("\n")
                    }
                }
                // Validate emitted grammar with the same parser used for import.
                do { _ = try readTOML(writer.text, options: options, indentation: indentation, convert: false) }
                catch let failure as TOMLFailure {
                    throw TOMLFailure(status: failure.status == .resourceLimit ? .resourceLimit : .unsupported,
                        message: "The generated document exceeds TOML representability or parser limits. " + failure.message,
                        range: document.nodes[0].range, precision: .region)
                }
                notes.append(options.tables == .sections ? "Scalar/inline fields precede child sections; object member order can change. Array order is preserved." : "Inline tables preserve JSON member order. String content is preserved; TOML quoting is regenerated.")
                notes.append("Number tokens are copied exactly. TOML consumers may use binary floating point and round decimal values independently of Toolbox.")
            } else {
                let result = try readTOML(source, options: options, indentation: indentation, convert: true)
                writer.text = result.output
                if let date = result.dateRange {
                    let position = JSONSourceCoordinates(source).location(at: date.location)
                    diagnostics = [.init(severity: .warning, code: "TOML-DATE-STRING", message: "TOML date/time values became JSON strings with their original text. JSON has no date/time type; no timezone conversion was applied.", range: date, line: position.line, column: position.column)]
                }
            }
            try Task.checkCancellation()
            return .init(status: .success, output: produceOutput ? writer.text : nil, diagnostics: diagnostics, notes: notes)
        } catch is CancellationError { return .init(status: .cancelled) }
        catch let failure as TOMLFailure {
            if Task.isCancelled { return .init(status: .cancelled) }
            let offset = min(source.utf16.count, max(0, failure.range.location))
            let position = JSONSourceCoordinates(source).location(at: offset)
            return .init(status: failure.status, diagnostics: [.init(severity: .error,
                code: failure.status == .resourceLimit ? "TOML-LIMIT" : failure.status == .unsupported ? "TOML-MAPPING" : "TOML-SYNTAX",
                message: failure.message, range: .init(location: offset, length: min(max(0, failure.range.length), source.utf16.count - offset)),
                line: position.line, column: position.column, precision: failure.precision)])
        } catch {
            return .init(status: .unsupported, diagnostics: [.init(severity: .error, code: "TOML-FAILED", message: "Conversion could not be completed. No partial output was published.", range: .init(location: 0, length: 0), line: 1, column: 1, precision: .region)])
        }
    }

    private static func deferred(_ document: JSONStructureDocument, id: Int) -> Bool {
        let node = document.nodes[id]
        return (node.kind == .object && !node.children.isEmpty) || (node.kind == .array && !node.children.isEmpty && node.children.allSatisfy { document.nodes[$0].kind == .object })
    }
    private static func emitSection(_ document: JSONStructureDocument, id: Int, path: [String], header: String?, writer: inout TOMLWriter) throws {
        try writer.tick()
        if let header {
            if !writer.text.isEmpty { try writer.append("\n") }
            try writer.append(header + "\n")
        }
        for child in document.nodes[id].children where !deferred(document, id: child) {
            try writer.append(JSONTextEncoding.quote(document.nodes[child].key!) + " = ")
            try emitInline(document, id: child, writer: &writer); try writer.append("\n")
        }
        for child in document.nodes[id].children where deferred(document, id: child) {
            let node = document.nodes[child], next = path + [node.key!]
            let name = next.map(JSONTextEncoding.quote).joined(separator: ".")
            if node.kind == .object { try emitSection(document, id: child, path: next, header: "[" + name + "]", writer: &writer) }
            else {
                for value in node.children { try emitSection(document, id: value, path: next, header: "[[" + name + "]]", writer: &writer) }
            }
        }
    }
    private static func emitInline(_ document: JSONStructureDocument, id: Int, writer: inout TOMLWriter) throws {
        try writer.tick()
        let node = document.nodes[id]
        switch node.kind {
        case .object, .array:
            let object = node.kind == .object
            try writer.append(object ? "{" : "[")
            for (index,child) in node.children.enumerated() {
                if index > 0 { try writer.append(", ") }
                if object { try writer.append(JSONTextEncoding.quote(document.nodes[child].key!) + " = ") }
                try emitInline(document, id: child, writer: &writer)
            }
            try writer.append(object ? "}" : "]")
        case .string: try writer.append(JSONTextEncoding.quote(node.scalar ?? ""))
        case .number, .boolean: try writer.append(node.scalar ?? document.fragment(id))
        case .null: throw TOMLFailure(status: .unsupported, message: "TOML has no null value.", range: node.range)
        }
    }

    private static func readTOML(_ source: String, options: JSONTOMLOptions, indentation: JSONIndentation, convert: Bool) throws -> (output: String, dateRange: NSRange?) {
        var bytes = Array(source.utf8); bytes.append(0)
        let parsed = bytes.withUnsafeBytes { buffer in
            toml_toolbox_parse(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(bytes.count - 1), { _ in Task.isCancelled ? 1 : 0 }, nil)
        }
        defer { toml_free(parsed) }
        try Task.checkCancellation()
        let coordinates = TOMLSourceMap(source)
        guard parsed.ok else {
            var error = parsed.errmsg
            let reported = withUnsafeBytes(of: &error) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
            let status: JSONTOMLStatus = parsed.toolbox_error_kind == 1 ? .resourceLimit : parsed.toolbox_error_kind == 2 ? .unsupported : .invalid
            let message = parsed.toolbox_error_kind == 2
                ? "This number is outside the signed 64-bit integer or finite binary64 range supported by the TOML parser. No rounding or substitution was performed."
                : parsed.toolbox_error_kind == 1 ? "Parser resource limit reached. " + reported : reported
            let range = coordinates.range(offset: Int(parsed.toolbox_error_offset), length: 0)
            throw TOMLFailure(status: status, message: message, range: range, precision: .region)
        }
        guard convert else { return ("", nil) }
        var writer = TOMLWriter(), firstDate: NSRange?
        func emit(_ node: toml_datum_t, depth: Int) throws {
            try writer.tick()
            let container = node.type == TOML_ARRAY || node.type == TOML_TABLE
            guard !container || depth < JSONProcessor.maximumDepth else { throw TOMLFailure(status: .resourceLimit, message: "Mapped JSON exceeds 64 container levels.", range: coordinates.region(node)) }
            let count: Int
            switch node.type {
            case TOML_TABLE:
                count = Int(node.u.tab.size); try writer.append("{")
                for index in 0..<count {
                    if index > 0 { try writer.append(",") }
                    let keyBytes = UnsafeBufferPointer(start: UnsafeRawPointer(node.u.tab.key[index]!).assumingMemoryBound(to: UInt8.self), count: Int(node.u.tab.len[index]))
                    guard let key = String(bytes: keyBytes, encoding: .utf8) else { throw TOMLFailure(status: .invalid, message: "A TOML key escape is not a valid Unicode scalar sequence.", range: coordinates.region(node), precision: .region) }
                    try writer.append(JSONTextEncoding.quote(key) + ":")
                    try emit(node.u.tab.value[index], depth: depth + 1)
                }
                try writer.append("}")
            case TOML_ARRAY:
                count = Int(node.u.arr.size); try writer.append("[")
                for index in 0..<count { if index > 0 { try writer.append(",") }; try emit(node.u.arr.elem[index], depth: depth + 1) }
                try writer.append("]")
            case TOML_STRING:
                let valueBytes = UnsafeBufferPointer(start: UnsafeRawPointer(node.u.str.ptr!).assumingMemoryBound(to: UInt8.self), count: Int(node.u.str.len))
                guard let text = String(bytes: valueBytes, encoding: .utf8) else { throw TOMLFailure(status: .invalid, message: "A TOML string escape is not a valid Unicode scalar sequence.", range: coordinates.region(node)) }
                try writer.append(JSONTextEncoding.quote(text))
            case TOML_INT64:
                let raw = coordinates.token(node).replacingOccurrences(of: "_", with: "")
                if raw.hasPrefix("0x") || raw.hasPrefix("0o") || raw.hasPrefix("0b") { try writer.append(String(node.u.int64)) }
                else { try writer.append(raw.hasPrefix("+") ? String(raw.dropFirst()) : raw) }
            case TOML_FP64:
                guard node.u.fp64.isFinite else { throw TOMLFailure(status: .unsupported, message: "JSON has no NaN or Infinity values. They are not converted to null or strings automatically.", range: coordinates.region(node)) }
                let raw = coordinates.token(node).replacingOccurrences(of: "_", with: "")
                try writer.append(raw.hasPrefix("+") ? String(raw.dropFirst()) : raw)
            case TOML_BOOLEAN: try writer.append(node.u.boolean ? "true" : "false")
            case TOML_DATE, TOML_TIME, TOML_DATETIME, TOML_DATETIMETZ:
                guard options.datesAsStrings else { throw TOMLFailure(status: .unsupported, message: "JSON has no date/time type. Enable date/time-to-string conversion explicitly or change the source.", range: coordinates.region(node)) }
                if firstDate == nil { firstDate = coordinates.region(node) }
                try writer.append(JSONTextEncoding.quote(coordinates.token(node)))
            default: throw TOMLFailure(status: .unsupported, message: "The TOML value cannot be represented in strict JSON.", range: coordinates.region(node))
            }
        }
        try emit(parsed.toptab, depth: 0)
        let json = JSONProcessor.process(writer.text, operation: .format, indentation: indentation)
        if case .cancelled = json.status { throw CancellationError() }
        guard json.isValid, let output = json.output else { throw TOMLFailure(status: .resourceLimit, message: "The mapped JSON exceeds existing processing limits.") }
        guard output.utf16.count <= JSONProcessor.maximumUTF16Length else { throw TOMLFailure(status: .resourceLimit, message: "Formatted JSON exceeds 262,144 UTF-16 code units. No partial output was published.") }
        return (output, firstDate)
    }
}

private struct TOMLWriter {
    var text = "", length = 0, steps = 0
    mutating func tick() throws {
        steps += 1
        if steps & 255 == 0 { try Task.checkCancellation() }
        guard steps <= 2_000_000 else { throw TOMLFailure(status: .resourceLimit, message: "TOML conversion work budget reached.") }
    }
    mutating func append(_ value: String) throws {
        try tick(); let count = value.utf16.count
        guard count <= JSONProcessor.maximumUTF16Length - length else { throw TOMLFailure(status: .resourceLimit, message: "Converted output exceeds 262,144 UTF-16 code units.") }
        text += value; length += count
    }
}

private struct TOMLSourceMap {
    let bytes: [UInt8]
    let offsets: [Int]
    let lines: [Int]
    init(_ source: String) {
        bytes = Array(source.utf8)
        var map: [Int] = [], offset = 0, starts = [0], cursor = 0
        for scalar in source.unicodeScalars {
            let count = scalar.utf8.count
            map.append(contentsOf: repeatElement(offset, count: count))
            offset += scalar.utf16.count; cursor += count
            if scalar.value == 10 { starts.append(cursor) }
        }
        map.append(offset); offsets = map; lines = starts
    }
    func range(offset: Int, length: Int) -> NSRange {
        let start = min(bytes.count, max(0, offset)), end = min(bytes.count, max(start, offset + length))
        return NSRange(location: offsets[start], length: offsets[end] - offsets[start])
    }
    func region(_ node: toml_datum_t) -> NSRange {
        if node.toolbox_length > 0 { return range(offset: Int(node.toolbox_offset), length: Int(node.toolbox_length)) }
        let line = min(lines.count - 1, max(0, Int(node.lineno) - 1))
        return range(offset: min(bytes.count, lines[line] + max(0, Int(node.colno) - 1)), length: 0)
    }
    func token(_ node: toml_datum_t) -> String {
        let start = min(bytes.count, max(0, Int(node.toolbox_offset)))
        let end = min(bytes.count, start + max(0, Int(node.toolbox_length)))
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }
}
