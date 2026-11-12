import Foundation
import Testing
import Darwin
@testable import JSONCore

struct JSONSchemaPerformanceTests {
    @Test func maximumDocumentsAndReportBudget() throws {
        let fixtures: [(String, String, String, JSONSchemaStatus)] = [
            ("maximum-array", "[" + Array(repeating: "0", count: 131_071).joined(separator: ",") + "]", #"{"items":{"type":"integer"}}"#, .valid),
            ("many-issues", "[" + Array(repeating: "0", count: 24_000).joined(separator: ",") + "]", #"{"items":{"type":"string"}}"#, .nonconforming),
            ("wide-object", "{" + (0..<15_000).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}", #"{"additionalProperties":{"type":"integer"}}"#, .valid),
            ("deep-64", String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64), "true", .valid),
            ("long-string", "\"" + String(repeating: "x", count: 262_142) + "\"", #"{"type":"string","minLength":262142}"#, .valid)
        ]
        for (name, data, schema, expected) in fixtures {
            let start = ContinuousClock.now
            let input = try #require(JSONProcessor.inspectStructure(data).document)
            let rules = try #require(JSONProcessor.inspectStructure(schema).document)
            let parsed = ContinuousClock.now
            let result = JSONSchemaValidation.evaluate(instance: input, schema: rules, seconds: 5)
            print("SCHEMA_BENCH \(name) utf16=\(data.utf16.count) nodes=\(input.nodes.count) parse=\(start.duration(to: parsed)) evaluate=\(parsed.duration(to: .now)) status=\(result.report.status) issues=\(result.report.issues.count)")
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("SCHEMA_PEAK \(name) bytes=\(usage.ru_maxrss)")
            #expect(result.report.status == expected)
            #expect(result.report.issues.count <= 1000)
            if name == "many-issues" { #expect(result.report.truncated) }
        }
    }
    @Test func maximumLocalResourceSet() throws {
        let rule = "{\"description\":\"" + String(repeating: "x", count: 262_120) + "\"}"
        let doc = try #require(JSONProcessor.inspectStructure(rule).document)
        let data = try #require(JSONProcessor.inspectStructure("null").document)
        let root = try #require(JSONProcessor.inspectStructure(#"{"$ref":"r0.json"}"#).document)
        let resources = (0..<7).map { JSONSchemaResource(name: "r\($0).json", retrievalURI: URL(string: "r\($0).json", relativeTo: JSONSchemaRegistry.base)!.absoluteURL, document: doc) }
        let start = ContinuousClock.now
        let result = JSONSchemaValidation.evaluate(instance: data, schema: root, resources: resources)
        print("SCHEMA_RESOURCE_BENCH resources=7 utf16=\(rule.utf16.count * 7) evaluate=\(start.duration(to: .now)) status=\(result.report.status)")
        #expect(result.report.status == .valid)
        let tooMany = resources + resources.enumerated().map { n, r in JSONSchemaResource(name: "extra\(n).json", retrievalURI: URL(string: "https://example.test/extra\(n).json")!, document: r.document) }
        #expect(JSONSchemaValidation.evaluate(instance: data, schema: root, resources: tooMany).report.status == .resourceLimit)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("SCHEMA_RESOURCE_PEAK bytes=\(usage.ru_maxrss)")
    }

}
