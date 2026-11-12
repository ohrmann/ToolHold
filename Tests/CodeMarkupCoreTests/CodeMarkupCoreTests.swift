import XCTest
@testable import CodeMarkupCore

final class CodeMarkupCoreTests: XCTestCase, @unchecked Sendable {
    func result(_ tool: MarkupTool, _ source: String, _ op: String = "format", options: MarkupOptions = .init()) async -> MarkupResult {
        await MarkupProcessor.process(.init(tool: tool, source: source, operation: op, options: options))
    }
    func testAllEnginePaths() async {
        for (tool, source) in [(MarkupTool.sql,"select a from t"),(.xml,"<root><child>ok</child></root>"),(.yaml,"a: [1, 2]"),(.html,"<div><p>Hello</p></div>"),(.css,"a { color: red; }"),(.javascript,"const a = 1;"),(.markdown,"# Hello"),(.preview,"<h1>Hello</h1>"),(.mjml,"<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>")] {
            let r = await result(tool,source)
            XCTAssertTrue(r.succeeded,"\(tool): \(r)")
            XCTAssertFalse(r.output?.isEmpty ?? true,"\(tool)")
            if tool.isPreview { XCTAssertNotNil(r.preview,"\(tool)") }
        }
    }
    func testPreviewExternalResourcesAreExplicitAndHTTPSOnly() async {
        let source="""
        <html><head>
        <link rel="stylesheet" href="https://example.invalid/font.css">
        <link rel="prefetch" href="https://example.invalid/private">
        <style>@import url('https://example.invalid/style.css');
        @font-face{font-family:Remote;src:url('https://example.invalid/font.woff2') format('woff2')}
        .hero{background-image:url('https://example.invalid/background.png')}
        .bad{background-image:url('file:///etc/passwd')}</style>
        </head><body><h1>Visible offline</h1>
        <img src="https://example.invalid/image.png" onerror="fetch('/data')">
        <img src="http://example.invalid/insecure.png">
        <img src="https://user:password@example.invalid/private.png">
        <script>fetch('https://example.invalid/script')</script>
        <iframe src="https://example.invalid/frame"></iframe>
        <a href="https://example.invalid/navigation">Link</a>
        </body></html>
        """
        var options=MarkupOptions();options.document=true
        let offline=await result(.preview,source,options:options)
        XCTAssertTrue(offline.succeeded)
        XCTAssertTrue(offline.preview?.contains("Visible offline") == true)
        XCTAssertFalse(offline.preview?.contains("https://") == true)
        let online=await MarkupProcessor.process(.init(tool:.preview,source:source,options:options,allowsExternalResources:true))
        XCTAssertTrue(online.succeeded)
        let html=online.preview ?? ""
        for value in ["font.css","style.css","font.woff2","background.png","image.png","no-referrer","font-src https:"] {XCTAssertTrue(html.contains(value),value)}
        for value in ["<script","<iframe","onerror","prefetch","file:///","http://example.invalid","user:password","https://example.invalid/navigation"] {XCTAssertFalse(html.contains(value),value)}
        XCTAssertTrue(html.contains("script-src 'none'"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertEqual(online.output,source) // Opt-in changes only preview, never source/export.
        let mjml="""
        <mjml><mj-head><mj-font name="Manrope" href="https://example.invalid/font.css" /></mj-head>
        <mj-body><mj-section><mj-column><mj-text>A gift for you!</mj-text>
        <mj-image src="https://example.invalid/gift.png" /></mj-column></mj-section></mj-body></mjml>
        """
        let compiled=await result(.mjml,mjml)
        let remote=await MarkupProcessor.process(.init(tool:.mjml,source:mjml,allowsExternalResources:true))
        XCTAssertTrue(compiled.succeeded);XCTAssertTrue(remote.succeeded)
        XCTAssertEqual(compiled.output,remote.output)
        XCTAssertTrue(compiled.preview?.contains("A gift for you!") == true)
        XCTAssertTrue(remote.preview?.contains("https://example.invalid/gift.png") == true)
    }

    @MainActor func testExternalPermissionIsSourceScopedAndNeverPersisted() async throws {
        let name="toolbox.remote-test."+UUID().uuidString,defaults=UserDefaults(suiteName:name)!
        defer {defaults.removePersistentDomain(forName:name)}
        let w=MarkupWorkspace(.preview,defaults:defaults);w.options.live=false
        w.input="<p>First</p><img src='https://example.invalid/image.png'>"
        XCTAssertFalse(w.allowsExternalResources)
        w.setExternalResourcesAllowed(true)
        while w.busy {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(w.snapshot?.allowsExternalResources == true)
        XCTAssertTrue(w.snapshot?.html.contains("https://example.invalid/image.png") == true)
        w.input="<p>Changed</p>"
        XCTAssertFalse(w.allowsExternalResources) // Revoke before async replacement is ready.
        XCTAssertNil(w.result)
        w.run();while w.busy {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertFalse(w.snapshot?.allowsExternalResources ?? true)
        w.setExternalResourcesAllowed(true)
        w.input="<p>Latest</p>";w.run()
        while w.busy {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertFalse(w.allowsExternalResources)
        XCTAssertFalse(w.snapshot?.allowsExternalResources ?? true)
        XCTAssertTrue(w.snapshot?.html.contains("Latest") == true)
        w.setExternalResourcesAllowed(true)
        while w.busy {try await Task.sleep(for:.milliseconds(10))}
        w.setExternalResourcesAllowed(false)
        XCTAssertFalse(w.allowsExternalResources)
        while w.busy {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertFalse(w.snapshot?.allowsExternalResources ?? true)
        let fresh=MarkupWorkspace(.preview,defaults:defaults)
        XCTAssertFalse(fresh.allowsExternalResources);XCTAssertTrue(fresh.input.isEmpty)
        let stored=try XCTUnwrap(defaults.data(forKey:"codeMarkup.preferences.preview"))
        XCTAssertFalse(String(decoding:stored,as:UTF8.self).contains("allowsExternalResources"))
    }
    func testYAMLScalarsAliasesAndStreams() async {
        for source in ["big: 123456789012345678901234567890\ndec: 1.234567890123456789\nz: -0\n", "# note\na: &a [1, 2]\nb: *a\n", "---\na: true\n---\nb: null\n", "text: |\n  hello\n  world\n"] {
            let r=await result(.yaml,source);XCTAssertTrue(r.succeeded,"\(r)")
        }
        for source in ["a: 1\na: 2", "a: *missing"] { let r=await result(.yaml,source);XCTAssertEqual(r.status,"invalid") }
        let unsupported=await result(.yaml,"%YAML 1.1\n---\nyes");XCTAssertEqual(unsupported.status,"unsupported")
    }
    func testXMLSecurityMixedContent() async {
        let bom=await result(.xml,"\u{FEFF}<?xml version='1.0'?><r><a/></r>");XCTAssertTrue(bom.succeeded);XCTAssertTrue(bom.output?.hasPrefix("\u{FEFF}<?xml") == true)
        let profile=await result(.xml,"<?xml version='1.1'?><r/>");XCTAssertEqual(profile.status,"unsupported")
        for source in ["<r>\u{00A0}<n/>\u{2003}</r>","<r xml:space=\"pres&#101;rve\">  <n/>  </r>","<r xml:space='preserve'><n a=\"xml:space='default'\">  <x/>  </n></r>"] {
            let checked=await result(.xml,source);XCTAssertTrue(checked.succeeded);XCTAssertEqual(checked.output,source)
        }
        let source="<root><p>Hello <b>world</b> !</p><n xml:space=\"preserve\">  <a/>  </n></root>"
        let r=await result(.xml,source);XCTAssertTrue(r.output?.contains("Hello <b>world</b> !") == true);XCTAssertTrue(r.output?.contains("  <a/>  ") == true)
        let dtd=await result(.xml,"<!DOCTYPE r [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><r>&x;</r>");XCTAssertEqual(dtd.status,"unsupported")
        let bad=await result(.xml,"<a>😀\r\n</b>");XCTAssertEqual(bad.status,"invalid");XCTAssertEqual(bad.diagnostics.first?.line,2)
        let comment=await result(.xml,"<!-- <!DOCTYPE literal> --><r/>");XCTAssertTrue(comment.succeeded)
    }
    func testStaticPreviewBoundary() async {
        let r=await result(.preview,"<html><head><base href='https://example.invalid'><style>@import 'https://example.invalid';p{color:red;background:url(https://example.invalid)}</style></head><body><script>while(true){}</script><iframe srcdoc='<script>alert(1)</script>'></iframe><p onclick='x()'>Safe</p><img src='https://example.invalid/x'><a href='javascript:alert(1)'>link</a></body></html>")
        XCTAssertTrue(r.succeeded);let html=r.preview ?? ""
        XCTAssertFalse(html.contains("<script"));XCTAssertFalse(html.contains("<iframe"));XCTAssertFalse(html.contains("onclick"));XCTAssertFalse(html.contains("https://example.invalid"));XCTAssertTrue(html.contains("color:red"));XCTAssertTrue(html.contains("Content-Security-Policy"));XCTAssertEqual(r.images?.count,1);XCTAssertFalse(r.notices.isEmpty)
    }
    func testMinifiersPreserveContent() async {
        let js=await result(.javascript,"function name() { return\n { value: 1 }; } const n=12345678901234567890n;", "minify")
        XCTAssertTrue(js.succeeded);XCTAssertTrue(js.output?.contains("12345678901234567890n") == true)
        let html=await result(.html,"<span  title = 'a  b'>a</span> <span>b</span>","minify")
        XCTAssertTrue(html.succeeded);XCTAssertTrue(html.output?.contains("'a  b'") == true);XCTAssertTrue(html.output?.contains("</span> <span>") == true)
        let css=await result(.css,"a { --x:  1  2; width: calc(1px + 2px); color: red; color: blue; }","minify")
        XCTAssertTrue(css.succeeded,"\(css)");XCTAssertTrue(css.output?.contains("--x:  1  2") == true)
    }
    func testLimitsCancellationAndNoExecution() async {
        let tooLarge=await result(.javascript,String(repeating:"a",count:262145));XCTAssertEqual(tooLarge.status,"resourceLimit")
        let c=MarkupCancellation();c.cancel();let cancelled=await MarkupProcessor.process(.init(tool:.sql,source:"select a from t"),cancellation:c);XCTAssertEqual(cancelled.status,"cancelled")
        let script=await result(.javascript,"while(true){}; fetch('https://example.invalid'); eval('throw 1')");XCTAssertTrue(script.succeeded)
        let following=await result(.sql,"select 1");XCTAssertTrue(following.succeeded)
    }
}

extension CodeMarkupCoreTests {
    func testEverySQLDialectAndQuotedProcedure() async {
        for dialect in MarkupOptions.dialects { var o=MarkupOptions();o.dialect=dialect;let r=await result(.sql,"SELECT value FROM sample WHERE value = 1",options:o);XCTAssertTrue(r.succeeded,"\(dialect): \(r)") }
        var o=MarkupOptions();o.dialect="postgresql"
        let r=await result(.sql,"select $$CREATE FUNCTION example()$$",options:o);XCTAssertTrue(r.succeeded)
        let unsupported=await result(.sql,"DELIMITER $$\nCREATE PROCEDURE test() BEGIN SELECT 1; END");XCTAssertEqual(unsupported.status,"unsupported")
    }
    func testPostgreSQLCastsCTEAndAggregateFilters() async {
        let source = """
        WITH cop_events AS (
        SELECT
        unnest(o.registration_ids) AS registration_id,
        rr.account_type, rr.reason_code, rr.request_data, rr.created_utc
        FROM "Reporting".reporting_records AS rr
        JOIN "Reporting".organisations o ON o.id = rr.organisation_id
        WHERE rr.created_utc >= make_date(2025, 8, 1)
        AND rr.created_utc < (make_date(2025, 8, 1) + interval '1 month')
        and rr.reason_code <>'MAINTENANCE'
        )
        SELECT
        registration_id::int,
        COUNT(*) FILTER (WHERE account_type = 'Personal') AS "Requests with a Personal Account marker",
        0::int AS "Personal Account - Beneficiary set up complete & payment complete in same session",
        COUNT(*) FILTER (WHERE account_type = 'Business') AS "Requests with a Business Account marker",
        COUNT(*) FILTER (WHERE reason_code = 'MATCH') AS "TRUE",
        COUNT(*) FILTER (WHERE reason_code = 'TIMEOUT')"Responses outside of response time SLA"
        FROM cop_events
        GROUP BY registration_id
        ORDER BY registration_id;
        """
        let standard = await result(.sql,source)
        XCTAssertEqual(standard.status,"invalid")
        XCTAssertNil(standard.output)
        var options=MarkupOptions();options.dialect="postgresql"
        let formatted=await result(.sql,source,options:options)
        XCTAssertTrue(formatted.succeeded,"\(formatted)")
        let output=formatted.output ?? ""
        for token in ["registration_id::int", "0::int", "'1 month'", "'MAINTENANCE'", "'Personal'", "'Business'", "'TIMEOUT'", "\"Reporting\"", "\"Responses outside of response time SLA\""] {
            XCTAssertTrue(output.contains(token),"Missing preserved token: \(token)")
        }
        XCTAssertEqual(output.components(separatedBy:"FILTER").count-1,4)
        let again=await result(.sql,output,options:options)
        XCTAssertTrue(again.succeeded)
        XCTAssertEqual(again.output,formatted.output)
    }

    @MainActor func testSQLDialectSwitchPreservesInputAndPreference() async throws {
        let suite="toolbox.sql-test."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let w=MarkupWorkspace(.sql,defaults:defaults)
        XCTAssertEqual(w.options.dialect,"sql")
        w.input="SELECT registration_id::int FROM events;"
        w.run();while w.busy {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(w.result?.status,"invalid")
        w.options.dialect="postgresql"
        XCTAssertEqual(w.input,"SELECT registration_id::int FROM events;")
        XCTAssertNil(w.result)
        w.run();while w.busy {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(w.result?.succeeded == true)
        let fresh=MarkupWorkspace(.sql,defaults:defaults)
        XCTAssertEqual(fresh.options.dialect,"postgresql")
        XCTAssertTrue(fresh.input.isEmpty)
        XCTAssertTrue(fresh.output.isEmpty)
        XCTAssertNil(fresh.result)
        XCTAssertEqual(Set(MarkupOptions.dialects.map(MarkupOptions.dialectName)).count,19)
    }

    func testHTMLWhitespaceAndFragmentContexts() async {
        for source in ["<span>a</span> <span>b</span>","<pre>  a\n b  </pre>","<script>var a = 'x  y';</script>","<textarea> a\n b </textarea>"] {
            let r=await result(.html,source);XCTAssertTrue(r.succeeded,"\(r)")
        }
        var o=MarkupOptions();o.fragmentContext="tr"
        let preview=await result(.preview,"<td>cell</td>",options:o);XCTAssertTrue(preview.preview?.contains("<tr><td>cell</td></tr>") == true)
        let duplicate=await result(.html,"<p id='1' id='2'>text</p>");XCTAssertEqual(duplicate.status,"unsupported")
    }
    func testJSSemanticsAndUnsupportedProfiles() async {
        for source in ["'use strict'; const x=-0;", "const p=/[a-z]+/giu;", "const t=String.raw`a\\nb`;", "class X { #x=1; get(){ return this?.#x; } }", "function f(){return\n{x:1}}", "const emoji='😀é';"] {
            for op in ["format","minify"] {let r=await result(.javascript,source,op);XCTAssertTrue(r.succeeded,"\(r)")}
        }
        var o=MarkupOptions();o.module=true
        let module=await result(.javascript,"export const x=1; import y from 'never-fetch';",options:o);XCTAssertTrue(module.succeeded)
        let ts=await result(.javascript,"const n: number=1;");XCTAssertEqual(ts.status,"invalid")
    }
    func testMJMLDiagnosticsAndIncludes() async {
        let r=await result(.mjml,"<mjml>\n<mj-body><mj-text>x</mj-text></mj-body></mjml>")
        XCTAssertEqual(r.status,"invalid");XCTAssertEqual(r.diagnostics.first?.line,2)
        let include=await result(.mjml,"<mjml><mj-body><mj-include path='file:///secret'/></mj-body></mjml>")
        XCTAssertEqual(include.status,"unsupported")
        let inline=await result(.mjml,"<mjml><mj-head><mj-style inline='inline'>.red { color: red; }</mj-style></mj-head><mj-body><mj-section><mj-column><mj-text css-class='red'>Hello</mj-text></mj-column></mj-section></mj-body></mjml>")
        XCTAssertTrue(inline.succeeded,"\(inline)");XCTAssertNotNil(inline.preview)
    }
    func testYAMLCustomTagsCyclicAliasAndUnicode() async {
        for source in ["a: &a [*a]", "name: !custom '😀 é'", "? [a, b]\n: value", "a: >-\n  hello\n  world\n", "a: 1.23456789012345678901234567890\r\nb: 1e+100\r\n"] {
            let r=await result(.yaml,source);XCTAssertTrue(r.succeeded,"\(r)")
        }
    }
    func testPreviewAdversarialCSSAndHTML() async {
        let fixtures=[
            "<svg><foreignObject><script>alert(1)</script></foreignObject></svg>",
            "<math><mtext><table><mglyph><style><!--</style><img src=x onerror=alert(1)>",
            "<style>p{background: image-set('https://example.invalid/a' 1x);--x:url(https://example.invalid);animation:test 1s infinite}</style><p>ok</p>",
            "<style>p{font-family:'</style><script>alert(1)</script>'}</style>",
            "<form action='https://example.invalid'><input autofocus value='x'><button>Send</button></form>",
            "<meta http-equiv=refresh content='0;url=https://example.invalid'><link rel=preload href='https://example.invalid/a'>"
        ]
        for source in fixtures {
            let r=await result(.preview,source);XCTAssertTrue(r.succeeded,"\(r)")
            let h=r.preview ?? "";XCTAssertFalse(h.contains("<script"));XCTAssertFalse(h.contains("onerror="));XCTAssertFalse(h.contains("https://example.invalid"));XCTAssertFalse(h.contains("autofocus"));XCTAssertFalse(h.contains("animation:"))
        }
    }
    func testXMLPreserveTextAndDepth() async {
        var o=MarkupOptions();o.preserveXMLText=true
        let r=await result(.xml,"<r a=\"😀\" b='v'>  <n/> </r>",options:o)
        XCTAssertTrue(r.succeeded);XCTAssertTrue(r.output?.contains("a=\"😀\"") == true);XCTAssertTrue(r.output?.contains(">  <n/> </r>") == true)
        let deep=await result(.xml,String(repeating:"<r>",count:129)+String(repeating:"</r>",count:129));XCTAssertEqual(deep.status,"resourceLimit")
        let encoding=await result(.xml,"<?xml version='1.0' encoding='ISO-8859-1'?><r/>");XCTAssertEqual(encoding.status,"unsupported")
        let token=MarkupCancellation();token.cancel();let cancelled=await MarkupProcessor.process(.init(tool:.xml,source:"<r/>"),cancellation:token);XCTAssertEqual(cancelled.status,"cancelled")
    }
    @MainActor func testWorkspaceRevisionOutputAndPrivacy() async throws {
        let suite="toolbox.markup-test."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let w=MarkupWorkspace(.yaml,defaults:defaults);w.options.live=false;w.input="a: [1,2]";w.run()
        while w.busy {try await Task.sleep(for:.milliseconds(10))}
        let formatted=w.output;XCTAssertFalse(formatted.isEmpty)
        w.run("validate");while w.busy {try await Task.sleep(for:.milliseconds(10))};XCTAssertEqual(w.output,formatted)
        w.cancel();XCTAssertEqual(w.output,formatted)
        w.run();w.input="b: 3";try await Task.sleep(for:.milliseconds(500));XCTAssertNil(w.result);XCTAssertTrue(w.output.isEmpty)
        w.options.indent=4;w.options.wrap=false
        let fresh=MarkupWorkspace(.yaml,defaults:defaults);XCTAssertEqual(fresh.options.indent,4);XCTAssertFalse(fresh.options.wrap);XCTAssertTrue(fresh.input.isEmpty);XCTAssertTrue(fresh.output.isEmpty);XCTAssertNil(fresh.snapshot)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter{$0.hasPrefix("codeMarkup.")}.count,1)
    }
}
