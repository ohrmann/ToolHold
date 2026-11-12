import Foundation

struct JSONResult: Sendable {
    let output: String?
    let diagnostics: [JSONDiagnostic]
    let status: JSONProcessingStatus
    var isValid: Bool { status == .valid }
    init(output: String?, diagnostics: [JSONDiagnostic], status: JSONProcessingStatus? = nil) {
        self.output = output; self.diagnostics = diagnostics
        if let status { self.status = status }
        else if let error = diagnostics.first(where: { $0.severity == .error }) {
            if case .resourceLimit(let reason) = error.kind { self.status = .resourceLimit(reason) }
            else { self.status = .invalid }
        } else { self.status = .valid }
    }
}

enum JSONIndentation: Int, Codable, CaseIterable, Sendable {
    case two = 2, four = 4
    var spaces: String { String(repeating: " ", count: rawValue) }
}

enum JSONProcessor {
    enum Operation: Sendable { case validate, format, minify }
    static let maximumUTF16Length = 262_144
    static let maximumDepth = 64

    static func inspectStructure(_ source: String) -> JSONStructureResult {
        var parser = Parser(source: source, indentation: .two, capture: true)
        do {
            try Task.checkCancellation()
            guard parser.units.count <= maximumUTF16Length else {
                throw parser.diagnostic("JSON-LIMIT", "Input exceeds the 262,144 UTF-16 code unit limit.", length: 0,
                                        kind: .resourceLimit(.inputSize))
            }
            _ = try parser.document(pretty: false)
            try Task.checkCancellation()
            let document = JSONStructureDocument(source: source, nodes: parser.nodes)
            return JSONStructureResult(result: JSONResult(output: nil, diagnostics: parser.warnings), document: document)
        } catch is CancellationError {
            return JSONStructureResult(result: JSONResult(output: nil, diagnostics: [], status: .cancelled), document: nil)
        } catch let error as JSONDiagnostic {
            return JSONStructureResult(result: JSONResult(output: nil, diagnostics: parser.warnings + [error]), document: nil)
        } catch {
            return JSONStructureResult(result: JSONResult(output: nil, diagnostics: [parser.diagnostic("JSON-INVALID", "The document could not be processed.", precision: .region)]), document: nil)
        }
    }

    static func process(_ source: String, operation: Operation, indentation: JSONIndentation = .two) -> JSONResult {
        if Task.isCancelled { return JSONResult(output: nil, diagnostics: [], status: .cancelled) }
        var parser = Parser(source: source, indentation: indentation)
        do {
            guard parser.units.count <= maximumUTF16Length else {
                throw parser.diagnostic("JSON-LIMIT", "Input exceeds the 262,144 UTF-16 code unit limit.", length: 0,
                                        kind: .resourceLimit(.inputSize))
            }
            let output = try parser.document(pretty: operation == .format)
            try Task.checkCancellation()
            return JSONResult(output: operation == .validate ? nil : output, diagnostics: parser.warnings)
        } catch is CancellationError {
            return JSONResult(output: nil, diagnostics: [], status: .cancelled)
        } catch let error as JSONDiagnostic {
            return JSONResult(output: nil, diagnostics: parser.warnings + [error])
        } catch {
            return JSONResult(output: nil, diagnostics: [parser.diagnostic("JSON-INVALID", "The document could not be processed.", precision: .region)])
        }
    }
}

private struct Parser {
    let units: [UInt16]
    let indentation: JSONIndentation
    var offset = 0
    var warnings: [JSONDiagnostic] = []
    var containers: [JSONRelatedLocation] = []
    let capture: Bool
    var nodes: [JSONStructureNode] = []
    var parent: Int?
    var memberKey: String?
    var memberKeyRange: NSRange?
    var arrayIndex: Int?


    init(source: String, indentation: JSONIndentation, capture: Bool = false) {
        self.capture = capture
        units = Array(source.utf16.prefix(JSONProcessor.maximumUTF16Length + 1))
        self.indentation = indentation
    }
    var current: UInt16? { offset < units.count ? units[offset] : nil }
    mutating func whitespace() throws {
        while let c = current, [9, 10, 13, 32].contains(c) {
            if offset & 255 < 8 { try Task.checkCancellation() }
            offset += 1
        }
    }
    func diagnostic(_ code: String, _ message: String, at position: Int? = nil,
                    severity: JSONDiagnostic.Severity = .error, length: Int = 1,
                    expected: [JSONExpectedToken] = [], related: [JSONRelatedLocation] = [],
                    precision: JSONDiagnostic.Precision = .exact, kind: JSONDiagnostic.Kind = .syntax) -> JSONDiagnostic {
        let p = min(max(0, position ?? offset), units.count)
        var line = 1, column = 1, index = 0
        while index < p {
            if units[index] == 13 {
                line += 1; column = 1
                if index + 1 < p, units[index + 1] == 10 { index += 1 }
            } else if units[index] == 10 { line += 1; column = 1 }
            else { column += 1 }
            index += 1
        }
        var locations = related
        if let container = containers.last, !locations.contains(container) { locations.append(container) }
        return JSONDiagnostic(severity: severity, code: code, message: message,
                              range: NSRange(location: p, length: min(max(0, length), units.count - p)),
                              line: line, column: column, expected: expected, related: locations,
                              precision: precision, kind: kind)
    }
    mutating func document(pretty: Bool) throws -> String {
        try whitespace()
        guard current != nil else { throw diagnostic("JSON-EMPTY", "Enter a JSON value.", expected: [.value]) }
        let rootStart = offset
        let output = try value(depth: 0, pretty: pretty)
        try whitespace()
        guard current == nil else { throw diagnostic("JSON-011", "Unexpected text after the root JSON value.", expected: [.endOfDocument], related: [.init(.valueStart, NSRange(location: rootStart, length: 0))]) }
        return output
    }
    mutating func value(depth: Int, pretty: Bool, introducedBy: JSONRelatedLocation? = nil) throws -> String {
        try Task.checkCancellation()
        try whitespace()
        let related = introducedBy.map { [$0] } ?? []
        guard let c = current else { throw diagnostic("JSON-EOF", "Expected a JSON value before end of input.", expected: [.value], related: related) }
        let nodeID = capture ? nodes.count : nil
        let start = offset
        if capture {
            let kind: JSONStructureNode.Kind = c == 123 ? .object : c == 91 ? .array : c == 34 ? .string : c == 110 ? .null : (c == 116 || c == 102) ? .boolean : .number
            nodes.append(JSONStructureNode(id: nodes.count, parent: parent, kind: kind, depth: depth,
                key: memberKey, keyRange: memberKeyRange, arrayIndex: arrayIndex,
                range: NSRange(location: start, length: 0)))
            if let parent { nodes[parent].children.append(nodeID!) }
        }
        let previousParent = parent
        if let nodeID { parent = nodeID }
        defer {
            if let nodeID { nodes[nodeID].range.length = offset - start }
            parent = previousParent
        }
        switch c {
        case 123, 91:
            guard depth < JSONProcessor.maximumDepth else { throw diagnostic("JSON-DEPTH", "Nesting exceeds the 64-level limit.", kind: .resourceLimit(.nestingDepth)) }
            return try container(object: c == 123, depth: depth, pretty: pretty)
        case 34:
            let token = try string()
            if let nodeID { nodes[nodeID].scalar = try JSONDecoder().decode(String.self, from: Data(token.utf8)) }
            return token
        case 45, 48...57:
            let token = try number()
            if let nodeID { nodes[nodeID].scalar = token }
            return token
        case 116: if let nodeID { nodes[nodeID].scalar = "true" }; return try literal("true", expected: .trueLiteral)
        case 102: if let nodeID { nodes[nodeID].scalar = "false" }; return try literal("false", expected: .falseLiteral)
        case 110: if let nodeID { nodes[nodeID].scalar = "null" }; return try literal("null", expected: .nullLiteral)
        case 39, 0x201C, 0x201D: throw diagnostic("JSON-006", "JSON strings require straight double quotes (\").", expected: [.value], related: related)
        default: throw diagnostic("JSON-008", "Expected an object, array, string, number, true, false or null.", expected: [.value], related: related)
        }
    }
    mutating func container(object: Bool, depth: Int, pretty: Bool) throws -> String {
        let opening = JSONRelatedLocation(.containerStart, NSRange(location: offset, length: 1))
        containers.append(opening)
        defer { containers.removeLast() }
        let close: UInt16 = object ? 125 : 93
        let closeText = object ? "}" : "]"
        offset += 1; try whitespace()
        if current == close { offset += 1; return object ? "{}" : "[]" }
        var members: [String] = []
        var keys: [Data: NSRange] = [:]
        var count = 0
        let containerID = capture ? parent : nil
        var introducer = opening
        while true {
            try whitespace()
            try requireMember(object: object, first: count == 0, introducer: introducer)
            memberKey = nil; memberKeyRange = nil; arrayIndex = object ? nil : count
            let prefix = object ? try fieldPrefix(keys: &keys, pretty: pretty, introducer: &introducer) : ""
            let content = try value(depth: depth + 1, pretty: pretty, introducedBy: introducer)
            if !capture { members.append(prefix + content) }
            count += 1
            if try finishMember(object: object, introducer: &introducer) { break }
        }
        if let containerID, object {
            var occurrences: [Data: [Int]] = [:]
            for id in nodes[containerID].children { occurrences[Data(nodes[id].key!.utf8), default: []].append(id) }
            for ids in occurrences.values where ids.count > 1 {
                for (ordinal, id) in ids.enumerated() { nodes[id].occurrence = ordinal + 1; nodes[id].occurrences = ids.count }
            }
        }
        if capture { return "" }
        if !pretty { return (object ? "{" : "[") + members.joined(separator: ",") + closeText }
        let indent = String(repeating: indentation.spaces, count: depth + 1)
        return (object ? "{" : "[") + "\n" + indent + members.joined(separator: ",\n" + indent)
            + "\n" + String(repeating: indentation.spaces, count: depth) + closeText
    }
    // Keep error construction out of recursive container frames. This preserves the
    // 64-level contract on the smaller Swift concurrency worker stacks in Debug too.
    @inline(never) func requireMember(object: Bool, first: Bool, introducer: JSONRelatedLocation) throws {
        let closeText = object ? "}" : "]"
        let closeToken: JSONExpectedToken = object ? .objectEnd : .arrayEnd
        let expected: [JSONExpectedToken] = object ? (first ? [.fieldName, closeToken] : [.fieldName]) : (first ? [.value, closeToken] : [.value])
        let code = object ? "JSON-003" : "JSON-002"
        if current == nil {
            throw diagnostic(code, "Expected \(object ? "a field name" : "an array value")\(first ? " or '\(closeText)'" : "") before end of input.", expected: expected, related: [introducer])
        }
        if object, current != 34 {
            let wrongQuotes = current == 39 || current == 0x201C || current == 0x201D
            throw diagnostic(wrongQuotes ? "JSON-006" : current == 93 ? code : "JSON-007", "Expected a field name in straight double quotes\(first ? " or '}'" : "").", expected: expected, related: [introducer])
        }
        if !object, current == 125 {
            throw diagnostic(code, first ? "Unexpected '}'; expected a value or ']'." : "Unexpected '}'; expected a value after the comma.", expected: expected, related: [introducer])
        }
    }
    @inline(never) mutating func fieldPrefix(keys: inout [Data: NSRange], pretty: Bool, introducer: inout JSONRelatedLocation) throws -> String {
        let start = offset
        let key = try string()
        let range = NSRange(location: start, length: offset - start)
        let decoded = try JSONDecoder().decode(String.self, from: Data(key.utf8))
        let identity = Data(decoded.utf8) // Exact decoded scalar sequence; never canonical String equality.
        if capture { memberKey = decoded; memberKeyRange = range }
        if let first = keys[identity], warnings.count < 32 {
            warnings.append(diagnostic("JSON-010", "Duplicate field name. All occurrences are preserved.", at: start,
                                       severity: .warning, length: range.length, related: [.init(.firstOccurrence, first)]))
        } else if keys[identity] == nil { keys[identity] = range }
        try whitespace()
        guard current == 58 else { throw diagnostic("JSON-COLON", "Expected ':' after the field name.", expected: [.colon], related: [.init(.fieldName, range)]) }
        introducer = .init(.separator, NSRange(location: offset, length: 1))
        offset += 1
        return key + (pretty ? ": " : ":")
    }
    @inline(never) mutating func finishMember(object: Bool, introducer: inout JSONRelatedLocation) throws -> Bool {
        try whitespace()
        let close: UInt16 = object ? 125 : 93
        let closeText = object ? "}" : "]"
        let closeToken: JSONExpectedToken = object ? .objectEnd : .arrayEnd
        let closeCode = object ? "JSON-003" : "JSON-002"
        if current == close { offset += 1; return true }
        let expected: [JSONExpectedToken] = [.comma, closeToken]
        if current == nil { throw diagnostic(closeCode, "Expected '\(closeText)' before end of input.", expected: expected) }
        if current == 125 || current == 93 {
            throw diagnostic(closeCode, "Unexpected '\(current == 125 ? "}" : "]")'; expected ',' or '\(closeText)'.", expected: expected)
        }
        guard current == 44 else {
            let context = object ? "object" : "array"
            let message = current == 34 ? "Unexpected quote after \(context) value; expected ',' or '\(closeText)'." : "Expected ',' or '\(closeText)' after \(context) value."
            throw diagnostic("JSON-001", message, expected: expected)
        }
        introducer = .init(.separator, NSRange(location: offset, length: 1))
        offset += 1; try whitespace()
        if current == close { throw diagnostic("JSON-005", "Trailing comma is not allowed in strict JSON.", expected: object ? [.fieldName] : [.value], related: [introducer]) }
        return false
    }
    mutating func string() throws -> String {
        let start = offset
        let stringStart = JSONRelatedLocation(.stringStart, NSRange(location: start, length: 1))
        offset += 1
        while let c = current {
            if offset & 255 < 8 { try Task.checkCancellation() }
            if c == 34 {
                offset += 1
                let token = String(decoding: units[start..<offset], as: UTF16.self)
                guard (try? JSONDecoder().decode(String.self, from: Data(token.utf8))) != nil else {
                    throw diagnostic("JSON-012", "String is not supported by the Unicode policy (invalid or unpaired surrogate). Exact code unit is unknown.",
                                     at: start, length: offset - start, related: [stringStart], precision: .region, kind: .unicodePolicy)
                }
                return token
            }
            if c < 32 { throw diagnostic("JSON-CONTROL", "Unescaped control character in string.", expected: [.stringContent, .quote], related: [stringStart]) }
            if c == 92 {
                let escapeStart = JSONRelatedLocation(.escapeStart, NSRange(location: offset, length: 1))
                offset += 1
                guard let escape = current else { throw diagnostic("JSON-004", "Unterminated escape sequence before end of input.", expected: [.escape], related: [escapeStart, stringStart]) }
                if escape == 117 {
                    for _ in 0..<4 {
                        offset += 1
                        guard let hex = current, (48...57).contains(hex) || (65...70).contains(hex) || (97...102).contains(hex) else {
                            throw diagnostic("JSON-012", "Unicode escape requires four hexadecimal digits.", expected: [.hexDigit], related: [escapeStart, stringStart])
                        }
                    }
                } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escape) {
                    throw diagnostic("JSON-ESCAPE", "Invalid escape. Allowed: quote, backslash, slash, b, f, n, r, t, uXXXX.", expected: [.escape], related: [escapeStart, stringStart])
                }
            }
            offset += 1
        }
        throw diagnostic("JSON-004", "Unterminated string before end of input.", expected: [.quote], related: [stringStart])
    }
    mutating func literal(_ text: String, expected: JSONExpectedToken) throws -> String {
        let start = offset
        for unit in text.utf16 {
            guard current == unit else { throw diagnostic("JSON-008", "Expected literal '\(text)'\(current == nil ? " before end of input" : "").", expected: [expected], related: [.init(.valueStart, NSRange(location: start, length: 0))]) }
            offset += 1
        }
        return text
    }
    mutating func number() throws -> String {
        let start = offset
        let related = [JSONRelatedLocation(.valueStart, NSRange(location: start, length: 0))]
        if current == 45 { offset += 1 }
        guard let digit = current, (48...57).contains(digit) else { throw diagnostic("JSON-NUMBER", "Expected a digit in the number.", expected: [.digit], related: related) }
        if digit == 48 {
            offset += 1
            if let c = current, (48...57).contains(c) { throw diagnostic("JSON-009", "Leading zeros are not allowed in JSON numbers.", expected: [.numberContinuation], related: related) }
        } else { try digits() }
        if current == 46 { offset += 1; try requiredDigits(related: related) }
        if current == 101 || current == 69 {
            offset += 1
            if current == 43 || current == 45 { offset += 1 }
            try requiredDigits(related: related)
        }
        return String(decoding: units[start..<offset], as: UTF16.self)
    }
    mutating func digits() throws {
        while let c = current, (48...57).contains(c) {
            if offset & 255 < 8 { try Task.checkCancellation() }
            offset += 1
        }
    }
    mutating func requiredDigits(related: [JSONRelatedLocation]) throws {
        guard let c = current, (48...57).contains(c) else { throw diagnostic("JSON-NUMBER", "Expected a digit after the decimal point or exponent.", expected: [.digit], related: related) }
        try digits()
    }
}
