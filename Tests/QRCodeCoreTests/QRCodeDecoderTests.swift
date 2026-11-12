import Foundation
import Testing
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import QRCodeCore

struct QRCodeDecoderTests {
    static func image(_ data: Data, side: Int = 512) throws -> CGImage {
        let filter = CIFilter(name:"CIQRCodeGenerator")!
        filter.setValue(data,forKey:"inputMessage"); filter.setValue("M",forKey:"inputCorrectionLevel")
        let ci = try #require(filter.outputImage)
        let scale = max(1,side/Int(ci.extent.width))
        return try #require(CIContext(options:[.useSoftwareRenderer:true]).createCGImage(ci.transformed(by:CGAffineTransform(scaleX:CGFloat(scale),y:CGFloat(scale))),from:CGRect(x:0,y:0,width:ci.extent.width*CGFloat(scale),height:ci.extent.height*CGFloat(scale))))
    }
    static func scan(_ data: Data) throws -> QRDecodedItem {
        let result = try QRCodeDecoderProcessor.scan(.init(image:image(data)))
        #expect(result.items.count == 1)
        return try #require(result.items.first)
    }
    @Test func exactUTF8AndNUL() throws {
        for value in ["hello","https://example.com/a?x=%2F&x=1","👩🏽‍💻 e\u{301} 中文\r\n\t","\0before","a\0b","after\0"] {
            let item = try Self.scan(Data(value.utf8))
            #expect(item.bytes == Data(value.utf8)); #expect(item.text?.utf8.elementsEqual(value.utf8) == true)
            #expect(QRDecodedPresentation.copy(item,as:.base64) == Data(value.utf8).base64EncodedString())
        }
    }
    @Test func binaryAndEmpty() throws {
        for data in [Data(0...255),Data([0xFF,0xFE,0x80]),Data()] {
            let item = try Self.scan(data)
            #expect(item.bytes == data)
            if item.text != nil && !data.isEmpty { #expect(item.interpretation == "Encoding inferred by reader") }
        }
    }
    static func collage(count: Int = 3) throws -> CGImage {
        let cols = min(11,count), rows = (count+cols-1)/cols, cell = 320
        let ctx = try #require(CGContext(data:nil,width:cols*cell,height:rows*cell,bitsPerComponent:8,bytesPerRow:cols*cell*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:cols*cell,height:rows*cell))
        ctx.interpolationQuality = .none
        for i in 0..<count {
            let qr = try image(Data((i == 1 ? "same" : i == 0 ? "same" : "code-\(i)").utf8),side:240)
            ctx.draw(qr,in:CGRect(x:(i%cols)*cell+(cell-qr.width)/2,y:(rows-1-i/cols)*cell+(cell-qr.height)/2,width:qr.width,height:qr.height))
        }
        return try #require(ctx.makeImage())
    }
    @Test func multipleAndGeometry() throws {
        let source = QRDecodeSource(image:try Self.collage())
        let result = try QRCodeDecoderProcessor.scan(source)
        #expect(result.items.count == 3)
        #expect(result.items.filter { $0.text == "same" }.count == 2)
        for item in result.items { #expect(item.bounds.width > 180); #expect(item.bounds.height > 180); #expect(item.corners.count == 4) }
        #expect(result.items[0].bounds.minX < result.items[1].bounds.minX)
    }
    @Test func loaderLimitsTypesAndSourceSnapshot() throws {
        let data = try QRCodeRenderer.png(Self.image(Data("loader".utf8)))
        let source = try QRCodeDecoderImageLoader.decode(data)
        #expect(source.format == "PNG"); #expect(source.originalWidth == source.image.width)
        #expect(try QRCodeDecoderProcessor.scan(source).items.first?.text == "loader")
        #expect(throws:QRDecodeIssue.self) { try QRCodeDecoderImageLoader.decode(Data("not image".utf8)) }
        #expect(throws:QRDecodeIssue.self) { try QRCodeDecoderImageLoader.decode(Data(repeating:0,count:QRDecodeBudget.encodedBytes+1)) }
    }
    @Test func exportsDoNotChangeBytesOrText() throws {
        let value = "\0 hello \r\n👋 \0"
        let item = try Self.scan(Data(value.utf8))
        #expect(QRDecodedExport(item:item,text:false)?.data == Data(value.utf8))
        #expect(QRDecodedExport(item:item,text:true)?.data == Data(value.utf8))
        let display = QRDecodedPresentation.safeText(value)
        #expect(QRDecodedPresentation.safeText("👩🏽‍💻 e\u{301}") == "👩🏽‍💻 e\u{301}")
        #expect(display != value); #expect(display.contains("\\0"))
        #expect(QRDecodedPresentation.copy(item,as:.text) == value)
        #expect(!QRDecodedPresentation.safeText("a\u{202E}b").contains("\u{202E}"))
        #expect(QRDecodedPresentation.hex(Data([0,0xAF,255])) == "00AFFF")
    }
    @Test func noCodesAndCancellation() async throws {
        let context = try #require(CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0))
        #expect(try QRCodeDecoderProcessor.scan(.init(image:#require(context.makeImage()))).items.isEmpty)
        let image = try Self.image(Data("cancel".utf8))
        let task = Task { try Task.checkCancellation(); return try QRCodeDecoderProcessor.scan(.init(image:image)) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation ignored") } catch is CancellationError {} catch { Issue.record("Wrong status") }
    }
    @Test @MainActor func sessionLifecycleAndPrivacy() async throws {
        let session = QRCodeDecoderWorkspaceSession()
        let data = try QRCodeRenderer.png(Self.image(Data("session".utf8)))
        session.importData(data)
        for _ in 0..<300 where session.busy { try await Task.sleep(for:.milliseconds(10)) }
        #expect(session.canOutput); #expect(session.selected?.text == "session")
        let sourceID = session.source?.id
        session.scanAgain(); session.cancel()
        #expect(session.canOutput); #expect(session.source?.id == sourceID)
        session.importData(Data("invalid".utf8))
        for _ in 0..<100 where session.busy { try await Task.sleep(for:.milliseconds(10)) }
        #expect(session.canOutput); #expect(session.selected?.text == "session")
        session.clear(); #expect(session.source == nil); #expect(session.snapshot == nil)
        #expect(QRCodeDecoderWorkspaceSession().source == nil)
    }
    @Test @MainActor func staleProviderCannotResurrectAfterClear() async throws {
        let session = QRCodeDecoderWorkspaceSession()
        let source = QRDecodeSource(image:try Self.image(Data("slow".utf8)))
        session.importImage { try? await Task.sleep(for:.milliseconds(100)); return source }
        try await Task.sleep(for:.milliseconds(10)); session.clear()
        try await Task.sleep(for:.milliseconds(180))
        #expect(session.snapshot == nil); #expect(session.source == nil); #expect(!session.busy)
        session.importImage { try? await Task.sleep(for:.milliseconds(60)); return source }
        let next = QRDecodeSource(image:try Self.image(Data("new".utf8)))
        session.importImage { next }
        for _ in 0..<300 where session.busy { try await Task.sleep(for:.milliseconds(10)) }
        #expect(session.selected?.text == "new")
    }
}

extension QRCodeDecoderTests {
    actor WorkerCounter {
        var active = 0, maximum = 0, calls = 0
        func begin() { active += 1; calls += 1; maximum = max(maximum,active) }
        func end() { active -= 1 }
        func values() -> (Int,Int) { (calls,maximum) }
    }
    @Test @MainActor func rapidRequestsAreBoundedAndLatestWins() async throws {
        let first = QRDecodeSource(image:try Self.image(Data("first".utf8)))
        let last = QRDecodeSource(image:try Self.image(Data("last".utf8)))
        let initial = try QRCodeDecoderProcessor.scan(first), final = try QRCodeDecoderProcessor.scan(last)
        let counter = WorkerCounter()
        let session = QRCodeDecoderWorkspaceSession { source,_ in
            await counter.begin()
            try? await Task.sleep(for:.milliseconds(100)) // Deliberately uncooperative worker.
            await counter.end()
            return source.id == first.id ? initial : final
        }
        session.importImage { first }
        try await Task.sleep(for:.milliseconds(20))
        for _ in 0..<20 { session.importImage { last } }
        for _ in 0..<100 where session.busy { try await Task.sleep(for:.milliseconds(10)) }
        let values = await counter.values()
        #expect(values.0 <= 2); #expect(values.1 == 1)
        #expect(session.source?.id == last.id); #expect(session.selected?.text == "last")
        #expect(session.canOutput)
    }
    @Test @MainActor func changingSurfaceInvalidatesAndClearDiscardsUncooperativeScan() async throws {
        let source = QRDecodeSource(image:try Self.image(Data("snapshot".utf8)))
        let result = try QRCodeDecoderProcessor.scan(source)
        let session = QRCodeDecoderWorkspaceSession { _,_ in
            try? await Task.sleep(for:.milliseconds(80)); return result
        }
        session.importImage { source }
        try await Task.sleep(for:.milliseconds(15)); session.clear()
        try await Task.sleep(for:.milliseconds(120))
        #expect(session.snapshot == nil); #expect(session.source == nil)
        session.importImage { source }
        for _ in 0..<100 where session.busy { try await Task.sleep(for:.milliseconds(10)) }
        session.setSurface(.dark)
        #expect(!session.canOutput)
        session.cancel()
        #expect(!session.canOutput) // The old white-surface check is not current for Dark.
    }
}
