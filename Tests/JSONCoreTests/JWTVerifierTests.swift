import Foundation
import CryptoKit
import Testing
import Security
import CertificateCore
@testable import JSONCore
struct JWTVerifierTests {
    let secret = String(repeating:"synthetic-fixture-",count:4)
    func token(_ payload: String = "{}", header: String = #"{"alg":"HS256"}"#) -> String {
        let message = JWTSigningProvider.base64URL(Data(header.utf8))+"."+JWTSigningProvider.base64URL(Data(payload.utf8))
        return message+"."+JWTSigningProvider.base64URL(Data(HMAC<SHA256>.authenticationCode(for:Data(message.utf8),using:SymmetricKey(data:Data(secret.utf8)))))
    }
    func request(_ payload: String = "{}", header: String = #"{"alg":"HS256"}"#) -> JWTVerifierRequest { .init(token:token(payload,header:header),key:secret,algorithm:.hs256,format:.secretUTF8) }
    @Test func fourteenIndependentVectorsAndTampering() throws {
        for vector in try JWTEncoderVector.all() {
            let request = JWTVerifierRequest(token:vector.token,key:vector.publicKey ?? vector.key,algorithm:.init(rawValue:vector.alg),format:vector.publicKey == nil ? .secretUTF8 : .publicPEM)
            let result = JWTVerifierProcessor.process(request)
            #expect(result.signature == .matches,"profile \(vector.alg): \(result.message)")
            var bad = request; var signature = Data(base64Encoded:vector.signature)!; signature[0] ^= 1
            bad.token = vector.message+"."+JWTSigningProvider.base64URL(signature)
            #expect(JWTVerifierProcessor.process(bad).signature == .doesNotMatch)
            bad.token = vector.message+"."+JWTSigningProvider.base64URL(Data(repeating:0,count:signature.count))
            #expect(JWTVerifierProcessor.process(bad).signature != .matches)
            bad = request; bad.algorithm = request.algorithm == .hs256 ? .hs512 : .hs256
            #expect(JWTVerifierProcessor.process(bad).signature == .notChecked)
        }
    }
    @Test func exactSourceAndStrictProfileFailures() {
        let r = request(#" { "big": 123456789012345678901234567890123456789, "escape":"\u0061", "n":-0.000e0 } "#)
        #expect(JWTVerifierProcessor.process(r).signature == .matches)
        for header in [#"{"alg":"HS256","typ":123}"#, #"{"alg":"HS256","cty":false}"#, #"{"alg":"HS256","alg":"HS256"}"#, #"{"alg":"HS256","crit":["x"],"x":true}"#, #"{"alg":"HS256","b64":false}"#, #"{"alg":"HS256","kid":23}"#, #"{"alg":"HS256","enc":"x"}"#, #"{"alg":"HS256","cty":"application/jwt"}"#] {
            #expect(JWTVerifierProcessor.process(request(header:header)).signature == .notChecked)
        }
        #expect(JWTVerifierProcessor.process(request(#"{"x":1,"x":2}"#)).signature == .notChecked)
        #expect(JWTVerifierProcessor.process(request(header:#"{"alg":"HS256","crit":["b64"],"b64":true}"#)).signature == .matches)
        var empty = request(); empty.algorithm = nil; #expect(JWTVerifierProcessor.process(empty).signature == .notChecked)
        empty = request(); empty.token += "="; #expect(JWTVerifierProcessor.process(empty).signature == .notChecked)
    }
    @Test func independentSignatureAndClaimsAxesAndExactDates() {
        let now = Date(timeIntervalSince1970:1000)
        let expired = JWTVerifierProcessor.process(request(#"{"exp":1000,"nbf":1000,"iat":1001}"#),now:now)
        #expect(expired.signature == .matches && !expired.claimsPassed)
        #expect(expired.checks.first { $0.id == "exp" }?.state == .failed)
        #expect(expired.checks.first { $0.id == "nbf" }?.state == .passed)
        #expect(expired.checks.first { $0.id == "iat" }?.state == .notConfigured)
        var r = request(#"{"exp":1000,"nbf":1001,"iat":1001}"#); r.policy.skew = 1; r.policy.checkFutureIat = true
        #expect(JWTVerifierProcessor.process(r,now:now).claimsPassed)
        r.policy.skew = 0; #expect(!JWTVerifierProcessor.process(r,now:now).claimsPassed)
        let exact = request(#"{"exp":1000.000000000000000000001,"nbf":1e-999999999999999999,"iat":1e999999999999999999}"#)
        #expect(JWTVerifierProcessor.process(exact,now:now).claimsPassed)
        var missing = request(); missing.policy.requireExp = true; #expect(!JWTVerifierProcessor.process(missing,now:now).claimsPassed)
        let malformed = JWTVerifierProcessor.process(request(#"{"exp":"1001","aud":[true]}"#),now:now)
        #expect(malformed.signature == .matches && !malformed.claimsPassed)
    }
    @Test func issuerAudienceScalarEqualityAndSummaryPrivacy() {
        var r = request(#"{"iss":"é","aud":["one","two"],"sub":"subject","exp":9999999999}"#)
        r.policy.issuerEnabled = true; r.policy.issuer = "e\u{301}"; r.policy.audienceEnabled = true; r.policy.audience = "two"
        var result = JWTVerifierProcessor.process(r); #expect(!result.claimsPassed)
        r.policy.issuer = "é"; result = JWTVerifierProcessor.process(r); #expect(result.claimsPassed)
        r.policy.subjectEnabled = true; r.policy.subject = "SUBJECT"; #expect(!JWTVerifierProcessor.process(r).claimsPassed)
        #expect(!result.summary.contains(secret) && !result.summary.contains(r.token) && !result.summary.contains("subject"))
    }
    @Test func sharedSecretEncodingsAndKeyConfusion() throws {
        var r = request(); let bytes = Data(secret.utf8)
        for (format,key) in [(JWTVerificationKeyFormat.secretUTF8,secret),(.secretHex,bytes.map { String(format:"%02x",$0) }.joined()),(.secretBase64,bytes.base64EncodedString()),(.secretBase64URL,JWTSigningProvider.base64URL(bytes))] {
            r.format = format; r.key = key; #expect(JWTVerifierProcessor.process(r).signature == .matches)
        }
        r = request(); r.key = String(repeating:"different-fixture-",count:4); #expect(JWTVerifierProcessor.process(r).signature == .doesNotMatch)
        r = request(); r.key = "too short"; #expect(JWTVerifierProcessor.process(r).signature == .notChecked)
        let rsa = try #require(JWTEncoderVector.all().first { $0.alg == "RS256" })
        r = request(); r.key = rsa.publicKey!; #expect(JWTVerifierProcessor.process(r).signature == .notChecked)
        let material = try PublicKeyMaterialImporter.read(rsa.publicKey!)
        r.format = .secretBase64; r.key = material.spki.base64EncodedString(); #expect(JWTVerifierProcessor.process(r).signature == .notChecked)
    }
    @Test func localJWKAndJWKSSelectionAndMetadata() throws {
        let k = JWTSigningProvider.base64URL(Data(secret.utf8))
        let jwk = #"{"kty":"oct","k":"\#(k)","kid":"test","use":"sig","key_ops":["verify"],"alg":"HS256"}"#
        var r = request(header:#"{"alg":"HS256","kid":"test","jku":"https://example.invalid","jwk":{"kty":"oct","k":"bad"}}"#)
        r.format = .jwk; r.key = jwk
        #expect(JWTVerifierProcessor.process(r).signature == .notChecked)
        r.keyIndex = 0; #expect(JWTVerifierProcessor.process(r).signature == .matches)
        r.key = #"{"keys":[\#(jwk),\#(jwk)]}"#
        #expect(try JWKReader.choices(r.key).count == 2); r.keyIndex = 1
        #expect(try JWKReader.choices(#"{"kty":"OKP","crv":"Ed448"}"#)[0].supported == false)
        #expect(JWTVerifierProcessor.process(r).signature == .matches)
        for bad in [jwk.replacingOccurrences(of:"\"verify\"",with:"\"sign\""),jwk.replacingOccurrences(of:"\"sig\"",with:"\"enc\""),jwk.replacingOccurrences(of:"\"test\"",with:"\"other\""),jwk.dropLast()+",\"d\":\"x\"}",jwk.dropLast()+",\"kty\":\"oct\"}"] {
            r.key = String(bad); r.keyIndex = 0; #expect(JWTVerifierProcessor.process(r).signature == .notChecked)
        }
    }
    @Test func publicJWKsAllFamiliesAndThumbprints() throws {
        for vector in try JWTEncoderVector.all() where vector.publicKey != nil {
            let material = try PublicKeyMaterialImporter.read(vector.publicKey!)
            let json: String
            switch material.kind {
            case .rsa:
                // Existing RSA fixtures use exponent 65537; modulus extracted via a standard DER object.
                let pkcs = try JWTDERReaderForTest.rsa(material.bytes)
                json = #"{"kty":"RSA","n":"\#(JWTSigningProvider.base64URL(pkcs.0))","e":"\#(JWTSigningProvider.base64URL(pkcs.1))"}"#
            case .ed25519: json = #"{"kty":"OKP","crv":"Ed25519","x":"\#(JWTSigningProvider.base64URL(material.bytes))"}"#
            default:
                let length = (material.bytes.count-1)/2, curve = material.kind == .p256 ? "P-256" : material.kind == .p384 ? "P-384" : "P-521"
                let point = Array(material.bytes)
                json = #"{"kty":"EC","crv":"\#(curve)","x":"\#(JWTSigningProvider.base64URL(Data(point[1...length])))","y":"\#(JWTSigningProvider.base64URL(Data(point[(length+1)...])))"}"#
            }
            let r = JWTVerifierRequest(token:vector.token,key:json,algorithm:.init(rawValue:vector.alg),format:.jwk,keyIndex:0)
            let result = JWTVerifierProcessor.process(r); #expect(result.signature == .matches,"JWK \(vector.alg): \(result.message)")
            #expect(result.keyIdentity.contains("thumbprint"))
        }
    }
    @Test func resourceAndCancellationStatuses() async {
        var huge = request(); huge.token = String(repeating:"x",count:262145)
        #expect(JWTVerifierProcessor.process(huge).processing == .resourceLimit)
        var key = request(); key.key = String(repeating:"x",count:65537)
        #expect(JWTVerifierProcessor.process(key).processing == .resourceLimit)
        key = request();key.key = String(repeating:"k",count:8193)
        #expect(JWTVerifierProcessor.process(key).processing == .resourceLimit)
        key = request();key.format = .secretBase64;key.key = Data(repeating:1,count:16385).base64EncodedString()
        #expect(JWTVerifierProcessor.process(key).processing == .resourceLimit)
        #expect(JWTVerifierProcessor.process(request(),budget:.init(seconds:0)).processing == .resourceLimit)
        let task = Task { () -> JWTVerifierResult in
            do { try await Task.sleep(for:.milliseconds(10)) } catch {}
            return JWTVerifierProcessor.process(request())
        }; task.cancel(); #expect(await task.value.processing == .cancelled)
    }
    @Test @MainActor func sessionPrivacyStaleResultAndForegroundExpiry() async {
        let name = "test.verifier."+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let session = JWTVerifierWorkspaceSession(defaults:defaults)
        session.token = token(); session.key = secret; session.algorithm = .hs256; session.format = .secretUTF8
        await session.run().value; #expect(session.result?.signature == .matches)
        session.token = "changed"; #expect(session.result == nil)
        session.token = token(); let task = session.run(); session.clear(); await task.value
        #expect(session.result == nil && session.token.isEmpty && session.key.isEmpty)
        let fresh = JWTVerifierWorkspaceSession(defaults:defaults)
        #expect(fresh.algorithm == nil && fresh.token.isEmpty && fresh.key.isEmpty && !fresh.policy.issuerEnabled)
    }
}
// Testing the existing small private-key DER reader on known fixtures is independent of the new public importer.
enum JWTDERReaderForTest {
    static func rsa(_ bytes: Data) throws -> (Data,Data) {
        var outer = JWTDERReader(bytes), inner = JWTDERReader(try outer.read(0x30))
        return (Data(try inner.integer().drop(while:{$0 == 0})),Data(try inner.integer().drop(while:{$0 == 0})))
    }
}

extension JWTVerifierTests {
    @Test func pssRejectsWrongSaltAndMGFWithIndependentOpenSSL() throws {
        let tool = URL(fileURLWithPath:"/opt/homebrew/bin/openssl")
        guard FileManager.default.isExecutableFile(atPath:tool.path) else { throw SkipUnavailable.openssl }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("t032-pss-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        for vector in try JWTEncoderVector.all() where vector.alg.hasPrefix("PS") {
            let key = directory.appendingPathComponent("key.pem"), message = directory.appendingPathComponent("message.bin"), sig = directory.appendingPathComponent("sig.bin")
            try Data(vector.key.utf8).write(to:key); try Data(vector.message.utf8).write(to:message)
            let digest = "sha"+String(vector.alg.dropFirst(2)), size = Int(vector.alg.dropFirst(2))!/8
            for (salt,mgf,expected) in [(String(size),digest,true),("0",digest,false),("max",digest,false),(String(size),digest == "sha256" ? "sha384" : "sha256",false)] {
                let process = Process(); process.executableURL = tool
                process.arguments = ["dgst","-"+digest,"-sign",key.path,"-sigopt","rsa_padding_mode:pss","-sigopt","rsa_pss_saltlen:"+salt,"-sigopt","rsa_mgf1_md:"+mgf,"-out",sig.path,message.path]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
                let token = vector.message+"."+JWTSigningProvider.base64URL(try Data(contentsOf:sig))
                let r = JWTVerifierProcessor.process(.init(token:token,key:vector.publicKey!,algorithm:.init(rawValue:vector.alg),format:.publicPEM))
                #expect((r.signature == .matches) == expected,"PSS \(vector.alg) salt \(salt) MGF \(mgf)")
            }
        }
    }
    enum SkipUnavailable: Error { case openssl }
}

private actor JWTVerifierRaceWorker {
    var active = 0, maximum = 0, calls = 0
    func process(_ request: JWTVerifierRequest) async -> JWTVerifierResult {
        active += 1;maximum = max(maximum,active);calls += 1
        // Deliberately noncooperative; only revision guards may publish this.
        let start = Date();while Date().timeIntervalSince(start) < 0.03 {await Task.yield()}
        active -= 1
        return .init(signature:.matches,message:request.token,revision:request.revision)
    }
}
extension JWTVerifierTests {
    @Test @MainActor func oneWorkerLatestWinsAndCancelledDoesNotPublish() async {
        let worker = JWTVerifierRaceWorker()
        let session = JWTVerifierWorkspaceSession(worker:{await worker.process($0)})
        session.token = "first";let job = session.run()
        try? await Task.sleep(for:.milliseconds(5))
        for i in 0..<20 {session.token = "request-\(i)";session.run()}
        session.token = "latest";let latestJob = session.run();await job.value;await latestJob.value
        #expect(session.result?.message == "latest")
        let maximum = await worker.maximum, calls = await worker.calls
        #expect(maximum == 1 && calls <= 3)
        let cancelled = session.run();session.cancel();await cancelled.value
        #expect(session.result?.message == "latest")
        let clearing = session.run();session.clear();await clearing.value
        #expect(session.result == nil && session.token.isEmpty)
    }
}


extension JWTVerifierTests {
    @Test func certificateKeySourceIsNotCertificateTrust() throws {
        let vector = try #require(JWTEncoderVector.all().first {$0.alg == "RS256"})
        let pem = try String(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/JWTVerifier/certificate.pem"),encoding:.utf8)
        let request = JWTVerifierRequest(token:vector.token,key:pem,algorithm:.rs256,format:.certificate)
        let r = JWTVerifierProcessor.process(request,now:.distantFuture)
        #expect(r.signature == .matches)
        #expect(r.keyNotes.contains {$0.contains("Expired")})
        #expect(r.keyNotes.contains {$0.contains("Trust") || $0.contains("trust")})
        #expect(r.keyIdentity.contains("SPKI SHA-256"))
    }
}
