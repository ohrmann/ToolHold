import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum JSONXMLDirection: String, CaseIterable, Sendable {
    case jsonToXML = "JSON → XML", xmlToJSON = "XML → JSON"
    var inputName: String { self == .jsonToXML ? "JSON" : "XML" }
    var outputName: String { self == .jsonToXML ? "XML" : "JSON" }
}
enum JSONXMLMapping: String, CaseIterable, Sendable {
    case elements = "Elements", typed = "Typed JSON"
    var note: String {
        switch self {
        case .elements: "One root key · @attributes · #text · repeated elements become arrays. XML text stays string; JSON scalar types are not retained."
        case .typed: "Toolbox typed XML vocabulary · preserves JSON types, ordered duplicate keys and exact number lexemes."
        }
    }
}
enum JSONXMLStatus: Equatable, Sendable { case success, invalid, unsupported, resourceLimit, cancelled }
struct JSONXMLResult: Sendable {
    let status: JSONXMLStatus
    var output: String?
    var diagnostics: [JSONDiagnostic] = []
    var notes: [String] = []
}
private struct XMLFailure: Error {
    let status: JSONXMLStatus
    let message: String
    var range = NSRange(location: 0, length: 0)
    var precision = JSONDiagnostic.Precision.region
}

/// XML grammar is exclusively Foundation XMLParser. JSON grammar is exclusively JSONProcessor.
/// Mapping is explicit; no inference, DTD, entity resolution, networking or persistent data.
enum JSONXMLConverter {
    static let namespace = "urn:developer-toolbox:json-xml:1"
    static func process(_ source: String, direction: JSONXMLDirection, mapping: JSONXMLMapping = .elements,
                        indentation: JSONIndentation = .two, produceOutput: Bool = true) -> JSONXMLResult {
        do {
            try Task.checkCancellation()
            guard source.utf16.count <= JSONProcessor.maximumUTF16Length else {
                throw XMLFailure(status: .resourceLimit, message: "Input exceeds 262,144 UTF-16 code units.")
            }
            var writer = XMLWriter()
            var notes = [mapping.note]
            if direction == .jsonToXML {
                let parsed = JSONProcessor.inspectStructure(source)
                guard let document = parsed.document else {
                    let status: JSONXMLStatus
                    switch parsed.result.status { case .cancelled: status = .cancelled; case .resourceLimit: status = .resourceLimit; default: status = .invalid }
                    return .init(status: status, diagnostics: parsed.result.diagnostics)
                }
                try writer.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
                if mapping == .typed { try emitTyped(document, id: 0, level: 0, indentation: indentation.spaces, writer: &writer) }
                else {
                    let root = document.nodes[0]
                    guard root.kind == .object, root.children.count == 1, let child = root.children.first,
                          let name = document.nodes[child].key, !name.hasPrefix("@"), name != "#text",
                          document.nodes[child].kind != .array else {
                        throw XMLFailure(status: .unsupported, message: "Elements needs one named root, for example {\"root\":{\"name\":\"Ada\"}}. Use Typed JSON for arbitrary JSON roots.", range: root.range, precision: .exact)
                    }
                    try emitElement(document, id: child, name: name, level: 0, indentation: indentation.spaces, writer: &writer)
                    // Validate generated names, namespace bindings and XML depth using the same native parser.
                    do { _ = try XMLReader.read(writer.text, mapping: mapping) }
                    catch let failure as XMLFailure {
                        if failure.status == .resourceLimit { throw XMLFailure(status: .resourceLimit, message: failure.message) }
                        throw XMLFailure(status: .unsupported, message: "These JSON names or namespace declarations cannot form a well-formed XML document. Names are never renamed automatically.", range: root.range)
                    }
                }
                if mapping == .elements { notes.append("Empty objects and strings share an empty element; single-item arrays become a single element and lose array shape. Empty arrays and null require Typed JSON.") }
            } else {
                let xml = try XMLReader.read(source, mapping: mapping)
                if xml.hasCommentsOrPI { notes.append("Comments and processing instructions are not represented in JSON.") }
                if mapping == .typed { try readTyped(xml, id: 0, root: true, writer: &writer) }
                else {
                    try writer.append("{" + JSONTextEncoding.quote(xml.nodes[0].name) + ":")
                    try readElement(xml, id: 0, writer: &writer)
                    try writer.append("}")
                }
                let formatted = JSONProcessor.process(writer.text, operation: .format, indentation: indentation)
                guard formatted.isValid, let output = formatted.output else {
                    if case .cancelled = formatted.status { throw CancellationError() }
                    throw XMLFailure(status: .resourceLimit, message: "The mapped JSON exceeds the existing output or nesting limits.")
                }
                guard output.utf16.count <= JSONProcessor.maximumUTF16Length else {
                    throw XMLFailure(status: .resourceLimit, message: "Formatted JSON output exceeds 262,144 UTF-16 code units. No partial result was published.")
                }
                writer.text = output
                notes.append("XML character references and CDATA become decoded text. XML line-ending/attribute normalization applies; original XML spelling and attribute order are not retained.")
            }
            try Task.checkCancellation()
            return .init(status: .success, output: produceOutput ? writer.text : nil, notes: notes)
        } catch is CancellationError { return .init(status: .cancelled) }
        catch let failure as XMLFailure {
            if Task.isCancelled { return .init(status: .cancelled) }
            let offset = min(source.utf16.count, max(0, failure.range.location))
            let range = NSRange(location: offset, length: min(max(0, failure.range.length), source.utf16.count - offset))
            let position = JSONSourceCoordinates(source).location(at: offset)
            return .init(status: failure.status, diagnostics: [.init(severity: .error,
                code: failure.status == .resourceLimit ? "XML-LIMIT" : failure.status == .unsupported ? "XML-MAPPING" : "XML-SYNTAX",
                message: failure.message, range: range, line: position.line, column: position.column, precision: failure.precision)])
        } catch {
            return .init(status: .unsupported, diagnostics: [.init(severity: .error, code: "XML-FAILED", message: "Conversion could not be completed. No partial output was published.", range: .init(location: 0, length: 0), line: 1, column: 1, precision: .region)])
        }
    }

    private static func emitTyped(_ document: JSONStructureDocument, id: Int, level: Int, indentation: String, writer: inout XMLWriter) throws {
        try writer.tick()
        let node = document.nodes[id], name = node.kind.rawValue.lowercased()
        try writer.append(String(repeating: indentation, count: level) + "<" + name)
        if id == 0 { try writer.append(" xmlns=\"" + namespace + "\"") }
        if let key = node.key { try writer.append(" key=\"" + (try xmlEscape(safeJSONToken(JSONTextEncoding.quote(key)), attribute: true)) + "\"") }
        if node.kind == .null { try writer.append("/>"); return }
        try writer.append(">")
        if node.kind == .object || node.kind == .array {
            for child in node.children {
                try writer.append("\n")
                try emitTyped(document, id: child, level: level + 1, indentation: indentation, writer: &writer)
            }
            if !node.children.isEmpty { try writer.append("\n" + String(repeating: indentation, count: level)) }
        } else { try writer.append(xmlEscape(safeJSONToken(document.fragment(id)))) }
        try writer.append("</" + name + ">")
    }

    private static func emitElement(_ document: JSONStructureDocument, id: Int, name: String, level: Int, indentation: String, writer: inout XMLWriter) throws {
        try writer.tick()
        let node = document.nodes[id]
        guard validName(name) else { throw XMLFailure(status: .unsupported, message: "An XML element or attribute name is invalid. Use Typed JSON to preserve arbitrary JSON keys.", range: node.keyRange ?? node.range, precision: .exact) }
        guard node.kind != .array && node.kind != .null else { throw XMLFailure(status: .unsupported, message: "Null and array-valued root/array items need Typed JSON. Repeated named fields may use a non-empty array.", range: node.range, precision: .exact) }
        try writer.append(String(repeating: indentation, count: level) + "<" + name)
        var children: [Int] = [], text: String?
        if node.kind == .object {
            for child in node.children {
                try writer.tick()
                let field = document.nodes[child], key = field.key!
                guard field.occurrences == 1 else { throw XMLFailure(status: .unsupported, message: "Duplicate JSON keys need Typed JSON; they are not overwritten or merged.", range: field.keyRange ?? field.range, precision: .exact) }
                if key.hasPrefix("@") {
                    let attribute = String(key.dropFirst())
                    guard validName(attribute), [.string, .number, .boolean].contains(field.kind) else { throw XMLFailure(status: .unsupported, message: "@attributes need valid XML names and scalar, non-null values.", range: field.range, precision: .exact) }
                    try writer.append(" " + attribute + "=\"" + xmlEscape(field.scalar ?? "", attribute: true) + "\"")
                } else if key == "#text" {
                    guard [.string, .number, .boolean].contains(field.kind) else { throw XMLFailure(status: .unsupported, message: "#text must be a non-null scalar.", range: field.range, precision: .exact) }
                    text = field.scalar ?? ""
                } else { children.append(child) }
            }
        } else { text = node.scalar ?? "" }
        guard children.isEmpty || text == nil || text == "" else { throw XMLFailure(status: .unsupported, message: "Mixed text and child elements need an ordered content model and cannot be converted with Elements. No text is discarded.", range: node.range, precision: .exact) }
        try writer.append(">")
        if let text, children.isEmpty { try writer.append(xmlEscape(text)) }
        for child in children {
            let field = document.nodes[child]
            let values = field.kind == .array ? field.children : [child]
            guard !values.isEmpty else { throw XMLFailure(status: .unsupported, message: "An empty array has no XML element representation. Use Typed JSON to retain it.", range: field.range, precision: .exact) }
            for value in values {
                try writer.append("\n")
                try emitElement(document, id: value, name: field.key!, level: level + 1, indentation: indentation, writer: &writer)
            }
        }
        if !children.isEmpty { try writer.append("\n" + String(repeating: indentation, count: level)) }
        try writer.append("</" + name + ">")
    }

    private static func readElement(_ xml: XMLDocumentSnapshot, id: Int, writer: inout XMLWriter) throws {
        try writer.tick()
        let node = xml.nodes[id], text = node.text.joined()
        guard node.children.isEmpty || text.unicodeScalars.allSatisfy({ [9, 10, 13, 32].contains($0.value) }) else {
            throw XMLFailure(status: .unsupported, message: "Mixed text and child elements cannot be represented by Elements without losing order. No partial JSON was produced.", range: node.region)
        }
        if !node.children.isEmpty, !text.isEmpty, node.preserveSpace {
            throw XMLFailure(status: .unsupported, message: "Whitespace in mixed content with xml:space='preserve' cannot be discarded. Elements conversion was stopped.", range: node.region)
        }
        if node.attributes.isEmpty && node.children.isEmpty { try writer.append(JSONTextEncoding.quote(text)); return }
        try writer.append("{")
        var printed = 0
        func field(_ key: String, writer: inout XMLWriter) throws {
            if printed > 0 { try writer.append(",") }; printed += 1
            try writer.append(JSONTextEncoding.quote(key) + ":")
        }
        for (name,value) in node.attributes { try writer.tick(); try field("@" + name, writer: &writer); try writer.append(JSONTextEncoding.quote(value)) }
        if !text.isEmpty && node.children.isEmpty { try field("#text", writer: &writer); try writer.append(JSONTextEncoding.quote(text)) }
        var groups: [(String, [Int])] = [], positions: [Data: Int] = [:]
        for child in node.children {
            try writer.tick()
            let name = xml.nodes[child].name, identity = Data(name.utf8)
            if let position = positions[identity] {
                guard position == groups.count - 1 else { throw XMLFailure(status: .unsupported, message: "Interleaved repeated element names cannot be grouped without losing sibling order. Elements conversion was stopped.", range: xml.nodes[child].region) }
                groups[position].1.append(child)
            } else { positions[identity] = groups.count; groups.append((name, [child])) }
        }
        for (name,children) in groups {
            try field(name, writer: &writer)
            if children.count > 1 { try writer.append("[") }
            for (index,child) in children.enumerated() {
                if index > 0 { try writer.append(",") }
                try readElement(xml, id: child, writer: &writer)
            }
            if children.count > 1 { try writer.append("]") }
        }
        try writer.append("}")
    }

    private static func readTyped(_ xml: XMLDocumentSnapshot, id: Int, root: Bool, writer: inout XMLWriter) throws {
        try writer.tick()
        let node = xml.nodes[id]
        let allowed: Set<String> = root ? ["xmlns"] : ["key"]
        guard node.attributes.allSatisfy({ allowed.contains($0.0) }),
              !root || node.attributes.contains(where: { $0.0 == "xmlns" && $0.1 == namespace }) else {
            throw XMLFailure(status: .unsupported, message: "Typed JSON needs the Toolbox namespace on its root and only JSON-quoted key attributes on object members.", range: node.region)
        }
        let text = node.text.joined()
        if node.name == "object" || node.name == "array" {
            guard text.unicodeScalars.allSatisfy({ [9, 10, 13, 32].contains($0.value) }) else { throw XMLFailure(status: .unsupported, message: "Typed containers may contain only typed value elements and formatting whitespace.", range: node.region) }
            let object = node.name == "object"
            try writer.append(object ? "{" : "[")
            for (index,child) in node.children.enumerated() {
                if index > 0 { try writer.append(",") }
                let key = xml.nodes[child].attributes.first { $0.0 == "key" }?.1
                if object {
                    guard let key else { throw XMLFailure(status: .unsupported, message: "Each typed object member needs a JSON string in its key attribute.", range: xml.nodes[child].region) }
                    let parsed = JSONProcessor.inspectStructure(key)
                    guard let keyDoc = parsed.document, keyDoc.nodes[0].kind == .string else { throw XMLFailure(status: .unsupported, message: "The key attribute must contain a complete JSON string token, including its quotes.", range: xml.nodes[child].region) }
                    try writer.append(keyDoc.fragment(0) + ":")
                } else if key != nil { throw XMLFailure(status: .unsupported, message: "Typed array items cannot have key attributes.", range: xml.nodes[child].region) }
                try readTyped(xml, id: child, root: false, writer: &writer)
            }
            try writer.append(object ? "}" : "]")
        } else {
            guard node.children.isEmpty, ["string", "number", "boolean", "null"].contains(node.name) else { throw XMLFailure(status: .unsupported, message: "Unknown typed value element or nested content in a scalar.", range: node.region) }
            let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if node.name == "null" {
                guard token.isEmpty else { throw XMLFailure(status: .unsupported, message: "The typed null element must be empty.", range: node.region) }
                try writer.append("null"); return
            }
            let parsed = JSONProcessor.inspectStructure(token)
            guard let document = parsed.document, document.nodes[0].kind.rawValue.lowercased() == node.name else {
                throw XMLFailure(status: .unsupported, message: "Typed \(node.name) must contain one strict JSON \(node.name) token. Strings include JSON quotes and escapes.", range: node.region)
            }
            try writer.append(document.fragment(0))
        }
    }

    private static func validName(_ name: String) -> Bool {
        func start(_ c: UInt32) -> Bool {
            c == 58 || c == 95 || (65...90).contains(c) || (97...122).contains(c) || (0xC0...0xD6).contains(c) || (0xD8...0xF6).contains(c) || (0xF8...0x2FF).contains(c) || (0x370...0x37D).contains(c) || (0x37F...0x1FFF).contains(c) || (0x200C...0x200D).contains(c) || (0x2070...0x218F).contains(c) || (0x2C00...0x2FEF).contains(c) || (0x3001...0xD7FF).contains(c) || (0xF900...0xFDCF).contains(c) || (0xFDF0...0xFFFD).contains(c) || (0x10000...0xEFFFF).contains(c)
        }
        guard let first = name.unicodeScalars.first, start(first.value) else { return false }
        return name.unicodeScalars.dropFirst().allSatisfy { start($0.value) || $0.value == 45 || $0.value == 46 || (48...57).contains($0.value) || $0.value == 0xB7 || (0x300...0x36F).contains($0.value) || (0x203F...0x2040).contains($0.value) }
    }
    fileprivate static func legalCharacter(_ value: UInt32) -> Bool {
        value == 9 || value == 10 || value == 13 || (0x20...0xD7FF).contains(value) || (0xE000...0xFFFD).contains(value) || (0x10000...0x10FFFF).contains(value)
    }
    private static func safeJSONToken(_ token: String) -> String {
        token.unicodeScalars.map { legalCharacter($0.value) ? String($0) : String(format: "\\u%04X", $0.value) }.joined()
    }
    private static func xmlEscape(_ value: String, attribute: Bool = false) throws -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            guard legalCharacter(scalar.value) else { throw XMLFailure(status: .unsupported, message: "A value contains characters forbidden by XML 1.0. Use Typed JSON to retain them as JSON escapes.") }
            switch scalar.value {
            case 38: result += "&amp;"
            case 60: result += "&lt;"
            case 62: result += "&gt;"
            case 34 where attribute: result += "&quot;"
            case 9 where attribute: result += "&#x9;"
            case 10 where attribute: result += "&#xA;"
            case 13: result += "&#xD;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

private struct XMLWriter {
    var text = "", length = 0, steps = 0
    mutating func tick() throws {
        steps += 1
        if steps & 255 == 0 { try Task.checkCancellation() }
        guard steps <= 2_000_000 else { throw XMLFailure(status: .resourceLimit, message: "XML conversion work budget reached.") }
    }
    mutating func append(_ string: String) throws {
        try tick()
        let size = string.utf16.count
        guard size <= JSONProcessor.maximumUTF16Length - length else { throw XMLFailure(status: .resourceLimit, message: "Converted output exceeds 262,144 UTF-16 code units. No partial result was published.") }
        text += string; length += size
    }
}

private struct XMLElementSnapshot {
    let name: String
    let attributes: [(String, String)]
    let region: NSRange
    let preserveSpace: Bool
    var children: [Int] = []
    var text: [String] = []
}
private struct XMLDocumentSnapshot {
    let nodes: [XMLElementSnapshot]
    let hasCommentsOrPI: Bool
}
private final class XMLReader: NSObject, XMLParserDelegate {
    let source: String
    let mapping: JSONXMLMapping
    let coordinates: JSONSourceCoordinates
    var nodes: [XMLElementSnapshot] = [], stack: [Int] = []
    var failure: XMLFailure?
    var hasCommentsOrPI = false
    var decodedLength = 0
    var namespaceDeclarations: [(String, String)] = []
    var namespaceScopes: [[Data: String]] = []
    init(_ source: String, mapping: JSONXMLMapping) { self.source = source; self.mapping = mapping; coordinates = .init(source) }
    static func read(_ source: String, mapping: JSONXMLMapping) throws -> XMLDocumentSnapshot {
        try preflight(source)
        let reader = XMLReader(source, mapping: mapping), parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.delegate = reader
        let parsed = parser.parse()
        try Task.checkCancellation()
        if let failure = reader.failure { throw failure }
        guard parsed, !reader.nodes.isEmpty else {
            throw XMLFailure(status: .invalid, message: "XML is not well-formed. Check matching tags, attributes, references and the single document root.", range: reader.region(parser))
        }
        return .init(nodes: reader.nodes, hasCommentsOrPI: reader.hasCommentsOrPI)
    }
    /// Security gate, not a second XML parser. Skip literal comment/CDATA/PI bodies;
    /// reject a real DTD declaration before Foundation can process its subset or entities.
    private static func preflight(_ source: String) throws {
        let units = Array(source.utf16)
        var index = 0
        func matches(_ text: String, at index: Int) -> Bool { units[index...].starts(with: text.utf16) }
        while index < units.count {
            if index & 255 == 0 { try Task.checkCancellation() }
            if units[index] != 60 { index += 1; continue }
            if matches("<!DOCTYPE", at: index) || matches("<!ENTITY", at: index) {
                throw XMLFailure(status: .unsupported, message: "DTD and custom entities are disabled. External files and network resources are never resolved.", range: .init(location: index, length: min(9, units.count - index)), precision: .exact)
            }
            var terminator: String?
            if matches("<!--", at: index) { terminator = "-->" }
            else if matches("<![CDATA[", at: index) { terminator = "]]>" }
            else if matches("<?", at: index) { terminator = "?>" }
            if let terminator {
                let start = index; index += 2
                while index < units.count && !matches(terminator, at: index) {
                    if index & 255 == 0 { try Task.checkCancellation() }; index += 1
                }
                if units[start...].starts(with: "<?xml".utf16), start + 5 < units.count, [9, 10, 13, 32].contains(units[start + 5]) {
                    let declaration = String(decoding: units[start..<index], as: UTF16.self)
                    if declaration.range(of: #"version\s*=\s*['"](?!1\.0['"])[^'"]+['"]"#, options: .regularExpression) != nil ||
                       declaration.range(of: #"encoding\s*=\s*['"](?![Uu][Tt][Ff]-8['"])[^'"]+['"]"#, options: .regularExpression) != nil {
                        throw XMLFailure(status: .unsupported, message: "Pasted XML supports XML 1.0 with UTF-8 or no encoding declaration. Other declarations are not rewritten automatically.", range: .init(location: start, length: index - start), precision: .exact)
                    }
                }
                index = min(units.count, index + terminator.utf16.count)
            } else if index + 1 < units.count, ![33, 47].contains(units[index + 1]) {
                // Foundation's [String:String] attribute callback cannot distinguish
                // canonically equivalent names. Reject such a collision before bridging.
                var cursor = index + 1, names: [String: Data] = [:]
                func whitespace(_ unit: UInt16) -> Bool { [9, 10, 13, 32].contains(unit) }
                while cursor < units.count, !whitespace(units[cursor]), ![47, 62].contains(units[cursor]) { cursor += 1 }
                while cursor < units.count {
                    try Task.checkCancellation()
                    while cursor < units.count, whitespace(units[cursor]) { cursor += 1 }
                    let start = cursor
                    while cursor < units.count, !whitespace(units[cursor]), ![61, 47, 62].contains(units[cursor]) { cursor += 1 }
                    guard cursor > start else { break }
                    let name = String(decoding: units[start..<cursor], as: UTF16.self), identity = Data(name.utf8)
                    if let previous = names[name], previous != identity {
                        throw XMLFailure(status: .unsupported, message: "Scalar-distinct but canonically equivalent attribute names cannot be preserved by the native XML attribute API. No attributes were merged.", range: .init(location: start, length: cursor - start), precision: .exact)
                    }
                    names[name] = identity
                    while cursor < units.count, whitespace(units[cursor]) { cursor += 1 }
                    guard cursor < units.count, units[cursor] == 61 else { break }; cursor += 1
                    while cursor < units.count, whitespace(units[cursor]) { cursor += 1 }
                    guard cursor < units.count, units[cursor] == 34 || units[cursor] == 39 else { break }
                    let quote = units[cursor]; cursor += 1
                    let valueStart = cursor
                    while cursor < units.count, units[cursor] != quote {
                        if cursor & 255 == 0 { try Task.checkCancellation() }; cursor += 1
                    }
                    if name == "xmlns" || name.hasPrefix("xmlns:"), let uri = namespaceValue(Array(units[valueStart..<cursor])) {
                        let prefix = name == "xmlns" ? "" : String(name.dropFirst(6))
                        let reserved = "http://www.w3.org/XML/1998/namespace"
                        guard prefix != "xmlns", uri != "http://www.w3.org/2000/xmlns/", (prefix != "xml" || uri == reserved),
                              (uri != reserved || prefix == "xml"), (prefix.isEmpty || !uri.isEmpty) else {
                            throw XMLFailure(status: .invalid, message: "Invalid reserved namespace binding or empty namespace URI for a prefix.", range: .init(location: start, length: cursor - start), precision: .exact)
                        }
                    }
                    if cursor < units.count { cursor += 1 }
                }
                index = max(index + 1, cursor)
            } else { index += 1 }
        }
    }
    /// Decode only the predefined/character references for reserved namespace checks.
    /// All XML grammar and attribute values still come from Foundation's strict parse.
    private static func namespaceValue(_ units: [UInt16]) -> String? {
        var text = "", index = 0
        while index < units.count {
            if units[index] != 38 {
                let start = index
                while index < units.count, units[index] != 38 { index += 1 }
                text += String(decoding: units[start..<index], as: UTF16.self); continue
            }
            let start = index; index += 1
            while index < units.count, units[index] != 59 { index += 1 }
            guard index < units.count else { return nil }
            let name = String(decoding: units[(start + 1)..<index], as: UTF16.self); index += 1
            if let value = ["amp":"&", "lt":"<", "gt":">", "quot":"\"", "apos":"'"][name] { text += value }
            else {
                let value: UInt32?
                if name.hasPrefix("#x") { value = UInt32(name.dropFirst(2), radix: 16) }
                else if name.hasPrefix("#") { value = UInt32(name.dropFirst()) }
                else { return nil }
                guard let value, JSONXMLConverter.legalCharacter(value), let scalar = UnicodeScalar(value) else { return nil }
                text.unicodeScalars.append(scalar)
            }
        }
        return text
    }
    private func region(_ parser: XMLParser) -> NSRange {
        // XMLParser columns are not promised to use UTF-16. Report the physical line as
        // a region rather than mislabelling a byte/scalar column as an exact source anchor.
        let line = min(max(1, parser.lineNumber), coordinates.lineStarts.count) - 1
        let start = coordinates.lineStarts[line]
        let end = line + 1 < coordinates.lineStarts.count ? coordinates.lineStarts[line + 1] : coordinates.utf16Length
        return NSRange(location: start, length: max(0, end - start))
    }
    private func fail(_ parser: XMLParser, _ status: JSONXMLStatus, _ message: String) {
        if failure == nil { failure = .init(status: status, message: message, range: region(parser)) }
        parser.abortParsing()
    }
    private func cancelled(_ parser: XMLParser) -> Bool {
        if Task.isCancelled { parser.abortParsing(); return true }; return false
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard !cancelled(parser) else { return }
        let limit = mapping == .typed ? 65 : 64
        guard stack.count < limit else { fail(parser, .resourceLimit, "XML nesting exceeds the supported depth."); return }
        if mapping == .typed, stack.count == 64, elementName == "object" || elementName == "array" { fail(parser, .resourceLimit, "Typed JSON exceeds 64 container levels."); return }
        let xmlNamespace = "http://www.w3.org/XML/1998/namespace"
        var scope = namespaceScopes.last ?? [Data("xml".utf8): xmlNamespace]
        for (attribute,uri) in namespaceDeclarations {
            let prefix = attribute == "xmlns" ? "" : String(attribute.dropFirst(6))
            guard prefix != "xmlns", uri != "http://www.w3.org/2000/xmlns/", (prefix != "xml" || uri == xmlNamespace),
                  (uri != xmlNamespace || prefix == "xml"), (prefix.isEmpty || !uri.isEmpty) else {
                fail(parser, .invalid, "Invalid reserved namespace binding or empty namespace URI for a prefix."); return
            }
            scope[Data(prefix.utf8)] = uri
        }
        func expandedName(_ name: String, attribute: Bool) -> Data? {
            let parts = name.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            let uri: String
            if parts.count == 2 {
                guard let bound = scope[Data(parts[0].utf8)], !bound.isEmpty, parts[0] != "xmlns" else { return nil }
                uri = bound
            } else { uri = attribute ? "" : scope[Data()] ?? "" }
            return Data(uri.utf8) + Data([0]) + Data(parts.last!.utf8)
        }
        guard expandedName(qName ?? elementName, attribute: false) != nil else { fail(parser, .invalid, "An element uses an undeclared namespace prefix or invalid qualified name."); return }
        var attributeNames: Set<Data> = []
        for name in attributeDict.keys {
            guard let identity = expandedName(name, attribute: true), attributeNames.insert(identity).inserted else {
                fail(parser, .invalid, "An attribute uses an undeclared prefix, invalid qualified name or duplicate expanded name."); return
            }
        }
        let id = nodes.count
        let attributes = attributeDict.map { ($0.key, $0.value) } + namespaceDeclarations
        namespaceDeclarations.removeAll(keepingCapacity: true)
        let space = attributeDict["xml:space"]
        let preserve = space == "preserve" || (space != "default" && stack.last.map { nodes[$0].preserveSpace } == true)
        nodes.append(.init(name: qName ?? elementName, attributes: attributes.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }, region: region(parser), preserveSpace: preserve))
        if let parent = stack.last { nodes[parent].children.append(id) }
        stack.append(id); namespaceScopes.append(scope)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !cancelled(parser), !stack.isEmpty { stack.removeLast(); namespaceScopes.removeLast() } }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !cancelled(parser) else { return }
        decodedLength += string.utf16.count
        guard decodedLength <= JSONProcessor.maximumUTF16Length else { fail(parser, .resourceLimit, "Decoded XML text exceeds the processing limit."); return }
        if let id = stack.last { nodes[id].text.append(string) }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let value = String(data: CDATABlock, encoding: .utf8) else { fail(parser, .invalid, "CDATA contains invalid text."); return }
        self.parser(parser, foundCharacters: value)
    }
    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) { self.parser(parser, foundCharacters: whitespaceString) }
    func parser(_ parser: XMLParser, foundComment comment: String) { hasCommentsOrPI = true; _ = cancelled(parser) }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) { hasCommentsOrPI = true; _ = cancelled(parser) }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) { namespaceDeclarations.append((prefix.isEmpty ? "xmlns" : "xmlns:" + prefix, namespaceURI)); _ = cancelled(parser) }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { if !Task.isCancelled && failure == nil { failure = .init(status: .invalid, message: "XML is not well-formed. Check matching tags, attributes, references and the single document root.", range: region(parser)) } }
    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) { self.parser(parser, parseErrorOccurred: validationError) }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { fail(parser, .invalid, "Undeclared entity reference. Only the predefined XML entities and character references are supported."); return nil }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { fail(parser, .unsupported, "Custom entities are disabled.") }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { fail(parser, .unsupported, "External entities are disabled.") }
}
