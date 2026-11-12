import Foundation
import Testing
@testable import JSONCore

struct JSONTreeTests {

    @MainActor @Test func pendingSearchCannotUndoExplicitCollapseAndCancelledProjectionIsAtomic() async throws {
        let session = JSONTreeWorkspaceSession()
        session.input = #"{"x":{"v":"admin"},"y":[]}"#
        await session.build().value
        session.query = "admin"
        let pending = session.scheduleSearch()
        await session.collapseAll()?.value
        await pending?.value
        #expect(session.visible == [0] && session.searchExpanded.isEmpty && session.activeHidden)
        await session.nextMatch()?.value
        #expect(session.visible.contains(2))
        let before = session.visible
        let work = session.expandAll()
        session.cancel(); await work?.value
        #expect(session.visible == before)
        session.input = #"{"é":0}"#; await session.build().value
        session.input = #"{"é":0}"# // Swift String equality is true, UTF-16 equality isn't.
        #expect(session.document == nil)
        let old = session.build(); session.input = "[]"; await old.value
        #expect(session.document == nil)
        await session.build().value
        #expect(session.document?.nodes[0].kind == .array)
    }
    @Test func nativeRowChangePlansPreserveStableTreeIdentities() throws {
        for (old, new) in [([0], [0,1,2,3,4]), ([0,1,2,3,4], [0]),
                           ([0,1,4,5], [0,1,2,3,4,5]), ([0,1,2,3,4,5], [0,1,4,5]),
                           ([0,1,4,5], [0,2,3,4]), ([], [0]), ([0], []), ([0,1], [0,1])] {
            let changes = try JSONTreeRowChanges.between(old, new, baseVersion: 7)
            var applied = old
            for index in changes.removed.reversed() { applied.remove(at: index) }
            for index in changes.inserted { applied.insert(new[index], at: index) }
            #expect(applied == new && changes.baseVersion == 7)
        }
        let many = Array(0..<131_072)
        let changes = try JSONTreeRowChanges.between(many, [0], baseVersion: 1)
        #expect(changes.removed.count == 131_071 && changes.inserted.isEmpty)
    }

    @Test func captureIsLosslessAndStrict() throws {
        let source = " \r\n" + #"{"a":-0,"\u0061":1e+03,"huge":123456789012345678901234567890,"s":"\uD83D\uDE00\n","empty":{},"list":[],"bool":true,"null":null}"# + "\r\n"
        let parsed = JSONProcessor.inspectStructure(source)
        let doc = try #require(parsed.document)
        #expect(doc.nodes.map(\.key).compactMap { $0 } == ["a", "a", "huge", "s", "empty", "list", "bool", "null"])
        #expect(doc.nodes[1].scalar == "-0")
        #expect(doc.nodes[2].scalar == "1e+03")
        #expect(doc.nodes[3].scalar == "123456789012345678901234567890")
        #expect(doc.nodes[4].scalar == "😀\n")
        #expect(doc.fragment(4) == #""\uD83D\uDE00\n""#)
        #expect(doc.nodes[1].occurrences == 2 && doc.nodes[2].occurrence == 2)
        #expect(doc.path(1).ambiguous && doc.path(2).ambiguous)
        #expect(doc.path(0).pointer.isEmpty && doc.path(0).jsonPath == "$")
        for operation in [JSONProcessor.Operation.validate, .format, .minify] {
            #expect(JSONProcessor.process(source, operation: operation).diagnostics == parsed.result.diagnostics)
        }
        for (source, kind) in [("{}", JSONStructureNode.Kind.object), ("[]", .array), ("null", .null), ("false", .boolean), ("-0", .number), (#""é😀""#, .string)] {
            let value = try #require(JSONProcessor.inspectStructure(source).document)
            #expect(value.nodes.count == 1 && value.nodes[0].kind == kind)
            #expect(value.fragment(0) == source)
        }
    }
    @Test func scalarIdentityAndAllDuplicateOccurrences() throws {
        let source = #"{"é":0,"e\u0301":1,"\u00e9":2,"a":3,"\u0061":4}"#
        let parsed = JSONProcessor.inspectStructure(source)
        let doc = try #require(parsed.document)
        #expect(parsed.result.diagnostics.count == 2)
        #expect(JSONProcessor.process(source, operation: .validate).diagnostics == parsed.result.diagnostics)
        #expect(doc.nodes[1].occurrences == 2)
        #expect(doc.nodes[2].occurrences == 1)
        let repeated = "{" + Array(repeating: #""x":{"v":0}"#, count: 40).joined(separator: ",") + "}"
        let many = try #require(JSONProcessor.inspectStructure(repeated).document)
        #expect(many.nodes[79].occurrences == 40)
        #expect(many.path(80).ambiguous)
    }
    @Test func pathsAndSourceRanges() throws {
        let source = #"{"a/b~c":[{"'\\\n\u0001":-0}],"0":true,"":false,"😀é":"x"}"#
        let doc = try #require(JSONProcessor.inspectStructure(source).document)
        #expect(doc.path(3).pointer == "/a~1b~0c/0/'\\\n\u{1}")
        #expect(doc.path(3).jsonPath == "$['a/b~c'][0]['\\'\\\\\\n\\u0001']")
        #expect(doc.path(4).jsonPath == "$['0']")
        #expect(doc.path(5).pointer == "/")
        #expect(doc.fragment(6) == #""x""#)
        #expect((source as NSString).substring(with: try #require(doc.nodes[6].keyRange)) == #""😀é""#)
        #expect(doc.nodes[3].parent == 2 && doc.nodes[2].arrayIndex == 0)
    }
    @Test(arguments: ["", "[1,]", "[1 2]", #"{"a":1 "b":2}"#, #"{"x":"\x"}"#, #""\uD800""#, "1e+", "{}x", "[}", "[", #""a"#])
    func invalidParity(_ source: String) {
        let old = JSONProcessor.process(source, operation: .validate)
        let new = JSONProcessor.inspectStructure(source)
        #expect(new.document == nil)
        #expect(old.status == new.result.status && old.diagnostics == new.result.diagnostics)
    }
    @Test func limitsAndCancellation() async throws {
        let boundary = "\"" + String(repeating: "x", count: JSONProcessor.maximumUTF16Length - 2) + "\""
        #expect(JSONProcessor.inspectStructure(boundary).document?.nodes[0].range.length == JSONProcessor.maximumUTF16Length)
        #expect(JSONProcessor.inspectStructure(String(repeating: " ", count: 262_145)).result.status == .resourceLimit(.inputSize))
        let valid = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        let response = await Task.detached { JSONProcessor.inspectStructure(valid) }.value
        #expect(response.document?.nodes.count == 65)
        #expect(JSONProcessor.inspectStructure("[" + valid + "]").result.status == .resourceLimit(.nestingDepth))
        let task = Task.detached { () -> JSONStructureResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return JSONProcessor.inspectStructure("{}")
        }
        #expect(await task.value.result.status == .cancelled)
    }
    @Test func globalSearchAndUnicodePreviews() throws {
        let doc = try #require(JSONProcessor.inspectStructure(#"{"admin":{"roles":["Admin admin","\u0061dmin"]},"x":1e+03,"bool":true,"nil":null}"#).document)
        let hits = try JSONTreeOperations.search("admin", in: doc)
        #expect(hits.count == 4)
        #expect(hits[0].field == .key)
        #expect(hits[1].range == NSRange(location: 0, length: 5))
        #expect(hits[2].range == NSRange(location: 6, length: 5))
        #expect(try JSONTreeOperations.search("1e+03", in: doc).count == 1)
        #expect(try JSONTreeOperations.search("root", in: doc).isEmpty)
        let unicode = try #require(JSONProcessor.inspectStructure(#"{"emoji":"\uD83D\uDE00 e\u0301"}"#).document)
        #expect(try JSONTreeOperations.search("😀", in: unicode).first?.range == NSRange(location: 0, length: 2))
        #expect(try JSONTreeOperations.search("é", in: unicode).first?.range == NSRange(location: 3, length: 2))
        let projection = try JSONTreeOperations.projection(doc, expanded: Set(doc.ancestors(of: hits[3].nodeID)))
        #expect(projection.contains(hits[3].nodeID))
        let value = String(repeating: "x", count: 8000) + "😀éadmin\n\u{202E}"
        let range = (value as NSString).range(of: "admin")
        let preview = JSONTreePreview.make(value, around: range)
        #expect(preview.text.hasPrefix("…") && preview.text.contains("admin\\n\\u{202E}"))
        #expect(!preview.displayRanges(for: range).isEmpty)
        #expect(preview.text.utf16.count < 1024)
        let huge = "e" + String(repeating: "\u{301}", count: 2000)
        #expect(JSONTreePreview.make(huge).text == "⟨large grapheme⟩")
    }
    @MainActor @Test func sessionFoldingSearchAndRevisions() async throws {
        let suite = "tree-tests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = JSONTreeWorkspaceSession(repository: .init(defaults: defaults))
        session.input = #"{"user":{"roles":["admin"]},"other":{"v":1}}"#
        await session.build().value
        #expect(session.manualExpanded == [0])
        await session.collapseAll()?.value
        #expect(session.visible == [0])
        session.query = "admin"
        await session.scheduleSearch()?.value
        #expect(session.searchExpanded == [0, 1, 2])
        #expect(!session.expanded(4))
        await session.toggle(1)?.value
        #expect(session.activeHidden)
        #expect(session.searchExpanded == [0])
        await session.nextMatch()?.value
        #expect(!session.activeHidden)
        await session.expandAll()?.value
        #expect(session.visible.count == 6)
        session.query = ""
        await session.collapseAll()?.value
        #expect(session.manualExpanded.isEmpty && session.searchExpanded.isEmpty)
        await session.toggle(0)?.value
        await session.toggle(1)?.value
        await session.toggle(0)?.value
        await session.toggle(0)?.value
        #expect(session.expanded(1))
        #expect(session.rowChanges?.baseVersion == session.rowsVersion - 1)
        let revision = session.document?.snapshotID
        await session.build().value
        #expect(session.document?.snapshotID == revision)
        session.query = "admin"; let stale = session.scheduleSearch()
        session.input = "null"; await session.build().value; await stale?.value
        #expect(session.document?.nodes.count == 1 && session.matches.isEmpty)
        session.input = "["; await session.didPaste()?.value
        #expect(session.document == nil && session.result?.status == .invalid)
        session.preferences.validateOnPaste = false
        session.input = "{}"; #expect(session.didPaste() == nil)
        #expect(JSONTreeWorkspaceSession(repository: .init(defaults: defaults)).input.isEmpty)
        #expect(defaults.dictionaryRepresentation().values.allSatisfy { String(describing: $0) != session.input })
    }
}
