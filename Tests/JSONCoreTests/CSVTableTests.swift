import Foundation
import Testing
@testable import JSONCore

struct CSVTableTests {
    @Test func losslessCellsHeadersAndRecords() throws {
        let source = "\u{FEFF}name,name,,n\r\n\"A, B\",\"say \"\"hi\"\"\",,0000123000000000000000001\r\n\"line\r\nbreak\",😀,é,-0\r\n"
        let result = CSVTableProcessor.build(source)
        let document = try #require(result.document)
        #expect(result.status == .success && result.diagnostics.isEmpty)
        #expect(document.rowCount == 2 && document.columnCount == 4)
        #expect(document.header(0) == "name" && document.header(1) == "name")
        #expect(document.header(2).contains("empty header"))
        #expect(document.cell(.init(row: 0, column: 1))?.value == "say \"hi\"")
        #expect(document.cell(.init(row: 0, column: 2))?.value == "")
        #expect(document.cell(.init(row: 0, column: 3))?.value == "0000123000000000000000001")
        #expect(document.fragment(0) == "\"A, B\",\"say \"\"hi\"\"\",,0000123000000000000000001")
        let cell = try #require(document.cell(.init(row: 1, column: 0)))
        #expect((source as NSString).substring(with: cell.range) == "\"line\r\nbreak\"")
        #expect(cell.value == "line\r\nbreak")
        #expect(document.cell(.init(row: 1, column: 3))?.value == "-0")
    }
    @Test func raggedIsViewableWithoutChangingStrictConverter() throws {
        let source = "a,b\n1,2,\n3\n4,"
        let result = CSVTableProcessor.build(source)
        let document = try #require(result.document)
        #expect(document.rowCount == 3 && document.columnCount == 3)
        #expect(result.diagnostics.first?.severity == .warning)
        #expect(document.cell(.init(row: 0, column: 2))?.value == "")
        #expect(document.cell(.init(row: 1, column: 1)) == nil)
        #expect(document.cell(.init(row: 2, column: 1))?.value == "")
        #expect(document.header(2) == "Column 3")
        #expect(JSONCSVConverter.process(source, direction: .toJSON).status == .invalid)
    }
    @Test func emptyHeaderOnlyNoHeaderTSVAndBlankRecords() throws {
        #expect(CSVTableProcessor.build("").document?.rowCount == 0)
        #expect(CSVTableProcessor.build("\u{FEFF}").document?.columnCount == 0)
        #expect(CSVTableProcessor.build("a,b\n").document?.rowCount == 0)
        let document = try #require(CSVTableProcessor.build("a\t\"b\tc\"\t\r\n\t\t", format: .tsv, hasHeader: false).document)
        #expect(document.rowCount == 2 && document.columnCount == 3)
        #expect(document.cell(.init(row: 0, column: 1))?.value == "b\tc")
        #expect(document.cell(.init(row: 1, column: 0))?.value == "")
        #expect(document.header(0) == "Column 1")
        #expect(CSVTableProcessor.build("\n\n", hasHeader: false).document?.rowCount == 2)
    }
    @Test func strictFailuresAndCoordinates() throws {
        for source in ["h\n\"unterminated", "h\nx\"y", "h\n\"x\"z"] {
            let result = CSVTableProcessor.build(source)
            #expect(result.status == .invalid && result.document == nil)
            #expect(result.diagnostics.first?.line == 2)
        }
        let result = CSVTableProcessor.build("h\r\n😀\"oops")
        #expect(result.diagnostics.first?.range.location == 5)
        #expect(result.diagnostics.first?.column == 3)
    }
    @Test func filteringIsLiteralDecodedCaseInsensitiveAndSafe() throws {
        let source = "key,value\nfirst,\"A \"\"quote\"\" 😀é\"\nsecond,abcABC\nthird,=SUM(1)\nfourth,\"\u{202E}unsafe\""
        let document = try #require(CSVTableProcessor.build(source).document)
        let query = try CSVTableProcessor.project(document, query: "abc")
        #expect(query.rows == [1] && query.positions == [-1, 0, -1, -1])
        #expect(query.previews.values.first?.matches.count == 2)
        #expect(try CSVTableProcessor.project(document, query: "key").rows.isEmpty)
        #expect(try CSVTableProcessor.project(document, query: "\"quote\" 😀").rows == [0])
        #expect(try CSVTableProcessor.project(document, query: ".*").rows.isEmpty)
        #expect(document.cell(.init(row: 2, column: 1))?.value == "=SUM(1)")
        #expect(!document.previews.last!.text.contains("\u{202E}"))
    }
    @Test func longCellPreviewRevealsFarMatchAndMapsUnicode() throws {
        let value = String(repeating: "x", count: 10000) + "😀needlé\u{202E}" + String(repeating: "z", count: 10000)
        let document = try #require(CSVTableProcessor.build("h\n" + value).document)
        let projection = try CSVTableProcessor.project(document, query: "😀needlé")
        let preview = try #require(projection.previews[1])
        #expect(preview.text.contains("😀needlé"))
        #expect(preview.text.utf16.count < 250)
        #expect(!preview.matches.isEmpty)
        #expect(preview.matches.allSatisfy { NSMaxRange($0) <= preview.text.utf16.count })
        #expect(document.cell(.init(row: 0, column: 0))?.value == value)
    }
    @Test func stableTextSortAndSourceOrder() throws {
        let document = try #require(CSVTableProcessor.build("n,v\n2,a\n10,b\n2,c\n1,d\n,e\n9,f").document)
        let ascending = try CSVTableProcessor.project(document, sort: .init(column: 0, ascending: true))
        #expect(ascending.rows == [4, 3, 1, 0, 2, 5])
        #expect(try CSVTableProcessor.project(document, sort: .init(column: 0, ascending: false)).rows == [5, 0, 2, 1, 3, 4])
        #expect(try CSVTableProcessor.project(document).rows == [0, 1, 2, 3, 4, 5])
    }
    @Test func sizeLimitAndCancellation() async throws {
        #expect(CSVTableProcessor.build(String(repeating: "x", count: 262145)).status == .resourceLimit)
        #expect(CSVTableProcessor.build(String(repeating: "x", count: 262144)).status == .success)
        let task = Task.detached { () -> CSVTableResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return CSVTableProcessor.build("h\na")
        }
        #expect(await task.value.status == .cancelled)
        let document = try #require(CSVTableProcessor.build("h\na").document)
        let projection = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try CSVTableProcessor.project(document); return false } catch { return true }
        }
        #expect(await projection.value)
    }
    @Test @MainActor func sessionRevisionPasteSelectionAndPrivacy() async throws {
        let suite = "CSVTableTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = CSVTableWorkspaceSession(repository: .init(defaults: defaults))
        session.input = "a,b\n1,2\n3,4"; await session.build().value
        let original = try #require(session.document?.id)
        session.selection = .init(row: 0, column: 1)
        await session.build().value
        #expect(session.document?.id == original && session.selection?.column == 1)
        session.preferences.wordWrap.toggle()
        #expect(session.document?.id == original)
        session.query = "3"; await session.scheduleProjection()?.value
        #expect(session.projection?.rows == [1] && session.selection == nil)
        #expect(!session.go(row: 0, column: 0))
        #expect(session.go(row: 1, column: 1))
        session.query = "1"; session.query = "4"; await session.scheduleProjection()?.value
        #expect(session.projection?.query == "4" && session.projection?.rows == [1])
        session.input = "h\nnew"; #expect(session.document == nil && session.selection == nil)
        let stale = session.build(); session.input = "h\nlatest"; await stale.value
        #expect(session.document == nil)
        session.query = ""; session.preferences.validateOnPaste = true
        await session.didPaste()?.value
        #expect(session.document?.cell(.init(row: 0, column: 0))?.value == "latest")
        session.input = "h\nmanual"; session.preferences.validateOnPaste = false
        #expect(session.didPaste() == nil && session.document == nil)
        let fresh = CSVTableWorkspaceSession(repository: .init(defaults: defaults))
        #expect(fresh.input.isEmpty && fresh.document == nil && fresh.query.isEmpty && fresh.selection == nil)
    }
}
