import Testing

@testable import NetworkReferenceCore

@Suite struct PermissionTests {
  @Test func conversionAndChanges() throws {
    for value in UInt16(0)...UInt16(0o7777) {
      let m = PermissionMode(bits: value)
      #expect(try PermissionMode(symbolic: m.symbolic) == m)
      #expect(try PermissionMode(octal: m.octal) == m)
    }
    #expect(try PermissionMode(octal: "0644").applying("u+x,g=u,o-rwx").octal == "0770")
    #expect(try PermissionMode(octal: "0644").applying("a+X", directory: true).octal == "0755")
  }
}
