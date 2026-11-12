import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import EncodingCore

struct Base64FileImageTests {
    @Test func boundedRasterFirstImageAndMIMEMismatch() throws {
        let context = try #require(CGContext(data:nil,width:2,height:3,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try #require(context.makeImage()), bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,cg,nil); #expect(CGImageDestinationFinalize(destination))
        let preview = Base64FileImagePreview.make(bytes as Data,declared:"image/jpeg")
        #expect(preview.image?.width == 2 && preview.image?.height == 3 && preview.message.contains("differs"))
        #expect(preview.mime == "image/png")
        #expect(Base64FileImagePreview.make(Data(),declared:nil).message.contains("Zero-byte"))
        #expect(Base64FileImagePreview.make(nil,declared:nil).image == nil)
        #expect(Base64FileImagePreview.make(Data(repeating:0,count:8*1024*1024+1),declared:nil).image == nil)
        for bytes in [Data("<svg><script/></svg>".utf8), Data("<html/>".utf8), Data([137,80,78,71,13,10,26,10])] {
            #expect(Base64FileImagePreview.make(bytes,declared:"image/png").image == nil)
        }
    }
    @Test func oversizedTIFFHeaderNeverDecodesPixels() {
        // Valid tiny-in-bytes grayscale TIFF: oversized width, rejected before thumbnail decoding.
        var bytes = Data([0x49,0x49,42,0,8,0,0,0])
        func append16(_ value: UInt16) { bytes.append(UInt8(truncatingIfNeeded:value)); bytes.append(UInt8(truncatingIfNeeded:value>>8)) }
        func append32(_ value: UInt32) { for shift in [0,8,16,24] { bytes.append(UInt8(truncatingIfNeeded:value>>shift)) } }
        let fields:[(UInt16,UInt16,UInt32)] = [(256,4,40000),(257,4,1),(258,3,8),(259,3,1),(262,3,1),(273,4,122),(277,3,1),(278,4,1),(279,4,40000)]
        append16(UInt16(fields.count))
        for (tag,type,value) in fields { append16(tag); append16(type); append32(1); append32(value) }
        append32(0); bytes.append(Data(repeating: 0,count: 40_000))
        let result = Base64FileImagePreview.make(bytes,declared:"image/tiff")
        #expect(result.image == nil)
        #expect(result.message.contains("dimensions"))
    }
}
