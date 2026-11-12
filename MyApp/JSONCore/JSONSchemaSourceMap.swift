import Foundation

/// Index is snapshot-scoped and compares pointer tokens without Unicode normalization.
struct JSONSchemaSourceMap: Sendable {
    let document: JSONStructureDocument
    let pointers: [Data: Int]
    init(_ document: JSONStructureDocument) {
        self.document = document
        var pointers: [Data: Int] = [:]
        var paths = Array(repeating: "", count: document.nodes.count)
        for node in document.nodes {
            if let parent = node.parent {
                let token = node.key.map(JSONPointer.escapeToken) ?? String(node.arrayIndex!)
                paths[node.id] = paths[parent] + "/" + token
            }
            pointers[Data(paths[node.id].utf8)] = node.id
        }
        self.pointers = pointers
    }
    func node(_ pointer: String) -> Int? { pointers[Data(pointer.utf8)] }
    func value() throws -> JSONValue {
        var values: [JSONValue] = Array(repeating: .null, count: document.nodes.count)
        for node in document.nodes.reversed() {
            guard SchemaRuntime.check() else { throw CancellationError() }
            switch node.kind {
            case .object:
                var members = OrderedDictionary<String, JSONValue>()
                for id in node.children { members[document.nodes[id].key!] = values[id] }
                values[node.id] = .object(members)
            case .array: values[node.id] = .array(node.children.map { values[$0] })
            case .string: values[node.id] = .string(node.scalar!)
            case .number: values[node.id] = .numberLiteral(try JSONNumberLiteral(node.scalar!))
            case .boolean: values[node.id] = .boolean(node.scalar == "true")
            case .null: values[node.id] = .null
            }
        }
        return values[0]
    }
    func pointer(_ id: Int) -> String { document.path(id).pointer }
    func field(_ name: String, of id: Int) -> Int? {
        document.nodes[id].children.first { document.nodes[$0].key?.utf8.elementsEqual(name.utf8) == true }
    }
}

struct JSONSchemaRegistry: Sendable {
    static let base = URL(string: "https://developer-toolbox.invalid/schema")!
    static let dialect = "https://json-schema.org/draft/2020-12/schema"
    let source: JSONSchemaSourceMap
    let dialect: Dialect
    let options: JSONSchemaOptions
    var resources: [URL: Int] = [:]
    var anchors: [URL: Int] = [:]
    var schemaNodes: [Int] = []
    var additionalSchemaRoots: [Int] = []
    var bases: [Int: URL] = [:]
    var notes: [String] = []
    var policyIssue: JSONSchemaIssue?
    var policyStatus: JSONSchemaStatus?

    init(_ document: JSONStructureDocument, base: URL = Self.base, options: JSONSchemaOptions = .init(), check: Bool = true) {
        source = JSONSchemaSourceMap(document)
        self.options = options
        let declared = document.nodes[0].children.first { document.nodes[$0].key == "$schema" }.flatMap { document.nodes[$0].scalar }
        dialect = declared.flatMap { Dialect(uri: $0) } ?? options.assumedDialect
        resources[base] = 0
        visit(0, base: base)
        if check, policyStatus == nil { checkReferences() }
    }
    private mutating func reject(_ status: JSONSchemaStatus, _ message: String, at id: Int, keyword: String) {
        guard policyStatus == nil else { return }
        policyStatus = status
        policyIssue = JSONSchemaIssue(id: 0, keyword: keyword, message: message, instancePointer: "",
            schemaPointer: source.pointer(id), instanceNode: nil, schemaNode: id, depth: 0)
    }
    private mutating func visit(_ id: Int, base: URL) {
        guard SchemaRuntime.check(), policyStatus == nil else { return }
        let node = source.document.nodes[id]
        guard node.kind == .object || node.kind == .boolean else { return }
        guard bases[id] == nil else { return }
        schemaNodes.append(id)
        var base = base
        if !(dialect == .draft7 && source.field("$ref", of: id) != nil),
           let field = source.field("$id", of: id), let value = source.document.nodes[field].scalar,
           let resolved = URL(string: value, relativeTo: base)?.absoluteURL,
           let url = resolved.withoutFragment {
            if dialect == .draft7, let fragment = resolved.fragment, !fragment.isEmpty {
                if let old = anchors[resolved], old != id { reject(.invalidSchema, "Schema anchor is not unique.", at: field, keyword: "$id"); return }
                anchors[resolved] = id; base = url
            } else {
                if let old = resources[url], old != id { reject(.invalidSchema, "Schema resource identifier is not unique.", at: field, keyword: "$id"); return }
                base = url; resources[url] = id
            }
        }
        bases[id] = base
        if let field = source.field("$schema", of: id), source.document.nodes[field].kind == .string, let text = source.document.nodes[field].scalar,
           Dialect(uri: text) != dialect {
            reject(.unsupportedDialect, "This schema uses an unsupported or mixed dialect.", at: field, keyword: "$schema"); return
        }
        if dialect != .draft7, let field = source.field("$vocabulary", of: id) {
            let supported = dialect.supportedVocabularies
            for entry in source.document.nodes[field].children where source.document.nodes[entry].kind == .boolean && source.document.nodes[entry].scalar == "true" {
                if !supported.contains(source.document.nodes[entry].key ?? "") {
                    reject(.unsupportedVocabulary, "The schema requires an unsupported vocabulary. Format is annotation-only.", at: entry, keyword: "$vocabulary"); return
                }
            }
        }
        if let field = source.field("format", of: id), let name = source.document.nodes[field].scalar, options.validateFormats {
            if ToolboxSchemaFormat.standardNames.contains(name), !ToolboxSchemaFormat.names.contains(name) {
                reject(.unsupportedFormat, "This format is not supported by Validate formats: " + name, at: field, keyword: "format"); return
            }
            if !ToolboxSchemaFormat.standardNames.contains(name), notes.count < 8 { notes.append("Unknown format treated as annotation: " + JSONTreePreview.make(name, budget: 50).text) }
        }
        if dialect == .draft7, source.field("$ref", of: id) != nil { return }
        var patterns: [Int] = []
        if let pattern = source.field("pattern", of: id) { patterns.append(pattern) }
        if let patternMap = source.field("patternProperties", of: id) {
            for child in source.document.nodes[patternMap].children {
                if SchemaPattern(source.document.nodes[child].key ?? "") == nil {
                    reject(SchemaRuntime.current?.failure == .resourceLimit ? .resourceLimit : .unsupportedFeature,
                        "A property pattern cannot be evaluated by the supported regular-expression profile.", at: child, keyword: "patternProperties"); return
                }
            }
        }
        for field in patterns {
            if let pattern = source.document.nodes[field].scalar, SchemaPattern(pattern) == nil {
                let status: JSONSchemaStatus = switch SchemaRuntime.current?.failure {
                case .resourceLimit: .resourceLimit
                case .unsupportedPattern: .unsupportedFeature
                default: .invalidSchema
                }
                reject(status, "The pattern is invalid or outside the supported regular-expression profile.", at: field, keyword: "pattern"); return
            }
        }
        for name in (dialect == .draft7 ? [] : dialect == .draft2019_09 ? ["$anchor"] : ["$anchor", "$dynamicAnchor"]) {
            if let field = source.field(name, of: id), let text = source.document.nodes[field].scalar {
                var components = URLComponents(url: base, resolvingAgainstBaseURL: true)!
                components.fragment = text
                if let url = components.url {
                    if let old = anchors[url], old != id { reject(.invalidSchema, "Schema anchor is not unique.", at: field, keyword: name); return }
                    anchors[url] = id
                }
            }
        }
        let maps: Set<String> = dialect == .draft7 ? ["definitions", "properties", "patternProperties", "dependencies"] : ["$defs", "definitions", "properties", "patternProperties", "dependentSchemas", "dependencies"]
        let lists: Set<String> = dialect == .draft2020_12 ? ["allOf", "anyOf", "oneOf", "prefixItems"] : ["allOf", "anyOf", "oneOf"]
        let singles: Set<String> = ["additionalItems", "items", "additionalProperties", "unevaluatedProperties", "unevaluatedItems", "contains", "propertyNames", "not", "if", "then", "else", "contentSchema"]
        let known = Set(dialect.keywords.map { $0.name }).union(["definitions", "$comment"])
        for child in node.children {
            let name = source.document.nodes[child].key!
            if name == "items", dialect != .draft2020_12, source.document.nodes[child].kind == .array {
                for value in source.document.nodes[child].children { visit(value, base: base) }
            } else if maps.contains(name) || lists.contains(name) {
                for value in source.document.nodes[child].children { visit(value, base: base) }
            } else if singles.contains(name) { visit(child, base: base) }
            else if dialect == .draft2020_12, ["dependencies", "$recursiveRef", "$recursiveAnchor"].contains(name), notes.count < 8 {
                notes.append("Legacy keyword is not evaluated in this profile: " + name)
            }
            else if !known.contains(name), notes.count < 8 {
                notes.append("Unknown keyword (annotation): " + JSONTreePreview.make(name, budget: 50).text)
            }
        }
    }
    mutating func includeReferencedTarget(_ id: Int) {
        guard bases[id] == nil else { return }
        additionalSchemaRoots.append(id)
        let inherited = source.document.ancestors(of: id).reversed().compactMap { bases[$0] }.first ?? Self.base
        visit(id, base: inherited)
    }
    var referenceKeywords: [String] { dialect == .draft7 ? ["$ref"] : dialect == .draft2019_09 ? ["$ref", "$recursiveRef"] : ["$ref", "$dynamicRef"] }
    private mutating func checkReferences() {
        var index = 0
        while index < schemaNodes.count, policyStatus == nil, SchemaRuntime.check() {
            let id = schemaNodes[index]; index += 1
            for keyword in referenceKeywords {
                guard let field = source.field(keyword, of: id), let text = source.document.nodes[field].scalar else { continue }
                guard let url = URL(string: text, relativeTo: bases[id])?.absoluteURL else {
                    reject(.unresolvedReference, "Reference URI cannot be resolved.", at: field, keyword: keyword); return
                }
                if let target = resolve(url) {
                    let kind = source.document.nodes[target].kind
                    guard kind == .object || kind == .boolean else {
                        reject(.invalidSchema, "Reference target must be an object or boolean schema.", at: field, keyword: keyword); return
                    }
                    if bases[target] == nil {
                        let ancestorBase = source.document.ancestors(of: target).reversed().compactMap { bases[$0] }.first ?? Self.base
                        visit(target, base: ancestorBase)
                    }
                } else {
                    let bundled = Set(["schema", "meta/core", "meta/applicator", "meta/validation", "meta/unevaluated", "meta/meta-data", "meta/format-annotation", "meta/content"].map { "https://json-schema.org/draft/2020-12/" + $0 })
                    if !bundled.contains(url.withoutFragment?.absoluteString ?? "") {
                        reject(.unresolvedReference, "Referenced schema is not available in this document. No network or file loading is performed.", at: field, keyword: keyword); return
                    }
                }
            }
        }
    }

    func resolve(_ url: URL, physicalPointer: Bool = false) -> Int? {
        if let anchor = anchors[url] { return anchor }
        guard let base = url.withoutFragment, let root = resources[base] else { return nil }
        let fragment = URLComponents(url: url, resolvingAgainstBaseURL: true)?.fragment ?? ""
        guard fragment.isEmpty || fragment.hasPrefix("/") else { return nil }
        // Some upstream locations already contain the physical document prefix.
        let prefix = source.pointer(root)
        if physicalPointer, !prefix.isEmpty, (fragment.utf8.elementsEqual(prefix.utf8) || fragment.utf8.starts(with: (prefix + "/").utf8)), let node = source.node(fragment) { return node }
        return source.node(prefix + fragment)
    }
}
