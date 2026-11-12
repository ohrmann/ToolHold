import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Base64FileImagePreview: @unchecked Sendable {
    let image: CGImage?
    let message: String
    let mime: String?
    static func make(_ bytes: Data?, declared: String?) -> Self {
        guard let bytes, bytes.count <= Base64FileBudget.imageBytes else {
            return .init(image: nil, message: "Image preview is unavailable above 8 MiB. Exact file export is still available.", mime: nil)
        }
        guard !bytes.isEmpty else { return .init(image: nil, message: "There are no image bytes to preview. Zero-byte file export is available.", mime: nil) }
        guard !Task.isCancelled, let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let rawType = CGImageSourceGetType(source), let type = UTType(rawType as String),
              [UTType.png, .jpeg, .gif, .heic, .heif, .tiff].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return .init(image: nil, message: "No supported raster image was detected. The original bytes can still be exported.", mime: nil)
        }
        let width = w.int64Value, height = h.int64Value
        guard width > 0 && height > 0 && width <= 32_768 && height <= 32_768 && width * height <= 40_000_000 else {
            return .init(image: nil, message: "Image dimensions exceed the preview budget. Exact file export is still available.", mime: type.preferredMIMEType)
        }
        guard !Task.isCancelled, let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            return .init(image: nil, message: "The image could not be previewed. Exact file export is still available.", mime: type.preferredMIMEType)
        }
        let mime = type.preferredMIMEType
        let mismatch = declared != nil && declared != "application/octet-stream" && declared?.lowercased() != mime?.lowercased()
        return .init(image: thumbnail, message: "\(width) × \(height) · \(mime ?? type.identifier) · first image/frame" +
            (mismatch ? "\nDeclared media type differs from the detected image type." : "") +
            "\nExport preserves all original bytes and metadata, including any EXIF/GPS data.", mime: mime)
    }
}
