import Foundation
import Testing
@testable import JSONCore

struct JSONDiffTests {
    private func diff(_ a: String, _ b: String) throws -> JSONDiffResult {
        try JSONStructuralDiff.compare(#require(JSONProcessor.inspectStructure(a).document), #require(JSONProcessor.inspectStructure(b).document))
    }
    @Test func formattingObjectOrderAndEscapesAreIgnored() throws {
        let result = try diff(#"{"b":1,"a":"\u0061","x":{}}"#, "{\n \"x\":{},\"a\":\"a\",\"b\":1 }")
        #expect(result.changes.isEmpty)
    }
    @Test(arguments: [("1", "1.0"), ("1.0", "1e0"), ("0", "-0"), ("1e2", "1E+2"),
                      ("999999999999999999999999999999", "999999999999999999999999999998")])
    func exactNumbers(_ pair: (String, String)) throws {
        let result = try diff(pair.0, pair.1), change = try #require(result.changes.first)
        #expect(result.changes.count == 1 && change.kind == .changed)
        #expect(result.value(change, side: .before) == pair.0 && result.value(change, side: .after) == pair.1)
        #expect(result.path(for: change).pointer.isEmpty)
    }
    @Test func missingNullEmptyTypeAndSubtreeCounts() throws {
        let result = try diff(#"{"gone":{"x":[1,2]},"n":null,"empty":{},"type":1}"#,
                              #"{"n":{},"empty":[],"type":"1","added":{"x":[3,4]}}"#)
        #expect(result.changes.map(\.kind) == [.removed, .typeChanged, .typeChanged, .typeChanged, .added])
        #expect(result.removed == 1 && result.added == 1 && result.changed == 3)
        #expect(result.changes.map { result.path(for: $0).pointer } == ["/gone", "/n", "/empty", "/type", "/added"])
        #expect(result.fragment(result.changes[0], side: .before) == #"{"x":[1,2]}"#)
        #expect(result.value(result.changes[0], side: .before) == nil)
    }
    @Test func arraysUseIndexNotAlignment() throws {
        let result = try diff("[1,2]", "[0,1,2]")
        #expect(result.changes.map(\.kind) == [.changed, .changed, .added])
        #expect(result.changes.map { result.path(for: $0).pointer } == ["/0", "/1", "/2"])
        let reverse = try diff("[0,1,2]", "[1,2]")
        #expect(reverse.changes.map(\.kind) == [.changed, .changed, .removed])
    }
    @Test func duplicateOccurrencesAndAmbiguityOnEitherSide() throws {
        let result = try diff(#"{"a":1,"\u0061":2,"x":0}"#, #"{"x":0,"a":2,"a":1,"a":3}"#)
        #expect(result.changes.map(\.kind) == [.changed, .changed, .added])
        #expect(result.changes.allSatisfy { result.path(for: $0).ambiguous })
        #expect(result.hasDuplicates)
        let oneSide = try diff(#"{"a":{"v":1},"a":0}"#, #"{"a":{"v":2}}"#)
        #expect(oneSide.path(for: oneSide.changes[0]).ambiguous)
        let many = "{" + Array(repeating: "\"a\":0", count: 40).joined(separator: ",") + "}"
        let uncapped = try diff(many, "{\"a\":1}")
        #expect(uncapped.changes.count == 40 && uncapped.hasDuplicates)
        #expect(uncapped.changes.allSatisfy { uncapped.path(for: $0).ambiguous })
    }
    @Test func unicodeScalarIdentityAndSourceFragments() throws {
        let result = try diff(#"{"é":"👩🏽‍💻","e\u0301":"a","~\/":"\u0061\n"}"#,
                              #"{"e\u0301":"b","é":"👩🏽‍💻","~\/":"a\r"}"#)
        #expect(result.changes.count == 2 && !result.hasDuplicates)
        #expect(result.changes.map { result.path(for: $0).pointer } == ["/e\u{0301}", "/~0~1"])
        let last = result.changes[1]
        #expect(result.fragment(last, side: .before) == #""\u0061\n""#)
        #expect(result.value(last, side: .before) == "a\n")
        let different = try diff("\"é\"", "\"e\u{0301}\"")
        #expect(different.changes.count == 1)
        #expect(different.changes[0].beforeText?.difference == NSRange(location: 0, length: 1))
        #expect(different.changes[0].afterText?.difference == NSRange(location: 0, length: 2))
    }
    @Test func boundedContextShowsLateDifferenceAndSafeControls() throws {
        let prefix = String(repeating: "x", count: 20_000)
        let pair = JSONDiffText.pair(prefix + "👩🏽‍💻e\u{0301}\u{202E}", prefix + "👩🏽‍💻é\u{202E}")
        #expect(pair.0.preview.text.hasPrefix("…"))
        #expect(pair.0.preview.text.utf16.count < 1024 && pair.0.preview.text.contains("\\u{202E}"))
        let range = try #require(pair.0.difference)
        #expect(range.location == 20_007 && range.length == 2)
        #expect(!pair.0.preview.displayRanges(for: range).isEmpty)
    }
    @Test func rootScalarsAndExactCRLFAnchors() throws {
        for (a,b) in [("null","false"), ("{}","[]"), ("true","false"), (#""a b""#,#""ab""#)] {
            let result = try diff(a,b)
            #expect(result.changes.count == 1 && result.path(for: result.changes[0]).pointer.isEmpty)
        }
        let result = try diff("{\r\n\"😀\":1\r\n}", "{\r\n\"😀\":2\r\n}")
        let change = result.changes[0]
        #expect(result.before.nodes[change.before!].range == NSRange(location: 8, length: 1))
        #expect(JSONSourceCoordinates(result.before.source).location(at: 8).line == 2)
    }
    @Test func cancellationDoesNotReturnPartialResult() async throws {
        let doc = try #require(JSONProcessor.inspectStructure("[1,2,3]").document)
        let task = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try JSONStructuralDiff.compare(doc, doc); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        task.cancel(); #expect(await task.value)
    }
    @MainActor @Test func sessionPasteCompareInvalidationAndPrivacy() async throws {
        let name = "developerToolbox.diff.tests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = JSONDiffWorkspaceSession(repository: .init(defaults: defaults))
        session.before.source = #"{"a":1}"#; session.after.source = #"{"a":1.0}"#
        await session.didPaste(.before)?.value
        #expect(session.before.document != nil && session.after.document == nil && session.result == nil)
        let snapshot = session.before.document?.snapshotID
        await session.compare().value
        #expect(session.result?.changes.count == 1 && session.before.document?.snapshotID == snapshot)
        let diffSnapshot = session.result?.after.snapshotID
        session.selection = 0; session.inputsCollapsed = true
        await session.compare().value
        session.cancel()
        #expect(session.result?.after.snapshotID == diffSnapshot && session.selection == 0)
        session.preferences.wordWrap = false
        #expect(session.before.source == #"{"a":1}"# && session.result != nil)
        session.after.source = #"{"a":1,}"#
        #expect(session.result == nil && session.rows.isEmpty && session.selection == nil && session.before.document != nil)
        await session.compare().value
        #expect(session.after.result?.status == .invalid && session.result == nil && session.after.context != nil)
        let fresh = JSONDiffWorkspaceSession(repository: .init(defaults: defaults))
        #expect(fresh.before.source.isEmpty && fresh.after.source.isEmpty && fresh.result == nil && !fresh.preferences.wordWrap)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox.") } == [JSONPreferencesRepository.key])
    }
    @MainActor @Test func revisionRacesExactUnicodeAndPasteDisabled() async {
        let session = JSONDiffWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: "developerToolbox.diff.isolated.\(UUID())")!))
        session.preferences.validateOnPaste = false
        session.before.source = "\"é\""; session.after.source = "\"é\""
        #expect(session.didPaste(.after) == nil)
        let pending = session.compare()
        session.after.source = "\"e\u{0301}\""
        await pending.value
        #expect(session.result == nil && !session.busy)
        await session.compare().value
        #expect(session.result?.changes.count == 1)
        let again = session.compare(); session.cancel(); await again.value
        #expect(session.result != nil)
        session.before.source = "[0]"; session.after.source = "[1]"
        let cancelled = session.compare(); session.cancel(); await cancelled.value
        #expect(session.wasCancelled && session.result == nil)
        await session.compare().value
        #expect(session.result?.changes.count == 1 && !session.wasCancelled)
    }
    @MainActor @Test func sourceStatusesAndLimitsStayDistinct() async {
        let session = JSONDiffWorkspaceSession(repository: .init(defaults: UserDefaults(suiteName: "developerToolbox.diff.isolated.\(UUID())")!))
        await session.compare().value
        #expect(session.result == nil && session.before.result == nil)
        session.before.source = String(repeating: "0", count: JSONProcessor.maximumUTF16Length + 1)
        session.after.source = String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)
        await session.compare().value
        #expect(session.before.result?.status == .resourceLimit(.inputSize))
        #expect(session.after.result?.status == .resourceLimit(.nestingDepth))
        #expect(session.result == nil && !session.busy)
        session.before.source = "{"; session.after.source = "["
        await session.compare().value
        #expect(session.before.result?.status == .invalid && session.after.result?.status == .invalid)
    }
}
