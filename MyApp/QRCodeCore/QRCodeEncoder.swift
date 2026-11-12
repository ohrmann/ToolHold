import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

public enum QRCodeEncoder {
    public static func encode(_ source: String, correction: QRCorrection) throws -> QRMatrix {
        try Task.checkCancellation()
        guard !source.isEmpty else { throw QRIssue(.content,"Enter text or a URL to generate a QR code.") }
        guard source.utf16.count <= 32_768 else { throw QRIssue(.resource,"Input exceeds the 32,768 UTF-16 unit processing limit.") }
        let filter = CIFilter.qrCodeGenerator()
        let payload = Data(source.utf8)
        filter.message = payload; filter.correctionLevel = correction.rawValue
        guard let image = filter.outputImage else { throw QRIssue(.content,"Content does not fit at correction level \(correction.rawValue). Shorten the input or choose another level.") }
        // Core Image emits a single white module border. Validate it, not a dark-pixel bounding box.
        let side = Int(image.extent.width), n = side-2
        guard image.extent == CGRect(x:0,y:0,width:side,height:side), (21...177).contains(n), (n-17)%4 == 0 else { throw QRIssue(.generation,"The system returned an unsupported QR matrix.") }
        var pixels = [UInt8](repeating:0,count:side*side)
        let context = CIContext(options:[.useSoftwareRenderer:true])
        context.render(image, toBitmap:&pixels, rowBytes:side, bounds:image.extent, format:.L8, colorSpace:CGColorSpaceCreateDeviceGray())
        guard pixels.allSatisfy({ $0 == 0 || $0 == 255 }), (0..<side).allSatisfy({ pixels[$0] == 255 && pixels[(side-1)*side+$0] == 255 && pixels[$0*side] == 255 && pixels[$0*side+side-1] == 255 }) else { throw QRIssue(.generation,"The system QR border or module layout is unsupported.") }
        // CIContext bitmap scanlines here are top-to-bottom; verify the three finder corners.
        var bits = [Bool](); bits.reserveCapacity(n*n)
        for y in 0..<n { for x in 0..<n { bits.append(pixels[(y+1)*side+x+1] == 0) } }
        for (ox,oy) in [(0,0),(n-7,0),(0,n-7)] {
            for y in 0..<7 { for x in 0..<7 {
                let expected = x == 0 || x == 6 || y == 0 || y == 6 || ((2...4).contains(x) && (2...4).contains(y))
                guard bits[(oy+y)*n+ox+x] == expected else { throw QRIssue(.generation,"The QR matrix orientation could not be established.") }
            } }
        }
        try Task.checkCancellation()
        return QRMatrix(size:n,dark:bits,functional:try functionMask(version:(n-17)/4),payload:payload,correction:correction)
    }
    /// Alignment-center spacing follows Project Nayuki (MIT); see ThirdPartyNotices/QRCodeGeometry.
    /// QR Model 2 geometry only. No encoding, masking selection, ECC or payload parsing.
    public static func functionMask(version: Int) throws -> [Bool] {
        guard (1...40).contains(version) else { throw QRIssue(.generation,"Unsupported QR version.") }
        let n = version*4+17
        var mask = [Bool](repeating:false,count:n*n)
        func mark(_ x: Int,_ y: Int) { if (0..<n).contains(x) && (0..<n).contains(y) { mask[y*n+x] = true } }
        func rect(_ x: Int,_ y: Int,_ w: Int,_ h: Int) { for dy in 0..<h { for dx in 0..<w { mark(x+dx,y+dy) } } }
        rect(0,0,9,9); rect(n-8,0,8,9); rect(0,n-8,9,8) // finders, separators, format and dark module
        for i in 0..<n { mark(6,i); mark(i,6) }
        if version >= 2 {
            let count = version/7+2
            let step = version == 32 ? 26 : ((version*4+count*2+1)/(count*2-2))*2
            var centers = [6]
            for i in (0..<(count-1)).reversed() { centers.append(n-7-i*step) }
            for (i,x) in centers.enumerated() { for (j,y) in centers.enumerated() {
                if (i == 0 && j == 0) || (i == 0 && j == count-1) || (i == count-1 && j == 0) { continue }
                rect(x-2,y-2,5,5)
            } }
        }
        if version >= 7 { rect(n-11,0,3,6); rect(0,n-11,6,3) }
        return mask
    }
}
