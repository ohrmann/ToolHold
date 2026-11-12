import Foundation
import SwiftASN1
import CryptoKit

/// Schema mapping over Apple's DER decoder; preserves unknown OIDs and original bytes.
public enum CertificateDER {
    public static func children(_ node: ASN1Node, tag: ASN1Identifier = .sequence) throws -> [ASN1Node] {
        guard node.identifier == tag, case .constructed(let nodes) = node.content else { throw invalid }
        return Array(nodes)
    }
    public static func primitive(_ node: ASN1Node, tag: ASN1Identifier? = nil) throws -> Data {
        if let tag, node.identifier != tag { throw invalid }
        guard case .primitive(let bytes) = node.content else { throw invalid }; return Data(bytes)
    }
    public static func oid(_ node: ASN1Node) throws -> String { try ASN1ObjectIdentifier(derEncoded: node).oidComponents.map(String.init).joined(separator: ".") }
    public static var invalid: CertificateFailure { .init("Invalid or unsupported DER field structure.") }
    public static func integer(_ node: ASN1Node) throws -> Data {
        let bytes = try primitive(node, tag: .integer)
        guard let first = bytes.first, first & 128 == 0, bytes.count < 2 || first != 0 || bytes[1] & 128 != 0 else { throw invalid }
        return bytes
    }
    public static func smallInteger(_ node: ASN1Node) throws -> Int {
        let data = try integer(node); guard data.count <= 4 else { throw invalid }
        return data.reduce(0) { $0 * 256 + Int($1) }
    }
    public static func algorithm(_ node: ASN1Node) throws -> (String, [ASN1Node]) {
        let nodes = try children(node); guard (1...2).contains(nodes.count) else { throw invalid }
        return (try oid(nodes[0]), Array(nodes.dropFirst()))
    }
    static let names: [String: String] = ["2.5.4.3":"CN", "2.5.4.6":"C", "2.5.4.7":"L", "2.5.4.8":"ST", "2.5.4.10":"O", "2.5.4.11":"OU", "1.2.840.113549.1.9.1":"Email", "2.5.29.17":"Subject Alternative Name", "2.5.29.19":"Basic Constraints", "2.5.29.15":"Key Usage", "2.5.29.37":"Extended Key Usage", "2.5.29.14":"Subject Key Identifier", "2.5.29.35":"Authority Key Identifier", "1.3.6.1.5.5.7.1.1":"Authority Information Access", "2.5.29.31":"CRL Distribution Points", "2.5.29.32":"Certificate Policies", "1.2.840.113549.1.1.1":"RSA", "1.2.840.10045.2.1":"EC", "1.3.101.112":"Ed25519", "1.2.840.113549.1.1.11":"RSA with SHA-256", "1.2.840.113549.1.1.12":"RSA with SHA-384", "1.2.840.113549.1.1.13":"RSA with SHA-512", "1.2.840.113549.1.1.10":"RSA-PSS", "1.2.840.10045.4.3.2":"ECDSA with SHA-256", "1.2.840.10045.4.3.3":"ECDSA with SHA-384", "1.2.840.10045.4.3.4":"ECDSA with SHA-512", "1.2.840.10045.3.1.7":"P-256", "1.3.132.0.34":"P-384", "1.3.132.0.35":"P-521"]
    public static func name(_ oid: String) -> String { names[oid].map { "\($0) · \(oid)" } ?? oid }
    static func string(_ node: ASN1Node) throws -> String {
        let data = try primitive(node)
        switch node.identifier {
        case .utf8String: guard let s = String(data: data, encoding: .utf8) else { throw invalid }; return s
        case .printableString, .ia5String:
            guard data.allSatisfy({ $0 < 128 }) else { throw invalid }; return String(decoding: data, as: UTF8.self)
        default:
            if node.identifier.tagClass == .universal && node.identifier.tagNumber == 30 {
                guard data.count % 2 == 0, let s = String(data: data, encoding: .utf16BigEndian) else { throw invalid }; return s
            }
            return "[ASN.1 tag \(node.identifier.tagNumber)] \(CertificateDisplay.hex(data))"
        }
    }
    static func distinguishedName(_ node: ASN1Node) throws -> [String] {
        try children(node).map { set in
            try children(set, tag: .set).map { attribute in
                let a = try children(attribute); guard a.count == 2 else { throw invalid }
                let id = try oid(a[0]); return "\(names[id] ?? id)=\(escapeDN(try string(a[1])))"
            }.joined(separator: " + ")
        }
    }
    private static func escapeDN(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        return scalars.enumerated().map { index, scalar in
            let special = ",+\"\\<>;=".unicodeScalars.contains(scalar) || (index == 0 && (scalar == " " || scalar == "#")) || (index == scalars.count-1 && scalar == " ")
            return (special ? "\\" : "") + String(scalar)
        }.joined()
    }
    static func time(_ node: ASN1Node) throws -> Date {
        var parts: DateComponents
        if node.identifier == .utcTime {
            let t = try UTCTime(derEncoded: node); parts = DateComponents(year: t.year, month: t.month, day: t.day, hour: t.hours, minute: t.minutes, second: t.seconds)
        } else {
            let t = try GeneralizedTime(derEncoded: node); parts = DateComponents(year: t.year, month: t.month, day: t.day, hour: t.hours, minute: t.minutes, second: t.seconds)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: parts) else { throw invalid }; return date
    }
    public static func inspect(_ der: Data, id: Int = 0, sourceRange: NSRange? = nil) -> CertificateEntry {
        var entry = CertificateEntry(id: id, der: der, sourceRange: sourceRange)
        guard der.count <= CertificateLimits.certificate else { entry.issues = ["Certificate exceeds 256 KiB."]; return entry }
        entry.sha256 = CertificateDisplay.digest(der)
        entry.sha1 = Insecure.SHA1.hash(data:der).map { String(format:"%02X",$0) }.joined(separator:":")
        do {
            guard der.count <= CertificateLimits.certificate else { throw CertificateFailure(.resource, "Certificate exceeds 256 KiB.") }
            let root = try DER.parse(Array(der)), outer = try children(root)
            guard outer.count == 3 else { throw invalid }
            let signature = try algorithm(outer[1]); _ = try ASN1BitString(derEncoded: outer[2])
            let tbs = try children(outer[0]); var offset = 0, version = 0
            if tbs.first?.identifier == ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific) {
                let v = try children(tbs[0], tag: tbs[0].identifier); guard v.count == 1 else { throw invalid }
                version = try smallInteger(v[0]); guard version <= 2 else { throw invalid }; offset += 1
            }
            guard tbs.count >= offset + 6 else { throw invalid }
            let serial = try integer(tbs[offset]), tbsAlgorithm = try algorithm(tbs[offset+1])
            let issuer = try distinguishedName(tbs[offset+2]), dates = try children(tbs[offset+3]), subject = try distinguishedName(tbs[offset+4])
            guard dates.count == 2 else { throw invalid }
            entry.notBefore = try time(dates[0]); entry.notAfter = try time(dates[1])
            entry.subject = subject.joined(separator: ", "); if entry.subject.isEmpty { entry.subject = "Empty subject" }
            entry.issuer = issuer.joined(separator: ", ")
            entry.spki = Data(tbs[offset+5].encodedBytes)
            entry.spkiDigest = entry.spki.map(CertificateDisplay.digest)
            let spki = try children(tbs[offset+5]); guard spki.count == 2 else { throw invalid }
            let publicAlgorithm = try algorithm(spki[0]); _ = try ASN1BitString(derEncoded: spki[1])
            func add(_ name: String, _ value: String) { entry.fields.append(.init(id: entry.fields.count, name: name, value: value)) }
            add("Version", "v\(version+1)"); add("Serial number · hex", CertificateDisplay.hex(serial))
            add("Subject", entry.subject); add("Issuer", entry.issuer)
            add("Signature algorithm", name(signature.0)); add("Signature parameters · DER", signature.1.map { CertificateDisplay.hex(Data($0.encodedBytes)) }.joined(separator: " "))
            add("Public-key algorithm", name(publicAlgorithm.0))
            if let curve = publicAlgorithm.1.first, curve.identifier == .objectIdentifier { add("Curve", name(try oid(curve))) }
            if let spki = entry.spki, let key = try? PublicKeyMaterialImporter.spki(spki) { add("Key size", "\(key.bits) bits") }
            if !outer[1].encodedBytes.elementsEqual(tbs[offset+1].encodedBytes) { entry.issues.append("Inner and outer signature algorithm identifiers differ.") }
            if tbsAlgorithm.0.isEmpty { throw invalid }
            if let a = entry.notBefore, let b = entry.notAfter, a > b { entry.issues.append("Validity interval is inverted.") }
            var seen = Set<String>(), optionalTag: UInt = 0
            for extra in tbs.dropFirst(offset+6) {
                guard extra.identifier.tagClass == .contextSpecific, (1...3).contains(extra.identifier.tagNumber), extra.identifier.tagNumber > optionalTag else { throw invalid }
                optionalTag = extra.identifier.tagNumber
                if optionalTag != 3 { continue }
                guard version == 2 else { throw invalid }
                let wrapper = try children(extra, tag: extra.identifier); guard wrapper.count == 1 else { throw invalid }
                for ext in try children(wrapper[0]) {
                    try Task.checkCancellation()
                    let fields = try children(ext); guard (2...3).contains(fields.count) else { throw invalid }
                    let oid = try self.oid(fields[0]); var critical = false
                    if fields.count == 3 { critical = try Bool(derEncoded: fields[1]) }
                    let bytes = try primitive(fields.last!, tag: .octetString)
                    if !seen.insert(oid).inserted { entry.issues.append("Duplicate extension OID: \(oid).") }
                    entry.extensions.append(CertificateExtensions.decode(id: entry.extensions.count, oid: oid, critical: critical, bytes: bytes))
                }
            }
            entry.issues += entry.extensions.compactMap(\.issue)
            entry.parsed = true
        } catch is CancellationError { entry.issues = ["Inspection cancelled."] }
        catch let e as CertificateFailure { entry.issues.append(e.message) }
        catch { entry.issues.append("Certificate DER could not be decoded. No exact byte position is available.") }
        return entry
    }
}
