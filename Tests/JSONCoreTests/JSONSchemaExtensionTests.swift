import Foundation
import Testing
@testable import JSONCore

struct JSONSchemaExtensionTests {
    func document(_ text: String) throws -> JSONStructureDocument { try #require(JSONProcessor.inspectStructure(text).document) }
    @Test func formatsOfficialProfile() throws {
        let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("Schema202012/tests/optional/format")
        var failures: [String] = [], passed = 0
        for name in ToolboxSchemaFormat.names.sorted() {
            let groups = try JSONValue.parse(Data(contentsOf: root.appendingPathComponent(name + ".json"))).array!
            for group in groups {
                for test in group.object!["tests"]!.array! {
                    // format is ignored for other instance types.
                    let actual = test.object!["data"]!.string.map { ToolboxSchemaFormat(formatName: name).validate($0) } ?? true
                    if actual != test.object!["valid"]!.boolean! { failures.append(name + ": " + test.object!["description"]!.string!) }
                    else { passed += 1 }
                }
            }
        }
        print("FORMAT CTS passed=\(passed) failed=\(failures.count)")
        for item in failures { print("FORMAT MISMATCH " + item) }
        #expect(failures.isEmpty)
    }
    @Test(arguments: [Dialect.draft7, .draft2019_09]) func legacyOfficial(_ dialect: Dialect) throws {
        let fixture = dialect == .draft7 ? "Schema7" : "Schema2019-09"
        let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(fixture)
        var remotes: [String: JSONValue] = [:]
        let rr = root.deletingLastPathComponent().appendingPathComponent("Schema202012/remotes").resolvingSymlinksInPath()
        for case let url as URL in FileManager.default.enumerator(at: rr, includingPropertiesForKeys: nil)! where url.pathExtension == "json" {
            remotes["http://localhost:1234/" + (try schemaFixtureRelativePath(url, within: rr))] = try JSONValue.parse(Data(contentsOf: url))
        }
        var failures: [String] = [], passed = 0
        for url in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("tests"), includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
            for group in try JSONValue.parse(Data(contentsOf: url)).array! {
                for test in group.object!["tests"]!.array! {
                    let runtime = SchemaRuntime(seconds: 3)
                    let result = try SchemaRuntime.$current.withValue(runtime) {
                        try Schema(rawSchema: group.object!["schema"]!, context: SchemaEngineContext(dialect: dialect, remoteSchema: remotes)).validate(test.object!["data"]!)
                    }
                    if runtime.failure != nil || result.isValid != test.object!["valid"]!.boolean! {
                        failures.append(url.lastPathComponent + " / " + group.object!["description"]!.string! + " / " + test.object!["description"]!.string! + " [" + (runtime.failure?.rawValue ?? "mismatch") + "]")
                    } else { passed += 1 }
                }
            }
        }
        print("LEGACY CTS \(dialect.title) passed=\(passed) failed=\(failures.count)")
        failures.forEach { print("LEGACY MISMATCH " + $0) }
        #expect(failures.isEmpty)
    }
    @Test func resourceAndProfileContract() throws {
        let data = try document(##"{"age":"x"}"##)
        let root = try document(##"{"$ref":"age.json"}"##)
        let id = UUID()
        let resource = JSONSchemaResource(id: id, name: "age.json", retrievalURI: URL(string: "age.json", relativeTo: JSONSchemaRegistry.base)!.absoluteURL,
            document: try document(##"{"properties":{"age":{"type":"integer"}}}"##))
        let evaluation = JSONSchemaValidation.evaluate(instance: data, schema: root, resources: [resource])
        #expect(evaluation.report.status == .nonconforming)
        let identifiedRoot = try document(##"{"$id":"https://example.test/schemas/main.json","$ref":"age.json"}"##)
        let identified = JSONSchemaValidation.evaluate(instance: data, schema: identifiedRoot, resources: [resource])
        #expect(identified.report.status == .nonconforming)
        #expect(identified.report.issues.contains { $0.schemaDocumentID == id && $0.schemaPointer == "/properties/age/type" })
        let issue = try #require(evaluation.report.issues.first { $0.keyword == "type" })
        #expect(issue.schemaDocumentID == id)
        #expect(issue.schemaPointer == "/properties/age/type")
        #expect(issue.schemaDocumentName == "age.json")
        #expect(JSONSchemaValidation.evaluate(instance: data, schema: root).report.status == .unresolvedReference)
        let format = try document(##"{"format":"email"}"##), value = try document(##""bad""##)
        let first = JSONSchemaValidation.evaluate(instance: value, schema: format)
        #expect(first.report.status == .valid)
        let second = JSONSchemaValidation.evaluate(instance: value, schema: format, cached: first.compiled, options: .init(validateFormats: true))
        #expect(second.report.status == .nonconforming)
        #expect(second.report.issues.contains { $0.keyword == "format" })
        for dialect in [Dialect.draft7, .draft2019_09] {
            let rules = try document("{\"$schema\":\"" + dialect.rawValue + "\",\"items\":[{\"type\":\"integer\"}],\"additionalItems\":false}")
            #expect(JSONSchemaValidation.evaluate(instance: try document("[1]"), schema: rules).report.status == .valid)
            #expect(JSONSchemaValidation.evaluate(instance: try document("[1,2]"), schema: rules).report.status == .nonconforming)
        }
    }
}

extension JSONSchemaExtensionTests {
    @Test func localResourceIdentityAndFailureMatrix() throws {
        func resource(_ name: String, _ text: String) throws -> JSONSchemaResource {
            .init(name: name, retrievalURI: URL(string: name, relativeTo: JSONSchemaRegistry.base)!.absoluteURL, document: try document(text))
        }
        let source = try document(##""x""##)
        let root = try document(##"{"$ref":"a.json"}"##)
        let a = try resource("a.json", ##"{"$ref":"b.json#integer"}"##)
        let b = try resource("b.json", ##"{"$defs":{"rule":{"$anchor":"integer","type":"integer"}}}"##)
        let result = JSONSchemaValidation.evaluate(instance: source, schema: root, resources: [a,b])
        #expect(result.report.status == .nonconforming)
        #expect(result.report.issues.contains { $0.schemaDocumentID == b.id && $0.schemaPointer == "/$defs/rule/type" })
        let broken = try resource("a.json", ##"{"properties":{"a":{"type":42}}}"##)
        let invalid = JSONSchemaValidation.evaluate(instance: source, schema: root, resources: [broken])
        #expect(invalid.report.status == .invalidSchema)
        #expect(invalid.report.issues.contains { $0.schemaDocumentID == broken.id && $0.instanceNode == nil })
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: root, resources: [a]).report.status == .unresolvedReference)
        let duplicate = try resource("dup.json", ##"{"a":1,"\u0061":2}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: try document("true"), resources: [duplicate]).report.status == .ambiguousInput)
        let x = try resource("x.json", ##"{"$id":"urn:same"}"##), y = try resource("y.json", ##"{"$id":"urn:same"}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: try document("true"), resources: [x,y]).report.status == .invalidSchema)
        let old = try resource("a.json", ##"{"$schema":"http://json-schema.org/draft-07/schema#"}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: root, resources: [old]).report.status == .unsupportedDialect)
        let legacy = try document(##"{"$schema":"http://json-schema.org/draft-07/schema#","$ref":"a.json"}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: legacy, resources: [try resource("a.json", ##"{"type":"string"}"##)]).report.status == .valid)
        let anchored = try document(##"{"$schema":"http://json-schema.org/draft-07/schema#","definitions":{"a":{"$id":"#rule","type":"integer"}},"$ref":"#rule"}"##)
        // Draft-07 $ref objects ignore sibling definitions; the pointer target must be separately discoverable.
        let nonRefRoot = try document(##"{"$schema":"http://json-schema.org/draft-07/schema#","definitions":{"a":{"$id":"#rule","type":"integer"}},"allOf":[{"$ref":"#rule"}]}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: nonRefRoot).report.status == .nonconforming)
        _ = anchored
        let hiddenInvalid = try document(##"{"extension":{"type":42},"$ref":"#/extension"}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: hiddenInvalid).report.status == .invalidSchema)
        let hiddenDialect = try document(##"{"extension":{"$schema":"http://json-schema.org/draft-07/schema#"},"$ref":"#/extension"}"##)
        #expect(JSONSchemaValidation.evaluate(instance: source, schema: hiddenDialect).report.status == .unsupportedDialect)
        let unsupported = JSONSchemaValidation.evaluate(instance: source, schema: try document(##"{"format":"idn-email"}"##), options: .init(validateFormats: true))
        #expect(unsupported.report.status == .unsupportedFormat)
        let unknown = JSONSchemaValidation.evaluate(instance: source, schema: try document(##"{"format":"my-custom-format"}"##), options: .init(validateFormats: true))
        #expect(unknown.report.status == .valid && unknown.report.notes.contains { $0.contains("Unknown format") })
        #expect(unsupported.report.profile.contains("validate supported"))
    }
    @Test func legacyProductSemantics() throws {
        let cases: [(Dialect, String, String, JSONSchemaStatus)] = [
            (.draft7, #"{"a":1}"#, #"{"dependencies":{"a":["b"]}}"#, .nonconforming),
            (.draft7, #""x""#, ##"{"definitions":{"rule":{"$id":"https://example.test/other#named","type":"integer"}},"allOf":[{"$ref":"https://example.test/other#named"}]}"##, .nonconforming),
            (.draft7, #""x""#, ##"{"definitions":{"n":{"type":"string"}},"$ref":"#/definitions/n","type":"integer"}"##, .valid),
            (.draft7, #"[1,"x"]"#, #"{"items":[{"type":"integer"},{"type":"string"}],"additionalItems":false}"#, .valid),
            (.draft2019_09, "[1,2]", #"{"items":{"type":"integer"},"unevaluatedItems":false}"#, .valid),
            (.draft2019_09, #"[1,"x"]"#, #"{"items":[{"type":"integer"}],"unevaluatedItems":false}"#, .nonconforming),
            (.draft2019_09, #"{"child":{"a":1}}"#, ##"{"$recursiveAnchor":true,"type":"object","properties":{"child":{"$recursiveRef":"#"}},"additionalProperties":false}"##, .nonconforming)
        ]
        for (dialect, data, rules, expected) in cases {
            let result = JSONSchemaValidation.evaluate(instance: try document(data), schema: try document(rules), options: .init(assumedDialect: dialect))
            #expect(result.report.status == expected, "\(dialect.title) \(rules) -> \(result.report.status)")
            if rules.contains("other#named") { #expect(result.report.issues.contains { $0.keyword == "type" && $0.schemaPointer == "/definitions/rule/type" && $0.schemaNode != nil }) }
        }
    }
    @Test @MainActor func importBatchBudgetAndCancellationAreAtomic() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("schema-budget-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for index in 0..<9 {
            let url = directory.appendingPathComponent("r\(index).json")
            try Data(String(repeating: " ", count: 262_144).utf8).write(to: url); urls.append(url)
        }
        let workspace = JSONSchemaWorkspaceSession()
        await workspace.importResources(urls).value
        #expect(workspace.importMessage != nil && workspace.referenced.isEmpty)
        let task = workspace.importResources(urls)
        workspace.cancelImport(); await task.value
        #expect(workspace.referenced.isEmpty && !workspace.importing)
    }
    @Test @MainActor func importReplaceRemoveOptionsAndPrivacy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("schema-import-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rules.json")
        try Data(##"{"type":"integer"}"##.utf8).write(to: file)
        let suite = "schema.extension.tests.\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = JSONSchemaWorkspaceSession(repository: .init(defaults: defaults))
        workspace.instance.source = ##""x""##
        workspace.schema.source = ##"{"$ref":"rules.json"}"##
        await workspace.importResources([file]).value
        #expect(workspace.referenced.count == 1 && workspace.report == nil)
        let id = try #require(workspace.referenced.first?.id)
        await workspace.validate().value
        #expect(workspace.report?.status == .nonconforming)
        let issue = try #require(workspace.selectedIssue)
        #expect(workspace.sourceRange(issue, schemaSide: true) != nil)
        workspace.revealSchema(for: issue)
        #expect(workspace.activeResource == id)
        #expect(workspace.schema.source == ##"{"$ref":"rules.json"}"##)
        try Data(##"{"type":"string"}"##.utf8).write(to: file)
        await workspace.importResources([file], replacing: id).value
        #expect(workspace.report == nil && workspace.referenced.first?.id == id)
        await workspace.validate().value
        #expect(workspace.report?.status == .valid)
        workspace.validateFormats = true
        #expect(workspace.report == nil)
        workspace.assumedDialect = .draft7
        #expect(workspace.instance.source == ##""x""##)
        workspace.removeResource(id)
        #expect(workspace.referenced.isEmpty && workspace.activeResource == nil)
        await workspace.validate().value
        #expect(workspace.report?.status == .unresolvedReference)
        let fresh = JSONSchemaWorkspaceSession(repository: .init(defaults: defaults))
        #expect(fresh.validateFormats && fresh.assumedDialect == .draft7)
        #expect(fresh.referenced.isEmpty && fresh.instance.source.isEmpty && fresh.schema.source.isEmpty)
        #expect(!String(describing: defaults.dictionaryRepresentation()).contains("rules.json"))
        // Failed import must not replace an already loaded resource.
        await workspace.importResources([directory.appendingPathComponent("missing.json")]).value
        #expect(workspace.importMessage != nil && workspace.referenced.isEmpty)
    }
}
