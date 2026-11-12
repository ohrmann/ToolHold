import Foundation
import Testing
@testable import JSONCore

struct JSONPathTests {
    private func document(_ source: String) throws -> JSONStructureDocument {
        try #require(JSONProcessor.inspectStructure(source).document)
    }
    @Test func officialComplianceSuite() throws {
        let file = Bundle.module.url(forResource: "cts", withExtension: "json", subdirectory: "Fixtures/JSONPath")!
        let fixture = try document(String(contentsOf: file, encoding: .utf8))
        func child(_ node: Int, _ key: String) -> Int? { fixture.nodes[node].children.first { fixture.nodes[$0].key == key } }
        func paths(_ node: Int) -> [String] { fixture.nodes[node].children.map { fixture.nodes[$0].scalar! } }
        let cases = fixture.nodes[try #require(child(0, "tests"))].children
        #expect(cases.count == 715)
        for test in cases {
            let name = fixture.nodes[try #require(child(test, "name"))].scalar!
            let query = fixture.nodes[try #require(child(test, "selector"))].scalar!
            let invalid = child(test, "invalid_selector").map { fixture.nodes[$0].scalar == "true" } ?? false
            let input = try document(child(test, "document").map { fixture.fragment($0) } ?? "{}")
            do {
                let result = try JSONPathOperations.evaluate(query, in: input)
                #expect(!invalid, "Accepted invalid query: \(name): \(query)")
                if !invalid {
                    let actual = result.nodeIDs.map { input.path($0).jsonPath }
                    var alternatives: [[String]] = []
                    if let expected = child(test, "result_paths") { alternatives = [paths(expected)] }
                    if let expected = child(test, "results_paths") { alternatives = fixture.nodes[expected].children.map { paths($0) } }
                    // These upstream fixtures contradict RFC 9485 NormalChar (^ and $).
                    // Assert the normative result explicitly; keep the original suite intact.
                    if name == "functions, match, explicit caret" || name == "functions, match, explicit dollar" {
                        #expect(actual.isEmpty, "RFC 9485 anchors are literal characters: \(name)")
                    } else {
                        #expect(alternatives.contains(actual), "\(name): \(query); got \(actual), expected \(alternatives)")
                    }
                }
            } catch {
                #expect(invalid, "Valid query failed: \(name): \(query); \(error)")
            }
        }
    }
    @Test func losslessNumbersKeysAndCopies() throws {
        let doc = try document(#"{"values":[1,1.0,1e0,-0,123456789012345678901234567890,1e999999999999999999999],"é":1,"e\u0301":2,"s":"\u0061\n😀"}"#)
        let ones = try JSONPathOperations.evaluate("$.values[?@ == 1]", in: doc)
        #expect(ones.nodeIDs.map { doc.fragment($0) } == ["1", "1.0", "1e0"])
        let huge = try JSONPathOperations.evaluate("$.values[?@ > 123456789012345678901234567889]", in: doc)
        #expect(huge.nodeIDs.count == 2)
        #expect(try JSONPathOperations.evaluate("$['é']", in: doc).nodeIDs != JSONPathOperations.evaluate("$['e\\u0301']", in: doc).nodeIDs)
        let repeated = try JSONPathOperations.evaluate("$.values[0,0,2]", in: doc)
        #expect(repeated.nodeIDs.count == 3 && repeated.nodeIDs[0] == repeated.nodeIDs[1])
        #expect(try JSONPathOperations.copyArray(repeated, document: doc) == "[1,\n1,\n1e0]")
        let s = try JSONPathOperations.evaluate("$.s", in: doc)
        #expect(doc.fragment(s.nodeIDs[0]) == #""\u0061\n😀""#)
    }
    @Test func duplicateKeysBlockQueriesWithoutInvalidatingJSON() throws {
        let parsed = JSONProcessor.inspectStructure(#"{"a":1,"\u0061":2}"#)
        #expect(parsed.result.isValid)
        do { _ = try JSONPathOperations.evaluate("$", in: #require(parsed.document)); Issue.record("Expected duplicate rejection") }
        catch JSONPathFailure.duplicates {} catch { Issue.record("Wrong failure: \(error)") }
    }
    @Test func exactDecimalOrdering() {
        for (a, b, expected) in [("1", "1.00e0", 0), ("-0", "0e999999", 0), ("0.01", "0.1", -1),
                                 ("-123", "-122", -1), ("9999999999999999999", "10000000000000000000", -1),
                                 ("10e99999999999999999", "1e100000000000000000", 0),
                                 ("1e-999999999999999999", "1e-999999999999999998", -1)] {
            #expect(JSONPathNumber(a).compare(JSONPathNumber(b)) == expected)
        }
    }
}

extension JSONPathTests {
    @Test func utf16QueryErrorAndTypedExpressions() throws {
        let doc = try document("{}")
        let query = "$['😀']."
        do { _ = try JSONPathOperations.evaluate(query, in: doc); Issue.record("Expected query error") }
        catch JSONPathFailure.syntax(_, let range) { #expect(range == NSRange(location: query.utf16.count, length: 0)) }
        for query in ["$[?unknown(@)]", "$[?length(@)]", "$[?count(1) == 1]", "$[?@ + 1]", "$[?true]", "$[?@ == 01]", "$[9007199254740992]", "$['\\uD800']"] {
            #expect(throws: (any Error).self) { try JSONPathOperations.evaluate(query, in: doc) }
        }
        let unicode = try document(#"["e\u0301","é","😀","^abc","abc$"]"#)
        #expect(try JSONPathOperations.evaluate("$[?length(@) == 2]", in: unicode).nodeIDs == [1])
        #expect(try JSONPathOperations.evaluate("$[?match(@, '^abc')]", in: unicode).nodeIDs == [4])
        #expect(try JSONPathOperations.evaluate("$[?match(@, 'abc$')]", in: unicode).nodeIDs == [5])
        #expect(try JSONPathOperations.evaluate("$[?match(@, 'a|abc$')]", in: unicode).nodeIDs == [5])
    }
    @Test func boundedWorkCancellationAndCopy() async throws {
        let doc = try document("[0,1]")
        let repeated = "$" + String(repeating: "[0,0]", count: 20)
        let nested = try document(String(repeating: "[", count: 20) + "0" + String(repeating: "]", count: 20))
        do { _ = try JSONPathOperations.evaluate(repeated, in: nested); Issue.record("Expected expansion limit") }
        catch JSONPathFailure.limit {} catch { Issue.record("Wrong error \(error)") }
        #expect(throws: (any Error).self) { try JSONPathOperations.evaluate("$" + String(repeating: " ", count: 4096), in: doc) }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return Result { try JSONPathOperations.evaluate("$[*]", in: doc) }
        }
        if case .failure(let error) = await task.value { #expect(error is CancellationError) }
        else { Issue.record("Cancellation ignored") }
        let huge = try document("\"" + String(repeating: "x", count: 262_140) + "\"")
        let result = JSONPathEvaluation(snapshotID: huge.snapshotID, nodeIDs: Array(repeating: 0, count: 20))
        #expect(throws: (any Error).self) { try JSONPathOperations.copyArray(result, document: huge) }
        #expect(throws: (any Error).self) { try JSONPathOperations.copyArray(result, document: doc) }
    }
    @MainActor @Test func sessionPasteRunInvalidationAndPrivacy() async throws {
        let domain = "developerToolbox.path.tests.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = JSONPathWorkspaceSession(repository: .init(defaults: defaults))
        session.input = #"{"values":[1,1.0,1e0],"null":null}"#
        session.query = "$.values[?@ == 1]"
        await session.didPaste()?.value
        #expect(session.document != nil && session.result == nil && session.status == .ready)
        let snapshot = session.document?.snapshotID
        await session.run().value
        #expect(session.rows.count == 3 && session.status == .complete && session.document?.snapshotID == snapshot)
        #expect(session.rowNumbers == [0:1, 1:2, 2:3])
        session.selection = 1; session.inputCollapsed = true
        let version = session.version
        await session.run().value
        session.cancel()
        #expect(session.version == version && session.selection == 1 && session.result != nil)
        session.preferences.wordWrap = false
        #expect(session.input.contains("1e0") && session.result != nil)
        session.query = "$.absent"
        #expect(session.result == nil && session.selection == nil && session.document?.snapshotID == snapshot)
        await session.run().value
        #expect(session.result != nil && session.rows.isEmpty && session.status == .complete)
        session.input = #"{"x":1,}"#
        #expect(session.document == nil && session.result == nil)
        await session.run().value
        #expect(session.status == .invalidJSON && session.context != nil && session.validation?.status == .invalid)
        session.input = #"{"x":1,"x":2}"#; session.query = "$"
        await session.run().value
        #expect(session.status == .blocked && session.validation?.isValid == true)
        session.input = String(repeating: " ", count: 262_145)
        await session.run().value
        #expect(session.status == .limited && session.result == nil)
        let fresh = JSONPathWorkspaceSession(repository: .init(defaults: defaults))
        #expect(fresh.input.isEmpty && fresh.query.isEmpty && fresh.document == nil && fresh.result == nil && !fresh.preferences.wordWrap)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox.") } == [JSONPreferencesRepository.key])
    }
    @MainActor @Test func sessionRevisionRacesAndPasteDisabled() async throws {
        let domain = "developerToolbox.path.races.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = JSONPathWorkspaceSession(repository: .init(defaults: defaults))
        session.preferences.validateOnPaste = false
        session.input = "[1,2]"; session.query = "$[*]"
        #expect(session.didPaste() == nil && session.document == nil)
        let old = session.run()
        session.input = #"{"é":1,"e\u0301":2}"#; session.query = "$['é']"
        let current = session.run()
        await old.value; await current.value
        #expect(session.result?.nodeIDs == [1])
        let queryOld = session.run()
        session.query = "$['e\\u0301']"
        await queryOld.value
        #expect(session.result == nil)
        await session.run().value
        #expect(session.result?.nodeIDs == [2])
        session.query = "$..*"
        let cancelled = session.run(); session.cancel(); await cancelled.value
        #expect(session.status == .cancelled && session.result == nil)
    }
}

extension JSONPathTests {
    @Test func expensiveRegexStopsWithResourceStatus() throws {
        let doc = try #require(JSONProcessor.inspectStructure("[\"" + String(repeating: "a", count: 8_000) + "!\"]").document)
        let start = ContinuousClock.now
        do { _ = try JSONPathOperations.evaluate("$[?match(@, '(a+)+')]", in: doc); Issue.record("Expected regex work limit") }
        catch JSONPathFailure.limit { #expect(start.duration(to: .now) < .seconds(3)) }
        catch { Issue.record("Wrong error: \(error)") }
    }
}
