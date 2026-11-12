import Foundation
import Testing
@testable import JSONCore

struct JSONModelGenerationTests {
    @Test func mergesEverySampleAndKeepsMissingSeparateFromNull() throws {
        let analysis = JSONModelGenerator.analyze(#"[{"id":1,"name":"A"},{"id":2,"name":null,"active":true}]"#)
        let graph = try #require(analysis.graph)
        let object = try #require(graph.objects.first)
        #expect(object.sampleCount == 2)
        #expect(object.fields.map(\.key) == ["id", "name", "active"])
        #expect(object.fields.map(\.presentCount) == [2, 2, 1])
        #expect(graph.shapes[object.fields[1].shape].nullable)
        #expect(!graph.shapes[object.fields[2].shape].nullable)
        for language in JSONModelLanguage.allCases {
            let result = JSONModelGenerator.generate(analysis, options: .init(language: language))
            #expect(result.status == .success, "\(language): \(result.issues.map(\.message))")
            #expect(result.artifact?.text == JSONModelGenerator.generate(analysis, options: .init(language: language)).artifact?.text)
            #expect(result.artifact?.text.contains("\"A\"") == false)
        }
        #expect(JSONModelGenerator.generate(analysis, options: .init(language: .typeScript)).artifact?.text.contains("\"active\"?: boolean;") == true)
        #expect(JSONModelGenerator.generate(analysis, options: .init(language: .kotlin)).artifact?.text.contains("val active: Boolean? = null") == true)
    }

    @Test func emptyEvidenceDoesNotWidenKnownTypes() throws {
        let graph = try #require(JSONModelGenerator.analyze(#"[{"x":[]},{"x":[1,2]}]"#).graph)
        let shape = graph.shapes[graph.objects[0].fields[0].shape]
        #expect(graph.shapes[try #require(shape.element)].numbers.count == 2)
        let result = JSONModelGenerator.process(#"[{"x":null},{"x":1}]"#)
        #expect(result.artifact?.text.contains("Int64?") == true)
        #expect(!result.issues.contains { $0.code == "MODEL-UNKNOWN-TYPE" })
    }

    @Test func scalarIdentityAndDuplicatesAreNotDictionarySemantics() throws {
        let duplicate = JSONModelGenerator.process(#"{"a":1,"\u0061":2}"#)
        #expect(duplicate.status == .unsupported)
        #expect(duplicate.issues[0].related != nil)
        let source = "{\"é\":1,\"e\\u0301\":2}"
        let analysis = JSONModelGenerator.analyze(source)
        #expect(analysis.graph?.objects[0].fields.count == 2)
        #expect(JSONModelGenerator.generate(analysis, options: .init(language: .swift)).status == .unsupported)
        for language in JSONModelLanguage.allCases where language != .swift {
            #expect(JSONModelGenerator.generate(analysis, options: .init(language: language)).status == .success)
        }
    }

    @Test func numericProfilesDoNotRoundOrCoerce() throws {
        for source in ["9007199254740993", "9223372036854775808", "0.123456789012345678901234567890"] {
            #expect(JSONModelGenerator.process(source, options: .init(language: .typeScript)).status == .unsupported)
        }
        #expect(JSONModelGenerator.process("9223372036854775808").artifact?.rootType == "Decimal")
        #expect(JSONModelGenerator.process("9223372036854775808", options: .init(language: .java)).artifact?.rootType == "BigInteger")
        #expect(JSONModelGenerator.process("9223372036854775808", options: .init(language: .kotlin)).artifact?.rootType == "ToolboxJSONValue")
        #expect(JSONModelGenerator.process("79228162514264337593543950335", options: .init(language: .cSharp)).artifact?.rootType == "decimal")
        #expect(JSONModelGenerator.process("79228162514264337593543950336", options: .init(language: .cSharp)).artifact?.rootType == "JsonElement")
        #expect(JSONModelGenerator.process("[9007199254740993,0.5]", options: .init(language: .kotlin)).artifact?.rootType == "List<ToolboxJSONValue>")
        #expect(JSONModelGenerator.process("1e999999999999").status == .unsupported)
        #expect(JSONModelGenerator.process("1e999999999999", options: .init(language: .java)).status == .unsupported)
        #expect(JSONModelGenerator.process("0.1", options: .init(language: .typeScript)).status == .success)
        #expect(JSONModelNumericPolicy.dotnetDecimal("1e-28"))
        #expect(!JSONModelNumericPolicy.dotnetDecimal("1e-29"))
        #expect(JSONModelNumericPolicy.dotnetDecimal("1.2300"))
    }

    @Test func generationAnchorsRemainSourceUTF16Ranges() throws {
        let source = "{\r\n\"😀é\":9007199254740993}"
        let result = JSONModelGenerator.process(source, options: .init(language: .typeScript))
        let anchor = try #require(result.issues.first?.range)
        #expect((source as NSString).substring(with: anchor) == "9007199254740993")
        #expect(anchor == (source as NSString).range(of: "9007199254740993"))
        let duplicate = #"{"😀":1,"\uD83D\uDE00":2}"#
        let issue = try #require(JSONModelGenerator.process(duplicate).issues.first)
        #expect((duplicate as NSString).substring(with: try #require(issue.range)) == #""\uD83D\uDE00""#)
        #expect((duplicate as NSString).substring(with: try #require(issue.related)) == "\"😀\"")
    }

    @Test func namingRootsEmptyMixedAndStructuralIsolation() throws {
        for source in ["{}", "[]", "null", "true", "42", #""hello""#, "[[1],[2,null],[]]", #"[1,"x",true,null,{"a":1},[2]]"#] {
            for language in JSONModelLanguage.allCases {
                let result = JSONModelGenerator.process(source, options: .init(language: language))
                #expect(result.status == .success, "\(source) / \(language): \(result.issues.map(\.message))")
            }
        }
        let graph = try #require(JSONModelGenerator.analyze(#"{"billing":{"id":1},"shipping":{"id":"s"}}"#).graph)
        #expect(graph.objects.count == 3)
        let input = #"{"user-id":1,"user_id":2,"userId2":3,"class":true,"":0,"1st":"x"}"#
        let result = try #require(JSONModelGenerator.process(input).artifact)
        #expect(result.text.contains("let userId: Int64"))
        #expect(result.text.contains("let userId2: Int64"))
        #expect(result.text.contains("let userId22: Int64"))
        #expect(result.text.contains("classValue"))
        #expect(JSONModelGenerator.process("{}", options: .init(rootName: "../bad")).status == .invalidOptions)
    }

    @Test func resourceCancellationAndSourceRanges() async throws {
        let input = "{\r\n\"😀\": [1,]}"
        let result = JSONModelGenerator.process(input)
        #expect(result.status == .invalidJSON)
        #expect(result.parseResult.diagnostics.first?.line == 2)
        #expect(JSONModelGenerator.process(String(repeating: " ", count: JSONProcessor.maximumUTF16Length + 1)).status == .resourceLimit)
        let wide = "{" + (0..<101).map { "\"p\($0)\":1" }.joined(separator: ",") + "}"
        #expect(JSONModelGenerator.process(wide, options: .init(language: .kotlin)).status == .unsupported)
        #expect(JSONModelGenerator.process("[" + wide + ",0]", options: .init(language: .kotlin)).status == .success)
        let dynamicKey = "[{\"" + String(repeating: "x", count: 65_536) + "\":0},0]"
        for language in [JSONModelLanguage.java, .kotlin] {
            #expect(JSONModelGenerator.process(dynamicKey, options: .init(language: language)).status == .success)
        }
        let maximum = "{" + (0..<100).map { "\"p\($0)\":1" }.joined(separator: ",") + "}"
        #expect(JSONModelGenerator.process(maximum, options: .init(language: .kotlin)).status == .success)
        let task = Task { () -> JSONModelResult in
            try? await Task.sleep(for: .milliseconds(30))
            return JSONModelGenerator.process("{}")
        }
        task.cancel()
        #expect(await task.value.status == .cancelled)
    }

    /// Explicit dev command exports only synthetic fixtures, never application input.
    @Test func exportProductionArtifactsForCompilerVerification() throws {
        guard let directory = ProcessInfo.processInfo.environment["MODELS_FIXTURE_DIRECTORY"] else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let fixtures: [(String, String)] = [
            ("Basic", #"{"id":1,"name":"A","active":true,"nested":{"value":1.25}}"#),
            ("Optional", #"[{"id":1,"name":"A"},{"id":2,"name":null,"active":true}]"#),
            ("Mixed", #"[1,"x",true,null,{"a":1},[2]]"#),
            ("EmptyObject", "{}"), ("EmptyArray", "[]"), ("Null", "null"), ("Primitive", "42"), ("Boolean", "true"),
            ("Text", #""Hello 😀 é""#), ("NestedArray", "[[1],[2,null],[]]"),
            ("Numbers", #"{"value":9007199254740993,"other":9223372036854775808,"fraction":12345678901234567890.125}"#),
            ("PreciseRoot", "12345678901234567890.125"),
            ("Escapes", #"{"a\"b":1,"a\\u000a":2,"new\nline":3,"carriage\rreturn":4,"nul\u0000":5,"$test":6,"\\(x)":7,"😀":8,"e\u0301":9,"bidi\u202E":10}"#),
            ("Collisions", #"{"user-id":1,"user_id":2,"userId2":3,"class":true,"":0,"1st":"x","copy":7,"fromJson":8}"#),
            ("Unknown", #"{"value":null,"items":[],"empty":{}}"#),
            ("EmptyKeyNested", #"{"":{"values":[1,2]},"nested":{"":12345678901234567890.125}}"#),
            ("EmptyKeyConflict", #"{"":1,"field":2,"additionalProperties":3,"readAdditionalProperty":4,"toolboxAdditionalProperties":5,"toolboxReadAdditionalProperty":6}"#),
            ("Canonical", "{\"é\":1,\"e\\u0301\":2}"),
            ("Wide", "{" + (0..<100).map { "\"p\($0)\":1" }.joined(separator: ",") + "}")
        ]
        var manifest: [[String: String]] = []
        for (name, source) in fixtures {
            for language in JSONModelLanguage.allCases {
                let options = JSONModelOptions(language: language, rootName: "Fixture" + name)
                let result = JSONModelGenerator.process(source, options: options)
                if (name == "Numbers" || name == "PreciseRoot" || name == "EmptyKeyNested") && language == .typeScript { #expect(result.status == .unsupported); continue }
                if name == "Canonical" && language == .swift { #expect(result.status == .unsupported); continue }
                let artifact = try #require(result.artifact, "\(name) \(language): \(result.issues.map(\.message))")
                let folder = root.appendingPathComponent(language.rawValue).appendingPathComponent(name)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try artifact.text.write(to: folder.appendingPathComponent(artifact.fileName), atomically: true, encoding: .utf8)
                try source.write(to: folder.appendingPathComponent("sample.json"), atomically: true, encoding: .utf8)
                manifest.append(["language":language.rawValue,"fixture":name,"file":artifact.fileName,"root":options.rootName,"rootType":artifact.rootType])
            }
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("manifest.json"))
    }
}
