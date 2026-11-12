import Foundation

struct JSONSchemaLocation: Sendable { let resourceID: UUID?; let node: Int }
/// A closed, memory-only resource set. URI lookup never performs IO.
struct JSONSchemaResourceSet: Sendable {
    var primary: JSONSchemaRegistry
    var locals: [(JSONSchemaResource, JSONSchemaRegistry)] = []
    var policyStatus: JSONSchemaStatus?
    var policyIssue: JSONSchemaIssue?
    var source: JSONSchemaSourceMap { primary.source }
    var dialect: Dialect { primary.dialect }
    var notes: [String] { Array((primary.notes + locals.flatMap { $0.1.notes }).prefix(12)) }
    init(_ document: JSONStructureDocument, resources: [JSONSchemaResource], options: JSONSchemaOptions) {
        primary = JSONSchemaRegistry(document, options: options, check: false)
        policyStatus = primary.policyStatus; policyIssue = primary.policyIssue
        // Shared budget prevents a set of individually small resources from bypassing limits.
        // Eight maximum-size inputs is a bounded session allocation, not a larger per-file limit.
        guard resources.reduce(document.source.utf16.count, { $0 + $1.document.source.utf16.count }) <= 8 * 262_144 else {
            policyStatus = .resourceLimit; return
        }
        for original in resources {
            let resource = original.located(beside: primary.bases[0] ?? JSONSchemaRegistry.base)
            guard SchemaRuntime.check() else { policyStatus = .resourceLimit; return }
            let registry = JSONSchemaRegistry(resource.document, base: resource.retrievalURI, options: .init(validateFormats: options.validateFormats, assumedDialect: dialect), check: false)
            locals.append((resource, registry))
            if registry.dialect != dialect { reject(.unsupportedDialect, "Mixed-dialect resource sets are not supported. Use the same draft for every schema.", location: .init(resourceID: resource.id, node: 0)); return }
            if let duplicate = resource.document.nodes.first(where: { $0.occurrences > 1 }) {
                reject(.ambiguousInput, "Duplicate member names make schema validation ambiguous.", location: .init(resourceID: resource.id, node: duplicate.id)); return
            }
            if let status = registry.policyStatus {
                policyStatus = status; policyIssue = registry.policyIssue
                policyIssue?.schemaDocumentID = resource.id; return
            }
        }
        guard policyStatus == nil else { return }
        var identifiers: [URL: JSONSchemaLocation] = [:]
        for (id, registry) in entries {
            for uri in registry.resources.keys {
                if Self.bundledURIs(dialect).contains(uri.absoluteString) { reject(.invalidSchema, "Schema identifier conflicts with a bundled meta-schema.", location: .init(resourceID: id, node: 0)); return }
                if identifiers[uri] != nil { reject(.invalidSchema, "Conflicting schema resource identifiers.", location: .init(resourceID: id, node: 0)); return }
                identifiers[uri] = .init(resourceID: id, node: registry.resources[uri]!)
            }
        }
        // Worklist includes schemas reached by pointers into extension-data positions.
        var pending = entries.flatMap { id, registry in registry.schemaNodes.map { JSONSchemaLocation(resourceID: id, node: $0) } }
        var cursor = 0
        while cursor < pending.count, policyStatus == nil, SchemaRuntime.check() {
            let current = pending[cursor]; cursor += 1
            let registry = current.resourceID.flatMap { key in locals.first { $0.0.id == key }?.1 } ?? primary
            for keyword in registry.referenceKeywords {
                guard let field = registry.source.field(keyword, of: current.node), let ref = registry.source.document.nodes[field].scalar else { continue }
                guard let url = URL(string: ref, relativeTo: registry.bases[current.node])?.absoluteURL else {
                    reject(.unresolvedReference, "Reference URI cannot be resolved.", location: .init(resourceID: current.resourceID, node: field)); return
                }
                if let location = resolve(url) {
                    let kind = map(location.resourceID)!.document.nodes[location.node].kind
                    if kind != .object && kind != .boolean { reject(.invalidSchema, "Reference target must be an object or boolean schema.", location: .init(resourceID: current.resourceID, node: field)); return }
                    var target = location.resourceID.flatMap { key in locals.first { $0.0.id == key }?.1 } ?? primary
                    let previousCount = target.schemaNodes.count
                    target.includeReferencedTarget(location.node)
                    if let id = location.resourceID, let index = locals.firstIndex(where: { $0.0.id == id }) { locals[index].1 = target }
                    else { primary = target }
                    if let status = target.policyStatus {
                        policyStatus = status; policyIssue = target.policyIssue
                        policyIssue?.schemaDocumentID = location.resourceID; return
                    }
                    pending += target.schemaNodes.dropFirst(previousCount).map { JSONSchemaLocation(resourceID: location.resourceID, node: $0) }
                } else if !Self.bundledURIs(dialect).contains(url.withoutFragment?.absoluteString ?? "") {
                    reject(.unresolvedReference, "Referenced schema is not loaded. Add it explicitly in Referenced Schemas. No network or file lookup is performed.", location: .init(resourceID: current.resourceID, node: field)); return
                }
            }
        }
        identifiers.removeAll(keepingCapacity: true)
        for (id, registry) in entries {
            for uri in registry.resources.keys {
                if identifiers[uri] != nil || Self.bundledURIs(dialect).contains(uri.absoluteString) {
                    reject(.invalidSchema, "Conflicting schema resource identifiers.", location: .init(resourceID: id, node: 0)); return
                }
                identifiers[uri] = .init(resourceID: id, node: registry.resources[uri]!)
            }
        }
    }
    static func bundledURIs(_ dialect: Dialect) -> Set<String> {
        if dialect == .draft7 { return [dialect.rawValue] }
        let names = dialect == .draft2019_09 ? ["schema", "meta/core", "meta/applicator", "meta/validation", "meta/meta-data", "meta/format", "meta/content"] : ["schema", "meta/core", "meta/applicator", "meta/validation", "meta/meta-data", "meta/format-annotation", "meta/content", "meta/unevaluated"]
        return Set(names.map { "https://json-schema.org/draft/" + dialect.family + "/" + $0 })
    }
    var entries: [(UUID?, JSONSchemaRegistry)] { [(nil, primary)] + locals.map { (Optional($0.0.id), $0.1) } }
    func map(_ id: UUID?) -> JSONSchemaSourceMap? { id == nil ? source : locals.first { $0.0.id == id }?.1.source }
    func name(_ id: UUID?) -> String { id.flatMap { id in locals.first { $0.0.id == id }?.0.name } ?? "Schema" }
    func resolve(_ url: URL, physicalPointer: Bool = false) -> JSONSchemaLocation? {
        for (id, registry) in entries {
            if let node = registry.resolve(url, physicalPointer: physicalPointer) { return .init(resourceID: id, node: node) }
        }
        return nil
    }
    private mutating func reject(_ status: JSONSchemaStatus, _ text: String, location: JSONSchemaLocation) {
        policyStatus = status
        policyIssue = .init(id: 0, keyword: "schema", message: text, instancePointer: "", schemaPointer: map(location.resourceID)?.pointer(location.node) ?? "", instanceNode: nil, schemaNode: location.node, depth: 0, schemaDocumentID: location.resourceID)
    }
}
