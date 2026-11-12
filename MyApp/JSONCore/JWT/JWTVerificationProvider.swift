import Foundation
import Security
import CryptoKit
#if SWIFT_PACKAGE
import CertificateCore
#endif

enum JWTVerificationProvider {
    static func verify(_ request: JWTVerifierRequest, algorithm: JWTSigningAlgorithm, tokenKid: String?, message: Data, signature: Data, now: Date = .now) throws -> (Bool,String,[String]) {
        let inputLimit = request.format == .certificate ? 400000 : request.format == .jwk ? 262144 : 65536
        guard request.key.utf16.prefix(inputLimit+1).count <= inputLimit else { throw JWTVerificationFailure("Verification key input exceeds its limit.",resource:true) }
        let material: PublicKeyMaterial?, secret: Data?, identity: String
        var notes: [String] = []
        if request.format == .jwk {
            let key = try JWKReader.key(request.key,index:request.keyIndex,algorithm:algorithm,tokenKid:tokenKid)
            material = key.material; secret = key.secret; identity = key.identity
        } else if request.format.secret {
            guard algorithm.family == .hmac else { throw JWTVerificationFailure("Select a public key source for this algorithm.") }
            guard !request.key.contains("-----BEGIN ") else { throw JWTVerificationFailure("Asymmetric PEM material is not accepted as an HMAC secret.") }
            let encoding: JWTSigningKeyEncoding
            switch request.format { case .secretUTF8: encoding = .utf8; case .secretHex: encoding = .hex; case .secretBase64: encoding = .base64; default: encoding = .base64URL }
            do { secret = try JWTSigningProvider.decodedSecret(request.key,encoding:encoding) }
            catch let failure as JWTSigningFailure { throw JWTVerificationFailure(failure.message,resource:failure.status == .resourceLimit) }
            catch is CancellationError { throw CancellationError() }
            catch { throw JWTVerificationFailure("Secret is invalid in the selected exact encoding.") }
            material = nil; identity = "Explicit shared secret"
        } else {
            guard algorithm.family != .hmac else { throw JWTVerificationFailure("Select Shared Secret or a local oct JWK for HMAC. Public keys cannot become secrets.") }
            if request.format == .edHex || request.format == .edBase64 {
                let raw: Data
                do { raw = try JWTSigningProvider.decodedSecret(request.key,encoding:request.format == .edHex ? .hex : .base64) }
                catch { throw JWTVerificationFailure("Invalid Ed25519 public key encoding.") }
                guard raw.count == 32 else { throw JWTVerificationFailure("Ed25519 public key must be exactly 32 bytes.") }
                material = try PublicKeyMaterialImporter.spki(PublicKeyDEREncoding.edSPKI(raw))
            } else {
                let allowed: Set<String> = request.format == .certificate ? ["CERTIFICATE"] : ["PUBLIC KEY","RSA PUBLIC KEY"]
                let block = try PEMEnvelopeReader.read(request.key,allowed:allowed,maximumBytes:request.format == .certificate ? CertificateLimits.certificate : 16384)[0]
                if request.format == .certificate {
                    let cert = CertificateDER.inspect(block.der)
                    guard cert.parsed, let spki = cert.spki else { throw JWTVerificationFailure("Certificate could not be inspected.") }
                    material = try PublicKeyMaterialImporter.spki(spki)
                    notes = ["Certificate: "+cert.validity(at:now),"Certificate trust and revocation not evaluated."]
                    notes += cert.extensions.filter { ["2.5.29.15","2.5.29.37"].contains($0.oid) }.flatMap { $0.fields.map { $0.value } }
                } else { material = try block.label == "RSA PUBLIC KEY" ? PublicKeyMaterialImporter.rsaPKCS1(block.der) : PublicKeyMaterialImporter.spki(block.der) }
            }
            secret = nil; identity = "SPKI SHA-256 · " + CertificateDisplay.digest(material!.spki)
        }
        if let secret {
            guard secret.count <= 8192 else { throw JWTVerificationFailure("Shared secret exceeds 8,192 decoded bytes.",resource:true) }
            guard algorithm.family == .hmac, secret.count >= algorithm.signatureBytes else { throw JWTVerificationFailure("Key policy failed: HMAC needs at least \(algorithm.signatureBytes) bytes.") }
            // Reject a DER asymmetric public key even if supplied through an explicit binary secret encoding.
            if (try? PublicKeyMaterialImporter.spki(secret)) != nil || (try? PublicKeyMaterialImporter.rsaPKCS1(secret)) != nil { throw JWTVerificationFailure("Asymmetric public-key DER is not accepted as a shared secret.") }
            let key = SymmetricKey(data:secret), valid: Bool
            guard signature.count == algorithm.signatureBytes else { return (false,identity,notes) }
            switch algorithm { case .hs256: valid = HMAC<SHA256>.isValidAuthenticationCode(signature,authenticating:message,using:key)
            case .hs384: valid = HMAC<SHA384>.isValidAuthenticationCode(signature,authenticating:message,using:key)
            default: valid = HMAC<SHA512>.isValidAuthenticationCode(signature,authenticating:message,using:key) }
            return (valid,identity,notes)
        }
        guard let material else { throw JWTVerificationFailure("No verification key selected.") }
        let valid: Bool
        switch (algorithm.family,material.kind) {
        case (.rsa,.rsa):
            guard (2048...8192).contains(material.bits) else { throw JWTVerificationFailure("Key policy failed: RSA requires 2,048–8,192 bits.") }
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(material.bytes as CFData,[kSecAttrKeyType:kSecAttrKeyTypeRSA,kSecAttrKeyClass:kSecAttrKeyClassPublic] as CFDictionary,&error) else { if let error { _ = error.takeRetainedValue() }; throw JWTVerificationFailure("RSA public key import failed.") }
            if let error { _ = error.takeRetainedValue() }; error = nil
            let native: SecKeyAlgorithm
            switch algorithm {
            case .rs256: native = .rsaSignatureMessagePKCS1v15SHA256; case .rs384: native = .rsaSignatureMessagePKCS1v15SHA384; case .rs512: native = .rsaSignatureMessagePKCS1v15SHA512
            case .ps256: native = .rsaSignatureMessagePSSSHA256; case .ps384: native = .rsaSignatureMessagePSSSHA384; default: native = .rsaSignatureMessagePSSSHA512
            }
            guard SecKeyIsAlgorithmSupported(key,.verify,native) else { throw JWTVerificationFailure("The system does not support this key/algorithm.") }
            guard signature.count == SecKeyGetBlockSize(key) else { return (false,identity,notes) }
            valid = SecKeyVerifySignature(key,native,message as CFData,signature as CFData,&error)
            if let error { _ = error.takeRetainedValue() }
        case (.ec,.p256) where algorithm == .es256:
            let key = try P256.Signing.PublicKey(x963Representation:material.bytes)
            valid = (try? P256.Signing.ECDSASignature(rawRepresentation:signature)).map { key.isValidSignature($0,for:message) } ?? false
        case (.ec,.p384) where algorithm == .es384:
            let key = try P384.Signing.PublicKey(x963Representation:material.bytes)
            valid = (try? P384.Signing.ECDSASignature(rawRepresentation:signature)).map { key.isValidSignature($0,for:message) } ?? false
        case (.ec,.p521) where algorithm == .es512:
            let key = try P521.Signing.PublicKey(x963Representation:material.bytes)
            valid = (try? P521.Signing.ECDSASignature(rawRepresentation:signature)).map { key.isValidSignature($0,for:message) } ?? false
        case (.ed,.ed25519): valid = try Curve25519.Signing.PublicKey(rawRepresentation:material.bytes).isValidSignature(signature,for:message)
        default: throw JWTVerificationFailure("Public key family or curve does not match the expected algorithm.")
        }
        return (valid,identity,notes)
    }
}
