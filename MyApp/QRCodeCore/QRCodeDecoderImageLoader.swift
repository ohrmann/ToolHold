import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers

public enum QRCodeDecoderImageLoader {
    public static func readFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw QRDecodeIssue(.loading,"Choose a local image file.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // Check before any provider coordination/open that could block on a special file.
        let info = try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard info.isRegularFile == true else { throw QRDecodeIssue(.unsupported,"Choose one regular image file.") }
        guard let length = info.fileSize, length >= 0, length <= QRDecodeBudget.encodedBytes else { throw sizeIssue }
        let fd = url.withUnsafeFileSystemRepresentation { $0.map { Darwin.open($0,O_RDONLY|O_NONBLOCK|O_CLOEXEC) } ?? -1 }
        guard fd >= 0 else { throw QRDecodeIssue(.loading,"The image could not be opened.") }
        let file = FileHandle(fileDescriptor:fd,closeOnDealloc:true); defer { try? file.close() }
        var before = stat(), after = stat()
        guard fstat(fd,&before) == 0, (before.st_mode & S_IFMT) == S_IFREG else { throw QRDecodeIssue(.loading,"Choose a regular image file.") }
        guard before.st_size >= 0, before.st_size <= QRDecodeBudget.encodedBytes else { throw sizeIssue }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount:min(65536,QRDecodeBudget.encodedBytes-data.count+1)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk); guard data.count <= QRDecodeBudget.encodedBytes else { throw sizeIssue }
        }
        guard fstat(fd,&after) == 0, after.st_size == before.st_size, Int64(data.count) == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw QRDecodeIssue(.loading,"The image changed while loading. Choose it again.")
        }
        return data
    }
    public static var sizeIssue: QRDecodeIssue { .init(.resource,"Image too large. Choose an image up to 32 MiB and 40 megapixels.") }
    public static func decode(_ data: Data) throws -> QRDecodeSource {
        try Task.checkCancellation()
        guard data.count <= QRDecodeBudget.encodedBytes else { throw sizeIssue }
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let raw = CGImageSourceGetType(source), let type = UTType(raw as String),
              [.png,.jpeg,.heic,.heif,.tiff,.gif].contains(type) else {
            throw QRDecodeIssue(.unsupported,"Use a PNG, JPEG, HEIC, TIFF or static GIF image.")
        }
        guard CGImageSourceGetCount(source) == 1 else { throw QRDecodeIssue(.unsupported,"Choose a single still image. Animated and multipage images are not supported.") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w = properties[kCGImagePropertyPixelWidth] as? NSNumber, let h = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw QRDecodeIssue(.loading,"The image metadata could not be read.")
        }
        let width = w.int64Value, height = h.int64Value
        guard width > 0, height > 0, width <= QRDecodeBudget.sourceSide, height <= QRDecodeBudget.sourceSide,
              width*height <= QRDecodeBudget.pixels else { throw sizeIssue }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
            kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:min(QRDecodeBudget.scanSide,Int(max(width,height))),
            kCGImageSourceShouldCacheImmediately:true
        ] as CFDictionary) else { throw QRDecodeIssue(.loading,"The image could not be decoded. Try another image.") }
        try Task.checkCancellation()
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapped = (5...8).contains(orientation)
        return QRDecodeSource(image:image,width:Int(swapped ? height : width),height:Int(swapped ? width : height),format:type.preferredFilenameExtension?.uppercased() ?? "Image")
    }
}
