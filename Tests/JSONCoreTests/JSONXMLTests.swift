import Foundation
import Testing
@testable import JSONCore

struct JSONXMLTests {
    private func run(_ source: String, _ direction: JSONXMLDirection = .xmlToJSON, _ mapping: JSONXMLMapping = .elements) -> JSONXMLResult {
        JSONXMLConverter.process(source, direction: direction, mapping: mapping)
    }
    private func compact(_ source: String) -> String? { JSONProcessor.process(source, operation: .minify).output }
    @Test func elementsAttributesRepeatedTagsAndText() throws {
        let input = #"<user id="001"><name>Ada &amp; Bob</name><role>admin</role><role>dev</role><empty/></user>"#
        let result = run(input)
        #expect(result.status == .success)
        let json = try #require(result.output)
        #expect(compact(json) == #"{"user":{"@id":"001","name":"Ada & Bob","role":["admin","dev"],"empty":""}}"#)
        let xml = try #require(run(json, .jsonToXML).output)
        #expect(xml.contains("id=\"001\"") && xml.contains("<role>admin</role>"))
        #expect(compact(try #require(run(xml).output)) == compact(json))
    }
    @Test func attributesWithTextCDATACommentsAndNamespaces() throws {
        let result = run(#"<?xml version="1.0"?><p:root xmlns:p="urn:test"><p:text id="a"> hi <![CDATA[<b>]]>&#xD;</p:text><!-- comment --><?info data?></p:root>"#)
        let output = try #require(result.output)
        #expect(result.status == .success && result.notes.contains { $0.contains("Comments") })
        #expect(output.contains("@xmlns:p") && output.contains("p:text"))
        let structure = try #require(JSONProcessor.inspectStructure(output).document)
        #expect(structure.nodes.first { $0.key == "#text" }?.scalar == " hi <b>\r")
        #expect(run(output, .jsonToXML).status == .success)
        #expect(run("<r><v>001</v><v>true</v><v>null</v></r>").output?.contains("\"001\"") == true)
        let namespaced = run("<r xmlns:p='urn:a' xmlns:q='urn:b' p:x='1' q:x='2'/>")
        #expect(namespaced.output?.contains("@p:x") == true && namespaced.output?.contains("@q:x") == true)
        #expect(run("<r xmlns:xml='http://www.w3.org/XML/1998/namesp&#x61;ce'/>").status == .success)
    }
    @Test func JSONScalarsHaveExplicitElementsLossPolicy() throws {
        let source = #"{"root":{"number":90071992547409931234567890,"negative":-0,"exponent":1.2300e+999,"ok":true,"empty":{}}}"#
        let result = run(source, .jsonToXML)
        let output = try #require(result.output)
        #expect(result.status == .success && output.contains("90071992547409931234567890") && output.contains("1.2300e+999"))
        #expect(result.notes.first?.contains("not retained") == true)
        let reverse = try #require(run(output).output)
        #expect(reverse.contains("\"-0\"") && reverse.contains("\"true\""))
        for source in ["null", "[1]", #"{"a":1,"b":2}"#, #"{"r":null}"#, #"{"r":{"v":[]}}"#, #"{"r":[1]}"#, #"{"r":{"@id":null}}"#] {
            let result = run(source, .jsonToXML)
            #expect(result.status == .unsupported && result.output == nil)
        }
    }
    @Test func typedJSONPreservesLexemesOrderDuplicateKeysAndRootValues() throws {
        let fixtures = [
            #"{"n":90071992547409931234567890,"n":-0,"n":1.2300e+999,"s":"\u0061\n\uD83D\uDE00","nil":null,"empty":{},"list":[],"bool":true}"#,
            #"{"é":1,"é":2,"a/b~":false,"\u0000":"\u0001","":null}"#,
            "[0,-0,1e999999,{},[],true,false,null,\"😀é\"]", "null", "false", "90071992547409931234567890", #""\u0061""#
        ]
        for source in fixtures {
            let exported = run(source, .jsonToXML, .typed)
            #expect(exported.status == .success)
            let xml = try #require(exported.output)
            let imported = run(xml, .xmlToJSON, .typed)
            #expect(imported.status == .success)
            #expect(compact(try #require(imported.output)) == source)
        }
    }
    @Test func UnicodeControlsAndXMLCharactersAreNotSilentlyLost() throws {
        let source = "{\"x\":\"\u{FFFF}\",\"emoji\":\"😀é\"}"
        let xml = try #require(run(source, .jsonToXML, .typed).output)
        let restored = try #require(run(xml, .xmlToJSON, .typed).output)
        let document = try #require(JSONProcessor.inspectStructure(restored).document)
        #expect(document.nodes.first { $0.key == "x" }?.scalar == "\u{FFFF}")
        #expect(document.nodes.first { $0.key == "emoji" }?.scalar == "😀é")
        #expect(run(#"{"r":"\u0000"}"#, .jsonToXML).status == .unsupported)
        #expect(run(##"{"r":{"@id":"a\tb\nc\rd","#text":"<&>\r"}}"##, .jsonToXML).output?.contains("&#xD;") == true)
    }
    @Test func malformedXMLIsInvalidAndDiagnosticsStayWithinUTF16Source() throws {
        for source in ["", "<r>", "<r><a></r>", "<a/><b/>", "<r a='1' a='2'/>", "<r>&unknown;</r>", "<r>&#0;</r>", "<r><![CDATA[no</r>", "<r><p:unknown/></r>", "<r p:a='1'/>", "<r xmlns:p='urn:a' xmlns:q='urn:a' p:x='1' q:x='2'/>", "<r xmlns:xml='urn:wrong'/>"] {
            let result = run(source)
            #expect(result.status == .invalid && result.output == nil, "Fixture: \(source); status: \(result.status)")
            let diagnostic = try #require(result.diagnostics.first)
            #expect(diagnostic.range.location >= 0 && NSMaxRange(diagnostic.range) <= source.utf16.count)
        }
        let source = "<r>\r\n😀é\r\n<x></r>"
        let issue = try #require(run(source).diagnostics.first)
        #expect(issue.precision == .region && issue.line == 3 && issue.column == 1)
    }
    @Test func XMLNamesAndMixedContentAreExplicitlyUnsupported() {
        for source in [#"{"bad name":"x"}"#, #"{"r":{"1bad":1}}"#, #"{"r":{"a":1,"a":2}}"#, ##"{"r":{"#text":"before","child":"after"}}"##, #"{"r":{"p:a":1}}"#] {
            #expect(run(source, .jsonToXML).status == .unsupported)
        }
        for source in ["<r>before<b/>after</r>", "<r><a/><b/><a/></r>", "<r xml:space='preserve'> <a/> </r>", "<r xml:space='preserve'><x> <a/> </x></r>", "<r é='a' é='b'/>"] {
            #expect(run(source).status == .unsupported)
        }
        #expect(run(#"{"root":{"é":"x","é":"y"}}"#, .jsonToXML).status == .success)
    }
    @Test func DTDAndEntitiesAreBlockedBeforeResolution() throws {
        for source in [
            "<!DOCTYPE r SYSTEM 'file:///private/tmp/never-read'><r/>",
            "<!DOCTYPE r SYSTEM 'https://example.invalid/never-fetch'><r/>",
            "<!DOCTYPE r [<!ENTITY a 'hello'>]><r>&a;</r>",
            "<!DOCTYPE r [<!ENTITY % p SYSTEM 'file:///etc/passwd'>%p;]><r/>",
            "<!DOCTYPE r [<!ENTITY a '123'><!ENTITY b '&a;&a;&a;'>]><r>&b;</r>"
        ] {
            let result = run(source)
            #expect(result.status == .unsupported && result.output == nil)
            let issue = try #require(result.diagnostics.first)
            #expect(issue.precision == .exact && issue.range.location == 0 && issue.message.contains("disabled"))
        }
        // A declaration-looking sequence in a literal body is data, not a DTD.
        #expect(run("<r><![CDATA[<!DOCTYPE data>]]></r>").status == .success)
        #expect(run("<!-- <!DOCTYPE data> --><r/>").status == .success)
        #expect(run("<?info <!DOCTYPE data> ?><r/>").status == .success)
    }
    @Test func typedMappingRejectsForeignVocabularyAndInvalidTokens() {
        let ns = JSONXMLConverter.namespace
        for body in ["<string>not quoted</string>", "<number>01</number>", "<boolean>1</boolean>", "<null>null</null>", "<array><string key='&quot;x&quot;'>\"v\"</string></array>", "<object><null/></object>", "<tree></tree>", "<string><null/></string>"] {
            let source = body.replacingOccurrences(of: ">", with: " xmlns='\(ns)'>", range: body.range(of: ">"))
            #expect(run(source, .xmlToJSON, .typed).status == .unsupported)
        }
        #expect(run("<object/>", .xmlToJSON, .typed).status == .unsupported)
        #expect(run("<?xml version='1.1'?><r/>").status == .unsupported)
        #expect(run("<?xml\nversion='1.1'?><r/>").status == .unsupported)
        #expect(run("<?xml version='1.0' encoding='UTF-16'?><r/>").status == .unsupported)
    }
    @Test func limitsCheckOnlyAndDepthBoundaries() throws {
        #expect(run(String(repeating: "x", count: 262_145)).status == .resourceLimit)
        let deep = String(repeating: "<r>", count: 65) + String(repeating: "</r>", count: 65)
        #expect(run(deep).status == .resourceLimit)
        let json = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        let typed = try #require(run(json, .jsonToXML, .typed).output)
        #expect(run(typed, .xmlToJSON, .typed).status == .success)
        #expect(run(String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65), .jsonToXML, .typed).status == .resourceLimit)
        let huge = "{\"r\":\"" + String(repeating: "&", count: 60_000) + "\"}"
        #expect(run(huge, .jsonToXML).status == .resourceLimit)
        let check = JSONXMLConverter.process("<r/>", direction: .xmlToJSON, produceOutput: false)
        #expect(check.status == .success && check.output == nil)
    }
    @Test func cancellationHasNoPartialOutput() async {
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return JSONXMLConverter.process("<r/>", direction: .xmlToJSON)
        }
        worker.cancel()
        let result = await worker.value
        #expect(result.status == .cancelled && result.output == nil && result.diagnostics.isEmpty)
    }
}

@MainActor struct JSONXMLWorkspaceTests {
    @Test func revisionsPasteCheckOutputPrivacyAndProfileChanges() async throws {
        let suite = "JSONXMLTests.\(UUID())"
        let storage = UserDefaults(suiteName: suite)!
        defer { storage.removePersistentDomain(forName: suite) }
        let repository = JSONPreferencesRepository(defaults: storage), session = JSONXMLWorkspaceSession(repository: .init(defaults: storage))
        session.input = #"{"root":{"n":9007199254740993}}"#
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        await session.run().value
        let output = session.output
        #expect(output?.contains("9007199254740993") == true)
        await session.run(convert: false).value
        #expect(session.output == output)
        let cancelled = session.run(); session.cancel(); await cancelled.value
        #expect(session.output == output && session.wasCancelled)
        let stale = session.run(); session.mapping = .typed; await stale.value
        #expect(session.output == nil && session.result == nil && !session.busy)
        await session.run().value
        session.preferences.wordWrap = false
        #expect(session.output != nil)
        session.input = #"{"é":1}"#; let older = session.run(); session.input = #"{"é":2}"#; await older.value
        #expect(session.output == nil && session.result == nil)
        session.direction = .xmlToJSON; session.mapping = .elements; session.input = "<root/>"
        await session.run().value
        #expect(session.output != nil)
        session.preferences.validateOnPaste = false; session.input = "<bad>"
        #expect(session.didPaste() == nil && session.result == nil)
        let fresh = JSONXMLWorkspaceSession(repository: repository)
        #expect(fresh.input.isEmpty && fresh.output == nil && fresh.result == nil && fresh.mapping == .elements)
        #expect(storage.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox") } == [JSONPreferencesRepository.key])
    }
}
