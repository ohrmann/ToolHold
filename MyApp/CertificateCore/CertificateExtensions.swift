import Foundation
import SwiftASN1
import Darwin

enum CertificateExtensions {
    static func decode(id: Int, oid: String, critical: Bool, bytes: Data) -> CertificateExtension {
        var values: [CertificateField] = [], issue: String?
        func add(_ name: String, _ value: String) { values.append(.init(id: values.count, name: name, value: value)) }
        do {
            let root = try DER.parse(Array(bytes))
            switch oid {
            case "2.5.29.17":
                for node in try CertificateDER.children(root) {
                    guard node.identifier.tagClass == .contextSpecific else { throw CertificateDER.invalid }
                    let number = node.identifier.tagNumber
                    if [1,2,6].contains(number) {
                        let data = try CertificateDER.primitive(node); guard data.allSatisfy({ $0 < 128 }) else { throw CertificateDER.invalid }
                        add(number == 1 ? "Email" : number == 2 ? "DNS" : "URI", String(decoding: data, as: UTF8.self))
                    } else if number == 7 {
                        let data = try CertificateDER.primitive(node); guard data.count == 4 || data.count == 16 else { throw CertificateDER.invalid }
                        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        let success = data.withUnsafeBytes { inet_ntop(data.count == 4 ? AF_INET : AF_INET6, $0.baseAddress!, &buffer, socklen_t(buffer.count)) != nil }
                        guard success else { throw CertificateDER.invalid }; add("IP address", String(cString: buffer))
                    } else if number == 4 {
                        let contents = try CertificateDER.children(node, tag: node.identifier); guard contents.count == 1 else { throw CertificateDER.invalid }
                        add("Directory name", try CertificateDER.distinguishedName(contents[0]).joined(separator: ", "))
                    } else if number == 8 {
                        let tag = ASN1Identifier(tagWithNumber: 8, tagClass: .contextSpecific)
                        add("Registered ID", try ASN1ObjectIdentifier(derEncoded: node, withIdentifier: tag).oidComponents.map(String.init).joined(separator: "."))
                    } else { add("GeneralName tag \(number) · DER", CertificateDisplay.hex(Data(node.encodedBytes))) }
                }
            case "2.5.29.19":
                let nodes = try CertificateDER.children(root); var index = 0, ca = false
                if nodes.first?.identifier == .boolean { ca = try Bool(derEncoded: nodes[0]); index += 1 }
                add("Certificate authority", ca ? "Yes" : "No")
                if index < nodes.count {
                    guard ca else { throw CertificateDER.invalid }
                    add("Path length", "\(try CertificateDER.smallInteger(nodes[index]))"); index += 1
                }
                guard index == nodes.count else { throw CertificateDER.invalid }
            case "2.5.29.15":
                let bits = try ASN1BitString(derEncoded: root)
                let names = ["Digital signature", "Content commitment", "Key encipherment", "Data encipherment", "Key agreement", "Certificate signing", "CRL signing", "Encipher only", "Decipher only"]
                for (i, name) in names.enumerated() {
                    if i/8 < bits.bytes.count, Array(bits.bytes)[i/8] & (128 >> (i%8)) != 0 { add("Usage", name) }
                }
                if bits.bytes.count > 2 || (bits.bytes.count == 2 && Array(bits.bytes)[1] & 0x7f != 0) { issue = "Key Usage has unknown bits; raw value retained." }
            case "2.5.29.37":
                let names = ["1.3.6.1.5.5.7.3.1":"TLS server", "1.3.6.1.5.5.7.3.2":"TLS client", "1.3.6.1.5.5.7.3.3":"Code signing", "1.3.6.1.5.5.7.3.4":"Email protection", "1.3.6.1.5.5.7.3.8":"Timestamping", "1.3.6.1.5.5.7.3.9":"OCSP signing", "2.5.29.37.0":"Any extended key usage"]
                for node in try CertificateDER.children(root) { let value = try CertificateDER.oid(node); add("Purpose", names[value].map { "\($0) · \(value)" } ?? value) }
            case "2.5.29.14": add("Key identifier", CertificateDisplay.hex(try CertificateDER.primitive(root, tag: .octetString)))
            case "2.5.29.35":
                for node in try CertificateDER.children(root) {
                    if node.identifier == ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific) { add("Key identifier", CertificateDisplay.hex(try CertificateDER.primitive(node))) }
                    else { add("Authority field · DER", CertificateDisplay.hex(Data(node.encodedBytes))) }
                }
            case "1.3.6.1.5.5.7.1.1":
                for access in try CertificateDER.children(root) {
                    let a = try CertificateDER.children(access); guard a.count == 2 else { throw CertificateDER.invalid }
                    let method = try CertificateDER.oid(a[0])
                    if a[1].identifier == ASN1Identifier(tagWithNumber: 6, tagClass: .contextSpecific) {
                        let data = try CertificateDER.primitive(a[1]); guard data.allSatisfy({ $0 < 128 }) else { throw CertificateDER.invalid }
                        add("\(method) · never fetched", String(decoding: data, as: UTF8.self))
                    } else { add(method, CertificateDisplay.hex(Data(a[1].encodedBytes))) }
                }
            case "2.5.29.32":
                for policy in try CertificateDER.children(root) {
                    let fields = try CertificateDER.children(policy); guard let first = fields.first else { throw CertificateDER.invalid }
                    add("Policy", try CertificateDER.oid(first))
                    for raw in fields.dropFirst() { add("Qualifiers · raw DER", CertificateDisplay.hex(Data(raw.encodedBytes))) }
                }
            case "2.5.29.31":
                _ = try CertificateDER.children(root); add("Distribution points · raw DER · never fetched", CertificateDisplay.hex(bytes))
            default:
                add("Raw extension · DER", CertificateDisplay.hex(bytes))
                if critical { issue = "Critical extension not interpreted: \(oid)." }
            }
        } catch {
            values = []; issue = "Malformed extension \(oid). Raw bytes retained."
        }
        return .init(id: id, oid: oid, critical: critical, bytes: bytes, fields: values, issue: issue, rawHex: CertificateDisplay.hex(bytes))
    }
}
