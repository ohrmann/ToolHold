import XCTest
import CQuickJS
import ImageIO
import UniformTypeIdentifiers
@testable import CodeMarkupCore

final class MarkupRuntimeTests: XCTestCase, @unchecked Sendable {
    // Trusted test-only code exercises the native interrupt boundary, never a user-source path.
    private func bridge(_ code: String, token: MarkupCancellation) -> Int32 {
        var status: Int32=0, length=0
        let result=code.withCString { b in "{}".withCString { r in
            tb_script_run(b,code.utf8.count,nil,0,r,2,token.pointer,&status,&length)
        }}
        tb_script_free(result);return status
    }
    func testHardDeadlineAndNativeCancellation() async throws {
        let clock=ContinuousClock(), start=clock.now, token=MarkupCancellation()
        let job=Task.detached {self.bridge("globalThis.ToolboxMarkup=()=>{while(true){}}",token:token)}
        try await Task.sleep(for:.milliseconds(80));token.cancel()
        let status=await job.value
        XCTAssertEqual(status,1);XCTAssertLessThan(start.duration(to:clock.now),.seconds(2))
        let deadlineStart=clock.now
        let timeout=await Task.detached {self.bridge("globalThis.ToolboxMarkup=()=>{while(true){}}",token:.init())}.value
        XCTAssertEqual(timeout,2);XCTAssertLessThan(deadlineStart.duration(to:clock.now),.seconds(7))
        let recovered=await MarkupProcessor.process(.init(tool:.javascript,source:"const answer = 42;"))
        XCTAssertTrue(recovered.succeeded)
    }
    func testImagesReencodedAndExportDoesNotLeakInternalURLs() throws {
        let context=try XCTUnwrap(CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg=try XCTUnwrap(context.makeImage()), data=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,cg,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image=try MarkupImage.decode(data as Data);XCTAssertEqual(image.pixels,4)
        XCTAssertThrowsError(try MarkupImage.decode(Data("<svg/>".utf8)))
        XCTAssertThrowsError(try MarkupImage.decode(Data(repeating:0,count:5*1024*1024+1)))
        let snapshot=MarkupPreviewSnapshot(nonce:"test",html:"<img src=\"toolbox-preview://test/a\"><img src=\"toolbox-preview://test/b\">",images:["a":image.png])
        XCTAssertTrue(snapshot.exportHTML.contains("data:image/png;base64,"));XCTAssertFalse(snapshot.exportHTML.contains("toolbox-preview:"))
    }
    @MainActor func testPasteDoesNotFormatAndPreviewNeverPublishesStaleRevision() async throws {
        let name="toolbox.markup.revision."+UUID().uuidString,defaults=UserDefaults(suiteName:name)!
        defer{defaults.removePersistentDomain(forName:name)}
        let sql=MarkupWorkspace(.sql,defaults:defaults);sql.input="select 1";sql.pasted(automatic:true)
        try await Task.sleep(for:.milliseconds(100));XCTAssertNil(sql.result);XCTAssertTrue(sql.output.isEmpty)
        let xml=MarkupWorkspace(.xml,defaults:defaults);xml.input="<r/>";xml.pasted(automatic:true)
        while xml.busy {try await Task.sleep(for:.milliseconds(10))};XCTAssertTrue(xml.result?.succeeded == true);XCTAssertTrue(xml.output.isEmpty)
        let preview=MarkupWorkspace(.markdown,defaults:defaults);preview.options.live=false;preview.input="# Old";preview.run();preview.input="# New";preview.run()
        while preview.busy{try await Task.sleep(for:.milliseconds(10))};XCTAssertTrue(preview.output.contains("New"));XCTAssertFalse(preview.output.contains("Old"))
        preview.input="changed";XCTAssertFalse(preview.canCopy);XCTAssertNil(preview.result)
    }
    func testLargeDocumentsAndRecovery() async {
        let cases:[(MarkupTool,String)]=[
            (.sql,String(repeating:"select a, b from items where a = 1;\n",count:6000)),
            (.xml,"<r>"+String(repeating:"<item>value</item>",count:14000)+"</r>"),
            (.yaml,(0..<13000).map{"key\($0): value\n"}.joined()),
            (.html,String(repeating:"<p>value</p>\n",count:18000)),
            (.css,String(repeating:".item { color: red; }\n",count:11000)),
            (.javascript,String(repeating:"value += 1;\n",count:21000)),
            (.markdown,String(repeating:"Paragraph **value**.\n\n",count:11000)),
            (.preview,String(repeating:"<p>value</p>\n",count:18000)),
            (.mjml,"<mjml><mj-body><mj-section><mj-column><mj-text>"+String(repeating:"text ",count:45000)+"</mj-text></mj-column></mj-section></mj-body></mjml>")]
        for (tool,source) in cases {
            XCTAssertLessThanOrEqual(source.utf16.count,262144)
            let start=ContinuousClock.now
            let result=await MarkupProcessor.process(.init(tool:tool,source:source))
            print("MARKUP_STRESS \(tool.rawValue) units=\(source.utf16.count) time=\(start.duration(to:.now)) status=\(result.status)")
            XCTAssertTrue(result.succeeded || result.status == "resourceLimit","Unexpected status for \(tool): \(result.status)")
            if result.status == "resourceLimit"{XCTAssertNil(result.output)}
            if tool == .preview && result.succeeded {XCTAssertNotNil(result.preview,"18000 elements fit the 50000-element preview budget")}
        }
        let last=await MarkupProcessor.process(.init(tool:.yaml,source:"recovered: true"));XCTAssertTrue(last.succeeded)
    }
}
