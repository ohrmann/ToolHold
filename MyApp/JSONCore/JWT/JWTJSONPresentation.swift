import Foundation

/// Presentation of an already validated arena, never another grammar parser.
struct JWTJSONPresentation: Sendable {
    let text: String
    let nodeRanges: [Int: NSRange]
    let keyRanges: [Int: NSRange]
    static func make(_ document: JSONStructureDocument, budget: JWTBudget, limit: Int = 262_144) throws -> Self? {
        let source = document.source as NSString
        var text = "", length = 0, nodes: [Int: NSRange] = [:], keys: [Int: NSRange] = [:]
        enum Full: Error { case display }
        func append(_ value: String) throws {
            let count = value.utf16.count
            guard count <= limit - length else { throw Full.display }
            text += value; length += count
        }
        func emit(_ id: Int, depth: Int) throws {
            try budget.check()
            let node = document.nodes[id], start = length
            if node.kind == .object || node.kind == .array {
                let object = node.kind == .object
                try append(object ? "{" : "[")
                if !node.children.isEmpty {
                    try append("\n")
                    for (index, child) in node.children.enumerated() {
                        try append(String(repeating: " ", count: (depth + 1) * 2))
                        if let range = document.nodes[child].keyRange {
                            let begin = length
                            try append(source.substring(with: range)); keys[child] = .init(location: begin, length: length - begin)
                            try append(": ")
                        }
                        try emit(child, depth: depth + 1)
                        try append(index == node.children.count - 1 ? "\n" : ",\n")
                    }
                    try append(String(repeating: " ", count: depth * 2))
                }
                try append(object ? "}" : "]")
            } else { try append(source.substring(with: node.range)) }
            nodes[id] = .init(location: start, length: length - start)
        }
        do { try emit(0, depth: 0); return .init(text: text, nodeRanges: nodes, keyRanges: keys) }
        catch is Full { return nil }
    }
}
