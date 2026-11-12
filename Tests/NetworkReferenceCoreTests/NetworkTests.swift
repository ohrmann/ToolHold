import Foundation
import NumberCore
import Testing

@testable import NetworkReferenceCore

@Suite struct NetworkTests {
  @Test func cidrGolden() throws {
    let v4 = try IPNetwork("192.168.1.130/25")
    #expect(v4.canonical == "192.168.1.128/25")
    #expect(v4.last.text == "192.168.1.255")
    #expect(try v4.count.digits(radix: 10) == "128")
    #expect(
      try IPNetwork("::/0").count.digits(radix: 10) == "340282366920938463463374607431768211456")
    #expect(try IPAddress("2001:0:0:1:0:0:1:1").text == "2001::1:0:0:1:1")
    #expect(try IPAddress("::ffff:192.0.2.1").text == "::ffff:192.0.2.1")
    #expect(try IPNetwork("::/0").contains(IPNetwork("2001:db8::/32")))
    #expect(try !IPNetwork("192.168.1.0/24").overlaps(IPNetwork("192.168.2.0/24")))
    #expect(try IPNetwork("0.0.0.0/31").report().notes.contains { $0.contains("point-to-point") })
    for bad in [
      "01.2.3.4", "256.1.2.3", "1.2.3.4/33", "1::2::3", "::1%en0", "[::1]:80", "1:2:3:4:5:6:7:8:9",
      "example.com",
    ] { #expect(throws: CalculationIssue.self) { try IPNetwork(bad) } }
  }
  @Test func referencesAndContentType() throws {
    let http = try NetworkReferences.http()
    let mime = try NetworkReferences.mime()
    let extensions = try NetworkReferences.extensions()
    #expect(http.count == 75)
    #expect(mime.count == 2364)
    #expect(Set(mime.map(\.id)).count == mime.count)
    #expect(http.contains { $0.low == 104 && $0.name.contains("TEMPORARY") })
    #expect(try NetworkReferences.httpSearch("404").rows.first?.value == "Not Found")
    #expect(
      try NetworkReferences.httpSearch("599").rows.contains { $0.value.contains("Unassigned") })
    #expect(extensions.contains { $0.extension == "json" && $0.type == "application/json" })
    #expect(
      try NetworkReferences.mimeSearch("file.JSON").rows.contains { $0.value == "application/json" }
    )
    let p = try ContentTypeParser.parse(
      "Text/Plain; charset=\"UTF-8\"; x=\"a;b\\\"c\"; charset=ascii; filename*=UTF-8''a")
    #expect(p.mediaType == "text/plain")
    #expect(p.parameters[1].value == "a;b\"c")
    #expect(p.parameters.count == 4)
    #expect(p.report.notes.count == 2)
    for invalid in [
      "text", "text/plain\r\nx: y", "text/plain; x=\"unterminated", "text/plain; x=",
      "text/plain; x=ok garbage",
    ] { #expect(throws: CalculationIssue.self) { try ContentTypeParser.parse(invalid) } }
    let classification = try NetworkReferences.classify(IPNetwork("192.0.0.9/32"))
    #expect(classification[1].contains("192.0.0.9/32"))
    #expect(
      try NetworkReferences.classify(IPNetwork("0.0.0.0/0")).contains {
        $0.contains("Overlaps part")
      })
  }
  @Test func completedReferenceContracts() throws {
    let images = try NetworkReferences.mimeSearch("image/*", mode: "Media Types")
    #expect(
      !images.rows.isEmpty && images.rows.allSatisfy { $0.label.lowercased().hasPrefix("image/") })
    #expect(
      try NetworkReferences.mimeSearch("backup.tar.gz").rows.contains { $0.id == "compound:tar.gz" }
    )
    #expect(try NetworkReferences.extensions().contains { $0.extension == "svgz" })
    let input = "  text/plain; x=\"😀\"; y="
    do {
      _ = try ContentTypeParser.parse(input)
      Issue.record("Expected failure")
    } catch let issue as CalculationIssue {
      #expect(issue.range == NSRange(location: input.utf16.count, length: 0))
    }
    #expect(try IPNetwork("ff00::/8").report().notes.contains { $0.contains("Multicast") })
  }
  @Test func chmodSequenceAndBoundaries() throws {
    #expect(try PermissionMode(octal: "4755").applying("u=").octal == "0055")
    #expect(try PermissionMode(octal: "0644").applying("a+X").octal == "0644")
    #expect(try PermissionMode(octal: "0644").applying("a+X", directory: true).octal == "0755")
    #expect(try PermissionMode(octal: "0644").applying("u+x,g=u,o-rwx").octal == "0770")
    for invalid in ["+x", "u+rwxz", "u+ug", "u+x,"] {
      #expect(throws: CalculationIssue.self) { try PermissionMode(octal: "0644").applying(invalid) }
    }
  }
}
