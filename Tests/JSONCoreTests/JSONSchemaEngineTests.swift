import Foundation
import Testing
@testable import JSONCore

struct JSONSchemaEngineTests {
    @Test func officialDraft202012() throws {
        let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("Schema202012")
        var remotes: [String: JSONValue] = [:]
        let remoteRoot = root.appendingPathComponent("remotes").resolvingSymlinksInPath()
        for case let url as URL in FileManager.default.enumerator(at: remoteRoot, includingPropertiesForKeys: nil)! where url.pathExtension == "json" {
            let relative = try schemaFixtureRelativePath(url, within: remoteRoot)
            remotes["http://localhost:1234/" + relative] = try JSONValue.parse(Data(contentsOf: url))
        }
        let testRoot = root.appendingPathComponent("tests")
        var passed = 0, failures: [String] = [], limited: [String] = []
        let baseFiles = try FileManager.default.contentsOfDirectory(at: testRoot, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let optional = ["bignum", "float-overflow", "non-bmp-regex", "ecmascript-regex", "anchor", "dynamicRef", "no-schema", "unknownKeyword", "refOfUnknownKeyword", "id"].map { testRoot.appendingPathComponent("optional/" + $0 + ".json") }
        for url in (baseFiles + optional).sorted(by: { $0.path < $1.path }) {
            let groups = try JSONValue.parse(Data(contentsOf: url)).array!
            for group in groups {
                for test in group.object!["tests"]!.array! {
                    let label = url.lastPathComponent + " / " + group.object!["description"]!.string! + " / " + test.object!["description"]!.string!
                    let runtime = SchemaRuntime(seconds: 3)
                    let actual: Bool? = try SchemaRuntime.$current.withValue(runtime) {
                        let schema = try Schema(rawSchema: group.object!["schema"]!, context: SchemaEngineContext(dialect: .draft2020_12, remoteSchema: remotes))
                        return schema.validate(test.object!["data"]!).isValid
                    }
                    if let failure = runtime.failure { limited.append(label + " [" + failure.rawValue + "]") }
                    else if actual == test.object!["valid"]!.boolean! { passed += 1 }
                    else { failures.append(label) }
                }
            }
        }
        print("SCHEMA CTS passed=\(passed), failures=\(failures.count), limited=\(limited.count)")
        for line in failures { print("MISMATCH " + line) }
        for line in limited { print("LIMIT " + line) }
        #expect(failures.isEmpty)
        #expect(limited.isEmpty)
    }
}
