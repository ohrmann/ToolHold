import Foundation
import CryptoKit
import Darwin

struct GZipFileMetadata: Sendable {
    let url: URL
    let name: String
    let size: Int64
    static func load(_ url: URL) throws -> Self {
        guard url.isFileURL else { throw GZipFailure(.unsupportedFormat, .unsupported, "Choose one local regular file.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var value: Self?, thrown: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            do {
                let fd = open(location.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { throw GZipFailure(.ioFailure, .io, "The selected file cannot be opened.") }
                defer { close(fd) }
                let stamp = try GZipFileStamp(fd)
                guard stamp.regular else { throw GZipFailure(.unsupportedFormat, .unsupported, "Choose a regular file, not a folder or special device.") }
                value = .init(url: url, name: Base64FileDisplay.safeLabel(url.lastPathComponent), size: stamp.size)
            } catch { thrown = error }
        }
        if let thrown { throw thrown }
        guard coordinationError == nil, let value else { throw GZipFailure(.ioFailure, .io, "The file provider could not grant access.") }
        return value
    }
}

enum GZipFileProcessor {
    static func run(source: GZipSource, options: GZipOptions, intent: GZipIntent = .convert,
                    destination: GZipDestination? = nil, expectedDigest: Data? = nil,
                    operation: GZipOperation = .init(), limits: GZipLimits = .init(),
                    progress: @escaping @Sendable (GZipProgress) -> Void = { _ in }) -> GZipResult {
        do {
            try operation.check()
            switch source {
            case .text(let text):
                guard text.utf16.prefix(limits.textInput + 1).count <= limits.textInput else {
                    throw GZipFailure(.resourceLimit, .budget, "Text Input exceeds 262,144 UTF-16 units. Choose a file instead.")
                }
                let original = Data(text.utf8), digest = Data(SHA256.hash(data: Data(text.utf8)))
                var notes: [String] = []
                let bytes: Data
                if options.direction == .decompress {
                    let decoded = try GZipProcessor.base64(text, mode: options.base64Mode, limits: limits, operation: operation)
                    bytes = decoded.0; notes = decoded.1
                } else { bytes = original }
                var offset = 0
                let body: (FileHandle?) throws -> GZipResult = { output in
                    var value = try GZipProcessor.stream(options: options, intent: intent, limits: limits, operation: operation,
                        total: Int64(bytes.count), read: {
                            let end = min(bytes.count, offset + max(1, limits.chunk)); defer { offset = end }
                            return bytes.subdata(in: offset..<end)
                        }, write: output.map { handle in { data in try handle.write(contentsOf: data) } }, progress: progress)
                    guard expectedDigest == nil || expectedDigest == digest else { throw changed() }
                    value.sourceDigest = digest; value.notes = notes; return value
                }
                if let destination { return try export(destination, source: source, operation: operation, body: body) }
                return try body(nil)
            case .file(let url):
                guard url.isFileURL else { throw GZipFailure(.unsupportedFormat, .unsupported, "Choose a local file URL. Network URLs are not opened.") }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var value: GZipResult?, thrown: Error?, coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
                    do {
                        let fd = open(location.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                        guard fd >= 0 else { throw GZipFailure(.ioFailure, .io, "The selected file cannot be opened. Check access and local availability.") }
                        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                        defer { try? handle.close() }
                        let stamp = try GZipFileStamp(fd)
                        guard stamp.regular else { throw GZipFailure(.unsupportedFormat, .unsupported, "Choose one regular file, not a folder or special device.") }
                        let body: (FileHandle?) throws -> GZipResult = { output in
                            let processed = try GZipProcessor.stream(options: options, intent: intent, limits: limits, operation: operation, total: stamp.size,
                                read: { try handle.read(upToCount: max(1, limits.chunk)) ?? Data() },
                                write: output.map { file in { data in try file.write(contentsOf: data) } }, progress: progress)
                            var current = stat()
                            guard try GZipFileStamp(handle.fileDescriptor) == stamp,
                                  stat(location.path, &current) == 0, GZipFileStamp(current) == stamp,
                                  expectedDigest == nil || expectedDigest == processed.sourceDigest else { throw changed() }
                            return processed
                        }
                        if let destination { value = try export(destination, source: source, operation: operation, body: body) }
                        else { value = try body(nil) }
                    } catch { thrown = error }
                }
                if let thrown { throw thrown }
                guard coordinationError == nil, let value else { throw GZipFailure(.ioFailure, .io, "The source provider could not grant access.") }
                return value
            }
        } catch { return GZipProcessor.failure(error) }
    }
    private static func changed() -> GZipFailure {
        .init(.sourceChanged, .sourceChanged, "The source changed or differs from the checked snapshot. Check it again before exporting.")
    }
    static func validFilename(_ name: String) -> Bool { Base64FileProcessor.validFilename(name) }
    private static func export(_ destination: GZipDestination, source: GZipSource, operation: GZipOperation,
                               body: (FileHandle?) throws -> GZipResult) throws -> GZipResult {
        guard validFilename(destination.name) else { throw GZipFailure(.unsupportedFormat, .unsupported, "Enter a plain filename without path separators, control or directional characters.") }
        let directory = destination.directory
        guard directory.isFileURL else { throw GZipFailure(.unsupportedFormat, .unsupported, "Choose a local export folder URL.") }
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let target = directory.appendingPathComponent(destination.name)
        if case let .file(input) = source, input.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL {
            throw GZipFailure(.ioFailure, .io, "The source file cannot be replaced. Choose a new filename.")
        }
        var outcome: GZipResult?, thrown: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: directory, options: .forMerging, error: &coordinationError) { folder in
            let target = folder.appendingPathComponent(destination.name)
            let partial = folder.appendingPathComponent("DeveloperToolbox-\(UUID().uuidString).partial")
            var fd: Int32 = -1, identity: GZipFileStamp?, committed = false
            do {
                try operation.check()
                var existing = stat()
                guard lstat(target.path, &existing) != 0 && errno == ENOENT else { throw GZipFailure(.ioFailure, .io, "That filename already exists or is unavailable. Existing files are never replaced.") }
                fd = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
                guard fd >= 0 else { throw GZipFailure(.ioFailure, .io, "An export file could not be created in this folder.") }
                identity = try GZipFileStamp(fd)
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); fd = -1
                defer { try? handle.close() }
                var result = try body(handle)
                try handle.synchronize(); try operation.check(); try handle.close()
                try operation.commit(name: destination.name) {
                    var current = stat()
                    guard lstat(partial.path, &current) == 0, identity?.sameIdentity(GZipFileStamp(current)) == true else {
                        throw GZipFailure(.ioFailure, .io, "The partial export was replaced. Export was not published.")
                    }
                    guard renameatx_np(AT_FDCWD, partial.path, AT_FDCWD, target.path, UInt32(RENAME_EXCL)) == 0 else {
                        throw GZipFailure(.ioFailure, .io, "The export could not be published safely. Choose a new name or local folder; this provider may not support safe export.")
                    }
                    committed = true
                }
                result.exportedName = destination.name; outcome = result
            } catch {
                if fd >= 0 { close(fd) }
                var failure = (error as? GZipFailure) ?? (error is CancellationError
                    ? GZipFailure(.cancelled, .cancelled, "Export cancelled.")
                    : GZipFailure(.ioFailure, .io, "Export failed. Check access and available space."))
                if !committed, let identity {
                    var current = stat()
                    if lstat(partial.path, &current) == 0 {
                        if !identity.sameIdentity(GZipFileStamp(current)) || unlink(partial.path) != 0 { failure.cleanupPath = partial.path }
                    } else if errno != ENOENT { failure.cleanupPath = partial.path }
                    if failure.cleanupPath != nil { failure.message += " The partial export could not be removed; remove it manually if present." }
                }
                thrown = failure
            }
        }
        if let thrown { throw thrown }
        guard coordinationError == nil, let outcome else { throw GZipFailure(.ioFailure, .io, "The destination provider could not authorize export.") }
        return outcome
    }
}

private struct GZipFileStamp: Equatable {
    let device: Int32, inode: UInt64, size: Int64, seconds: Int, nanos: Int, changed: Int, changedNanos: Int
    let regular: Bool
    init(_ fd: Int32) throws {
        var value = stat(); guard fstat(fd, &value) == 0 else { throw GZipFailure(.ioFailure, .io, "The selected file is unavailable.") }
        self.init(value)
    }
    init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; size = value.st_size
        seconds = value.st_mtimespec.tv_sec; nanos = value.st_mtimespec.tv_nsec
        changed = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        regular = value.st_mode & S_IFMT == S_IFREG
    }
    func sameIdentity(_ other: Self) -> Bool { device == other.device && inode == other.inode }
}
