// Derived query evaluation architecture: Copyright © 2024 Matthias Zenger.
// Licensed under Apache License 2.0; http://www.apache.org/licenses/LICENSE-2.0
// Modified for Developer Toolbox. Distributed on an AS IS basis, without warranties.
import Foundation

/// Query selection/slicing/filter architecture adapted from DynamicJSON's
/// JSONPathEvaluator.swift (Matthias Zenger, Apache-2.0). Modified to evaluate
/// source-scoped NodeIDs, exact decimals/scalars and bounded cancellable work.
/// See ThirdPartyNotices/DynamicJSON/README.md for provenance and changes.
enum JSONPathFailure: Error, Sendable {
    case syntax(String, NSRange)
    case evaluation(String)
    case limit(String)
    case duplicates
    var message: String {
        switch self {
        case .syntax(let message, _), .evaluation(let message), .limit(let message): return message
        case .duplicates: return "Query execution is unavailable for duplicate member names. The JSON is valid, but JSONPath addressing is ambiguous. Inspect occurrences in JSON Tree Viewer."
        }
    }
}

struct JSONPathEvaluation: Sendable {
    let snapshotID: UUID
    /// Ordered occurrences, not a set. A query can select the same node repeatedly.
    let nodeIDs: [Int]
}

enum JSONPathOperations {
    // Separate query budgets protect against repeated selectors/descendants expanding
    // a small document exponentially. They do not change JSONProcessor's input limits.
    static let maximumQueryLength = 4_096
    static let maximumResults = 262_144
    static let maximumWork = 2_000_000
    static let maximumCopyUTF16 = 4_194_304

    static func evaluate(_ query: String, in document: JSONStructureDocument) throws -> JSONPathEvaluation {
        try Task.checkCancellation()
        guard query.utf16.count <= maximumQueryLength else { throw JSONPathFailure.limit("Query exceeds 4,096 UTF-16 code units.") }
        var parser = JSONPathQueryParser(string: query)
        let compiled: JSONPathQuery
        do { compiled = try parser.parse() }
        catch let error as JSONPathFailure { throw error }
        catch { throw JSONPathFailure.syntax(error.localizedDescription, NSRange(location: parser.position, length: parser.position < query.utf16.count ? 1 : 0)) }
        var evaluator = JSONPathNodeEvaluator(document: document)
        try evaluator.validate(compiled)
        guard !document.nodes.contains(where: { $0.occurrences > 1 }) else { throw JSONPathFailure.duplicates }
        let ids = try evaluator.query(compiled, current: document.rootID)
        return JSONPathEvaluation(snapshotID: document.snapshotID, nodeIDs: ids)
    }
    static func copyArray(_ result: JSONPathEvaluation, document: JSONStructureDocument) throws -> String {
        guard result.snapshotID == document.snapshotID else { throw JSONPathFailure.evaluation("Results no longer match the input.") }
        var count = 2
        for id in result.nodeIDs {
            try Task.checkCancellation()
            count += document.nodes[id].range.length + 2
            guard count <= maximumCopyUTF16 else { throw JSONPathFailure.limit("Combined results exceed the 4 Mi UTF-16 copy budget. Copy individual fragments or narrow the query.") }
        }
        return "[" + result.nodeIDs.map { document.fragment($0) }.joined(separator: ",\n") + "]"
    }
}

private struct JSONPathNodeEvaluator {
    enum ValueType { case logical, value, nodes }
    enum Value { case logical(Bool), value(Atom), nodes([Int]) }
    enum Atom { case missing, null, boolean(Bool), number(JSONPathNumber), string(String), node(Int) }
    let document: JSONStructureDocument
    var work = 0
    var members: [Int: [Data: Int]] = [:]
    var numbers: [Int: JSONPathNumber] = [:]
    var regexes: [Data: NSRegularExpression] = [:]
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))

    mutating func tick(_ n: Int = 1) throws {
        work += n
        guard work <= JSONPathOperations.maximumWork else { throw JSONPathFailure.limit("Query work budget reached. Narrow the query.") }
        if work & 127 == 0 {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw JSONPathFailure.limit("Query time budget reached. Narrow the query.") }
        }
    }
    func signature(_ name: String) throws -> ([ValueType], ValueType) {
        switch name {
        case "length": return ([.value], .value)
        case "count": return ([.nodes], .value)
        case "value": return ([.nodes], .value)
        case "match", "search": return ([.value, .value], .logical)
        default: throw JSONPathFailure.evaluation("Unknown JSONPath function. Supported functions: length, count, value, match, search.")
        }
    }
    func failType() -> JSONPathFailure { .evaluation("Invalid JSONPath expression types. Use a singular value in comparisons and a logical expression in filters.") }
    mutating func validate(_ query: JSONPathQuery) throws {
        try tick()
        for segment in query.segments {
            for selector in segment.selectors {
                if case .filter(let expression) = selector { _ = try type(expression, expecting: .logical) }
            }
        }
    }
    mutating func type(_ expression: JSONPathQuery.Expression, expecting expected: ValueType) throws -> ValueType {
        try tick()
        let actual: ValueType
        switch expression {
        case .null, .true, .false, .number, .string: actual = .value
        case .query(let query), .singularQuery(let query):
            try validate(query)
            if expected == .value && !query.isSingular { throw failType() }
            actual = expected
        case .call(let name, let args):
            let (types, returned) = try signature(name)
            guard types.count == args.count else { throw JSONPathFailure.evaluation("Incorrect number of arguments for \(name).") }
            for (arg, type) in zip(args, types) { _ = try self.type(arg, expecting: type) }
            actual = returned
        case .prefix(let op, let arg):
            guard op == .not else { throw failType() }
            _ = try type(arg, expecting: .logical); actual = .logical
        case .operation(let lhs, let op, let rhs):
            let operand: ValueType
            switch op {
            case .and, .or: operand = .logical
            case .equals, .notEquals, .lessThan, .lessThanEquals, .greaterThan, .greaterThanEquals: operand = .value
            default: throw failType()
            }
            _ = try type(lhs, expecting: operand); _ = try type(rhs, expecting: operand); actual = .logical
        case .variable: throw JSONPathFailure.evaluation("Variables are not part of RFC 9535 JSONPath.")
        }
        guard actual == expected else { throw failType() }
        return actual
    }
    mutating func query(_ query: JSONPathQuery, current: Int) throws -> [Int] {
        try tick()
        var root = query
        while case .select(let parent, _) = root { root = parent }
        var ids = [root.isRelative ? current : document.rootID]
        for segment in query.segments {
            var next: [Int] = []
            for id in ids {
                if segment.isDescendant {
                    var stack = [id]
                    while let descendant = stack.popLast() {
                        try tick()
                        for selector in segment.selectors { try append(select(selector, from: descendant), to: &next) }
                        stack.append(contentsOf: document.nodes[descendant].children.reversed())
                    }
                } else {
                    for selector in segment.selectors { try append(select(selector, from: id), to: &next) }
                }
            }
            ids = next
        }
        return ids
    }
    mutating func append(_ values: [Int], to output: inout [Int]) throws {
        try tick()
        guard output.count + values.count <= JSONPathOperations.maximumResults else { throw JSONPathFailure.limit("Query exceeds 262,144 result occurrences. Narrow the query.") }
        output.append(contentsOf: values)
    }
    mutating func select(_ selector: JSONPathQuery.Selector, from id: Int) throws -> [Int] {
        try tick()
        let node = document.nodes[id]
        switch selector {
        case .wildcard: return node.children
        case .member(let key):
            guard node.kind == .object else { return [] }
            if members[id] == nil {
                var map: [Data: Int] = [:]
                for child in node.children { try tick(); map[Data(document.nodes[child].key!.utf8)] = child }
                members[id] = map
            }
            return members[id]![Data(key.utf8)].map { [$0] } ?? []
        case .index(let index):
            guard node.kind == .array else { return [] }
            let position = index < 0 ? node.children.count + index : index
            return node.children.indices.contains(position) ? [node.children[position]] : []
        case .slice(let s, let e, let increment):
            guard node.kind == .array else { return [] }
            let count = node.children.count, step = increment ?? 1
            guard step != 0 else { return [] }
            func normalize(_ value: Int) -> Int { value < 0 ? count + value : value }
            let start = normalize(s ?? (step > 0 ? 0 : count - 1))
            let end = normalize(e ?? (step > 0 ? count : -count - 1))
            var i = step > 0 ? min(max(start, 0), count) : min(max(start, -1), count - 1)
            let stop = step > 0 ? min(max(end, 0), count) : min(max(end, -1), count - 1)
            var result: [Int] = []
            while step > 0 ? i < stop : i > stop {
                try tick(); result.append(node.children[i]); i += step
            }
            return result
        case .filter(let expression):
            var result: [Int] = []
            for child in node.children {
                try tick()
                if case .logical(true) = try evaluate(expression, current: child, expecting: .logical) { result.append(child) }
            }
            return result
        }
    }
    mutating func atom(_ id: Int) throws -> Atom {
        let node = document.nodes[id]
        switch node.kind {
        case .string: return .string(node.scalar!)
        case .number:
            if numbers[id] == nil { numbers[id] = JSONPathNumber(node.scalar!) }
            return .number(numbers[id]!)
        case .boolean: return .boolean(node.scalar == "true")
        case .null: return .null
        default: return .node(id)
        }
    }
    mutating func evaluate(_ expression: JSONPathQuery.Expression, current: Int, expecting expected: ValueType) throws -> Value {
        try tick()
        switch expression {
        case .null: return .value(.null)
        case .true: return .value(.boolean(true))
        case .false: return .value(.boolean(false))
        case .number(let value): return .value(.number(JSONPathNumber(value)))
        case .string(let text): return .value(.string(text))
        case .query(let path), .singularQuery(let path):
            let ids = try query(path, current: current)
            switch expected {
            case .logical: return .logical(!ids.isEmpty)
            case .nodes: return .nodes(ids)
            case .value: return .value(try ids.first.map { try atom($0) } ?? .missing)
            }
        case .prefix(_, let arg):
            guard case .logical(let value) = try evaluate(arg, current: current, expecting: .logical) else { throw failType() }
            return .logical(!value)
        case .operation(let lhs, let op, let rhs):
            if op == .and || op == .or {
                guard case .logical(let left) = try evaluate(lhs, current: current, expecting: .logical) else { throw failType() }
                if (op == .and && !left) || (op == .or && left) { return .logical(left) }
                return try evaluate(rhs, current: current, expecting: .logical)
            }
            guard case .value(let left) = try evaluate(lhs, current: current, expecting: .value),
                  case .value(let right) = try evaluate(rhs, current: current, expecting: .value) else { throw failType() }
            let equal = try equals(left, right)
            switch op {
            case .equals: return .logical(equal)
            case .notEquals: return .logical(!equal)
            case .lessThan: return .logical(less(left, right))
            case .greaterThan: return .logical(less(right, left))
            case .lessThanEquals: return .logical(equal || less(left, right))
            case .greaterThanEquals: return .logical(equal || less(right, left))
            default: throw failType()
            }
        case .call(let name, let arguments):
            let (types, _) = try signature(name)
            var args: [Value] = []
            for (arg, type) in zip(arguments, types) { args.append(try evaluate(arg, current: current, expecting: type)) }
            return try call(name, args: args)
        case .variable: throw failType()
        }
    }
    mutating func equals(_ lhs: Atom, _ rhs: Atom) throws -> Bool {
        try tick()
        switch (lhs, rhs) {
        case (.missing, .missing), (.null, .null): return true
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.number(let a), .number(let b)): return a.compare(b) == 0
        case (.string(let a), .string(let b)): return a.unicodeScalars.elementsEqual(b.unicodeScalars)
        case (.node(let a), .node(let b)):
            let x = document.nodes[a], y = document.nodes[b]
            guard x.kind == y.kind, x.children.count == y.children.count else { return false }
            if x.kind == .array {
                for (i, j) in zip(x.children, y.children) { if try !equals(atom(i), atom(j)) { return false } }
            } else {
                for child in x.children {
                    guard let other = try select(.member(document.nodes[child].key!), from: b).first,
                          try equals(atom(child), atom(other)) else { return false }
                }
            }
            return true
        default: return false
        }
    }
    func less(_ lhs: Atom, _ rhs: Atom) -> Bool {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)): return a.compare(b) < 0
        case (.string(let a), .string(let b)): return a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
        default: return false
        }
    }
    mutating func call(_ name: String, args: [Value]) throws -> Value {
        switch name {
        case "count":
            guard case .nodes(let nodes) = args[0] else { throw failType() }
            return .value(.number(JSONPathNumber(String(nodes.count))))
        case "value":
            guard case .nodes(let nodes) = args[0] else { throw failType() }
            return .value(try nodes.count == 1 ? atom(nodes[0]) : .missing)
        case "length":
            guard case .value(let value) = args[0] else { throw failType() }
            let count: Int
            switch value {
            case .string(let text): count = text.unicodeScalars.count
            case .node(let id): count = document.nodes[id].children.count
            default: return .value(.missing)
            }
            return .value(.number(JSONPathNumber(String(count))))
        case "match", "search":
            guard case .value(.string(let text)) = args[0], case .value(.string(let pattern)) = args[1] else { return .logical(false) }
            return .logical(try match(text, pattern: pattern, whole: name == "match"))
        default: throw failType()
        }
    }
    mutating func match(_ text: String, pattern: String, whole: Bool) throws -> Bool {
        try tick()
        guard pattern.utf16.count <= 1_024 else { throw JSONPathFailure.limit("Regular expression exceeds the 1,024 UTF-16 code unit budget.") }
        // Avoid pathological ICU compilation before cancellable matching can begin.
        var quantifier = "", insideQuantifier = false
        for scalar in pattern.unicodeScalars {
            if scalar == "{" { insideQuantifier = true; quantifier = "" }
            else if scalar == "}" { insideQuantifier = false }
            else if insideQuantifier && (48...57).contains(scalar.value) {
                quantifier.unicodeScalars.append(scalar)
                if quantifier.count > 5 { throw JSONPathFailure.limit("Regular expression repetition budget reached.") }
            }
        }
        let regex: NSRegularExpression
        let key = Data(([whole ? "match:" : "search:"] + [pattern]).joined().utf8)
        if let cached = regexes[key] { regex = cached }
        else {
            guard let mapped = JSONPathRegex.map(pattern) else { return false }
            let wrapped = whole ? "\\A(?:" + mapped + ")\\z" : mapped
            guard let compiled = try? NSRegularExpression(pattern: wrapped, options: []) else { return false }
            regexes[key] = compiled; regex = compiled
        }
        var matched = false, aborted = false
        let deadline = min(self.deadline, ContinuousClock.now.advanced(by: .milliseconds(150)))
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: text.utf16.count)) { result, _, stop in
            if Task.isCancelled || ContinuousClock.now >= deadline { aborted = true; stop.pointee = true; return }
            if let result, !whole || result.range == NSRange(location: 0, length: text.utf16.count) { matched = true; stop.pointee = true }
        }
        if aborted { try Task.checkCancellation(); throw JSONPathFailure.limit("Regular expression work budget reached.") }
        return matched
    }
}
