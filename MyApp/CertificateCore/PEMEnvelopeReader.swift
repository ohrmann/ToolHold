import Foundation
import Darwin

public struct PEMEnvelope: Sendable {
    public let label: String, der: Data, range: NSRange
}
public enum PEMEnvelopeReader {
    public static func encode(_ bytes: Data, label: String) -> String {
        "-----BEGIN \(label)-----\n" + bytes.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]) + "\n-----END \(label)-----"
    }
    public static func read(_ source: String, allowed: Set<String>, maximumCount: Int = 1, maximumBytes: Int = CertificateLimits.certificate) throws -> [PEMEnvelope] {
        guard source.utf8.prefix(CertificateLimits.file + 1).count <= CertificateLimits.file else { throw CertificateFailure(.resource, "Input exceeds 4 MiB.") }
        let s = source as NSString; var position = 0; var output: [PEMEnvelope] = []
        func white(_ c: UInt16) -> Bool { [9,10,13,32].contains(c) }
        while position < s.length {
            try Task.checkCancellation()
            while position < s.length && white(s.character(at: position)) { position += 1 }
            if position == s.length { break }
            let start = position, prefix = "-----BEGIN "
            guard s.substring(from: position).hasPrefix(prefix) else { throw CertificateFailure("Expected a PEM BEGIN line; only whitespace may separate blocks.") }
            position += prefix.utf16.count
            let close = s.range(of: "-----", range: NSRange(location: position, length: s.length-position))
            guard close.location != NSNotFound else { throw CertificateFailure("Unterminated PEM BEGIN line.") }
            let label = s.substring(with: NSRange(location: position, length: close.location-position))
            guard allowed.contains(label) else { throw CertificateFailure(.unsupported, "Unsupported PEM type. Choose \(allowed.sorted().joined(separator: " or ")).") }
            position = NSMaxRange(close)
            let footer = "-----END \(label)-----", end = s.range(of: footer, range: NSRange(location: position, length: s.length-position))
            guard end.location != NSNotFound else { throw CertificateFailure("Missing matching PEM END line.") }
            let body = s.substring(with: NSRange(location: position, length: end.location-position))
            guard body.unicodeScalars.allSatisfy({ $0.value < 128 }) else { throw CertificateFailure("PEM Base64 must contain only ASCII characters.") }
            let compact = String(body.unicodeScalars.filter { ![9,10,13,32].contains($0.value) })
            guard let bytes = Data(base64Encoded: compact), !bytes.isEmpty, bytes.base64EncodedString() == compact else { throw CertificateFailure("Invalid PEM Base64 or padding. No input was repaired.") }
            guard bytes.count <= maximumBytes else { throw CertificateFailure(.resource, "Decoded PEM block exceeds its size limit.") }
            position = NSMaxRange(end)
            output.append(.init(label: label, der: bytes, range: .init(location: start, length: position-start)))
            guard output.count <= maximumCount else { throw CertificateFailure(.resource, "Too many PEM blocks (maximum \(maximumCount)).") }
        }
        guard !output.isEmpty else { throw CertificateFailure("Enter a PEM certificate or import a DER file.") }
        return output
    }
}

/// Regular files only, preflight before open, bounded reads, balanced security scope.
public enum CertificateFileLoader {
    public static func read(_ url: URL, limit: Int = CertificateLimits.file) throws -> Data {
        guard url.isFileURL else { throw CertificateFailure(.loading, "Choose a local file.") }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true else { throw CertificateFailure(.loading, "Choose a regular file.") }
        guard let size = info.fileSize, size >= 0, size <= limit else { throw CertificateFailure(.resource, "File exceeds the import limit.") }
        let fd = url.withUnsafeFileSystemRepresentation { $0.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1 }
        guard fd >= 0 else { throw CertificateFailure(.loading, "The file could not be opened.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        var a = stat(), b = stat()
        guard fstat(fd, &a) == 0, a.st_mode & S_IFMT == S_IFREG else { throw CertificateFailure(.loading, "Choose a regular file.") }
        guard a.st_size >= 0, a.st_size <= limit else { throw CertificateFailure(.resource, "File exceeds the import limit.") }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(65536, limit-data.count+1)) ?? Data()
            if chunk.isEmpty { break }; data.append(chunk)
            guard data.count <= limit else { throw CertificateFailure(.resource, "File exceeds the import limit.") }
        }
        guard fstat(fd, &b) == 0, a.st_size == b.st_size, Int64(data.count) == b.st_size,
              a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec, a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec,
              a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec, a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec else { throw CertificateFailure(.loading, "File changed during import. Choose it again.") }
        return data
    }
}
