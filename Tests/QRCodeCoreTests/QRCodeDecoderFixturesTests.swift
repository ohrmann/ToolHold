import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import QRCodeCore

struct QRCodeDecoderFixturesTests {
    struct Manifest: Decodable {
        struct Fixture: Decodable { let name: String; let bytesHex: String?; let text: String?; let eci: Bool? }
        let cases: [Fixture]
    }
    static var directory: URL { Bundle.module.url(forResource:"DecoderFixtures",withExtension:nil)! }
    static func fixture(_ name: String) throws -> Data { try Data(contentsOf:directory.appendingPathComponent(name+".png")) }
    @Test func independentlyEncodedModesAndECI() throws {
        let manifest = try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:Self.directory.appendingPathComponent("manifest.json")))
        for fixture in manifest.cases where fixture.bytesHex != nil {
            let snapshot = try QRCodeDecoderProcessor.scan(QRCodeDecoderImageLoader.decode(Self.fixture(fixture.name)))
            let item = try #require(snapshot.items.first,"Missing fixture \(fixture.name)")
            #expect(item.readable, "Unreadable fixture \(fixture.name)")
            #expect(item.bytes.map(QRDecodedPresentation.hex)?.lowercased() == fixture.bytesHex, "Bytes \(fixture.name)")
            if let text = fixture.text { #expect(item.text?.utf8.elementsEqual(text.utf8) == true,"Text \(fixture.name): \(item.interpretation)") }
            if fixture.eci == true { #expect(item.hasECI) }
            if fixture.name == "unknown-eci" { #expect(item.text == nil) }
        }
    }
    @Test func sequenceSegmentsAreNotAssembled() throws {
        var values: [String] = []
        for index in 0..<2 {
            let result = try QRCodeDecoderProcessor.scan(QRCodeDecoderImageLoader.decode(Self.fixture("sequence-\(index)")))
            let item = try #require(result.items.first)
            #expect(item.sequenceCount == 2); #expect(item.sequenceIndex == index)
            #expect(item.kind == "Sequence segment")
            values.append(try #require(item.text))
        }
        #expect(values.joined() == "structured append example for decoder")
    }
    @Test func rotatedAndMirroredOrientations() throws {
        let data = try Self.fixture("utf8-eci")
        let original = try #require(CGImageSourceCreateWithData(data as CFData,nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(original,0,nil))
        for orientation in 1...8 {
            let bytes = NSMutableData()
            let dest = try #require(CGImageDestinationCreateWithData(bytes,UTType.tiff.identifier as CFString,1,nil))
            CGImageDestinationAddImage(dest,image,[kCGImagePropertyOrientation:orientation] as CFDictionary)
            #expect(CGImageDestinationFinalize(dest))
            let source = try QRCodeDecoderImageLoader.decode(bytes as Data)
            let result = try QRCodeDecoderProcessor.scan(source)
            #expect(result.items.first?.text == "👩🏽‍💻 e\u{301} 中文","Orientation \(orientation)")
        }
    }
    @Test func multiPageAndOversizedDimensionsRejected() throws {
        for name in ["side-too-large","pixels-too-large"] {
            do { _ = try QRCodeDecoderImageLoader.decode(Self.fixture(name)); Issue.record("Budget accepted") }
            catch let error as QRDecodeIssue { #expect(error.kind == .resource) }
        }
        let source = try QRCodeDecoderImageLoader.decode(Self.fixture("numeric"))
        let data = NSMutableData(), dest = try #require(CGImageDestinationCreateWithData(data,UTType.tiff.identifier as CFString,2,nil))
        CGImageDestinationAddImage(dest,source.image,nil); CGImageDestinationAddImage(dest,source.image,nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(throws:QRDecodeIssue.self) { try QRCodeDecoderImageLoader.decode(data as Data) }
    }
    @Test func largeCollageAndResultLimit() throws {
        let result = try QRCodeDecoderProcessor.scan(.init(image:QRCodeDecoderTests.collage(count:101)))
        #expect(result.items.count == 100); #expect(result.limited)
        #expect(result.items.allSatisfy { $0.readable })
    }
    @Test func sourceCoordinatesAcrossRows() throws {
        let result = try QRCodeDecoderProcessor.scan(.init(image:QRCodeDecoderTests.collage(count:12)))
        #expect(result.items.count == 12)
        let bottom = try #require(result.items.first { $0.text == "code-11" })
        let top = try #require(result.items.first { $0.text == "code-10" })
        #expect(bottom.bounds.midY > top.bounds.midY)
    }
    @Test func transparencyAndInverse() throws {
        var p = QRPreferences(); p.opacity = 0
        let matrix = try QRCodeEncoder.encode("alpha exact",correction:.m)
        let geometry = try QRGeometry(matrix:matrix,preferences:p,hasLogo:false)
        let image = try QRCodeRenderer.image(geometry,logo:nil,target:512)
        let snapshot = try QRCodeDecoderProcessor.scan(.init(image:image),surface:.white)
        #expect(snapshot.items.first?.text == "alpha exact")
        p.foreground = .white; p.background = .black; p.opacity = 1
        let inverted = try QRCodeRenderer.image(QRGeometry(matrix:matrix,preferences:p,hasLogo:false),logo:nil,target:512)
        #expect(try QRCodeDecoderProcessor.scan(.init(image:inverted)).items.first?.text == "alpha exact")
    }
    @Test func fileReadIsBoundedAndLocal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let file = dir.appendingPathComponent("not-the-extension.txt"), bytes = try Self.fixture("numeric")
        try bytes.write(to:file)
        #expect(try QRCodeDecoderImageLoader.readFile(file) == bytes)
        #expect(try QRCodeDecoderImageLoader.decode(QRCodeDecoderImageLoader.readFile(file)).format == "PNG")
        #expect(throws:(any Error).self) { try QRCodeDecoderImageLoader.readFile(dir) }
        #expect(throws:QRDecodeIssue.self) { try QRCodeDecoderImageLoader.readFile(URL(string:"https://example.com/qr.png")!) }
    }
}
