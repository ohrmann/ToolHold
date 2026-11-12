import Foundation
import CYaml

/// Strict JSON ↔ YAML 1.2 Core data conversion. No Any/Double bridge, object construction or I/O.
enum JSONYAMLDirection: String, CaseIterable, Sendable {
    case jsonToYAML = "JSON → YAML", yamlToJSON = "YAML → JSON"
    var inputName: String { self == .jsonToYAML ? "JSON" : "YAML" }
    var outputName: String { self == .jsonToYAML ? "YAML" : "JSON" }
}
enum JSONYAMLStatus: Equatable, Sendable { case success, invalid, unsupported, resourceLimit, cancelled }
struct JSONYAMLResult: Sendable {
    let status: JSONYAMLStatus
    var output: String?
    var diagnostics: [JSONDiagnostic] = []
    var notes: [String] = []
}

enum JSONYAMLConverter {
    static let maximumOutputLength = JSONProcessor.maximumUTF16Length
    static let conversionNote = "Data conversion preserves values, not comments, anchor names, whitespace or string escape spelling."

    static func process(_ source: String, direction: JSONYAMLDirection, indentation: JSONIndentation = .two,
                        produceOutput: Bool = true) -> JSONYAMLResult {
        do {
            try Task.checkCancellation()
            guard source.utf16.count <= JSONProcessor.maximumUTF16Length else { throw Failure.limit("Input exceeds 262,144 UTF-16 code units.", 0) }
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalid("Enter a JSON or YAML value before converting.", 0, 0) }
            switch direction {
            case .jsonToYAML:
                let parsed = JSONProcessor.inspectStructure(source)
                guard let document = parsed.document else {
                    return JSONYAMLResult(status: parsed.result.status == .cancelled ? .cancelled : {
                        if case .resourceLimit = parsed.result.status { return .resourceLimit }; return .invalid
                    }(), diagnostics: parsed.result.diagnostics)
                }
                if let duplicate = document.nodes.first(where: { $0.occurrences > 1 }) {
                    throw Failure.unsupported("Duplicate object keys cannot be converted to a YAML mapping without losing identity.", duplicate.keyRange?.location ?? duplicate.range.location, duplicate.keyRange?.length ?? 0)
                }
                var writer = Writer(indent: indentation.spaces)
                try writer.yaml(document, id: 0, depth: 0)
                try writer.append("\n")
                try Task.checkCancellation()
                return JSONYAMLResult(status: .success, output: produceOutput ? writer.text : nil, notes: [conversionNote])
            case .yamlToJSON:
                var reader = YAMLReader(source)
                let nodes = try reader.read()
                var writer = Writer(indent: indentation.spaces)
                try writer.json(nodes, id: 0, depth: 0)
                try Task.checkCancellation()
                var warnings: [JSONDiagnostic] = []
                if let range = writer.mergeKey {
                    let location = JSONSourceCoordinates(source).location(at: range.location)
                    warnings.append(JSONDiagnostic(severity: .warning, code: "YAML-MERGE-LITERAL",
                        message: "YAML 1.2 Core treats '<<' as a literal key. Inherited fields are not merged; review the output before using it.",
                        range: range, line: location.line, column: location.column))
                }
                return JSONYAMLResult(status: .success, output: produceOutput ? writer.text : nil, diagnostics: warnings,
                    notes: [conversionNote, "YAML 1.2 Core types; yes/no/on/off and untagged dates remain strings. Aliases are expanded; merge-key extensions are not applied."])
            }
        } catch is CancellationError { return JSONYAMLResult(status: .cancelled) }
        catch let failure as Failure {
            let offset = min(max(0, failure.offset), source.utf16.count)
            let position = offset == 0 ? (line: 1, column: 1) : JSONSourceCoordinates(source).location(at: offset)
            let diagnostic = JSONDiagnostic(severity: .error, code: failure.code, message: failure.message,
                range: NSRange(location: offset, length: min(failure.length, source.utf16.count - offset)),
                line: position.line, column: position.column, precision: failure.precision)
            return JSONYAMLResult(status: failure.status, diagnostics: [diagnostic])
        } catch {
            return JSONYAMLResult(status: .unsupported, diagnostics: [JSONDiagnostic(severity: .error,
                code: "CONVERT-FAILED", message: "Conversion could not be completed. No partial output was published.",
                range: NSRange(location: 0, length: 0), line: 1, column: 1, precision: .region)])
        }
    }

    private struct Failure: Error {
        let status: JSONYAMLStatus, message: String, offset: Int, length: Int
        var precision = JSONDiagnostic.Precision.exact
        var code: String { status == .resourceLimit ? "CONVERT-LIMIT" : status == .unsupported ? "CONVERT-UNSUPPORTED" : "YAML-SYNTAX" }
        static func limit(_ text: String, _ offset: Int) -> Self { .init(status: .resourceLimit, message: text, offset: offset, length: 0) }
        static func invalid(_ text: String, _ offset: Int, _ length: Int = 1) -> Self { .init(status: .invalid, message: text, offset: offset, length: length) }
        static func unsupported(_ text: String, _ offset: Int, _ length: Int = 0) -> Self { .init(status: .unsupported, message: text, offset: offset, length: length) }
    }
    private struct YAMLNode {
        enum Kind { case map, sequence, scalar, alias(Int) }
        var kind: Kind
        var children: [Int] = []
        var scalar = ""
        var tag: String?
        var plain = true
        var offset: Int
        var length: Int
    }

    /// Event parsing never recursively composes aliases or a deep Swift value tree.
    private struct YAMLReader {
        let source: String
        let offsets: [Int]
        init(_ source: String) {
            self.source = source
            var positions = [0], offset = 0
            for scalar in source.unicodeScalars { offset += scalar.utf16.count; positions.append(offset) }
            offsets = positions // libyaml marks count Unicode scalars, not bytes or UTF-16.
        }
        func position(_ mark: yaml_mark_t) -> Int { offsets[min(Int(mark.index), offsets.count - 1)] }
        func string(_ ptr: UnsafePointer<UInt8>?) -> String? { ptr.map { String(cString: $0) } }
        mutating func read() throws -> [YAMLNode] {
            var parser = yaml_parser_t()
            guard yaml_parser_initialize(&parser) != 0 else { throw Failure.limit("YAML parser could not allocate memory.", 0) }
            defer { yaml_parser_delete(&parser) }
            var bytes = Array(source.utf8)
            // libyaml retains this pointer: its entire lifetime is enclosed by withUnsafeBytes.
            return try bytes.withUnsafeMutableBufferPointer { buffer in
                yaml_parser_set_input_string(&parser, buffer.baseAddress, buffer.count)
                var nodes: [YAMLNode] = [], stack: [Int] = [], anchors: [Data: Int] = [:], documents = 0
                while true {
                    try Task.checkCancellation()
                    var event = yaml_event_t()
                    guard yaml_parser_parse(&parser, &event) != 0 else {
                        if parser.error == YAML_MEMORY_ERROR { throw Failure.limit("YAML parser could not allocate memory.", position(parser.problem_mark)) }
                        let message = parser.problem.map { String(cString: $0) } ?? "YAML could not be parsed."
                        if parser.error == YAML_READER_ERROR {
                            let byteOffset = min(Int(parser.problem_offset), source.utf8.count)
                            let prefix = String(decoding: source.utf8.prefix(byteOffset), as: UTF8.self)
                            throw Failure.invalid(message.prefix(240).description, prefix.utf16.count, 1)
                        }
                        throw Failure.invalid(message.prefix(240).description, position(parser.problem_mark), 0)
                    }
                    defer { yaml_event_delete(&event) }
                    let start = position(event.start_mark), end = position(event.end_mark)
                    var node: YAMLNode?, anchor: String?
                    switch event.type {
                    case YAML_STREAM_END_EVENT:
                        guard !nodes.isEmpty else { throw Failure.invalid("No YAML value was found.", 0, 0) }
                        return nodes
                    case YAML_DOCUMENT_START_EVENT:
                        documents += 1
                        guard documents == 1 else { throw Failure.unsupported("Multiple YAML documents require an explicit selection; convert one document at a time.", start) }
                        if let version = event.data.document_start.version_directive?.pointee,
                           version.major != 1 || version.minor != 2 {
                            throw Failure.unsupported("This converter uses YAML 1.2 Core. Remove or update the incompatible YAML version directive.", start)
                        }
                    case YAML_SCALAR_EVENT:
                        let scalar = event.data.scalar
                        node = YAMLNode(kind: .scalar,
                            scalar: String(decoding: UnsafeBufferPointer(start: scalar.value, count: scalar.length), as: UTF8.self),
                            tag: string(scalar.tag), plain: scalar.style == YAML_PLAIN_SCALAR_STYLE,
                            offset: start, length: max(0, end - start))
                        anchor = string(scalar.anchor)
                    case YAML_MAPPING_START_EVENT:
                        guard stack.count < JSONProcessor.maximumDepth else { throw Failure.limit("Nesting exceeds the 64-level limit.", start) }
                        let tag = string(event.data.mapping_start.tag)
                        guard tag == nil || tag == "tag:yaml.org,2002:map" else { throw Failure.unsupported("This mapping tag has no supported JSON representation.", start) }
                        node = YAMLNode(kind: .map, offset: start, length: max(0, end - start))
                        anchor = string(event.data.mapping_start.anchor)
                    case YAML_SEQUENCE_START_EVENT:
                        guard stack.count < JSONProcessor.maximumDepth else { throw Failure.limit("Nesting exceeds the 64-level limit.", start) }
                        let tag = string(event.data.sequence_start.tag)
                        guard tag == nil || tag == "tag:yaml.org,2002:seq" else { throw Failure.unsupported("This sequence tag has no supported JSON representation.", start) }
                        node = YAMLNode(kind: .sequence, offset: start, length: max(0, end - start))
                        anchor = string(event.data.sequence_start.anchor)
                    case YAML_ALIAS_EVENT:
                        guard let name = string(event.data.alias.anchor), let target = anchors[Data(name.utf8)] else { throw Failure.invalid("Alias refers to an anchor that has not been defined.", start, max(0, end - start)) }
                        node = YAMLNode(kind: .alias(target), offset: start, length: max(0, end - start))
                    case YAML_MAPPING_END_EVENT, YAML_SEQUENCE_END_EVENT:
                        guard let id = stack.popLast() else { throw Failure.invalid("Unexpected container end.", start) }
                        nodes[id].length = max(0, end - nodes[id].offset)
                    default: break
                    }
                    if let node {
                        let id = nodes.count
                        if let parent = stack.last { nodes[parent].children.append(id) }
                        nodes.append(node)
                        if let anchor { anchors[Data(anchor.utf8)] = id }
                        switch node.kind { case .map, .sequence: stack.append(id); default: break }
                    }
                }
            }
        }
    }

    private struct Writer {
        let indent: String
        var text = ""
        var count = 0
        var steps = 0
        var active: Set<Int> = []
        var mergeKey: NSRange?
        mutating func append(_ value: String) throws {
            let size = value.utf16.count
            guard size <= maximumOutputLength - count else { throw Failure.limit("Converted output exceeds 262,144 UTF-16 code units. No partial result was published.", 0) }
            text += value; count += size
        }
        mutating func tick(_ offset: Int) throws {
            steps += 1; if steps & 255 == 0 { try Task.checkCancellation() }
            guard steps <= 2_000_000 else { throw Failure.limit("Conversion work budget reached.", offset) }
        }
        func padding(_ depth: Int) -> String { String(repeating: indent, count: depth) }
        mutating func yaml(_ doc: JSONStructureDocument, id: Int, depth: Int) throws {
            let node = doc.nodes[id]
            try tick(node.range.location)
            switch node.kind {
            case .object, .array:
                if node.children.isEmpty { try append(node.kind == .object ? "{}" : "[]"); return }
                for (index, childID) in node.children.enumerated() {
                    if index > 0 { try append("\n" + padding(depth)) }
                    let child = doc.nodes[childID]
                    if node.kind == .object { try append(quote(child.key!) + ":") }
                    else { try append("-") }
                    if (child.kind == .object || child.kind == .array), !child.children.isEmpty {
                        try append("\n" + padding(depth + 1)); try yaml(doc, id: childID, depth: depth + 1)
                    } else { try append(" "); try yaml(doc, id: childID, depth: depth + 1) }
                }
            case .string: try append(quote(node.scalar ?? ""))
            default: try append(node.scalar ?? "null")
            }
        }
        mutating func resolve(_ nodes: [YAMLNode], _ id: Int) throws -> Int {
            var target = id, seen: Set<Int> = []
            while case .alias(let next) = nodes[target].kind {
                try tick(nodes[target].offset)
                guard seen.insert(target).inserted else { throw Failure.unsupported("Cyclic YAML aliases cannot be represented as JSON.", nodes[id].offset, nodes[id].length) }
                target = next
            }
            return target
        }
        mutating func json(_ nodes: [YAMLNode], id original: Int, depth: Int) throws {
            let id = try resolve(nodes, original), node = nodes[id]
            try tick(node.offset)
            guard active.insert(id).inserted else { throw Failure.unsupported("Cyclic YAML aliases cannot be represented as JSON.", nodes[original].offset, nodes[original].length) }
            defer { active.remove(id) }
            switch node.kind {
            case .scalar:
                let scalar = try scalar(node)
                try append(scalar.string ? quote(scalar.text) : scalar.text)
            case .map, .sequence:
                guard depth < JSONProcessor.maximumDepth else { throw Failure.limit("Expanded aliases exceed the 64-level nesting limit.", nodes[original].offset) }
                let mapping: Bool = { if case .map = node.kind { return true }; return false }()
                try append(mapping ? "{" : "[")
                var seen: Set<Data> = [], index = 0
                while index < node.children.count {
                    try tick(node.offset)
                    if index > 0 { try append(",") }
                    try append("\n" + padding(depth + 1))
                    if mapping {
                        let key = nodes[try resolve(nodes, node.children[index])]
                        guard case .scalar = key.kind else { throw Failure.unsupported("JSON object keys must be strings; complex YAML mapping keys are not supported.", key.offset, key.length) }
                        let value = try scalar(key)
                        if key.plain, key.tag == nil, value.text == "<<", mergeKey == nil {
                            let originalKey = nodes[node.children[index]]
                            mergeKey = NSRange(location: originalKey.offset, length: originalKey.length)
                        }
                        guard value.string else { throw Failure.unsupported("JSON object keys must be strings. Quote this YAML key to keep its textual spelling.", key.offset, key.length) }
                        guard seen.insert(Data(value.text.utf8)).inserted else { throw Failure.unsupported("Duplicate mapping keys cannot be converted without losing identity.", key.offset, key.length) }
                        try append(quote(value.text) + ": ")
                        index += 1
                    }
                    guard index < node.children.count else { throw Failure.invalid("Mapping value is missing.", node.offset) }
                    try json(nodes, id: node.children[index], depth: depth + 1)
                    index += 1
                }
                if !node.children.isEmpty { try append("\n" + padding(depth)) }
                try append(mapping ? "}" : "]")
            case .alias: throw Failure.unsupported("Alias could not be represented as JSON.", node.offset, node.length)
            }
        }
    }

    private static func scalar(_ node: YAMLNode) throws -> (text: String, string: Bool) {
        let value = node.scalar, tag = node.tag
        let prefix = "tag:yaml.org,2002:"
        let name = tag.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }
        if name == "str" || name == "!" || (name == nil && !node.plain) { return (value, true) }
        if let name, !["null", "bool", "int", "float"].contains(name) {
            throw Failure.unsupported("This YAML tag has no supported JSON representation.", node.offset, node.length)
        }
        if (name == nil || name == "null"), ["", "~", "null", "Null", "NULL"].contains(value) { return ("null", false) }
        if (name == nil || name == "bool"), ["true", "True", "TRUE", "false", "False", "FALSE"].contains(value) { return (value.lowercased(), false) }
        if name == "int", value.range(of: #"\A(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)\z"#, options: .regularExpression) == nil {
            throw Failure.invalid("Scalar does not match its explicit YAML integer tag.", node.offset, node.length)
        }
        if name == "float", value.hasPrefix("0x") || value.hasPrefix("0o") {
            throw Failure.invalid("Scalar does not match its explicit YAML float tag.", node.offset, node.length)
        }
        if name == nil || name == "int" || name == "float" {
            if let number = try number(value, at: node.offset) { return (number, false) }
            if [".nan", ".NaN", ".NAN", ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF", "-.inf", "-.Inf", "-.INF"].contains(value) {
                throw Failure.unsupported("JSON does not support NaN or infinite numbers.", node.offset, node.length)
            }
        }
        if name != nil { throw Failure.invalid("Scalar does not match its explicit YAML tag.", node.offset, node.length) }
        return (value, true)
    }

    /// Exact decimal normalization; never passes through Int/Double/Decimal.
    private static func number(_ source: String, at offset: Int) throws -> String? {
        func matches(_ pattern: String) -> Bool { source.range(of: pattern, options: .regularExpression) != nil }
        if source.hasPrefix("0x") || source.hasPrefix("0o") {
            let base = source.hasPrefix("0x") ? 16 : 8
            let digits = source.dropFirst(2)
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.hexDigitValue.map { $0 < base } == true }) else { return nil }
            // Base conversion is quadratic; reject only unreasonably expensive non-decimal conversion.
            guard digits.count <= 4096 else { throw Failure.limit("Non-decimal integer conversion exceeds the bounded arithmetic budget.", offset) }
            var decimal: [Int] = [0]
            for (index, digit) in digits.enumerated() {
                if index & 31 == 0 { try Task.checkCancellation() }
                var carry = digit.hexDigitValue!
                for i in decimal.indices { let n = decimal[i] * base + carry; decimal[i] = n % 10; carry = n / 10 }
                while carry > 0 { decimal.append(carry % 10); carry /= 10 }
            }
            return decimal.reversed().map(String.init).joined()
        }
        guard matches(#"\A[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?\z"#) else { return nil }
        var value = source
        if value.first == "+" { value.removeFirst() }
        let negative = value.first == "-"
        if negative { value.removeFirst() }
        let exponentIndex = value.firstIndex { $0 == "e" || $0 == "E" }
        let exponent = exponentIndex.map { String(value[$0...]) } ?? ""
        var mantissa = exponentIndex.map { String(value[..<$0]) } ?? value
        if mantissa.first == "." { mantissa = "0" + mantissa }
        let decimal = mantissa.firstIndex(of: ".")
        var integer = decimal.map { String(mantissa[..<$0]) } ?? mantissa
        let fraction = decimal.map { String(mantissa[$0...]) } ?? ""
        let significant = integer.drop(while: { $0 == "0" })
        integer = significant.isEmpty ? "0" : String(significant)
        mantissa = integer + (fraction == "." ? ".0" : fraction)
        return (negative ? "-" : "") + mantissa + exponent
    }

    /// JSON double quotes are also valid YAML double quotes. Escape YAML's extra line breaks.
    static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0...31, 0x7F...0x9F, 0x2028, 0x2029:
                result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
