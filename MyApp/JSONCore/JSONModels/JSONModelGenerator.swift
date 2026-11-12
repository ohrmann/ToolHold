import Foundation

struct JSONModelAnalysis: Sendable {
    let parseResult: JSONResult
    let graph: JSONModelGraph?
    let failure: JSONModelFailure?
}

enum JSONModelGenerator {
    static let maximumOutputLength = JSONProcessor.maximumUTF16Length
    static func analyze(_ source: String) -> JSONModelAnalysis {
        let capture = JSONProcessor.inspectStructure(source)
        guard let document = capture.document else { return .init(parseResult: capture.result, graph: nil, failure: nil) }
        do { return .init(parseResult: capture.result, graph: try JSONModelInference.infer(document), failure: nil) }
        catch is CancellationError { return .init(parseResult: .init(output: nil, diagnostics: [], status: .cancelled), graph: nil, failure: nil) }
        catch let error as JSONModelFailure { return .init(parseResult: capture.result, graph: nil, failure: error) }
        catch { return .init(parseResult: capture.result, graph: nil, failure: .init(status: .unsupported, code: "MODEL-INFERENCE", message: "Model inference could not be completed.")) }
    }
    static func process(_ source: String, options: JSONModelOptions = .init()) -> JSONModelResult {
        generate(analyze(source), options: options)
    }
    static func generate(_ analysis: JSONModelAnalysis, options: JSONModelOptions, produceArtifact: Bool = true) -> JSONModelResult {
        func failure(_ error: JSONModelFailure) -> JSONModelResult {
            .init(status: error.status, parseResult: analysis.parseResult,
                  issues: [.init(id: 0, code: error.code, severity: .error, message: error.message, range: error.range, related: error.related)], issueCount: 1, artifact: nil)
        }
        do {
            try Task.checkCancellation()
            switch analysis.parseResult.status {
            case .invalid: return .init(status: .invalidJSON, parseResult: analysis.parseResult, issues: [], issueCount: 0, artifact: nil)
            case .resourceLimit: return .init(status: .resourceLimit, parseResult: analysis.parseResult, issues: [], issueCount: 0, artifact: nil)
            case .cancelled: throw CancellationError()
            case .valid: break
            }
            if let error = analysis.failure { return failure(error) }
            guard JSONModelNaming.validRoot(options.rootName) else {
                return failure(.init(status: .invalidOptions, code: "MODEL-ROOT-NAME", message: "Use 1–64 ASCII letters or digits, starting with an uppercase letter. Choose a name other than a language keyword or reserved runtime type."))
            }
            guard let graph = analysis.graph else { return failure(.init(status: .unsupported, code: "MODEL-NO-GRAPH", message: "No current model structure is available.")) }
            let emitter = try JSONModelEmitter(graph: graph, options: options)
            let artifact = produceArtifact ? try emitter.render() : nil
            try Task.checkCancellation()
            return .init(status: .success, parseResult: analysis.parseResult, issues: emitter.issues, issueCount: emitter.issueCount, artifact: artifact)
        } catch is CancellationError {
            return .init(status: .cancelled, parseResult: analysis.parseResult, issues: [], issueCount: 0, artifact: nil)
        } catch let error as JSONModelFailure { return failure(error) }
        catch { return failure(.init(status: .unsupported, code: "MODEL-GENERATION", message: "Code generation could not be completed.")) }
    }
}

/// Per-request renderer. All mutation is isolated in a detached worker, never a SwiftUI body.
final class JSONModelEmitter {
    let graph: JSONModelGraph
    let options: JSONModelOptions
    var language: JSONModelLanguage { options.language }
    var names: [String] = []
    var fields: [[String]] = []
    var numericTypes: [Int: String] = [:]
    var reachable: Set<Int> = []
    var orderedReachable: [Int] = []
    var needsDynamic = false
    var issues: [JSONModelIssue] = []
    var issueCount = 0
    var output = ""
    var outputLength = 0
    init(graph: JSONModelGraph, options: JSONModelOptions) throws {
        self.graph = graph; self.options = options
        // JVM code limits apply to declarations, not objects carried by a dynamic value.
        var namedObjects: Set<Int> = [], visitedShapes: Set<Int> = [], pendingShapes = [0]
        while let id = pendingShapes.popLast() {
            try Task.checkCancellation()
            guard visitedShapes.insert(id).inserted else { continue }
            let shape = graph.shapes[id]
            if shape.alternativeCount > 1 && options.language != .typeScript { continue }
            if let object = shape.object {
                namedObjects.insert(object)
                pendingShapes.append(contentsOf: graph.objects[object].fields.map(\.shape))
            }
            if let element = shape.element { pendingShapes.append(element) }
        }
        var scope = JSONModelNaming.Scope()
        scope.used.insert(options.rootName); scope.used.insert(options.rootName + "Json")
        for (objectID, object) in graph.objects.enumerated() {
            try Task.checkCancellation()
            let shape = graph.shapes[object.shape]
            let rootObject = object.shape == 0
            var stem = options.rootName + shape.path.map { JSONModelNaming.stem($0, upper: true) }.joined()
            if language == .java, shape.path == ["Item"] { stem = "Item" }
            let name = rootObject ? options.rootName : scope.allocate(stem)
            names.append(name)
            var fieldScope = JSONModelNaming.Scope()
            fieldScope.used.insert(name); fieldScope.used.formUnion(["fromJson", "Decode", "readAdditionalProperty", "additionalProperties", "emptyMemberValue", options.rootName + "Json"])
            fields.append(object.fields.map { fieldScope.allocate(JSONModelNaming.stem($0.key, upper: language == .cSharp)) })
            if language == .kotlin, namedObjects.contains(objectID), object.fields.count > 100 {
                throw JSONModelFailure(status: .unsupported, code: "MODEL-KOTLIN-CLASS-LIMIT", message: "This Kotlin data-class profile supports up to 100 properties per model to stay within JVM constructor limits.", range: graph.document.nodes[shape.sourceNode].range)
            }
            if language == .swift {
                var canonical: [String: JSONModelField] = [:]
                for field in object.fields {
                    if let first = canonical[field.key], Data(first.key.utf8) != Data(field.key.utf8) {
                        throw JSONModelFailure(status: .unsupported, code: "MODEL-SWIFT-KEY-COLLISION", message: "Two distinct JSON member names compare equal as Swift Strings. This Codable profile cannot map them reliably.", range: graph.document.nodes[field.sourceNode].keyRange, related: graph.document.nodes[first.sourceNode].keyRange)
                    }
                    canonical[field.key] = field
                }
            }
            if namedObjects.contains(objectID) && (language == .java || language == .kotlin) {
                for field in object.fields where JSONModelNaming.modifiedUTF8Length(field.key) > 65_535 {
                    throw JSONModelFailure(status: .unsupported, code: "MODEL-JVM-KEY-LIMIT", message: "A member name exceeds the JVM annotation string constant limit.", range: graph.document.nodes[field.sourceNode].keyRange)
                }
            }
        }
        for (id, shape) in graph.shapes.enumerated() {
            try Task.checkCancellation()
            if !shape.numbers.isEmpty {
                let numeric = try JSONModelNumericPolicy.type(nodes: shape.numbers, document: graph.document, language: language)
                numericTypes[id] = numeric.fallback && language == .kotlin ? "ToolboxJSONValue" : numeric.name
                if numeric.fallback {
                    if language == .kotlin { needsDynamic = true }
                    warn("MODEL-NUMERIC-FALLBACK", "A JSON element type is used because some sample numbers do not fit the profile's native numeric types.", node: shape.numbers[0])
                }
            }
            if shape.alternativeCount == 0 { warn("MODEL-UNKNOWN-TYPE", "The sample does not establish a non-null value type at this position. An unknown JSON type is used.", node: shape.sourceNode) }
            if shape.alternativeCount > 1, language != .typeScript { warn("MODEL-DYNAMIC-TYPE", "Incompatible sample value kinds share this position. A general JSON value type is used.", node: shape.sourceNode) }
        }
    }
    func warn(_ code: String, _ message: String, node: Int) {
        issueCount += 1
        if issues.count < 100 { issues.append(.init(id: issueCount, code: code, severity: .warning, message: message, range: graph.document.nodes[node].range)) }
    }
    func line(_ text: String = "", _ depth: Int = 0) throws {
        try Task.checkCancellation()
        let prefix = String(repeating: options.indentation.spaces, count: depth)
        let count = prefix.utf16.count + text.utf16.count + 1
        guard count <= JSONModelGenerator.maximumOutputLength - outputLength else {
            throw JSONModelFailure(status: .resourceLimit, code: "MODEL-OUTPUT-LIMIT", message: "Generated code exceeds the 262,144 UTF-16 output limit. No partial code was published.")
        }
        output += prefix + text + "\n"; outputLength += count
    }
    func literal(_ key: String) -> String { JSONModelNaming.literal(key, language: language) }
    func dynamic() -> String {
        switch language { case .swift, .kotlin: needsDynamic = true; return "ToolboxJSONValue"; case .typeScript: return "unknown"; case .cSharp: return "JsonElement"; case .java: return "JsonNode" }
    }
    func type(_ id: Int, missing: Bool = false) -> String {
        let shape = graph.shapes[id]
        var alternatives: [String] = []
        if shape.alternativeCount > 1 && language != .typeScript { alternatives = [dynamic()] }
        else {
            if shape.boolean { alternatives.append(language == .swift ? "Bool" : language == .typeScript ? "boolean" : language == .cSharp ? "bool" : "Boolean") }
            if !shape.numbers.isEmpty { alternatives.append(numericTypes[id]!) }
            if shape.string { alternatives.append(language == .typeScript ? "string" : language == .cSharp ? "string" : "String") }
            if let object = shape.object {
                if reachable.insert(object).inserted { orderedReachable.append(object) }
                if language == .typeScript && graph.objects[object].fields.isEmpty { alternatives.append("Record<string, unknown>") }
                else { alternatives.append(names[object]) }
            }
            if let element = shape.element {
                let inner = type(element)
                alternatives.append(language == .swift ? "[\(inner)]" : language == .typeScript ? "Array<\(inner)>" : "List<\(inner)>")
            }
        }
        if alternatives.isEmpty { alternatives = [dynamic()] }
        var value = alternatives.joined(separator: " | ")
        if language == .typeScript {
            if shape.nullable && value != "unknown" { value += " | null" }
        } else if (shape.nullable || missing) && language != .java { value += "?" }
        return value
    }
    func render() throws -> JSONModelArtifact {
        try line("// Inferred from a sample. Review types before use.")
        try line("// " + language.profile)
        if language == .typeScript || language == .kotlin { try line("// Native floating-point types use binary arithmetic.") }
        try line()
        let rootType = type(0)
        switch language {
        case .swift: try renderSwift(root: rootType)
        case .typeScript: try renderTypeScript(root: rootType)
        case .cSharp: try renderCSharp(root: rootType)
        case .java: try renderJava(root: rootType)
        case .kotlin: try renderKotlin(root: rootType)
        }
        return JSONModelArtifact(fileName: options.rootName + "." + language.fileExtension, text: output, rootType: rootType, usage: usage(root: rootType))
    }
    /// Fields can make additional object models reachable. No dead declarations under dynamic values.
    func renderObjects(_ body: (Int, JSONModelObject) throws -> Void) throws {
        var cursor = 0
        while cursor < orderedReachable.count {
            try Task.checkCancellation()
            let id = orderedReachable[cursor]; cursor += 1
            try body(id, graph.objects[id])
        }
    }
    func usage(root: String) -> String {
        switch language {
        case .swift: return "Foundation Codable; default key decoding strategy.\n\nlet model = try JSONDecoder().decode(\(options.rootName).self, from: data)\n\n" + language.note
        case .typeScript: return "TypeScript 5, strict mode. No runtime library required.\n\nimport type { \(options.rootName) } from './\(options.rootName)';\nconst model = JSON.parse(text) as \(options.rootName);\n\nThe assertion does not validate JSON against the types. " + language.note
        case .cSharp: return "C# 12 / .NET 8+ API profile. No external serializer package.\n\nvar model = \(options.rootName)Json.Decode(text);\n// Return type: \(root)\n\n" + language.note
        case .java: return "Java 17. Jackson 2: com.fasterxml.jackson.core:jackson-databind, compatible core and annotations (tested with 2.22.2 / annotations 2.22). Do not mix Jackson 3 imports.\n\nvar model = \(options.rootName).fromJson(text);\n\n" + language.note
        case .kotlin: return "Kotlin 2 + matching org.jetbrains.kotlin.plugin.serialization compiler plugin; org.jetbrains.kotlinx:kotlinx-serialization-json (tested: compiler/plugin 2.2.20, runtime 1.9.0).\n\nimport kotlinx.serialization.json.Json\nval json = Json { ignoreUnknownKeys = true; explicitNulls = true }\nval model = json.decodeFromString<\(options.rootName)>(text)\n\n" + language.note
        }
    }
}
