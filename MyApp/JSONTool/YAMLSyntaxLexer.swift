import Foundation

/// Bounded presentation lexer, not a YAML parser/type resolver. No structural pairs are
/// inferred in YAML: plain/block scalars can legally contain bracket characters.
enum YAMLSyntaxLexer {
    static func scan(_ source: String, limit: Int) -> JSONSyntaxSnapshot? {
        let units = Array(source.utf16.prefix(limit + 1))
        guard units.count <= limit else { return nil }
        var tokens: [JSONSyntaxToken] = [], index = 0
        var blockIndent: Int?, lineStart = true
        func space(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 }
        func newline(_ unit: UInt16) -> Bool { unit == 10 || unit == 13 || unit == 0x85 || unit == 0x2028 || unit == 0x2029 }
        func add(_ start: Int, _ end: Int, _ kind: JSONSyntaxKind) { if end > start { tokens.append(.init(range: NSRange(location: start, length: end - start), kind: kind)) } }
        while index < units.count {
            guard !Task.isCancelled, tokens.count < JSONSyntaxLexer.maximumTokens else { return nil }
            if newline(units[index]) { index += 1; lineStart = true; continue }
            if lineStart {
                let start = index
                while index < units.count, space(units[index]) { index += 1 }
                let indent = index - start
                if let blockIndent, index < units.count, !newline(units[index]), indent > blockIndent {
                    while index < units.count, !newline(units[index]) { index += 1 }
                    add(start, index, .string); continue
                }
                if index < units.count, !newline(units[index]) { blockIndent = nil }
                lineStart = false
                if index == units.count { break }
            }
            let start = index, unit = units[index]
            if space(unit) { index += 1; continue }
            if unit == 35 {
                while index < units.count, !newline(units[index]) { index += 1 }
                add(start, index, .comment); continue
            }
            if unit == 34 || unit == 39 {
                index += 1
                while index < units.count {
                    if index & 255 == 0, Task.isCancelled { return nil }
                    if unit == 34, units[index] == 92 { index = min(units.count, index + 2); continue }
                    if units[index] == unit {
                        index += 1
                        if unit == 39, index < units.count, units[index] == 39 { index += 1; continue }
                        break
                    }
                    index += 1
                }
                var next = index
                while next < units.count, space(units[next]) { next += 1 }
                add(start, index, next < units.count && units[next] == 58 ? .key : .string)
                continue
            }
            if [91, 93, 123, 125].contains(unit) { index += 1; add(start, index, .bracket); continue }
            if [44, 58].contains(unit) { index += 1; add(start, index, .separator); continue }
            if unit == 45, index + 1 == units.count || space(units[index + 1]) || newline(units[index + 1]) {
                index += 1; add(start, index, .separator); continue
            }
            if unit == 124 || unit == 62 {
                var line = start
                while line > 0, !newline(units[line - 1]) { line -= 1 }
                var leading = line
                while leading < units.count, space(units[leading]) { leading += 1 }
                blockIndent = leading - line
                while index < units.count, !newline(units[index]) { index += 1 }
                add(start, index, .separator); continue
            }
            while index < units.count {
                let c = units[index]
                if newline(c) || [44, 93, 125].contains(c) { break }
                if c == 58, index + 1 == units.count || space(units[index + 1]) || newline(units[index + 1]) || [91,123].contains(units[index + 1]) { break }
                if c == 35, index > start, space(units[index - 1]) { break }
                index += 1
            }
            if index == start { index += 1; continue }
            var end = index
            while end > start, space(units[end - 1]) { end -= 1 }
            let word = String(decoding: units[start..<end], as: UTF16.self)
            let kind: JSONSyntaxKind
            if index < units.count, units[index] == 58 { kind = .key }
            else if ["null", "Null", "NULL", "~", "true", "True", "TRUE", "false", "False", "FALSE"].contains(word) { kind = .literal }
            else if word.range(of: #"\A[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?\z"#, options: .regularExpression) != nil { kind = .number }
            else { kind = .string }
            add(start, end, kind)
        }
        return JSONSyntaxSnapshot(utf16Length: units.count, tokens: tokens, partners: [:])
    }
}
