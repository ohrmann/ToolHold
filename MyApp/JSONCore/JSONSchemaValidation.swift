import Foundation

enum JSONSchemaStatus: String, Sendable {
    case valid = "Matches schema", nonconforming = "Does not match schema", invalidSchema = "Invalid schema"
    case unsupportedDialect = "Unsupported dialect", unsupportedVocabulary = "Unsupported vocabulary"
    case unsupportedFormat = "Unsupported format"
    case unsupportedFeature = "Unsupported pattern", unresolvedReference = "Unresolved reference"
    case ambiguousInput = "Duplicate member names", resourceLimit = "Resource limit reached", cancelled = "Cancelled"
}
struct JSONSchemaIssue: Sendable, Identifiable {
    enum AnchorPrecision: Sendable { case token, containingValue, unavailable }
    let id: Int
    let keyword: String
    let message: String
    let instancePointer: String
    let schemaPointer: String
    let instanceNode: Int?
    let schemaNode: Int?
    var depth: Int
    var instanceKey = false
    var schemaResource: String? = nil
    var severity: JSONDiagnostic.Severity = .error
    var schemaDocumentID: UUID? = nil
    var schemaDocumentName: String = "Schema"
    var instancePrecision: AnchorPrecision {
        guard instanceNode != nil else { return .unavailable }
        if instanceKey { return .token }
        let regions: Set<String> = ["required", "dependentRequired", "dependencies", "format", "minProperties", "maxProperties", "minItems", "maxItems", "uniqueItems", "contains", "minContains", "maxContains", "minLength", "maxLength", "pattern", "allOf", "anyOf", "oneOf", "not", "if", "then", "else"]
        return regions.contains(keyword) ? .containingValue : .token
    }
}
struct JSONSchemaReport: Sendable {
    let status: JSONSchemaStatus
    var issues: [JSONSchemaIssue]
    var notes: [String] = []
    var truncated = false
    var profile = "Draft 2020-12 · Local refs only · format: annotation"
    var isComplete: Bool { status == .valid || status == .nonconforming || status == .invalidSchema }
    var copyText: String {
        func path(_ text: String) -> String { JSONTreePreview.make(text.isEmpty ? "root" : text, budget: 200).text }
        return ([status.rawValue, profile]
            + issues.map { "JSON \(path($0.instancePointer)) | \(path($0.schemaDocumentName)) \(path($0.schemaPointer)) · \($0.keyword): \($0.message)" }
            + notes + (truncated ? ["Report truncated"] : [])).joined(separator: "\n")
    }
}
struct JSONSchemaCompiled: Sendable {
    let snapshotID: UUID
    let engine: Schema
    let registry: JSONSchemaResourceSet
    let options: JSONSchemaOptions
    let resourceSnapshots: [JSONSchemaResourceKey]
    let notes: [String]
}
struct JSONSchemaEvaluation: Sendable {
    let report: JSONSchemaReport
    let compiled: JSONSchemaCompiled?
}

enum JSONSchemaValidation {
    static func evaluate(instance: JSONStructureDocument, schema: JSONStructureDocument,
                         cached: JSONSchemaCompiled? = nil, seconds: Double = 2,
                         options: JSONSchemaOptions = .init(), resources: [JSONSchemaResource] = []) -> JSONSchemaEvaluation {
        if Task.isCancelled { return .init(report: .init(status: .cancelled, issues: []), compiled: nil) }
        let runtime = SchemaRuntime(seconds: seconds)
        // Swift cooperative pool threads can have very small stacks. Schema evaluation
        // needs a bounded native stack for recursive references over a depth-64 document.
        // The session actor calls this off-main and serializes jobs. Cancellation is
        // relayed from the waiting task to the same cooperative runtime token.
        let response = LockIsolated<JSONSchemaEvaluation?>(nil)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            let result = evaluateBounded(instance: instance, schema: schema, cached: cached, runtime: runtime, options: options, resources: resources)
            response.withLock { $0 = result }; finished.signal()
        }
        thread.name = "DeveloperToolbox.Schema"
        thread.stackSize = 8 * 1024 * 1024
        thread.start()
        while finished.wait(timeout: .now() + .milliseconds(20)) == .timedOut {
            if Task.isCancelled { runtime.fail(.cancelled) }
        }
        if Task.isCancelled { return .init(report: .init(status: .cancelled, issues: []), compiled: nil) }
        let result = response.withLock { $0! }
        var report = result.report
        for index in report.issues.indices {
            if let id = report.issues[index].schemaDocumentID, let resource = resources.first(where: { $0.id == id }) { report.issues[index].schemaDocumentName = resource.name }
        }
        let declared = schema.nodes[0].children.first { schema.nodes[$0].key == "$schema" }.flatMap { schema.nodes[$0].scalar }.flatMap { Dialect(uri: $0) }
        report.profile = (declared ?? options.assumedDialect).title + " · Local refs only · format: " + (options.validateFormats ? "validate supported formats" : "annotation")
        if options.validateFormats { report.notes.append("Formats checked: " + ToolboxSchemaFormat.names.sorted().joined(separator: ", ") + ". Other standard formats are explicitly unsupported; unknown custom formats remain annotations. Full format-assertion vocabulary is not enabled.") }
        return .init(report: report, compiled: result.compiled)
    }
    private static func evaluateBounded(instance: JSONStructureDocument, schema: JSONStructureDocument,
                                        cached: JSONSchemaCompiled?, runtime: SchemaRuntime, options: JSONSchemaOptions, resources: [JSONSchemaResource]) -> JSONSchemaEvaluation {
        SchemaRuntime.$current.withValue(runtime) {
            var compiled = cached?.snapshotID == schema.snapshotID && cached?.options == options && cached?.resourceSnapshots == resources.map(JSONSchemaResourceKey.init) ? cached : nil
            let instanceMap = JSONSchemaSourceMap(instance)
            let schemaMap = JSONSchemaSourceMap(schema)
            for (document, isSchema) in [(instance, false), (schema, true)] {
                if let duplicate = document.nodes.first(where: { $0.occurrences > 1 }) {
                    let pointer = document.path(duplicate.id).pointer
                    let issue = JSONSchemaIssue(id: 0, keyword: "duplicate", message: "Duplicate member names make schema validation ambiguous. Values have not been merged.",
                        instancePointer: isSchema ? "" : pointer, schemaPointer: isSchema ? pointer : "",
                        instanceNode: isSchema ? nil : duplicate.id, schemaNode: isSchema ? duplicate.id : nil, depth: 0)
                    return .init(report: .init(status: .ambiguousInput, issues: [issue]), compiled: nil)
                }
            }
            do {
                if compiled == nil {
                    let registry = JSONSchemaResourceSet(schema, resources: resources, options: options)
                    if let status = registry.policyStatus {
                        return .init(report: .init(status: status, issues: registry.policyIssue.map { [$0] } ?? []), compiled: nil)
                    }
                    let raw = try schemaMap.value()
                    let meta = try registry.dialect.loadMetaSchema()
                    for (id, local) in registry.entries {
                        let localRaw = try local.source.value()
                        for rootID in [0] + local.additionalSchemaRoots {
                            let pointer = JSONPointer(from: local.source.pointer(rootID))
                            guard let target = localRaw.value(at: pointer) else { continue }
                            let shape = meta.validate(target, at: pointer)
                            if runtime.failure != nil { return failed(runtime, compiled: nil) }
                            if !shape.isValid {
                                let issues = project(shape.errors ?? [], instance: local.source, registry: registry, meta: true, metaResource: id)
                                if runtime.failure != nil { return failed(runtime, compiled: nil) }
                                return .init(report: .init(status: .invalidSchema, issues: Array(issues.prefix(1000)), truncated: issues.count > 1000), compiled: nil)
                            }
                        }
                    }
                    var remote: [String: JSONValue] = [:]
                    for (resource, _) in registry.locals { remote[resource.retrievalURI.absoluteString] = try JSONSchemaSourceMap(resource.document).value() }
                    let context = SchemaEngineContext(dialect: registry.dialect, remoteSchema: remote,
                        formatValidators: options.validateFormats ? ToolboxSchemaFormat.all : [], fixedStandardDialect: true)
                    // Register every explicit document and its embedded resources before resolving references.
                    for (resource, _) in registry.locals {
                        _ = try Schema(rawSchema: remote[resource.retrievalURI.absoluteString]!, context: context, baseURI: resource.retrievalURI)
                    }
                    let engine = try Schema(rawSchema: raw, context: context, baseURI: JSONSchemaRegistry.base)
                    if runtime.failure != nil { return failed(runtime, compiled: nil) }
                    var notes = registry.notes
                    if registry.source.field("$schema", of: 0) == nil { notes.insert(registry.dialect.title + " assumed because $schema is absent.", at: 0) }
                    compiled = JSONSchemaCompiled(snapshotID: schema.snapshotID, engine: engine, registry: registry, options: options, resourceSnapshots: resources.map(JSONSchemaResourceKey.init), notes: notes)
                }
                let value = try instanceMap.value()
                let result = compiled!.engine.validate(value)
                if runtime.failure != nil { return failed(runtime, compiled: compiled) }
                if !result.isEvaluationComplete {
                    return .init(report: .init(status: .resourceLimit, issues: [], notes: ["Evaluation could not be completed; conformance has not been established."]), compiled: compiled)
                }
                let issues = project(result.errors ?? [], instance: instanceMap, registry: compiled!.registry)
                if runtime.failure != nil { return failed(runtime, compiled: compiled) }
                return .init(report: .init(status: result.isValid ? .valid : .nonconforming, issues: Array(issues.prefix(1000)),
                    notes: compiled!.notes, truncated: issues.count > 1000, profile: compiled!.registry.dialect.title + " · Local refs only · format: " + (options.validateFormats ? "validate supported formats" : "annotation")), compiled: compiled)
            } catch {
                if runtime.failure != nil || Task.isCancelled { return failed(runtime, compiled: compiled) }
                return .init(report: .init(status: .invalidSchema, issues: [.init(id: 0, keyword: "schema",
                    message: "The schema could not be compiled. Check its declared dialect and keyword structure.",
                    instancePointer: "", schemaPointer: "", instanceNode: nil, schemaNode: 0, depth: 0)]), compiled: nil)
            }
        }
    }
    private static func failed(_ runtime: SchemaRuntime, compiled: JSONSchemaCompiled?) -> JSONSchemaEvaluation {
        let status: JSONSchemaStatus = switch runtime.failure {
        case .cancelled: .cancelled
        case .unsupportedPattern: .unsupportedFeature
        case .unresolvedReference: .unresolvedReference
        default: Task.isCancelled ? .cancelled : .resourceLimit
        }
        let text = status == .unsupportedFeature ? "This pattern uses syntax outside the supported ECMAScript-compatible subset. It was not ignored." : "Evaluation did not complete. JSON conformance has not been established."
        return .init(report: .init(status: status, issues: [], notes: [text]), compiled: compiled)
    }
    private static func project(_ errors: [ValidationError], instance: JSONSchemaSourceMap,
                                registry: JSONSchemaResourceSet, meta: Bool = false, metaResource: UUID? = nil) -> [JSONSchemaIssue] {
        var output: [JSONSchemaIssue] = []
        func visit(_ errors: [ValidationError], depth: Int) {
            for error in errors {
                guard output.count < 1001, SchemaRuntime.check() else { return }
                let transparent: Set<String> = ["properties", "items", "prefixItems", "patternProperties", "additionalProperties", "unevaluatedProperties", "unevaluatedItems", "$ref", "$dynamicRef", "dependentSchemas"]
                if transparent.contains(error.keyword), let children = error.errors, !children.isEmpty {
                    visit(children, depth: depth); continue
                }
                let pointer = error.instanceLocation.jsonPointerString
                let instanceID = instance.node(pointer)
                let location = error.absoluteKeywordLocation.flatMap { registry.resolve($0, physicalPointer: true) }
                let schemaID = location?.node ?? (error.absoluteKeywordLocation == nil ? registry.source.node(error.keywordLocation.jsonPointerString) : nil)
                let ruleMap = registry.map(location?.resourceID) ?? registry.source
                var issue = JSONSchemaIssue(id: output.count, keyword: error.keyword,
                    message: JSONTreePreview.make(error.message, budget: 240).text,
                    instancePointer: meta ? "" : pointer,
                    schemaPointer: meta ? pointer : schemaID.map { ruleMap.pointer($0) } ?? error.keywordLocation.jsonPointerString,
                    instanceNode: meta ? nil : instanceID, schemaNode: meta ? instanceID : schemaID, depth: depth)
                issue.schemaResource = meta ? error.absoluteKeywordLocation?.absoluteString : schemaID == nil ? error.absoluteKeywordLocation?.absoluteString : nil
                if !meta, let property = error.relatedProperty, let parent = instanceID,
                   let child = instance.field(property, of: parent) {
                    issue = JSONSchemaIssue(id: output.count, keyword: issue.keyword, message: issue.message,
                        instancePointer: instance.pointer(child), schemaPointer: issue.schemaPointer,
                        instanceNode: child, schemaNode: issue.schemaNode, depth: issue.depth, instanceKey: true)
                }
                if !meta, let parentID = issue.instanceNode, let child = error.errors?.first,
                   let id = instance.node(child.instanceLocation.jsonPointerString), instance.document.nodes[id].parent == parentID,
                   error.keyword == "additionalProperties" {
                    issue = JSONSchemaIssue(id: output.count, keyword: issue.keyword, message: "Property is not allowed by the schema.",
                        instancePointer: instance.pointer(id), schemaPointer: issue.schemaPointer,
                        instanceNode: id, schemaNode: issue.schemaNode, depth: issue.depth, instanceKey: true)
                }
                if !meta, error.keyword == "boolean", let rule = schemaID,
                   ruleMap.document.nodes[rule].key == "additionalProperties" {
                    issue = JSONSchemaIssue(id: issue.id, keyword: "additionalProperties", message: "Property is not allowed by the schema.",
                        instancePointer: issue.instancePointer, schemaPointer: issue.schemaPointer,
                        instanceNode: issue.instanceNode, schemaNode: issue.schemaNode, depth: issue.depth, instanceKey: true)
                }
                issue.schemaDocumentID = meta ? metaResource : location?.resourceID
                issue.schemaDocumentName = registry.name(issue.schemaDocumentID)
                output.append(issue)
                if let children = error.errors { visit(children, depth: depth + 1) }
            }
        }
        visit(errors, depth: 0)
        return output
    }
}
