import Foundation
import UniformTypeIdentifiers
import ImageIO

struct Base64FileMetadata: Sendable {
    let url: URL
    let name: String
    let size: Int64?
    let mime: String
    static func load(_ url: URL) throws -> Self {
        guard url.isFileURL else { throw Base64FileFailure(.unsupportedFormat, "Choose a local file URL.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var metadata: Self?, thrown: Error?, coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { source in
            do {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey,.contentTypeKey])
                guard values.isRegularFile == true else { throw Base64FileFailure(.unsupportedFormat, "Choose one regular file.") }
                var mime = values.contentType?.preferredMIMEType ?? "application/octet-stream"
                if let size = values.fileSize, size <= Base64FileBudget.imageBytes,
                   let image = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                   let type = CGImageSourceGetType(image) {
                    mime = UTType(type as String)?.preferredMIMEType ?? mime
                }
                metadata = .init(url: url, name: Base64FileDisplay.safeLabel(url.lastPathComponent), size: values.fileSize.map(Int64.init), mime: mime)
            } catch { thrown = error }
        }
        if let thrown { throw thrown }
        guard coordination == nil, let metadata else { throw Base64FileFailure(.ioFailure, "The file is unavailable. Choose a local file you can read.") }
        return metadata
    }
}
enum Base64FileDisplay {
    static func safeLabel(_ text: String, limit: Int = 180) -> String {
        var output = ""
        for scalar in text.unicodeScalars.prefix(limit) {
            if CharacterSet.controlCharacters.contains(scalar) || [0x061c,0x200e,0x200f,0x2028,0x2029].contains(scalar.value) ||
                (0x202a...0x202e).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) {
                output += "\\u{\(String(scalar.value, radix: 16))}"
            } else { output.unicodeScalars.append(scalar) }
        }
        return output + (text.unicodeScalars.count > limit ? "…" : "")
    }
    static func bytes(_ count: Int64) -> String { "\(count) bytes · \(ByteCountFormatter.string(fromByteCount: count, countStyle: .file))" }
}
