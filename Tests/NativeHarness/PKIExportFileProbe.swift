import Foundation
@testable import Developer_Toolbox

/// Run against the app module on macOS or with simctl spawn. No key material is used.
@main struct PKIExportFileProbe {
    static func main() async throws {
        if CommandLine.arguments.count == 2 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            guard url.lastPathComponent.hasPrefix("dt-release-") else { throw CocoaError(.fileReadNoPermission) }
            let key = try await PKIEngine().inspectKey(Data(contentsOf: url), password: "synthetic-release-password")
            guard key.isPrivate && key.consistent else { throw CocoaError(.fileReadCorruptFile) }
            print("PKI_SYSTEM_PROVIDER_ENCRYPTED_READBACK_PASSED")
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("public synthetic export fixture".utf8)
        let file = root.appendingPathComponent("fixture.pem")
        let wrapper = PKIExportDocument(bytes).makeFileWrapper()
        guard wrapper.fileAttributes[FileAttributeKey.type.rawValue] as? String == FileAttributeType.typeRegular.rawValue else { throw CocoaError(.fileWriteUnknown) }
        try wrapper.write(to: file, options: .atomic, originalContentsURL: nil)
        try check(file, permissions: 0o600, bytes: bytes)
        // Replacement must preserve restrictive permissions and exact contents.
        let changed = bytes + Data(" replacement".utf8)
        try PKIExportDocument(changed).makeFileWrapper().write(to: file, options: .atomic, originalContentsURL: file)
        try check(file, permissions: 0o600, bytes: changed)
        let folder = root.appendingPathComponent("bundle")
        try PKIDirectoryDocument(files: ["one.pem": bytes, "two.der": changed]).makeFileWrapper()
            .write(to: folder, options: .atomic, originalContentsURL: nil)
        let mode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
        guard mode?.intValue == 0o700 else { throw CocoaError(.fileWriteNoPermission) }
        try check(folder.appendingPathComponent("one.pem"), permissions: 0o600, bytes: bytes)
        try check(folder.appendingPathComponent("two.der"), permissions: 0o600, bytes: changed)
        print("PKI_EXPORT_FILE_PROBE_PASSED regular=0600 directory=0700 atomic_replace=true exact_bytes=true")
    }
    static func check(_ url: URL, permissions: Int, bytes: Data) throws {
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        guard mode?.intValue == permissions, try Data(contentsOf: url) == bytes else { throw CocoaError(.fileWriteNoPermission) }
    }
}
