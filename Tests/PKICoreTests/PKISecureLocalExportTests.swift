#if os(macOS)
import Foundation
import Darwin
import Testing
@testable import PKICore

private func withExportDirectory(_ body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("dt-owned-export-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}
private func addACL(_ rule: String, to url: URL) throws {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
    process.arguments = ["+a", rule, url.path]; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
}
private func accessIsPrivate(_ url: URL, mode: mode_t) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & 0o7777 == mode, info.st_uid == geteuid() else { return false }
    errno = 0
    guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else { return errno == ENOENT }
    defer { acl_free(UnsafeMutableRawPointer(acl)) }
    var entry: acl_entry_t?
    return acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1 && errno == EINVAL
}

@Test func secureLocalExportReplacesACLsAndHandlesInheritedPermissions() throws {
    try withExportDirectory { parent in
        let file = parent.appendingPathComponent("public-marker.pem"), bytes = Data("PUBLIC-NONSECRET-MARKER".utf8)
        try PKISecureLocalExport.coordinatedWrite(bytes, to: file)
        #expect(accessIsPrivate(file, mode: 0o600)); #expect(try Data(contentsOf: file) == bytes)
        for rule in ["everyone allow read,readattr,readextattr,readsecurity", "everyone deny read"] {
            try addACL(rule, to: file)
            #expect(!accessIsPrivate(file, mode: 0o600))
            try PKISecureLocalExport.write(bytes, to: file)
            #expect(accessIsPrivate(file, mode: 0o600)); #expect(try Data(contentsOf: file) == bytes)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try PKISecureLocalExport.write(bytes, to: file)
        #expect(accessIsPrivate(file, mode: 0o600))
        try addACL("everyone allow read,file_inherit,directory_inherit", to: parent)
        let inherited = parent.appendingPathComponent("inherited.pem")
        try PKISecureLocalExport.write(bytes, to: inherited)
        #expect(accessIsPrivate(inherited, mode: 0o600))
        let folder = parent.appendingPathComponent("bundle")
        try PKISecureLocalExport.write(files: ["public.pem": bytes, "private.pem": bytes], to: folder)
        #expect(accessIsPrivate(folder, mode: 0o700))
        for name in ["public.pem", "private.pem"] { #expect(accessIsPrivate(folder.appendingPathComponent(name), mode: 0o600)) }
        #expect(throws: Error.self) { try PKISecureLocalExport.write(files: ["new.pem": bytes], to: folder) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }
}

@Test func secureLocalExportRejectsSymlinksAndPreservesOldFileOnFailure() throws {
    try withExportDirectory { parent in
        let target = parent.appendingPathComponent("target"), link = parent.appendingPathComponent("link")
        let original = Data("PUBLIC-ORIGINAL".utf8), updated = Data("PUBLIC-UPDATED".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: Error.self) { try PKISecureLocalExport.write(updated, to: link) }
        #expect(try Data(contentsOf: target) == original)
        let directoryLink = parent.appendingPathComponent("directory-link")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: parent)
        #expect(throws: Error.self) { try PKISecureLocalExport.write(updated, to: directoryLink.appendingPathComponent("target")) }
        // A real rename failure after staging: remove directory write permission at the fault seam.
        defer { chmod(parent.path, 0o700) }
        var ownedStage: URL?
        do { try PKISecureLocalExport.write(updated, to: target, beforeReplace: { ownedStage = $0; chmod(parent.path, 0o500) }); Issue.record("Unexpected replacement") }
        catch { #expect(PKIExportOutcome(.failure(error)) == .permissionDenied) }
        chmod(parent.path, 0o700)
        #expect(try Data(contentsOf: target) == original)
        #expect(ownedStage.map { !FileManager.default.fileExists(atPath:$0.path) } == true)
        let leftovers = try FileManager.default.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix(".toolbox-export-") }
        for url in leftovers { #expect(try Data(contentsOf:url).isEmpty) }
        // Cancellation must clean only our owned replacement directory, leaving the result intact.
        #expect(throws: Error.self) {
            try PKISecureLocalExport.write(updated, to: target, beforeReplace: { ownedStage = $0; throw CancellationError() })
        }
        #expect(ownedStage.map { !FileManager.default.fileExists(atPath:$0.path) } == true)
        try PKISecureLocalExport.write(updated, to: target, beforeReplace: { ownedStage = $0 })
        #expect(ownedStage.map { !FileManager.default.fileExists(atPath:$0.path) } == true)
        #expect(try Data(contentsOf: target) == updated)
        #expect(accessIsPrivate(target, mode: 0o600))
        let raced = parent.appendingPathComponent("raced-target")
        #expect(throws: Error.self) {
            try PKISecureLocalExport.write(original,to:raced,beforeReplace:{
                ownedStage = $0
                try FileManager.default.createSymbolicLink(at:raced,withDestinationURL:target)
            })
        }
        #expect(try Data(contentsOf:target) == updated)
        #expect(ownedStage.map { !FileManager.default.fileExists(atPath:$0.path) } == true)
        let concurrent = Data("PUBLIC-CONCURRENT-WRITER".utf8)
        #expect(throws: Error.self) {
            try PKISecureLocalExport.write(original,to:target,beforeReplace:{
                ownedStage = $0; try concurrent.write(to:target,options:.atomic)
            })
        }
        #expect(try Data(contentsOf:target) == concurrent)
        #expect(ownedStage.map { !FileManager.default.fileExists(atPath:$0.path) } == true)
    }
}

@Test func cancelledLocalWriteCleansOwnedStageBeforeAtomicCommit() async throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("dt-cancel-owned-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:parent) }
    let target = parent.appendingPathComponent("marker"), original = Data("PUBLIC-ORIGINAL".utf8)
    try original.write(to:target)
    let (cancelled, stage) = await Task.detached { () -> (Bool, URL?) in
        var stage: URL?
        do {
            try PKISecureLocalExport.write(Data("PUBLIC-UPDATED".utf8),to:target,beforeReplace:{
                stage = $0
                withUnsafeCurrentTask { $0?.cancel() }
            })
            return (false,stage)
        } catch is CancellationError { return (true,stage) }
        catch { return (false,stage) }
    }.value
    #expect(cancelled && stage.map { !FileManager.default.fileExists(atPath:$0.path) } == true)
    #expect(try Data(contentsOf:target) == original)
    try PKISecureLocalExport.coordinatedWrite(Data("PUBLIC-RETRY".utf8),to:target)
    #expect(try Data(contentsOf:target) == Data("PUBLIC-RETRY".utf8))
}
#endif
