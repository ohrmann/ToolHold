import Foundation

struct JSONStructureResult: Sendable {
    let result: JSONResult
    let document: JSONStructureDocument?
}

/// Arena index, scoped to the owning document's snapshotID. Never a path or tree row number.
struct JSONStructureNode: Sendable, Identifiable {
    enum Kind: String, Sendable { case object = "Object", array = "Array", string = "String", number = "Number", boolean = "Boolean", null = "Null" }
    let id: Int
    let parent: Int?
    let kind: Kind
    let depth: Int
    let key: String?
    let keyRange: NSRange?
    let arrayIndex: Int?
    var range: NSRange
    var children: [Int] = []
    var scalar: String?
    var occurrence = 1
    var occurrences = 1
    var canExpand: Bool { !children.isEmpty }
    var name: String { key ?? arrayIndex.map { "[\($0)]" } ?? "root" }
    var summary: String {
        switch kind {
        case .object: return "Object · \(children.count) fields"
        case .array: return "Array · \(children.count) items"
        default: return scalar ?? ""
        }
    }
}

struct JSONStructureDocument: Sendable {
    let snapshotID = UUID()
    let source: String
    let nodes: [JSONStructureNode]
    var rootID: Int { 0 }
    func fragment(_ id: Int) -> String { (source as NSString).substring(with: nodes[id].range) }
    func ancestors(of id: Int) -> [Int] {
        var result: [Int] = [], parent = nodes[id].parent
        while let value = parent { result.append(value); parent = nodes[value].parent }
        return result.reversed()
    }
    func path(_ id: Int) -> JSONNodePath {
        var pointer = "", jsonPath = "$", ambiguous = false
        for nodeID in ancestors(of: id) + [id] {
            let node = nodes[nodeID]
            if let key = node.key {
                pointer += "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                jsonPath += "['" + Self.pathEscape(key) + "']"
                ambiguous = ambiguous || node.occurrences > 1
            } else if let index = node.arrayIndex {
                pointer += "/\(index)"; jsonPath += "[\(index)]"
            }
        }
        return JSONNodePath(pointer: pointer, jsonPath: jsonPath, ambiguous: ambiguous)
    }
    // RFC 9535 normalized, single-quoted name selector; no normalization.
    private static func pathEscape(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 39: return "\\'"
            case 92: return "\\\\"
            case 8: return "\\b"
            case 9: return "\\t"
            case 10: return "\\n"
            case 12: return "\\f"
            case 13: return "\\r"
            case 0...31: return String(format: "\\u%04x", scalar.value)
            default: return String(scalar)
            }
        }.joined()
    }
}
struct JSONNodePath: Sendable { let pointer: String; let jsonPath: String; let ambiguous: Bool }

struct JSONTreeMatch: Sendable, Equatable {
    enum Field: Sendable { case key, value }
    let nodeID: Int
    let field: Field
    /// Decoded field UTF-16 coordinates, deliberately distinct from source coordinates.
    let range: NSRange
}

struct JSONTreeNodeMatches: Sendable {
    var key: [Int] = []
    var value: [Int] = []
}

enum JSONTreeOperations {
    static func projection(_ document: JSONStructureDocument, expanded: Set<Int>) throws -> [Int] {
        var visible: [Int] = [], stack = [document.rootID]
        visible.reserveCapacity(document.nodes.count)
        while let id = stack.popLast() {
            if visible.count & 255 == 0 { try Task.checkCancellation() }
            visible.append(id)
            if expanded.contains(id) { stack.append(contentsOf: document.nodes[id].children.reversed()) }
        }
        return visible
    }
    static func search(_ query: String, in document: JSONStructureDocument) throws -> [JSONTreeMatch] {
        guard !query.isEmpty else { return [] }
        var matches: [JSONTreeMatch] = []
        for node in document.nodes {
            try Task.checkCancellation()
            for (field, text) in [(JSONTreeMatch.Field.key, node.key), (.value, node.scalar)] {
                guard let text else { continue }
                let string = text as NSString
                var start = 0
                while start < string.length {
                    if matches.count & 255 == 0 { try Task.checkCancellation() }
                    let range = string.range(of: query, options: [.caseInsensitive, .literal], range: NSRange(location: start, length: string.length - start))
                    guard range.location != NSNotFound, range.length > 0 else { break }
                    matches.append(JSONTreeMatch(nodeID: node.id, field: field, range: range))
                    start = NSMaxRange(range)
                }
            }
        }
        return matches
    }
}

/// Small safe presentation of decoded text. Spans retain exact decoded offsets,
/// including when a control/bidi scalar is replaced by a visible escape.
struct JSONTreePreview: Sendable {
    struct Span: Sendable { let source: NSRange; let display: NSRange }
    let text: String
    let spans: [Span]
    static func make(_ source: String, around anchor: NSRange? = nil, budget: Int = 140) -> JSONTreePreview {
        let utf16 = source.utf16
        let center = min(utf16.count, max(0, anchor?.location ?? 0))
        let position = String.Index(utf16.index(utf16.startIndex, offsetBy: center), within: source) ?? source.startIndex
        // Character boundary containing the match, with bounded context on each side.
        var start = position
        if start != source.endIndex { start = source.rangeOfComposedCharacterSequence(at: start).lowerBound }
        for _ in 0..<(anchor == nil ? 0 : 12) { if start > source.startIndex { start = source.index(before: start) } }
        var output = start > source.startIndex ? "…" : "", spans: [Span] = [], cursor = start, count = 0
        while cursor < source.endIndex, count < budget, output.utf16.count < 1024 {
            let end = source.index(after: cursor), range = NSRange(cursor..<end, in: source)
            let grapheme = source[cursor..<end]
            let rendered: String
            if range.length > 512 { rendered = "⟨large grapheme⟩" }
            else {
                rendered = grapheme.unicodeScalars.map { scalar in
                    switch scalar.value {
                    case 9: return "\\t"
                    case 10: return "\\n"
                    case 13: return "\\r"
                    case 0...31, 127...159, 0x061C, 0x200E...0x200F, 0x2028...0x202E, 0x2066...0x2069:
                        return String(format: "\\u{%04X}", scalar.value)
                    default: return String(scalar)
                    }
                }.joined()
            }
            spans.append(Span(source: range, display: NSRange(location: output.utf16.count, length: rendered.utf16.count)))
            output += rendered; count += 1; cursor = end
        }
        if cursor < source.endIndex { output += "…" }
        return JSONTreePreview(text: output, spans: spans)
    }
    func displayRanges(for sourceRange: NSRange) -> [NSRange] {
        spans.filter { NSIntersectionRange($0.source, sourceRange).length > 0 }.map(\.display)
    }
}
