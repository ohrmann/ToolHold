import Foundation

/// A bounded, sanitized display plus an explicit UTF-16 source → display mapping. Memory only.
struct JSONDiagnosticContext: Sendable {
    struct Segment: Sendable {
        let sourceRange: NSRange?
        let displayRange: NSRange
    }
    let text: String
    let detectionRange: NSRange
    let segments: [Segment]

    static func make(source: String, diagnostic: JSONDiagnostic) -> Self {
        make(source: source, range: diagnostic.range)
    }

    /// Shared safe source context; schema violations are not JSON grammar diagnostics.
    static func make(source: String, range anchorRange: NSRange, compactWhitespace: Bool = true) -> Self {
        let original = source as NSString
        let position = min(original.length, max(0, anchorRange.location))
        func safe(_ range: NSRange) -> String {
            guard range.length <= 32 else { return "⟪long grapheme⟫" }
            let text = original.substring(with: range)
            return text.unicodeScalars.map { scalar in
                switch scalar.value {
                case 9: return "⇥"
                case 10: return "↵"
                case 13: return "␍"
                case 0...8, 11...12, 14...31, 0x7F...0x9F, 0x061C, 0x200B, 0x200E, 0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF:
                    return String(format: "⟦U+%04X⟧", scalar.value)
                default: return String(scalar)
                }
            }.joined()
        }
        let whitespace = compactWhitespace ? Self.compactWhitespace(in: original, protecting: anchorRange) : []
        func item(at offset: Int) -> (NSRange, String) {
            var low = 0, high = whitespace.count
            while low < high {
                let middle = (low + high) / 2
                if NSMaxRange(whitespace[middle]) <= offset { low = middle + 1 }
                else { high = middle }
            }
            if low < whitespace.count, whitespace[low].location <= offset {
                return (whitespace[low], " ")
            }
            let range = original.rangeOfComposedCharacterSequence(at: offset)
            return (range, safe(range))
        }
        let pivot = position < original.length ? item(at: position) : (NSRange(location: position, length: 0), "⟂ EOF")
        var left: [(NSRange, String)] = [], right: [(NSRange, String)] = []
        var cursor = pivot.0.location, budget = 0
        while cursor > 0 {
            let (range, display) = item(at: cursor - 1)
            guard budget + display.utf16.count <= 72 else { break }
            left.append((range, display)); budget += display.utf16.count; cursor = range.location
        }
        let start = cursor
        cursor = NSMaxRange(pivot.0); budget = 0
        while cursor < original.length {
            let (range, display) = item(at: cursor)
            guard budget + display.utf16.count <= 96 else { break }
            right.append((range, display)); budget += display.utf16.count; cursor = NSMaxRange(range)
        }
        let end = cursor
        var display = "", segments: [Segment] = []
        func append(_ text: String, sourceRange: NSRange?) -> NSRange {
            let range = NSRange(location: display.utf16.count, length: text.utf16.count)
            display += text; segments.append(.init(sourceRange: sourceRange, displayRange: range))
            return range
        }
        if start > 0 { _ = append("…", sourceRange: nil) }
        for item in left.reversed() { _ = append(item.1, sourceRange: item.0) }
        var anchor: NSRange
        if anchorRange.length == 0 {
            anchor = append(position == original.length ? "⟂ EOF" : "│", sourceRange: NSRange(location: position, length: 0))
            if pivot.0.length > 0 { _ = append(pivot.1, sourceRange: pivot.0) }
        } else {
            anchor = append(pivot.1, sourceRange: pivot.0)
        }
        for item in right { _ = append(item.1, sourceRange: item.0) }
        if end < original.length { _ = append("…", sourceRange: nil) }
        if anchorRange.length > 0 {
            let affected = segments.compactMap { segment -> NSRange? in
                guard let range = segment.sourceRange,
                      NSIntersectionRange(range, anchorRange).length > 0 else { return nil }
                return segment.displayRange
            }
            if let first = affected.first, let last = affected.last {
                anchor = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            }
        }
        return Self(text: display, detectionRange: anchor, segments: segments)
    }

    /// Presentation only: ASCII JSON whitespace outside double-quoted strings.
    /// A collapsed space maps to the entire original run, before context cropping.
    private static func compactWhitespace(in source: NSString, protecting anchor: NSRange) -> [NSRange] {
        guard source.length <= JSONProcessor.maximumUTF16Length else { return [] }
        var ranges: [NSRange] = []
        var index = 0, quoted = false, escaped = false
        let position = min(source.length, max(0, anchor.location))
        let end = position + min(max(0, anchor.length), source.length - position)
        func isWhitespace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 13 }
        while index < source.length {
            if index & 255 == 0, Task.isCancelled { return [] }
            let unit = source.character(at: index)
            if quoted {
                if escaped { escaped = false }
                else if unit == 92 { escaped = true }
                else if unit == 34 { quoted = false }
                index += 1
            } else if unit == 34 {
                quoted = true; index += 1
            } else if isWhitespace(unit) {
                let start = index
                repeat {
                    index += 1
                    if index & 255 == 0, Task.isCancelled { return [] }
                } while index < source.length && isWhitespace(source.character(at: index))
                if index == start + 1, unit == 32 { continue }
                var boundaries = [start]
                if position > start, position < index { boundaries.append(position) }
                if end > start, end < index, end != position { boundaries.append(end) }
                boundaries.append(index)
                // Never split CRLF, surrogate pairs or a whitespace-based grapheme.
                guard boundaries.allSatisfy({ $0 == source.length || source.rangeOfComposedCharacterSequence(at: $0).location == $0 }) else { continue }
                for (lower, upper) in zip(boundaries, boundaries.dropFirst()) {
                    if anchor.length > 0, lower >= position, upper <= end { continue }
                    ranges.append(NSRange(location: lower, length: upper - lower))
                }
            } else {
                index += 1
            }
        }
        return ranges
    }
}
