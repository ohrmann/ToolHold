import Foundation
import Testing
@testable import JSONCore

struct JSONSchemaValidationTests {
    private func document(_ text: String) throws -> JSONStructureDocument { try #require(JSONProcessor.inspectStructure(text).document) }
    private func run(_ data: String, _ schema: String) throws -> JSONSchemaEvaluation {
        JSONSchemaValidation.evaluate(instance: try document(data), schema: try document(schema))
    }
    @Test(arguments: [
        ("null", "true", true), ("null", "false", false), ("{}", "{}", true),
        (##""wrong""##, ##"{"$vocabulary":{"https://json-schema.org/draft/2020-12/vocab/core":true},"type":"integer"}"##, false),
        ("1.0", ##"{"type":"integer"}"##, true), ("1e0", ##"{"type":"integer"}"##, true),
        ("-0", ##"{"const":0}"##, true), ("0.3", ##"{"multipleOf":0.1}"##, true),
        ("0.31", ##"{"multipleOf":0.1}"##, false),
        ("9007199254740993", ##"{"maximum":9007199254740992}"##, false),
        ("1e1000", ##"{"minimum":1e999}"##, true),
        (##""e\u0301""##, ##"{"minLength":2,"maxLength":2}"##, true),
        (##""👩‍💻""##, ##"{"minLength":3,"maxLength":3}"##, true),
        (##"{"é":1,"e\u0301":2}"##, ##"{"properties":{"é":{"const":1},"e\u0301":{"const":2}},"required":["é","e\u0301"],"additionalProperties":false}"##, true),
        (##"{"e\u0301":1}"##, ##"{"required":["é"]}"##, false),
        (##"{"e\u0301":1}"##, ##"{"properties":{"é":false}}"##, true),
        (##"{"e\u0301":1}"##, ##"{"properties":{"é":true},"unevaluatedProperties":false}"##, false),
        (##"["é","e\u0301"]"##, ##"{"uniqueItems":true}"##, true),
        (##"[{"é":1},{"e\u0301":1}]"##, ##"{"uniqueItems":true}"##, true),
        (##"[1,1.0]"##, ##"{"uniqueItems":true}"##, false),
        (##""bad-email""##, ##"{"type":"string","format":"email"}"##, true),
        (##"{"a":1}"##, ##"{"allOf":[{"properties":{"a":{"type":"integer"}}}],"unevaluatedProperties":false}"##, true),
        (##"[1,"x"]"##, ##"{"prefixItems":[{"type":"integer"}],"items":{"type":"string"}}"##, true)
    ]) func exactSemantics(_ fixture: (String, String, Bool)) throws {
        let result = try run(fixture.0, fixture.1)
        #expect(result.report.status == (fixture.2 ? .valid : .nonconforming))
    }
    @Test func referencesAndPhysicalRuleLocations() throws {
        let schema = ##"{"$id":"https://example.test/base","$defs":{"rule":{"$anchor":"rule","type":"integer"}},"properties":{"a":{"$ref":"#rule"}}}"##
        let result = try run(##"{"a":"x"}"##, schema)
        #expect(result.report.status == .nonconforming)
        let issue = try #require(result.report.issues.first { $0.keyword == "type" })
        #expect(issue.instancePointer == "/a")
        #expect(issue.schemaPointer == "/$defs/rule/type")
        #expect(issue.schemaNode != nil)
        let embedded = try run(##""x""##, ##"{"$defs":{"a":{"$id":"embedded","type":"integer"}},"$ref":"embedded"}"##)
        #expect(embedded.report.status == .nonconforming)
        #expect(embedded.report.issues.contains { $0.schemaPointer == "/$defs/a/type" })
        let boolean = try run("1", ##"{"$defs":{"a":{"$id":"embedded","properties":{"x":false}}},"$ref":"embedded"}"##)
        #expect(boolean.report.status == .valid)
        let rejected = try run(##"{"x":1}"##, ##"{"$defs":{"a":{"$id":"embedded","properties":{"x":false}}},"$ref":"embedded"}"##)
        #expect(rejected.report.status == .nonconforming)
        #expect(rejected.report.issues.contains { $0.schemaPointer == "/$defs/a/properties/x" && $0.schemaNode != nil })
        let escaped = try run("2", ##"{"$defs":{"a/b~c":{"const":1}},"$ref":"#/$defs/a~1b~0c"}"##)
        #expect(escaped.report.status == .nonconforming)
    }
    @Test func statusesDoNotClaimInvalidJSON() throws {
        for (schema, expected) in [
            (##"{"type":12}"##, JSONSchemaStatus.invalidSchema),
            (##"{"required":true}"##, .invalidSchema),
            (##"{"properties":{"a":42}}"##, .invalidSchema),
            (##"{"$schema":"http://json-schema.org/draft-06/schema#"}"##, .unsupportedDialect),
            (##"{"$vocabulary":{"https://json-schema.org/draft/2020-12/vocab/format-assertion":true}}"##, .unsupportedVocabulary),
            (##"{"$ref":"https://example.test/secret"}"##, .unresolvedReference),
            (##"{"$ref":"file:///etc/passwd"}"##, .unresolvedReference),
            (##"{"$ref":"#/$defs/missing"}"##, .unresolvedReference),
            (##"{"pattern":"(?i)hello"}"##, .unsupportedFeature),
            (##"{"$ref":"#"}"##, .resourceLimit),
            (##"{"type":"string","type":"integer"}"##, .ambiguousInput)
        ] {
            let result = try run(##""x""##, schema)
            #expect(result.report.status == expected, "schema \(schema): \(result.report.status)")
        }
        #expect(try run(##"{"a":1,"\u0061":2}"##, "{}").report.status == .ambiguousInput)
        #expect(try run("1", ##"{"enum":[{"$schema":"not-a-dialect"}]}"##).report.status == .nonconforming)
    }
    @Test func anchorsAreSourceExactIncludingUnicodeCRLFAndMissingProperty() throws {
        let data = "{\r\n\"👩‍💻\": \"bad\",\r\n\"extra\": 1\r\n}"
        let schema = ##"{"properties":{"👩‍💻":{"type":"integer"}},"required":["absent"],"additionalProperties":false}"##
        let doc = try document(data), rules = try document(schema)
        let report = JSONSchemaValidation.evaluate(instance: doc, schema: rules).report
        #expect(report.status == .nonconforming)
        let type = try #require(report.issues.first { $0.keyword == "type" })
        #expect(doc.fragment(try #require(type.instanceNode)) == ##""bad""##)
        #expect(rules.fragment(try #require(type.schemaNode)) == ##""integer""##)
        let extra = try #require(report.issues.first { $0.keyword == "additionalProperties" })
        #expect(extra.instanceKey)
        #expect(doc.nodes[try #require(extra.instanceNode)].key == "extra")
        let required = try #require(report.issues.first { $0.keyword == "required" })
        #expect(required.instancePrecision == .containingValue)
        #expect(required.instanceNode == 0) // The absent field has no invented source position.
        #expect(required.schemaNode != nil)
        #expect(JSONSourceCoordinates(data).location(at: doc.nodes[type.instanceNode!].range.location).line == 2)
    }
    @Test func metaSchemaIssuesPointIntoSchemaInput() throws {
        let result = try run("{}", ##"{"properties":{"a":{"type":5}}}"##)
        #expect(result.report.status == .invalidSchema)
        #expect(result.report.issues.allSatisfy { $0.instanceNode == nil })
        #expect(result.report.issues.contains { $0.schemaPointer == "/properties/a/type" && $0.schemaNode != nil })
    }
    @Test func cancellationResourceBudgetsAndIncompleteBranches() async throws {
        let data = try document("1"), rules = try document(##"{"not":{"$ref":"#"}}"##)
        let deadline = JSONSchemaValidation.evaluate(instance: data, schema: rules, seconds: 0)
        #expect(deadline.report.status == .resourceLimit)
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return JSONSchemaValidation.evaluate(instance: data, schema: rules)
        }
        task.cancel()
        #expect(await task.value.report.status == .cancelled)
        #expect(try run("1", ##"{"anyOf":[true,{"$ref":"#"}]}"##).report.status == .resourceLimit)
    }
    @Test func patternsAreBoundedAndDoNotExecuteCode() throws {
        let started = ContinuousClock.now
        let result = try run("\"" + String(repeating: "a", count: 8_000) + "!\"", ##"{"pattern":"(a+)+$"}"##)
        #expect(result.report.status == .resourceLimit)
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(try run(##""x""##, ##"{"pattern":"a{999999999}"}"##).report.status == .resourceLimit)
    }
    @Test func cacheAndReportsPreserveOriginalLexemes() throws {
        let data = try document(##"{"n":900719925474099312345,"s":"\u0061","z":-0,"e":1e+10}"##)
        let rules = try document("{}")
        let first = JSONSchemaValidation.evaluate(instance: data, schema: rules)
        let second = JSONSchemaValidation.evaluate(instance: data, schema: rules, cached: first.compiled)
        #expect(second.report.status == .valid)
        #expect(second.compiled?.snapshotID == rules.snapshotID)
        #expect(data.fragment(1) == "900719925474099312345")
        #expect(data.fragment(2) == ##""\u0061""##)
        #expect(data.fragment(3) == "-0")
        #expect(data.fragment(4) == "1e+10")
    }
    @Test func recursiveSchemaAtMaximumInputDepthHasBoundedStack() throws {
        let data = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        let schema = ##"{"anyOf":[{"type":"integer"},{"type":"array","items":{"$ref":"#"}}]}"##
        #expect(try run(data, schema).report.status == .valid)
    }
    @Test func contextUsesExactOffsetsAndSafeControlPresentation() throws {
        let source = "{\n        \"👩‍💻\":  \"abc\\u202Edef\"\n}"
        let doc = try document(source)
        let range = doc.nodes[1].range
        let context = JSONDiagnosticContext.make(source: source, range: range)
        #expect(context.segments.contains { $0.sourceRange?.location == range.location })
        #expect(!context.text.contains("        "))
        #expect(context.detectionRange.length > 0)
        #expect(!context.text.unicodeScalars.contains { $0.value == 0x202E })
        let report = try run("1", ##"{"type":"string"}"##).report
        #expect(report.copyText.contains("Schema /type"))
    }
    @Test @MainActor func workspacePasteRevisionCancelAndPrivacy() async throws {
        let domain = "toolbox.schema.tests.\(UUID())", defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let repository = JSONPreferencesRepository(defaults: defaults)
        let workspace = JSONSchemaWorkspaceSession(repository: repository)
        workspace.instance.source = ##"{"age":"bad"}"##
        workspace.schema.source = ##"{"properties":{"age":{"type":"integer"}}}"##
        await workspace.didPaste(schema: false)?.value
        #expect(workspace.instance.document != nil)
        #expect(workspace.report == nil) // Paste validates syntax only.
        await workspace.validate().value
        #expect(workspace.report?.status == .nonconforming)
        let snapshot = workspace.schema.document?.snapshotID
        let oldVersion = workspace.version
        await workspace.validate().value
        #expect(workspace.version == oldVersion)
        workspace.instance.source = ##"{"age":12}"##
        #expect(workspace.report == nil && workspace.rows.isEmpty)
        #expect(workspace.schema.document?.snapshotID == snapshot)
        await workspace.validate().value
        #expect(workspace.report?.status == .valid)
        workspace.instance.source = "[1,]"
        await workspace.validate().value
        #expect(workspace.report == nil)
        #expect(workspace.instance.result?.status == .invalid)
        workspace.instance.source = "1"
        workspace.schema.source = ##"{"$ref":"#"}"##
        let pending = workspace.validate()
        workspace.cancel()
        await pending.value
        #expect(workspace.wasCancelled && !workspace.busy && workspace.report == nil)
        workspace.schema.source = "true"
        let stale = workspace.validate()
        workspace.instance.source = "2"
        await stale.value
        #expect(workspace.report == nil)
        workspace.preferences.wordWrap = false
        let fresh = JSONSchemaWorkspaceSession(repository: repository)
        #expect(fresh.instance.source.isEmpty && fresh.schema.source.isEmpty && fresh.report == nil)
        #expect(!fresh.preferences.wordWrap)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox") } == [JSONPreferencesRepository.key])
    }
}
