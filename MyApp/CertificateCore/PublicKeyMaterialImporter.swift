import Foundation
import SwiftASN1

public struct PublicKeyMaterial: Sendable {
    public enum Kind: String, Sendable { case rsa, p256, p384, p521, ed25519 }
    public let kind: Kind
    public let bytes: Data // RSA PKCS#1, EC uncompressed point, or Ed25519 raw public bytes.
    public let spki: Data
    public let bits: Int
}
public enum PublicKeyMaterialImporter {
    static let rsaOID = "1.2.840.113549.1.1.1", ecOID = "1.2.840.10045.2.1", edOID = "1.3.101.112"
    public static func spki(_ data: Data) throws -> PublicKeyMaterial {
        guard data.count <= 16384 else { throw CertificateFailure(.resource, "Public key exceeds 16,384 bytes.") }
        let fields = try CertificateDER.children(DER.parse(Array(data)))
        guard fields.count == 2 else { throw CertificateDER.invalid }
        let (oid, parameters) = try CertificateDER.algorithm(fields[0])
        let bits = try ASN1BitString(derEncoded: fields[1]); guard bits.paddingBits == 0 else { throw CertificateDER.invalid }
        let bytes = Data(bits.bytes)
        if oid == rsaOID {
            guard parameters.isEmpty || (parameters.count == 1 && parameters[0].identifier == .null && (try? CertificateDER.primitive(parameters[0]))?.isEmpty == true) else { throw CertificateDER.invalid }
            let key = try rsaPKCS1(bytes); return .init(kind: .rsa, bytes: bytes, spki: data, bits: key.bits)
        }
        if oid == edOID {
            guard parameters.isEmpty, bytes.count == 32 else { throw CertificateDER.invalid }
            return .init(kind: .ed25519, bytes: bytes, spki: data, bits: 256)
        }
        if oid == ecOID {
            guard parameters.count == 1 else { throw CertificateFailure(.unsupported, "Use an EC public key with a named curve.") }
            let curve = try CertificateDER.oid(parameters[0])
            let kind: PublicKeyMaterial.Kind, size: Int, length: Int
            switch curve {
            case "1.2.840.10045.3.1.7": kind = .p256; size = 256; length = 65
            case "1.3.132.0.34": kind = .p384; size = 384; length = 97
            case "1.3.132.0.35": kind = .p521; size = 521; length = 133
            default: throw CertificateFailure(.unsupported, "Unsupported EC curve.")
            }
            guard bytes.count == length, bytes.first == 4 else { throw CertificateFailure(.unsupported, "Use an uncompressed public EC point for this named curve.") }
            return .init(kind: kind, bytes: bytes, spki: data, bits: size)
        }
        throw CertificateFailure(.unsupported, "Unsupported public-key algorithm. Restricted RSA-PSS keys are not treated as unrestricted RSA.")
    }
    public static func rsaPKCS1(_ data: Data) throws -> PublicKeyMaterial {
        guard data.count <= 16384 else { throw CertificateFailure(.resource, "Public key exceeds 16,384 bytes.") }
        let fields = try CertificateDER.children(DER.parse(Array(data))); guard fields.count == 2 else { throw CertificateDER.invalid }
        let n = try CertificateDER.integer(fields[0]), e = try CertificateDER.integer(fields[1])
        let significant = n.drop(while: { $0 == 0 }); guard let first = significant.first, !e.allSatisfy({ $0 == 0 }) else { throw CertificateDER.invalid }
        guard let last = n.last, last & 1 == 1, e.count <= 8 else { throw CertificateDER.invalid }
        let exponent = e.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard exponent >= 3, exponent & 1 == 1 else { throw CertificateDER.invalid }
        let size = significant.count * 8 - first.leadingZeroBitCount
        return .init(kind: .rsa, bytes: data, spki: PublicKeyDEREncoding.rsaSPKI(data), bits: size)
    }
    public static func read(_ source: String) throws -> PublicKeyMaterial {
        let block = try PEMEnvelopeReader.read(source, allowed: ["PUBLIC KEY", "RSA PUBLIC KEY", "CERTIFICATE"], maximumBytes: CertificateLimits.certificate)[0]
        if block.label == "CERTIFICATE" {
            let cert = CertificateDER.inspect(block.der)
            guard cert.parsed, let data = cert.spki else { throw CertificateFailure("The certificate could not be inspected.") }
            return try spki(data)
        }
        return try block.label == "RSA PUBLIC KEY" ? rsaPKCS1(block.der) : spki(block.der)
    }
}
/// Emits only public-key envelopes from already validated fixed-schema material.
public enum PublicKeyDEREncoding {
    public static func tlv(_ tag: UInt8, _ bytes: Data) -> Data {
        var prefix = Data([tag]); let count = bytes.count
        if count < 128 { prefix.append(UInt8(count)) }
        else {
            var n = count, length: [UInt8] = []
            while n > 0 { length.insert(UInt8(n & 255), at: 0); n >>= 8 }
            prefix.append(128 | UInt8(length.count)); prefix.append(contentsOf: length)
        }
        return prefix + bytes
    }
    public static func integer(_ bytes: Data) -> Data {
        let data = Data(bytes.drop(while: { $0 == 0 })); let nonempty = data.isEmpty ? Data([0]) : data
        return tlv(2, (nonempty.first! & 128 == 0 ? Data() : Data([0])) + nonempty)
    }
    public static func rsaSPKI(_ pkcs1: Data) -> Data { tlv(0x30, Data([0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00]) + tlv(3, Data([0]) + pkcs1)) }
    public static func ecSPKI(_ point: Data, curve: String) -> Data {
        let oid: Data = curve == "P-256" ? Data([6,8,0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07]) : Data([6,5,0x2b,0x81,0x04,0x00,curve == "P-384" ? 0x22 : 0x23])
        return tlv(0x30, tlv(0x30, Data([6,7,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01]) + oid) + tlv(3, Data([0])+point))
    }
    public static func edSPKI(_ raw: Data) -> Data { tlv(0x30, Data([0x30,5,6,3,0x2b,0x65,0x70]) + tlv(3, Data([0])+raw)) }
}
