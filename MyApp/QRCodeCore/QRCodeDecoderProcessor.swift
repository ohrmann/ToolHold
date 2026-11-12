import Foundation
import CoreGraphics
import CQRReader

public enum QRCodeDecoderProcessor {
    public static func composite(_ source: QRDecodeSource, surface: QRScanSurface) throws -> CGImage {
        let image = source.image
        guard let context = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw QRDecodeIssue(.resource,"Could not allocate the image surface.") }
        let value: CGFloat = surface == .white ? 1 : 0.06
        context.setFillColor(CGColor(gray:value,alpha:1)); context.fill(CGRect(x:0,y:0,width:image.width,height:image.height))
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let output = context.makeImage() else { throw QRDecodeIssue(.resource,"Could not prepare the image.") }; return output
    }
    public static func scan(_ source: QRDecodeSource, surface: QRScanSurface = .white) throws -> QRDecodeSnapshot {
        try Task.checkCancellation()
        guard source.image.width <= QRDecodeBudget.scanSide, source.image.height <= QRDecodeBudget.scanSide else { throw QRCodeDecoderImageLoader.sizeIssue }
        let image = try composite(source,surface:surface), width = image.width, height = image.height
        var pixels = [UInt8](repeating:0,count:width*height)
        let ok = pixels.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data:ptr.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            // The resulting memory is top-to-bottom; CoreGraphics renders a CGImage with that storage convention.
            ctx.draw(image,in:CGRect(x:0,y:0,width:width,height:height)); return true
        }
        guard ok else { throw QRDecodeIssue(.resource,"Could not allocate the scan buffer.") }
        try Task.checkCancellation()
        let result = pixels.withUnsafeBufferPointer { tqr_read($0.baseAddress,Int32(width),Int32(height),Int32(width)) }
        defer { tqr_free(result) }
        guard tqr_status(result) == 0 else { throw QRDecodeIssue(tqr_status(result) == 2 ? .resource : .reader,"The QR reader could not process this image. Try another image.") }
        try Task.checkCancellation()
        let count = tqr_count(result)
        var decoded: [(raw:TQRItem,bytes:Data?,text:String?,interpretation:String,corners:[CGPoint],version:String,correction:String,sequence:String)] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let item = tqr_item(result,index)
            let bytes: Data? = item.valid != 0 ? (item.bytes.map { Data(bytes:$0,count:item.bytes_count) } ?? Data()) : nil
            let reported = item.text.flatMap { String(data:Data(bytes:$0,count:item.text_count),encoding:.utf8) }
            let text: String?, interpretation: String
            if item.valid == 0 { text = nil; interpretation = "QR detected but unreadable" }
            else if item.has_eci == 0, let bytes, let utf8 = String(data:bytes,encoding:.utf8) {
                text = utf8; interpretation = "UTF-8 interpretation · no encoding marker"
            } else if item.content_type == 1 || item.content_type == 2 || item.content_type == 5 {
                text = nil; interpretation = "Binary, mixed or unsupported encoding · use decoded bytes"
            } else if let reported, (!reported.isEmpty || bytes?.isEmpty == true),
                      (!reported.unicodeScalars.contains(where: { $0.value == 0xFFFD }) || bytes == Data(reported.utf8)) {
                text = reported; interpretation = item.has_eci != 0 ? "Text decoded using ECI" : "Encoding inferred by reader"
            } else { text = nil; interpretation = "Text interpretation unavailable · use decoded bytes" }
            var xy = item.xy
            let corners = withUnsafeBytes(of:&xy) { raw in
                let v = raw.bindMemory(to:Double.self)
                return stride(from:0,to:8,by:2).map { CGPoint(x:v[$0],y:v[$0+1]) }
            }
            decoded.append((item,bytes,text,interpretation,corners,item.version.map { String(cString:$0) } ?? "",item.correction.map { String(cString:$0) } ?? "",item.sequence_id.map { String(cString:$0) } ?? ""))
        }
        decoded.sort {
            let l = $0.corners, r = $1.corners
            let ly = l.map(\.y).min() ?? 0, ry = r.map(\.y).min() ?? 0
            if ly != ry { return ly < ry }
            return (l.map(\.x).min() ?? 0) < (r.map(\.x).min() ?? 0)
        }
        let items = decoded.prefix(QRDecodeBudget.results).enumerated().map { index,value in
            QRDecodedItem(id:index,corners:value.corners,bytes:value.bytes,text:value.text,interpretation:value.interpretation,contentType:Int(value.raw.content_type),hasECI:value.raw.has_eci != 0,sequenceIndex:Int(value.raw.sequence_index),sequenceCount:Int(value.raw.sequence_count),sequenceID:value.sequence,version:value.version,correction:value.correction,mirrored:value.raw.mirrored != 0,inverted:value.raw.inverted != 0)
        }
        return QRDecodeSnapshot(source:source,image:image,surface:surface,items:items,limited:count > QRDecodeBudget.results)
    }
}
