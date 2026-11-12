import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Only the three large finder eyes are styled. Timing/alignment/format cells stay exact.
public struct QRFinderGeometry: Sendable {
    public let x: Int, y: Int
    public let style: QRModuleStyle
    public let rounding: Double
    private var radius: Double { style == .dots ? 3.5 : rounding*4 }
    public var ring: CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in:CGRect(x:x,y:y,width:7,height:7),cornerWidth:radius,cornerHeight:radius)
        path.addRoundedRect(in:CGRect(x:x+1,y:y+1,width:5,height:5),cornerWidth:max(0,radius-1),cornerHeight:max(0,radius-1))
        return path
    }
    public var pupil: CGPath {
        CGPath(roundedRect:CGRect(x:x+2,y:y+2,width:3,height:3),cornerWidth:style == .dots ? 1.5 : min(1.5,radius/1.5),cornerHeight:style == .dots ? 1.5 : min(1.5,radius/1.5),transform:nil)
    }
}
public struct QRGeometry: Sendable {
    public let matrix: QRMatrix
    public let preferences: QRPreferences
    public let plate: CGRect?
    public let protected: [Bool]
    public init(matrix: QRMatrix, preferences: QRPreferences, hasLogo: Bool) throws {
        guard preferences.valid else { throw QRIssue(.rendering,"Invalid QR appearance settings.") }
        self.matrix = matrix; self.preferences = preferences
        let n = matrix.size
        var protected = matrix.functional
        if hasLogo {
            // One-module moat around all functional cells, including their light cells.
            for y in 0..<n { for x in 0..<n where matrix.functional[y*n+x] {
                for dy in -1...1 { for dx in -1...1 where (0..<n).contains(x+dx) && (0..<n).contains(y+dy) { protected[(y+dy)*n+x+dx] = true } }
            } }
            plate = try Self.placeLogo(size:n,protected:protected,preferences:preferences)
        } else { plate = nil }
        self.protected = protected
    }
    private static func requestedLogoSide(size: Int, fraction: Double) -> Int {
        let side = Int((Double(size)*fraction).rounded(.down))
        return side%2 == 0 ? side-1 : side
    }
    /// A bounded near-center search, never moving QR modules or covering functional
    /// dark/light cells. Prefix sums make every candidate test constant-time.
    private static func placeLogo(size n: Int, protected: [Bool], preferences: QRPreferences) throws -> CGRect {
        let requested = requestedLogoSide(size:n,fraction:preferences.logoSize)
        guard requested > preferences.logoPadding*2 else { throw QRIssue(.logo,"Logo padding leaves no image area. Increase the logo size or reduce padding.") }
        let stride = n+1
        var sums = [Int](repeating:0,count:stride*stride)
        for y in 0..<n {
            if y%16 == 0 { try Task.checkCancellation() }
            for x in 0..<n {
                sums[(y+1)*stride+x+1] = (protected[y*n+x] ? 1 : 0)+sums[y*stride+x+1]+sums[(y+1)*stride+x]-sums[y*stride+x]
            }
        }
        let radius = max(2,Int(ceil(Double(n)*0.15)))
        var offsets: [(x:Int,y:Int,distance:Int)] = []
        for y in -radius...radius { for x in -radius...radius where x*x+y*y <= radius*radius { offsets.append((x,y,x*x+y*y)) } }
        offsets.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        for side in Swift.stride(from:requested,to:preferences.logoPadding*2,by:-2) {
            try Task.checkCancellation()
            let center = (n-side)/2
            for offset in offsets {
                let x = center+offset.x, y = center+offset.y
                guard x >= 0, y >= 0, x+side <= n, y+side <= n else { continue }
                let count = sums[(y+side)*stride+x+side]-sums[y*stride+x+side]-sums[(y+side)*stride+x]+sums[y*stride+x]
                if count == 0 { return CGRect(x:x,y:y,width:side,height:side) }
            }
        }
        throw QRIssue(.logo,"No safe logo area near the center. Reduce padding or remove the logo.")
    }
    public var logoMoved: Bool {
        guard let plate else { return false }
        let center = Double(matrix.size)/2
        return plate.midX != center || plate.midY != center
    }
    public var logoReduced: Bool {
        guard let plate else { return false }
        return Int(plate.width) < Self.requestedLogoSide(size:matrix.size,fraction:preferences.logoSize)
    }
    public func isLogoCell(_ x: Int,_ y: Int) -> Bool {
        guard let plate else { return false }
        return plate.contains(CGPoint(x:Double(x)+0.5,y:Double(y)+0.5))
    }
    public var finders: [QRFinderGeometry] {
        guard preferences.style != .square else { return [] }
        return [(0,0),(matrix.size-7,0),(0,matrix.size-7)].map { QRFinderGeometry(x:$0.0,y:$0.1,style:preferences.style,rounding:preferences.rounding) }
    }
    public func styledFinderCell(_ x: Int,_ y: Int) -> Bool {
        preferences.style != .square && ((y < 7 && (x < 7 || x >= matrix.size-7)) || (x < 7 && y >= matrix.size-7))
    }
    public func logoRect(_ image: CGImage) -> CGRect? {
        guard let plate else { return nil }
        let area = plate.insetBy(dx:CGFloat(preferences.logoPadding),dy:CGFloat(preferences.logoPadding))
        let scale = min(area.width/CGFloat(image.width),area.height/CGFloat(image.height))
        return CGRect(x:area.midX-CGFloat(image.width)*scale/2,y:area.midY-CGFloat(image.height)*scale/2,width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
    }
    public var logoCells: [CGRect] {
        guard let plate else { return [] }
        return [plate]
    }
}
public enum QRCodeRenderer {
    public static func image(_ geometry: QRGeometry, logo: QRLogo?, target: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard (1...8192).contains(target) else { throw QRIssue(.resource,"Image size exceeds the rendering budget.") }
        let matrix = geometry.matrix, p = geometry.preferences, n = matrix.size
        let side = matrix.pixelSide(target:target)
        guard side <= 8192, let c = CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw QRIssue(.resource,"The image could not be allocated within the rendering budget.") }
        c.translateBy(x:0,y:CGFloat(side)); c.scaleBy(x:1,y:-1)
        let scale = CGFloat(side)/CGFloat(n+8)
        c.scaleBy(x:scale,y:scale)
        c.setFillColor(p.background.cg(p.opacity)); c.fill(CGRect(x:0,y:0,width:n+8,height:n+8))
        c.translateBy(x:4,y:4)
        c.setFillColor(p.foreground.cg())
        for y in 0..<n {
            if y%16 == 0 { try Task.checkCancellation() }
            for x in 0..<n where matrix.dark[y*n+x] && !geometry.styledFinderCell(x,y) && !geometry.isLogoCell(x,y) {
                let rect = CGRect(x:x,y:y,width:1,height:1)
                let classic = matrix.functional[y*n+x] || p.style == .square
                c.setShouldAntialias(!classic)
                if classic { c.fill(rect) }
                else if p.style == .dots { c.fillEllipse(in:rect) }
                else { c.addPath(CGPath(roundedRect:rect,cornerWidth:p.rounding,cornerHeight:p.rounding,transform:nil)); c.fillPath() }
            }
        }
        c.setShouldAntialias(true)
        for eye in geometry.finders {
            c.addPath(eye.ring); c.fillPath(using:.evenOdd)
            c.addPath(eye.pupil); c.fillPath()
        }
        if let logo, let plate = geometry.plate, let imageRect = geometry.logoRect(logo.image) {
            c.setShouldAntialias(false); c.setFillColor(p.logoBackground.cg(p.logoBackgroundOpacity)); c.fill(plate)
            c.saveGState()
            let path = CGMutablePath(); path.addRects(geometry.logoCells); c.addPath(path); c.clip()
            c.interpolationQuality = .high
            c.translateBy(x:imageRect.minX,y:imageRect.maxY); c.scaleBy(x:1,y:-1)
            c.draw(logo.image,in:CGRect(origin:.zero,size:imageRect.size))
            c.restoreGState()
        }
        try Task.checkCancellation()
        guard let image = c.makeImage() else { throw QRIssue(.rendering,"The QR image could not be rendered.") }
        return image
    }
    public static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { throw QRIssue(.rendering,"PNG export is unavailable.") }
        CGImageDestinationAddImage(dest,image,[:] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw QRIssue(.rendering,"PNG export failed.") }
        return data as Data
    }
    public static func svg(_ g: QRGeometry, logo: QRLogo?) throws -> Data {
        try Task.checkCancellation()
        let n = g.matrix.size, p = g.preferences
        func f(_ x: Double) -> String { String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),x).replacingOccurrences(of:#"\.?0+$"#,with:"",options:.regularExpression) }
        func rect(_ r: CGRect, fill: String, extra: String = "") -> String { "<rect x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" fill=\"\(fill)\"\(extra)/>" }
        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(n+8) \(n+8)\" width=\"\(g.matrix.pixelSide(target:p.exportSize))\" height=\"\(g.matrix.pixelSide(target:p.exportSize))\">"
        s += rect(CGRect(x:0,y:0,width:n+8,height:n+8),fill:p.background.hex,extra:" fill-opacity=\"\(f(p.opacity))\"")
        s += "<g transform=\"translate(4 4)\">"
        for y in 0..<n {
            if y%16 == 0 { try Task.checkCancellation() }
            for x in 0..<n where g.matrix.dark[y*n+x] && !g.styledFinderCell(x,y) && !g.isLogoCell(x,y) {
                if !g.matrix.functional[y*n+x] && p.style == .dots {
                    s += "<circle cx=\"\(f(Double(x)+0.5))\" cy=\"\(f(Double(y)+0.5))\" r=\"0.5\" fill=\"\(p.foreground.hex)\"/>"
                } else {
                    let radius = !g.matrix.functional[y*n+x] && p.style == .rounded ? " rx=\"\(f(p.rounding))\"" : ""
                    s += rect(CGRect(x:x,y:y,width:1,height:1),fill:p.foreground.hex,extra:radius)
                }
            }
        }
        func pathData(_ path: CGPath) -> String {
            var out = ""
            path.applyWithBlock { element in
                let e = element.pointee
                func pt(_ i: Int) -> String { f(e.points[i].x)+" "+f(e.points[i].y) }
                switch e.type {
                case .moveToPoint: out += "M"+pt(0)
                case .addLineToPoint: out += "L"+pt(0)
                case .addQuadCurveToPoint: out += "Q"+pt(0)+" "+pt(1)
                case .addCurveToPoint: out += "C"+pt(0)+" "+pt(1)+" "+pt(2)
                case .closeSubpath: out += "Z"
                @unknown default: break
                }
            }
            return out
        }
        for eye in g.finders {
            s += "<path d=\"\(pathData(eye.ring))\" fill=\"\(p.foreground.hex)\" fill-rule=\"evenodd\"/>"
            s += "<path d=\"\(pathData(eye.pupil))\" fill=\"\(p.foreground.hex)\"/>"
        }
        if let logo, let plate = g.plate, let r = g.logoRect(logo.image) {
            s += rect(plate,fill:p.logoBackground.hex,extra:" fill-opacity=\"\(f(p.logoBackgroundOpacity))\"")
            s += "<defs><clipPath id=\"logo-area\">"
            for cell in g.logoCells { s += rect(cell,fill:"white") }
            s += "</clipPath></defs>"
            s += "<image x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" preserveAspectRatio=\"xMidYMid meet\" clip-path=\"url(#logo-area)\" href=\"data:image/png;base64,\(logo.png.base64EncodedString())\"/>"
        }
        s += "</g></svg>"
        guard s.utf8.count <= 16*1024*1024 else { throw QRIssue(.resource,"SVG exceeds the 16 MiB export budget.") }
        return Data(s.utf8)
    }
}
