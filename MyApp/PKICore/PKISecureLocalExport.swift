#if os(macOS)
import Foundation
import Darwin

/// Local macOS writer. No FileWrapper/system staging, no following symlink directories,
/// no inherited ACLs. The old destination is untouched until the final atomic rename.
/// Document providers are outside this contract and must use their own protection policies.
public enum PKISecureLocalExport {
    public enum Failure: Error { case unsafeDestination, permissions, changedDestination, write, replacement, existingDirectory }
    private static func accessFailure(_ fallback: Failure) -> Failure { errno == EACCES || errno == EPERM ? .permissions : fallback }

    public static func write(_ bytes: Data, to url: URL) throws {
        try write(bytes, to: url, beforeReplace: { _ in })
    }
    // Narrow fault-injection seam for replacement failures; no alternate write implementation.
    static func write(_ bytes: Data, to url: URL, beforeReplace: (URL) throws -> Void) throws {
        try commit(files: nil, bytes: bytes, to: url, beforeReplace: beforeReplace)
    }
    public static func write(files: [String: Data], to url: URL) throws {
        try commit(files: files, bytes: Data(), to: url, beforeReplace: { _ in })
    }
    /// Called off the main actor by the Save UI. Cooperating file presenters/providers
    /// see a replacement; uncoordinated filesystem races are still checked below.
    public static func coordinatedWrite(_ bytes: Data, files: [String:Data]? = nil, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        var coordinationError: NSError?, writeError: Error?, written = false
        NSFileCoordinator(filePresenter:nil).coordinate(writingItemAt:url,options:.forReplacing,error:&coordinationError) { destination in
            do {
                try Task.checkCancellation()
                if let files { try write(files:files,to:destination) } else { try write(bytes,to:destination) }
                written = true
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        guard written else { throw Failure.replacement }
    }
    private static func nameIsSafe(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.utf8.contains(0)
    }
    private static func directory(_ url: URL) throws -> Int32 {
        guard url.isFileURL else { throw Failure.unsafeDestination }
        // Ancestor traversal needs metadata access, not directory enumeration. Powerbox
        // grants a selected file without granting read-data access to its ancestors.
        var parts = Array(url.pathComponents.dropFirst())
        // Foundation canonicalizes these protected OS aliases back to /var and /tmp.
        // Resolve only these fixed root aliases; user-controlled symlink components stay rejected.
        if let first = parts.first, first == "var" || first == "tmp" { parts.insert("private", at: 0) }
        guard parts.allSatisfy(nameIsSafe) else { throw Failure.unsafeDestination }
        // O_NOFOLLOW_ANY rejects symlinks in *every* component atomically. An absolute
        // metadata-only open also lets the sandbox resolve the selected URL extension;
        // walking unrelated ancestor descriptors is denied by the sandbox.
        let fd = open("/" + parts.joined(separator:"/"), O_EVTONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw accessFailure(.unsafeDestination) }
        return fd
    }
    private static func restrict(_ fd: Int32, mode: mode_t) throws {
        guard let empty = acl_init(0) else { throw Failure.permissions }
        defer { acl_free(UnsafeMutableRawPointer(empty)) }
        guard acl_set_fd(fd, empty) == 0, fchmod(fd, mode) == 0 else { throw Failure.permissions }
        errno = 0
        if let actual = acl_get_fd(fd) {
            defer { acl_free(UnsafeMutableRawPointer(actual)) }
            var entry: acl_entry_t?
            guard acl_get_entry(actual, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw Failure.permissions }
        } else if errno != ENOENT { throw Failure.permissions }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & 0o7777 == mode, info.st_uid == geteuid() else { throw Failure.permissions }
    }
    private static func file(_ bytes: Data, name: String, parent: Int32) throws -> Int32 {
        let fd = openat(parent, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw accessFailure(.write) }
        var prepared = false
        defer { if !prepared { _ = ftruncate(fd, 0); close(fd) } }
        // Clear/verify inherited ACLs before writing even one sensitive byte.
        try restrict(fd, mode: 0o600)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.write }; offset += n
            }
        }
        guard fsync(fd) == 0 else { throw Failure.write }
        prepared = true; return fd
    }
    private static func snapshot(_ parent: Int32, _ name: String) throws -> stat? {
        var info = stat()
        if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }; throw accessFailure(.unsafeDestination)
        }
        guard info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unsafeDestination }
        return info
    }
    private static func same(_ a: stat?, _ b: stat?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static func commit(files: [String: Data]?, bytes: Data, to url: URL, beforeReplace: (URL) throws -> Void) throws {
        try Task.checkCancellation()
        guard nameIsSafe(url.lastPathComponent), files?.keys.allSatisfy(nameIsSafe) != false else { throw Failure.unsafeDestination }
        let parent = try directory(url.deletingLastPathComponent()); defer { close(parent) }
        let name = url.lastPathComponent, original = try snapshot(parent, name)
        if files != nil && original != nil { throw Failure.existingDirectory }
        if let original, original.st_mode & S_IFMT != S_IFREG { throw Failure.unsafeDestination }
        // A selected-file sandbox extension does not authorize arbitrary sibling files.
        // Ask Foundation for an owned replacement directory on the destination volume.
        let replacement = try FileManager.default.url(for:.itemReplacementDirectory,in:.userDomainMask,appropriateFor:url,create:true)
        defer { try? FileManager.default.removeItem(at:replacement) }
        let stagingParent = try directory(replacement); defer { close(stagingParent) }
        try restrict(stagingParent, mode:0o700)
        let staging = ".toolbox-export-" + UUID().uuidString
        var children = [String]()
        var folderFD: Int32 = -1
        var payloadFDs = [Int32](), committed = false
        defer {
            // If access to the parent was revoked during the operation, unlink may fail.
            // Retained descriptors still allow truncating our own uncommitted payloads.
            // This is logical cleanup, not secure erasure of filesystem blocks.
            for fd in payloadFDs { if !committed { _ = ftruncate(fd, 0) }; close(fd) }
            if folderFD >= 0 {
                for child in children { unlinkat(folderFD, child, 0) }
                close(folderFD); unlinkat(stagingParent, staging, AT_REMOVEDIR)
            } else { unlinkat(stagingParent, staging, 0) }
        }
        if let files {
            guard mkdirat(stagingParent, staging, 0o700) == 0 else { throw accessFailure(.write) }
            folderFD = openat(stagingParent, staging, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard folderFD >= 0 else { unlinkat(stagingParent, staging, AT_REMOVEDIR); throw Failure.write }
            try restrict(folderFD, mode: 0o700)
            for (child, bytes) in files { children.append(child); payloadFDs.append(try file(bytes, name: child, parent: folderFD)) }
            guard fsync(folderFD) == 0 else { throw Failure.write }
        } else { payloadFDs.append(try file(bytes, name: staging, parent: stagingParent)) }
        try beforeReplace(replacement)
        try Task.checkCancellation()
        guard same(original, try snapshot(parent, name)) else { throw Failure.changedDestination }
        // RENAME_EXCL also protects a previously absent destination against races.
        let flags = original == nil ? UInt32(RENAME_EXCL) : 0
        guard renameatx_np(stagingParent, staging, parent, name, flags) == 0 else { throw accessFailure(.replacement) }
        committed = true
        // Directory descriptor still references the committed folder: never remove its children.
        if folderFD >= 0 { close(folderFD); folderFD = -1; children.removeAll() }
    }
}
#endif
