import Foundation
import Testing

/// FileManager may enumerate /private/tmp while Bundle uses the /tmp symlink.
func schemaFixtureRelativePath(_ file: URL, within root: URL) throws -> String {
    let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let path = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    guard path.count > base.count, path.starts(with: base) else { throw CocoaError(.fileReadInvalidFileName) }
    return path.dropFirst(base.count).joined(separator: "/")
}

@Test func schemaFixturePathsResolveSymlinksAndRejectOutsideFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("remotes"), alias = directory.appendingPathComponent("alias")
    let file = root.appendingPathComponent("nested/integer.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: file)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
    #expect(try schemaFixtureRelativePath(file.resolvingSymlinksInPath(), within: alias) == "nested/integer.json")
    #expect(try schemaFixtureRelativePath(alias.appendingPathComponent("nested/integer.json"), within: root) == "nested/integer.json")
    #expect(throws: Error.self) { try schemaFixtureRelativePath(directory.appendingPathComponent("outside.json"), within: root) }
}
