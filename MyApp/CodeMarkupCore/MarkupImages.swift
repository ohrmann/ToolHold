import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MarkupImage: Sendable {
    let png: Data
    let pixels: Int
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 5*1024*1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.png","public.jpeg","com.compuserve.gif","org.webmproject.webp"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8_000_000/height,
              let image = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ImageFailure() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw ImageFailure() }
        CGImageDestinationAddImage(destination,image,[:] as CFDictionary)
        guard CGImageDestinationFinalize(destination),output.length <= 16*1024*1024 else { throw ImageFailure() }
        return .init(png:output as Data,pixels:width*height)
    }
    static func dataURI(_ reference: String) -> Data? {
        guard reference.hasPrefix("data:image/"),reference.utf8.count <= 7*1024*1024,
              let comma = reference.firstIndex(of:","),reference[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded:String(reference[reference.index(after:comma)...]))
    }
    struct ImageFailure: Error {}
}
struct MarkupPreviewSnapshot: Sendable {
    let nonce: String
    let html: String
    let images: [String:Data]
    var allowsExternalResources = false
    var exportHTML: String {
        var text=html
        for (id,data) in images { text=text.replacingOccurrences(of:"toolbox-preview://\(nonce)/\(id)",with:"data:image/png;base64,"+data.base64EncodedString()) }
        // Unknown image IDs remain blocked placeholders, never internal URLs in exports.
        text=text.replacingOccurrences(of:#" src="toolbox-preview://[^"]*""#,with:"",options:.regularExpression)
        text=text.replacingOccurrences(of:#"<meta http-equiv="Content-Security-Policy"[^>]*>"#,with:"",options:.regularExpression)
        return text
    }
}
