import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import QRCodeCore

struct QRCodeTests {
    @Test func exactPayloadsAndStyles() throws {
        for source in ["Hello", "https://example.com/?a=1&b=%20", "Привет 🌍 中文", "e\u{301} é", "a\r\nb\u{0}", "  \n", "12345678901234567890"] {
            for level in QRCorrection.allCases {
                var p = QRPreferences(); p.correction = level
                let original = try QRCodeProcessor.generate(source:source,preferences:p,logo:nil)
                #expect(original.matrix.payload == Data(source.utf8)); #expect(original.verification.passed)
                for style in QRModuleStyle.allCases {
                    p.style = style
                    let a = try QRCodeProcessor.generate(source:source,preferences:p,logo:nil,previous:original)
                    #expect(a.verification.passed, "\(source.debugDescription) \(level) \(style)")
                }
            }
        }
    }
    @Test func geometryVersions() throws {
        for v in 1...40 {
            let n = v*4+17, mask = try QRCodeEncoder.functionMask(version:v)
            #expect(mask.count == n*n)
            #expect(mask[0] && mask[8*n+8] && mask[(n-1)*n+6] && mask[6*n+n-1])
            if v >= 2 { #expect(mask[(n-7)*n+n-7]) }
            if v >= 7 { #expect(mask[n-11]); #expect(mask[(n-11)*n]) }
        }
        let m = try QRCodeEncoder.functionMask(version:32), n = 145
        for c in [6,34,60,86,112,138] { #expect(m[60*n+c]) }
    }
}

extension QRCodeTests {
    static func logo(width: Int = 128, height: Int = 64) throws -> QRLogo {
        let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(QRColor(0.8,0.1,0.2).cg()); c.fill(CGRect(x:0,y:0,width:width/2,height:height))
        c.setFillColor(QRColor(0.1,0.2,0.8).cg()); c.fill(CGRect(x:width/2,y:0,width:width/2,height:height))
        let image = c.makeImage()!
        return QRLogo(image:image,png:try QRCodeRenderer.png(image))
    }
    @Test func boundariesAndCorrection() throws {
        #expect(throws: QRIssue.self) { try QRCodeEncoder.encode("",correction:.m) }
        #expect(throws: QRIssue.self) { try QRCodeEncoder.encode(String(repeating:"x",count:32769),correction:.l) }
        #expect(throws: QRIssue.self) { try QRCodeEncoder.encode(String(repeating:"x",count:4000),correction:.h) }
        // Core Image uses byte mode for this input; test real boundary, without a numeric-mode assumption.
        let maximum = try QRCodeEncoder.encode(String(repeating:"x",count:2953),correction:.l)
        #expect(maximum.version == 40 && maximum.size == 177)
        #expect(throws: QRIssue.self) { try QRCodeEncoder.encode(String(repeating:"x",count:2954),correction:.l) }
        #expect(throws: QRIssue.self) { try QRCodeEncoder.functionMask(version:41) }
    }
    @Test func transparentSurfaceAndMismatch() throws {
        var p = QRPreferences(); p.opacity = 0
        let a = try QRCodeProcessor.generate(source:"surface fixture",preferences:p,logo:nil)
        #expect(a.verification == .readable(conditional:true))
        #expect(try QRCodeVerifier.verify(a.image,matrix:a.matrix,preferences:p,reference:a.reference).passed)
        p.surface = .dark
        let b = try QRCodeProcessor.generate(source:"surface fixture",preferences:p,logo:nil,previous:a)
        #expect(b.verification == .readable(conditional:true) || b.verification == .unavailable)
        #expect(p.contrastWarning)
        let other = try QRCodeProcessor.generate(source:"other payload",preferences:QRPreferences(),logo:nil)
        #expect(try QRCodeVerifier.verify(other.image,matrix:a.matrix,preferences:QRPreferences(),reference:a.reference) == .mismatch)
        p.foreground = .white; p.background = .white; p.opacity = 1
        #expect(try QRCodeProcessor.generate(source:"white fixture",preferences:p,logo:nil).verification == .unavailable)
        #expect(p.contrastWarning)
    }
    @Test func logoCaptureGeometryAndDecode() throws {
        let logo = try Self.logo()
        let decoded = try QRCodeLogoLoader.decode(logo.png)
        #expect(decoded.image.width == 128 && decoded.image.height == 64)
        #expect(throws:QRIssue.self) { try QRCodeLogoLoader.decode(Data("not an image".utf8)) }
        #expect(throws:QRIssue.self) { try QRCodeLogoLoader.decode(Data(repeating:0,count:8*1024*1024+1)) }
        #expect(throws:QRIssue.self) { try QRCodeLogoLoader.load(URL(string:"https://example.com/logo.png")!) }
        var p = QRPreferences(); p.style = .rounded
        let a = try QRCodeProcessor.generate(source:"https://example.com/logo",preferences:p,logo:logo)
        #expect(a.matrix.correction == .h && a.verification.passed)
        let g = a.geometry, rect = try #require(g.logoRect(logo.image))
        #expect(abs(rect.width/rect.height-2) < 0.001)
        #expect(g.logoCells.allSatisfy { !g.protected[Int($0.minY)*a.matrix.size+Int($0.minX)] })
        // Central alignment markers must now be completely OUTSIDE the logo area.
        let large = try QRCodeEncoder.encode(String(repeating:"x",count:110),correction:.h)
        var foundAdjustment = false
        for amount in [0.15,0.2] {
            p.logoSize = amount
            if let g = try? QRGeometry(matrix:large,preferences:p,hasLogo:true) {
                foundAdjustment = foundAdjustment || g.logoMoved || g.logoReduced
                for y in 0..<large.size { for x in 0..<large.size where g.isLogoCell(x,y) { #expect(!g.protected[y*large.size+x]) } }
            }
        }
        #expect(foundAdjustment)
        p.logoPadding = 2
        let tiny = try QRCodeEncoder.encode("a",correction:.h)
        #expect(throws:QRIssue.self) { try QRGeometry(matrix:tiny,preferences:p,hasLogo:true) }
    }
    @Test func pngSVGAndPixels() throws {
        var p = QRPreferences(); p.opacity = 0; p.style = .rounded
        let a = try QRCodeProcessor.generate(source:"PNG and SVG",preferences:p,logo:Self.logo())
        for format in QRExportFormat.allCases {
            let output = try QRCodeProcessor.export(a,format:format)
            #expect(output.side == a.side)
            if format == .png {
                let src = CGImageSourceCreateWithData(output.data as CFData,nil)!
                let image = CGImageSourceCreateImageAtIndex(src,0,nil)!
                #expect(image.width == a.side)
                let props = CGImageSourceCopyPropertiesAtIndex(src,0,nil) as! [CFString:Any]
                let exif = props[kCGImagePropertyExifDictionary] as? [String:Any] ?? [:]
                #expect(Set(exif.keys).isSubset(of:["ColorSpace","PixelXDimension","PixelYDimension"]))
                #expect(props[kCGImagePropertyGPSDictionary] == nil)
            } else {
                let s = String(decoding:output.data,as:UTF8.self)
                #expect(s.contains("data:image/png;base64,")); #expect(s.contains("clipPath"))
                #expect(!s.contains("PNG and SVG") && !s.contains("<script") && !s.contains("https://"))
            }
        }
        var square = QRPreferences(); square.exportSize = 512
        let m = try QRCodeEncoder.encode("pixel fixture",correction:.m)
        let image = try QRCodeRenderer.image(QRGeometry(matrix:m,preferences:square,hasLogo:false),logo:nil,target:512)
        let n = m.size, side = image.width, scale = side/(n+8)
        let c = CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image,in:CGRect(x:0,y:0,width:side,height:side))
        let bytes = c.data!.assumingMemoryBound(to:UInt8.self)
        for y in 0..<(n+8) { for x in 0..<(n+8) {
            let offset = ((y*scale+scale/2)*side+x*scale+scale/2)*4
            let dark = (4..<(n+4)).contains(x) && (4..<(n+4)).contains(y) ? m.dark[(y-4)*n+x-4] : false
            #expect(bytes[offset] == (dark ? 0 : 255)); #expect(bytes[offset+3] == 255)
        } }
    }
    @Test func cancellationAndPreferences() async throws {
        var p = QRPreferences(); p.rounding = .nan; #expect(!p.valid)
        p = .init(); p.opacity = 2; #expect(!p.valid)
        #expect(QRColor(hex:"#123abc")?.hex == "#123ABC"); #expect(QRColor(hex:"xyz") == nil)
        let task = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try QRCodeEncoder.encode("cancel",correction:.m); return false } catch is CancellationError { return true } catch { return false }
        }
        task.cancel(); #expect(await task.value)
    }
}

extension QRCodeTests {
    @Test func denseSymbolCanBeCheckedAtExportSize() throws {
        var p = QRPreferences(); p.correction = .q; p.exportSize = 2048
        let a = try QRCodeProcessor.generate(source:String(repeating:"x",count:1663),preferences:p,logo:nil)
        #expect(a.matrix.version == 40)
        #expect(a.verification.passed)
        #expect(a.image.width <= 1200)
        #expect(try QRCodeProcessor.export(a,format:.png).side >= 2048)
    }
    @Test func logoOrientationAndSanitization() throws {
        let logo = try Self.logo()
        let bytes = NSMutableData()
        let dest = CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(dest,logo.image,[kCGImagePropertyOrientation:6,kCGImagePropertyExifDictionary:["UserComment":"synthetic-private-comment"],kCGImagePropertyGPSDictionary:["Latitude":12.5,"Longitude":45.0]] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let loaded = try QRCodeLogoLoader.decode(bytes as Data)
        #expect(loaded.image.width == 64 && loaded.image.height == 128)
        let src = CGImageSourceCreateWithData(loaded.png as CFData,nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src,0,nil) as! [CFString:Any]
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyExifDictionary] as? [String:Any])?["UserComment"] == nil)
        #expect(!loaded.png.contains(Data("synthetic-private-comment".utf8)))
    }
}
