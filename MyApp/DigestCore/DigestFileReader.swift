import Foundation
import Darwin

/// Shared only by the two new tools. Never creates an on-disk snapshot or buffers a whole file.
enum DigestFileReader {
    struct Stamp: Equatable {
        let device: dev_t, inode: ino_t, size: off_t, modified: timespec, changed: timespec
        init(_ value: stat) { device = value.st_dev; inode = value.st_ino; size = value.st_size; modified = value.st_mtimespec; changed = value.st_ctimespec }
        static func ==(l: Self, r: Self) -> Bool {
            l.device == r.device && l.inode == r.inode && l.size == r.size && l.modified.tv_sec == r.modified.tv_sec && l.modified.tv_nsec == r.modified.tv_nsec && l.changed.tv_sec == r.changed.tv_sec && l.changed.tv_nsec == r.changed.tv_nsec
        }
    }
    static func read(_ url: URL, chunkSize: Int = 65_536,
                     progress: @Sendable (DigestProgress) -> Void = { _ in },
                     consume: (Data) throws -> Void) throws -> Int64 {
        guard url.isFileURL else { throw DigestIssue(status: .ioFailure, message: "Choose a local regular file.") }
        guard (1...65_536).contains(chunkSize) else { throw DigestIssue(status: .resourceLimit, message: "Unsupported read buffer size.") }
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // NSFileCoordinator may itself open a FIFO synchronously before invoking its accessor.
        // Reject known special files first, then re-check the actual opened descriptor below.
        var preliminary = stat()
        guard stat(url.path, &preliminary) == 0, preliminary.st_mode & S_IFMT == S_IFREG else {
            throw DigestIssue(status: .ioFailure, message: "Choose an available regular file, not a folder or special device.")
        }
        var count: Int64?, failure: Error?, coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { source in
            do {
                try Task.checkCancellation()
                let fd = open(source.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { throw DigestIssue(status: .ioFailure, message: "The file cannot be opened. Choose an available local file.") }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? handle.close() }
                var initial = stat()
                guard fstat(fd, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG else { throw DigestIssue(status: .ioFailure, message: "Choose a regular file, not a folder or special device.") }
                let stamp = Stamp(initial)
                var bytes: Int64 = 0, last = ProcessInfo.processInfo.systemUptime
                while try autoreleasepool(invoking: { () throws -> Bool in
                    try Task.checkCancellation()
                    let data = try handle.read(upToCount: chunkSize) ?? Data()
                    if data.isEmpty { return false }
                    let addition = bytes.addingReportingOverflow(Int64(data.count))
                    guard !addition.overflow else { throw DigestIssue(status: .resourceLimit, message: "File byte count exceeds the supported range.") }
                    try consume(data); bytes = addition.partialValue; try Task.checkCancellation()
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - last >= 0.1 { progress(.init(bytes: bytes, total: Int64(initial.st_size))); last = now }
                    return true
                }) { }
                try Task.checkCancellation()
                var final = stat(), path = stat()
                guard fstat(fd, &final) == 0, stat(source.path, &path) == 0,
                      stamp == Stamp(final), stamp == Stamp(path), bytes == initial.st_size else {
                    throw DigestIssue(status: .sourceChanged, message: "The source file changed, was replaced or removed. Calculate again.")
                }
                progress(.init(bytes: bytes, total: bytes)); count = bytes
            } catch { failure = error }
        }
        if let failure { throw failure }
        guard coordination == nil, let count else { throw DigestIssue(status: .ioFailure, message: "The file provider could not grant access. Choose an available local file.") }
        return count
    }
}
