import Testing
import Foundation
import CoreGraphics
@testable import QRCodeCore

struct QRCodeLogoTests {
    @Test func safeLogoPlacementAcrossAllVersions() throws {
        for version in 1...40 {
            let n = version*4+17
            let matrix = QRMatrix(size:n,dark:Array(repeating:false,count:n*n),functional:try QRCodeEncoder.functionMask(version:version),payload:Data(),correction:.h)
            for fraction in [0.1,0.15,0.2] { for padding in [1,2] {
                var p = QRPreferences(); p.logoSize = fraction; p.logoPadding = padding
                var requested = Int((Double(n)*fraction).rounded(.down)); if requested%2 == 0 { requested -= 1 }
                if requested <= padding*2 {
                    #expect(throws:QRIssue.self) { try QRGeometry(matrix:matrix,preferences:p,hasLogo:true) }
                    continue
                }
                let g = try QRGeometry(matrix:matrix,preferences:p,hasLogo:true)
                let plate = try #require(g.plate)
                #expect(plate.width <= Double(requested) && plate.width > Double(padding*2))
                #expect(plate.minX >= 0 && plate.minY >= 0 && plate.maxX <= Double(n) && plate.maxY <= Double(n))
                let dx = plate.midX-Double(n)/2, dy = plate.midY-Double(n)/2
                #expect(dx*dx+dy*dy <= pow(ceil(Double(n)*0.15),2))
                let repeated = try QRGeometry(matrix:matrix,preferences:p,hasLogo:true)
                #expect(repeated.plate == plate) // Deterministic on the same matrix/settings.
                for y in Int(plate.minY)..<Int(plate.maxY) { for x in Int(plate.minX)..<Int(plate.maxX) {
                    #expect(!g.protected[y*n+x])
                } }
            } }
        }
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating:0,count:image.width*image.height*4)
        bytes.withUnsafeMutableBytes { raw in
            let c = CGContext(data:raw.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
            c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return bytes
    }

    @Test func transparentLogoClearsDataModulesAndPreservesFunctionalPixels() throws {
        let c = CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.clear(CGRect(x:0,y:0,width:32,height:32))
        let image = try #require(c.makeImage()), logo = QRLogo(image:image,png:try QRCodeRenderer.png(image))
        let matrix = try QRCodeEncoder.encode(String(repeating:"x",count:110),correction:.h)
        for opacity in [0.0,0.4,1.0] {
            var p = QRPreferences(); p.opacity = 0; p.logoSize = 0.2
            p.logoBackground = QRColor(0.9,0.2,0.1); p.logoBackgroundOpacity = opacity
            let g = try QRGeometry(matrix:matrix,preferences:p,hasLogo:true)
            let decorated = try QRCodeRenderer.image(g,logo:logo,target:512)
            let baseline = try QRCodeRenderer.image(QRGeometry(matrix:matrix,preferences:p,hasLogo:false),logo:nil,target:512)
            let actual = pixels(decorated), original = pixels(baseline), side = decorated.width, scale = side/(matrix.size+8)
            var removedDarkModules = 0
            for y in 0..<matrix.size { for x in 0..<matrix.size {
                let i = ((y+4)*scale+scale/2)*side*4+((x+4)*scale+scale/2)*4
                if g.isLogoCell(x,y) {
                    if matrix.dark[y*matrix.size+x] { removedDarkModules += 1 }
                    for (channel,expected) in [0.9*opacity,0.2*opacity,0.1*opacity,opacity].enumerated() {
                        #expect(abs(Double(actual[i+channel])-expected*255) <= 2,"Logo pixel opacity \(opacity)")
                    }
                } else {
                    #expect(actual[i..<(i+4)].elementsEqual(original[i..<(i+4)]))
                }
            } }
            #expect(removedDarkModules > 0) // Alpha zero must not reveal QR underneath.
            let svg = String(decoding:try QRCodeRenderer.svg(g,logo:logo),as:UTF8.self)
            #expect(svg.contains("fill=\"#E6331A\" fill-opacity=\"\(opacity == 0 ? "0" : opacity == 1 ? "1" : "0.4")\""))
        }
    }

    @Test func logoOpacityAndPlacementRemainReadable() throws {
        let logo = try QRCodeTests.logo()
        for source in ["https://example.com/logo",String(repeating:"x",count:110)] {
            for opacity in [0.0,0.5,1.0] { for style in QRModuleStyle.allCases {
                var p = QRPreferences(); p.logoSize = 0.2; p.style = style; p.logoBackgroundOpacity = opacity
                let a = try QRCodeProcessor.generate(source:source,preferences:p,logo:logo)
                #expect(a.verification.passed,"\(style.rawValue)/\(opacity)")
                #expect(a.matrix.payload == Data(source.utf8) && a.matrix.correction == .h)
                #expect(!(try QRCodeProcessor.export(a,format:.png)).data.isEmpty)
            } }
        }
    }

    @Test func denseLogoUsesSafeAreaAndStillDecodes() throws {
        var p = QRPreferences(); p.style = .rounded; p.logoSize = 0.2
        p.logoBackgroundOpacity = 0.25; p.exportSize = 2048
        let source = String(repeating:"x",count:1273) // Maximum byte-mode H capacity.
        let a = try QRCodeProcessor.generate(source:source,preferences:p,logo:QRCodeTests.logo())
        #expect(a.matrix.version == 40 && a.matrix.correction == .h)
        #expect(a.verification.passed && a.matrix.payload == Data(source.utf8))
        #expect(a.logoReduced) // The full requested square cannot cover alignment markers.
        #expect(!(try QRCodeProcessor.export(a,format:.png)).data.isEmpty)
    }
}

extension QRCodeSessionTests {
    @Test func legacyPreferencesPreserveAppearanceAndDefaultLogoOpacity() throws {
        let suite = "qr-logo-migration-"+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        var p = QRPreferences(); p.style = .dots; p.opacity = 0.5; p.logoPadding = 2; p.exportSize = 2048
        var old = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any])
        old.removeValue(forKey:"logoBackgroundOpacity")
        defaults.set(try JSONSerialization.data(withJSONObject:old),forKey:QRCodeWorkspaceSession.key)
        let session = QRCodeWorkspaceSession(defaults:defaults)
        #expect(session.preferences == p && session.logo == nil && session.input.isEmpty)
        session.preferences.logoBackgroundOpacity = 0.25
        let restored = QRCodeWorkspaceSession(defaults:defaults)
        p.logoBackgroundOpacity = 0.25
        #expect(restored.preferences == p && restored.logo == nil && restored.input.isEmpty)
        p.logoBackgroundOpacity = .nan; #expect(!p.valid)
        p.logoBackgroundOpacity = 1.1; #expect(!p.valid)
        p.logoBackgroundOpacity = -0.1; #expect(!p.valid)
    }
}
