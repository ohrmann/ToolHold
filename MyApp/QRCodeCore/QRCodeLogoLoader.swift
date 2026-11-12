import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers

public enum QRCodeLogoLoader {
    public static func load(_ url: URL) throws -> QRLogo {
        guard url.isFileURL else { throw QRIssue(.logo,"Choose a local PNG, JPEG or HEIC image.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // Reject nonregular files before Foundation/provider coordination can open a FIFO.
        let values = try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 8*1024*1024 else { throw QRIssue(.logo,"Choose a regular image file no larger than 8 MiB.") }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.open($0,O_RDONLY|O_NONBLOCK|O_CLOEXEC) } ?? -1 }
        guard descriptor >= 0 else { throw QRIssue(.logo,"The image could not be opened.") }
        let handle = FileHandle(fileDescriptor:descriptor,closeOnDealloc:true); defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor,&before) == 0, (before.st_mode & S_IFMT) == S_IFREG, before.st_size <= 8*1024*1024 else { throw QRIssue(.logo,"Choose a regular image file no larger than 8 MiB.") }
        try Task.checkCancellation()
        let data = try handle.read(upToCount:8*1024*1024+1) ?? Data()
        var after = stat()
        guard fstat(descriptor,&after) == 0, before.st_size == after.st_size, Int64(data.count) == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw QRIssue(.logo,"The image changed while it was being loaded. Choose it again.") }
        return try decode(data)
    }
    public static func decode(_ data: Data) throws -> QRLogo {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 8*1024*1024,
              let src = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              CGImageSourceGetCount(src) == 1,
              let typeID = CGImageSourceGetType(src), let type = UTType(typeID as String), [.png,.jpeg,.heic,.heif].contains(type),
              let props = CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any],
              let w = props[kCGImagePropertyPixelWidth] as? NSNumber, let h = props[kCGImagePropertyPixelHeight] as? NSNumber,
              w.int64Value > 0, h.int64Value > 0, w.int64Value <= 32768, h.int64Value <= 32768, w.int64Value*h.int64Value <= 40_000_000 else { throw QRIssue(.logo,"Use a single PNG, JPEG or HEIC image, up to 8 MiB and 40 megapixels.") }
        guard let image = CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { throw QRIssue(.logo,"The logo could not be decoded.") }
        try Task.checkCancellation()
        return QRLogo(image:image,png:try QRCodeRenderer.png(image))
    }
}
