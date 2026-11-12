import Foundation

enum EditorSyntax: Sendable {
    case json, yaml, csv, tsv, xml, toml, plainText, sql, markup, css, javascript, markdown
    var name: String { switch self { case .json: "JSON"; case .yaml: "YAML"; case .csv: "CSV"; case .tsv: "TSV"; case .xml: "XML"; case .toml: "TOML"; case .plainText: "Generated code"; case .sql: "SQL"; case .markup: "Markup"; case .css: "CSS"; case .javascript: "JavaScript"; case .markdown: "Markdown" } }
}

struct JSONEditorOptions: Equatable, Sendable {
    var syntax = EditorSyntax.json
    var syntaxHighlighting = true
    var rainbowBrackets = true
    var matchingBrackets = true
    var wordWrap = true
    /// Opt-in for Code & Markup: validate already laid-out UIKit fragments after async colors arrive.
    var validateVisibleRendering = false
    var needsTokens: Bool { ([.json, .yaml, .sql, .markup, .css, .javascript, .markdown].contains(syntax)) && (syntaxHighlighting || rainbowBrackets || matchingBrackets) }
}

/// Presentation tokens, never a validity judgement or a decoded JSON value.
enum JSONSyntaxKind: Sendable { case key, string, number, literal, bracket, separator, comment }
struct JSONSyntaxToken: Sendable {
    let range: NSRange
    let kind: JSONSyntaxKind
    var depth: Int?
}
struct JSONSyntaxSnapshot: Sendable {
    let utf16Length: Int
    let tokens: [JSONSyntaxToken]
    let partners: [Int: Int]

    /// Prefer the bracket immediately before the caret, then the one after it.
    func matchingRanges(at selection: NSRange) -> [NSRange] {
        guard selection.length == 0, selection.location <= utf16Length else { return [] }
        for offset in [selection.location - 1, selection.location] {
            if let partner = partners[offset] {
                return [NSRange(location: offset, length: 1), NSRange(location: partner, length: 1)]
            }
        }
        return []
    }

    /// Binary search avoids a full token scan on every TextKit viewport redraw.
    func tokenIndices(intersecting range: NSRange) -> Range<Int> {
        var low = 0, high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(tokens[mid].range) <= range.location { low = mid + 1 } else { high = mid }
        }
        let start = low
        while low < tokens.count, tokens[low].range.location < NSMaxRange(range) { low += 1 }
        return start..<low
    }
}

enum JSONSyntaxLexer {
    // Presentation budget only. The strict processor's size/depth limits are unchanged.
    static let maximumTokens = 16_384

    static func scan(_ source: String, maximumUTF16Length: Int = 262_144) -> JSONSyntaxSnapshot? {
        let units = Array(source.utf16.prefix(maximumUTF16Length + 1))
        guard units.count <= maximumUTF16Length, !Task.isCancelled else { return nil }
        var tokens: [JSONSyntaxToken] = []
        var stack: [(unit: UInt16, offset: Int, token: Int)] = []
        var partners: [Int: Int] = [:]
        var index = 0
        func whitespace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        func delimiter(_ c: UInt16) -> Bool { whitespace(c) || [34, 39, 0x201C, 0x201D, 123, 125, 91, 93, 44, 58].contains(c) }
        while index < units.count {
            if Task.isCancelled || tokens.count >= maximumTokens { return nil }
            let start = index
            let unit = units[index]
            if whitespace(unit) { index += 1; continue }
            switch unit {
            case 34, 39, 0x201C, 0x201D:
                // Treat invalid quote-like spans as opaque too: no fake structure inside them.
                let quote: UInt16 = unit == 0x201C ? 0x201D : unit
                let standard = unit == 34
                if !standard { stack.removeAll() }
                index += 1
                var closed = false
                while index < units.count {
                    if index & 255 == 0, Task.isCancelled { return nil }
                    if units[index] == 92 { index = min(units.count, index + 2); continue }
                    if units[index] == quote { index += 1; closed = true; break }
                    index += 1
                }
                var next = index
                while next < units.count, whitespace(units[next]) { next += 1 }
                let key = standard && closed && next < units.count && units[next] == 58
                tokens.append(.init(range: NSRange(location: start, length: index - start), kind: key ? .key : .string))
            case 123, 91:
                tokens.append(.init(range: NSRange(location: index, length: 1), kind: .bracket))
                stack.append((unit, index, tokens.count - 1))
                index += 1
            case 125, 93:
                var depth: Int?
                if let opening = stack.last,
                   (opening.unit == 123 && unit == 125) || (opening.unit == 91 && unit == 93) {
                    depth = stack.count - 1
                    tokens[opening.token].depth = depth
                    partners[opening.offset] = index
                    partners[index] = opening.offset
                    stack.removeLast()
                } else {
                    // Never search down through a mismatched opener or invent a recovery pair.
                    stack.removeAll()
                }
                tokens.append(.init(range: NSRange(location: index, length: 1), kind: .bracket, depth: depth))
                index += 1
            case 44, 58:
                tokens.append(.init(range: NSRange(location: index, length: 1), kind: .separator))
                index += 1
            default:
                index += 1
                while index < units.count, !delimiter(units[index]) {
                    if index & 255 == 0, Task.isCancelled { return nil }
                    index += 1
                }
                let range = NSRange(location: start, length: index - start)
                if unit == 45 || (48...57).contains(unit) {
                    // Includes partially typed numbers; validity belongs to JSONProcessor.
                    tokens.append(.init(range: range, kind: .number))
                } else {
                    let word = String(decoding: units[start..<index], as: UTF16.self)
                    if ["true", "false", "null"].contains(word) {
                        tokens.append(.init(range: range, kind: .literal))
                    }
                }
            }
        }
        return JSONSyntaxSnapshot(utf16Length: units.count, tokens: tokens, partners: partners)
    }
}
