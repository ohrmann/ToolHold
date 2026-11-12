import Foundation

/// Node references belong to the two immutable snapshots, never to a displayed row number.
struct JSONDiffChange: Sendable, Identifiable {
    enum Kind: String, Sendable { case added = "Added", removed = "Removed", changed = "Changed", typeChanged = "Type changed" }
    let id: Int
    let kind: Kind
    let before: Int?
    let after: Int?
    let beforeText: JSONDiffText?
    let afterText: JSONDiffText?
}

struct JSONDiffResult: Sendable {
    let before: JSONStructureDocument
    let after: JSONStructureDocument
    let changes: [JSONDiffChange]
    let added: Int
    let removed: Int
    let changed: Int
    let hasDuplicates: Bool

    func path(for change: JSONDiffChange) -> JSONNodePath {
        let left = change.before.map { before.path($0) }
        let right = change.after.map { after.path($0) }
        let path = left ?? right!
        return JSONNodePath(pointer: path.pointer, jsonPath: path.jsonPath,
                            ambiguous: left?.ambiguous == true || right?.ambiguous == true)
    }
    func fragment(_ change: JSONDiffChange, side: JSONDiffSide) -> String? {
        let id = side == .before ? change.before : change.after
        return id.map { (side == .before ? before : after).fragment($0) }
    }
    func value(_ change: JSONDiffChange, side: JSONDiffSide) -> String? {
        let document = side == .before ? before : after
        guard let id = side == .before ? change.before : change.after else { return nil }
        return document.nodes[id].scalar
    }
}

enum JSONDiffSide: String, Sendable, CaseIterable { case before = "Before", after = "After" }

enum JSONStructuralDiff {
    static func compare(_ before: JSONStructureDocument, _ after: JSONStructureDocument) throws -> JSONDiffResult {
        var changes: [JSONDiffChange] = []
        var pending: [(Int?, Int?)] = [(before.rootID, after.rootID)]
        var added = 0, removed = 0, changed = 0
        while let (left, right) = pending.popLast() {
            try Task.checkCancellation()
            let kind: JSONDiffChange.Kind?
            if left == nil { kind = .added }
            else if right == nil { kind = .removed }
            else {
                let a = before.nodes[left!], b = after.nodes[right!]
                if a.kind != b.kind { kind = .typeChanged }
                else if a.kind == .object {
                    // Data compares exact decoded scalar sequences, unlike canonical Swift String equality.
                    var groups: [Data: [Int]] = [:], positions: [Data: Int] = [:]
                    for id in b.children {
                        try Task.checkCancellation()
                        groups[Data(after.nodes[id].key!.utf8), default: []].append(id)
                    }
                    var pairs: [(Int?, Int?)] = [], consumed: Set<Int> = []
                    for id in a.children {
                        try Task.checkCancellation()
                        let key = Data(before.nodes[id].key!.utf8), index = positions[key, default: 0]
                        let matches = groups[key] ?? []
                        let match = index < matches.count ? matches[index] : nil
                        positions[key] = index + 1
                        if let match { consumed.insert(match) }
                        pairs.append((id, match))
                    }
                    for id in b.children where !consumed.contains(id) {
                        try Task.checkCancellation(); pairs.append((nil, id))
                    }
                    pending.append(contentsOf: pairs.reversed())
                    continue
                } else if a.kind == .array {
                    for index in (0..<max(a.children.count, b.children.count)).reversed() {
                        try Task.checkCancellation()
                        pending.append((index < a.children.count ? a.children[index] : nil,
                                        index < b.children.count ? b.children[index] : nil))
                    }
                    continue
                } else {
                    kind = a.scalar!.utf8.elementsEqual(b.scalar!.utf8) ? nil : .changed
                }
            }
            if let kind {
                let a = left.flatMap { before.nodes[$0].scalar }, b = right.flatMap { after.nodes[$0].scalar }
                let previews: (JSONDiffText?, JSONDiffText?)
                if let a, let b { previews = JSONDiffText.pair(a, b) }
                else { previews = (a.map { JSONDiffText(preview: .make($0), difference: nil) },
                                   b.map { JSONDiffText(preview: .make($0), difference: nil) }) }
                changes.append(JSONDiffChange(id: changes.count, kind: kind, before: left, after: right,
                                              beforeText: previews.0, afterText: previews.1))
                switch kind { case .added: added += 1; case .removed: removed += 1; default: changed += 1 }
            }
        }
        var duplicates = false
        for document in [before, after] {
            for node in document.nodes {
                try Task.checkCancellation()
                if node.occurrences > 1 { duplicates = true; break }
            }
        }
        return JSONDiffResult(before: before, after: after, changes: changes, added: added, removed: removed,
                              changed: changed, hasDuplicates: duplicates)
    }
}

/// Bounded display context, with a grapheme-aligned differing span in decoded UTF-16.
/// No normalization: canonical-equivalent graphemes can still differ.
struct JSONDiffText: Sendable {
    let preview: JSONTreePreview
    let difference: NSRange?
    static func pair(_ left: String, _ right: String) -> (JSONDiffText, JSONDiffText) {
        let a = Array(left), b = Array(right)
        var prefix = 0, suffix = 0
        while prefix < min(a.count, b.count), a[prefix].utf8.elementsEqual(b[prefix].utf8) { prefix += 1 }
        while suffix < min(a.count, b.count) - prefix,
              a[a.count - 1 - suffix].utf8.elementsEqual(b[b.count - 1 - suffix].utf8) { suffix += 1 }
        func context(_ text: String, _ characters: [Character]) -> JSONDiffText {
            let start = characters.prefix(prefix).reduce(0) { $0 + $1.utf16.count }
            let length = characters.dropFirst(prefix).dropLast(suffix).reduce(0) { $0 + $1.utf16.count }
            let range = NSRange(location: start, length: length)
            return JSONDiffText(preview: .make(text, around: range), difference: range)
        }
        return (context(left, a), context(right, b))
    }
}
