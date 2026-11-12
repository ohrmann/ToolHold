import Foundation
import CryptoKit
import Security
#if SWIFT_PACKAGE
import EncodingCore
#endif

/// Key handles stay in one synchronous worker invocation; never stored in UI artifacts.
enum JWTPreparedSigningKey {
    case hmac(Data, JWTSigningAlgorithm)
    case rsa(SecKey, SecKeyAlgorithm)
    case p256(P256.Signing.PrivateKey), p384(P384.Signing.PrivateKey), p521(P521.Signing.PrivateKey)
    case ed(Curve25519.Signing.PrivateKey)
    case unsigned
    var signatureBytes: Int {
        switch self {
        case .hmac(_, let alg): alg.signatureBytes
        case .rsa(let key, _): SecKeyGetBlockSize(key)
        case .p256, .ed: 64
        case .p384: 96
        case .p521: 132
        case .unsigned: 0
        }
    }
    func sign(_ message: Data) throws -> Data {
        let signature: Data, verified: Bool
        switch self {
        case .hmac(let bytes, let algorithm):
            let key = SymmetricKey(data: bytes)
            switch algorithm {
            case .hs256:
                signature = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
                verified = HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: message, using: key)
            case .hs384:
                signature = Data(HMAC<SHA384>.authenticationCode(for: message, using: key))
                verified = HMAC<SHA384>.isValidAuthenticationCode(signature, authenticating: message, using: key)
            default:
                signature = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
                verified = HMAC<SHA512>.isValidAuthenticationCode(signature, authenticating: message, using: key)
            }
        case .rsa(let key, let algorithm):
            var error: Unmanaged<CFError>?
            let value = SecKeyCreateSignature(key, algorithm, message as CFData, &error)
            if let error { _ = error.takeRetainedValue() }; error = nil
            guard let value, let publicKey = SecKeyCopyPublicKey(key) else { throw JWTSigningProvider.failed }
            signature = value as Data
            verified = SecKeyVerifySignature(publicKey, algorithm, message as CFData, value, &error)
            if let error { _ = error.takeRetainedValue() }
        case .p256(let key):
            let value = try key.signature(for: message); signature = value.rawRepresentation
            verified = key.publicKey.isValidSignature(value, for: message)
        case .p384(let key):
            let value = try key.signature(for: message); signature = value.rawRepresentation
            verified = key.publicKey.isValidSignature(value, for: message)
        case .p521(let key):
            let value = try key.signature(for: message); signature = value.rawRepresentation
            verified = key.publicKey.isValidSignature(value, for: message)
        case .ed(let key): signature = try key.signature(for: message); verified = key.publicKey.isValidSignature(signature, for: message)
        case .unsigned: return Data()
        }
        guard verified, signature.count == signatureBytes else { throw JWTSigningProvider.failed }
        return signature
    }
}
enum JWTSigningProvider {
    static var failed: JWTSigningFailure { .init(code: "SIGN-FAILURE", message: "The system could not sign and verify this token with the supplied key.", status: .cryptoFailure) }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decodedSecret(_ source: String, encoding: JWTSigningKeyEncoding) throws -> Data {
        let bytes: Data
        switch encoding {
        case .utf8: bytes = Data(source.utf8)
        case .base64:
            guard let value = Data(base64Encoded: source), value.base64EncodedString() == source else { throw malformedEncoding }
            bytes = value
        case .base64URL:
            do { bytes = try JWTBase64URLDecoder.decode(source, maximumLength: JWTEncoderLimits.keyInput) }
            catch is CancellationError { throw CancellationError() }
            catch { throw malformedEncoding }
        case .hex:
            let digits = Array(source.utf8)
            guard digits.count % 2 == 0 else { throw malformedEncoding }
            func nibble(_ byte: UInt8) -> UInt8? {
                switch byte { case 48...57: byte - 48; case 65...70: byte - 55; case 97...102: byte - 87; default: nil }
            }
            var value = Data(); value.reserveCapacity(digits.count / 2)
            for i in stride(from: 0, to: digits.count, by: 2) {
                guard let a = nibble(digits[i]), let b = nibble(digits[i+1]) else { throw malformedEncoding }
                value.append(a * 16 + b)
            }
            bytes = value
        case .pem: throw malformedEncoding
        }
        guard bytes.count <= JWTEncoderLimits.keyBytes else { throw JWTSigningFailure(code: "KEY-SIZE", message: "Decoded key exceeds 16,384 bytes.", status: .resourceLimit) }
        return bytes
    }
    static var malformedEncoding: JWTSigningFailure { .init(code: "KEY-ENCODING", message: "Key text is not valid in the selected encoding. No whitespace, padding or characters were removed.") }
    static func prepare(_ request: JWTEncoderRequest, algorithm alg: JWTSigningAlgorithm) throws -> JWTPreparedSigningKey {
        try Task.checkCancellation()
        if alg == .none {
            guard request.unsignedConsent else { throw JWTSigningFailure(code: "UNSIGNED-CONSENT", message: "Explicitly enable Unsigned test token before generating a token without integrity protection.") }
            return .unsigned
        }
        guard request.key.utf16.prefix(JWTEncoderLimits.keyInput + 1).count <= JWTEncoderLimits.keyInput else { throw JWTSigningFailure(code: "KEY-SIZE", message: "Key input exceeds 65,536 UTF-16 code units.", status: .resourceLimit) }
        guard !request.key.isEmpty else { throw JWTSigningFailure(code: "KEY-EMPTY", message: "Enter a signing secret or private key.") }
        do {
            switch alg.family {
            case .hmac:
                let bytes = try decodedSecret(request.key, encoding: request.keyEncoding)
                guard bytes.count >= alg.signatureBytes else { throw JWTSigningFailure(code: "KEY-HMAC-SHORT", message: "\(alg.rawValue) requires at least \(alg.signatureBytes) key bytes. Text length alone does not establish entropy.") }
                guard bytes.count <= JWTEncoderLimits.hmacBytes else { throw JWTSigningFailure(code: "KEY-SIZE", message: "HMAC keys may contain at most 8,192 bytes.", status: .resourceLimit) }
                return .hmac(bytes, alg)
            case .rsa:
                guard request.keyEncoding == .pem else { throw JWTSigningFailure(code: "KEY-FORMAT", message: "Select PEM for an RSA private key.") }
                let key = try JWTPrivateKeyImporter.rsa(JWTPrivateKeyImporter.pem(request.key))
                let algorithm: SecKeyAlgorithm
                switch alg {
                case .rs256: algorithm = .rsaSignatureMessagePKCS1v15SHA256
                case .rs384: algorithm = .rsaSignatureMessagePKCS1v15SHA384
                case .rs512: algorithm = .rsaSignatureMessagePKCS1v15SHA512
                case .ps256: algorithm = .rsaSignatureMessagePSSSHA256
                case .ps384: algorithm = .rsaSignatureMessagePSSSHA384
                default: algorithm = .rsaSignatureMessagePSSSHA512
                }
                guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else { throw JWTSigningFailure(code: "KEY-UNSUPPORTED", message: "The system does not support this algorithm with the supplied key.", status: .unsupported) }
                return .rsa(key, algorithm)
            case .ec:
                guard request.keyEncoding == .pem else { throw JWTSigningFailure(code: "KEY-FORMAT", message: "Select PEM for an EC private key.") }
                let pem = try JWTPrivateKeyImporter.pem(request.key)
                try validateEC(pem, algorithm: alg)
                switch alg {
                case .es256: return .p256(try P256.Signing.PrivateKey(pemRepresentation: pem.canonical))
                case .es384: return .p384(try P384.Signing.PrivateKey(pemRepresentation: pem.canonical))
                default: return .p521(try P521.Signing.PrivateKey(pemRepresentation: pem.canonical))
                }
            case .ed:
                let seed: Data
                if request.keyEncoding == .pem { seed = try JWTPrivateKeyImporter.edSeed(JWTPrivateKeyImporter.pem(request.key)) }
                else {
                    guard request.keyEncoding == .hex || request.keyEncoding == .base64 else { throw JWTSigningFailure(code: "KEY-FORMAT", message: "Use PEM, Base64 or Hex for a 32-byte Ed25519 seed.") }
                    seed = try decodedSecret(request.key, encoding: request.keyEncoding)
                }
                guard seed.count == 32 else { throw JWTSigningFailure(code: "KEY-ED-SIZE", message: "Ed25519 requires exactly 32 seed bytes. Expanded 64-byte secrets are not truncated.") }
                return .ed(try Curve25519.Signing.PrivateKey(rawRepresentation: seed))
            case .unsigned: return .unsigned
            }
        } catch let error as JWTSigningFailure { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw JWTSigningFailure(code: "KEY-IMPORT", message: "The private key could not be imported for the selected algorithm and curve.") }
    }
    private static func validateEC(_ pem: JWTPEMBlock, algorithm: JWTSigningAlgorithm) throws {
        let curve: Data = algorithm == .es256 ? Data([0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07]) : algorithm == .es384 ? Data([0x2b,0x81,0x04,0x00,0x22]) : Data([0x2b,0x81,0x04,0x00,0x23])
        var outer = JWTDERReader(pem.der), seq = JWTDERReader(try outer.read(0x30))
        guard outer.finished else { throw JWTDERReader.invalid }
        switch pem.label {
        case "PRIVATE KEY":
            guard try seq.integer() == Data([0]) else { throw JWTSigningFailure(code: "KEY-PKCS8-VERSION", message: "Only PKCS#8 version 0 is supported.", status: .unsupported) }
            var info = JWTDERReader(try seq.read(0x30))
            guard try info.read(6) == JWTPrivateKeyImporter.ecOID, try info.read(6) == curve, info.finished else { throw JWTDERReader.invalid }
            _ = try seq.read(4); guard seq.finished else { throw JWTDERReader.invalid }
        case "EC PRIVATE KEY":
            guard try seq.integer() == Data([1]) else { throw JWTDERReader.invalid }
            _ = try seq.read(4)
            var parameters = JWTDERReader(try seq.read(0xa0))
            guard try parameters.read(6) == curve, parameters.finished else { throw JWTDERReader.invalid }
            if !seq.finished { _ = try seq.read(0xa1) }
            guard seq.finished else { throw JWTDERReader.invalid }
        default: throw JWTSigningFailure(code: "KEY-TYPE", message: "An EC private key matching the selected curve is required.")
        }
    }
}
