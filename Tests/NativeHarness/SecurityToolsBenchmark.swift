import Foundation
import CryptoKit
import Darwin
import SwiftASN1
@testable import Developer_Toolbox

@main struct SecurityToolsBenchmark {
    static func rss() -> UInt64 {
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to:&info) { pointer in pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) } }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
    static func ms(_ start: Date) -> Double {Date().timeIntervalSince(start)*1000}
    static func main() async throws {
        setbuf(stdout,nil)
        let pem = try String(contentsOf:Bundle.main.url(forResource:"certificate",withExtension:"pem")!,encoding:.utf8)
        let bundle = Data(Array(repeating:pem,count:64).joined(separator:"\n").utf8)
        var start = Date();let cert = await Task.detached {CertificateProcessor.inspect(bundle)}.value
        print("T030_BENCH certificateCount=\(cert.entries.count) PEMbytes=\(bundle.count) ms=\(ms(start)) rssBytes=\(rss())")
        let original = try PEMEnvelopeReader.read(pem,allowed:["CERTIFICATE"])[0].der
        let parts = try CertificateDER.children(DER.parse(Array(original))), tbs = try CertificateDER.children(parts[0])
        let names = (0..<6000).map { PublicKeyDEREncoding.tlv(0x82,Data("host-\($0).example.test".utf8)) }.reduce(Data(),+)
        let extensionDER = PublicKeyDEREncoding.tlv(0x30,Data([6,3,0x55,0x1d,0x11])+PublicKeyDEREncoding.tlv(4,PublicKeyDEREncoding.tlv(0x30,names)))
        let fields = tbs.dropLast().map {Data($0.encodedBytes)}.reduce(Data(),+)+PublicKeyDEREncoding.tlv(0xa3,PublicKeyDEREncoding.tlv(0x30,extensionDER))
        let largeDER = PublicKeyDEREncoding.tlv(0x30,PublicKeyDEREncoding.tlv(0x30,fields)+Data(parts[1].encodedBytes)+Data(parts[2].encodedBytes))
        let largePEM = PEMEnvelopeReader.encode(largeDER,label:"CERTIFICATE")
        let count = min(64,CertificateLimits.file/(largePEM.utf8.count+1))
        let nearLimit = Data(Array(repeating:largePEM,count:count).joined(separator:"\n").utf8)
        start = Date();let largeResult = await Task.detached {CertificateProcessor.inspect(nearLimit)}.value
        print("T030_BENCH SANperCertificate=6000 DERbytes=\(largeDER.count) count=\(largeResult.entries.count) PEMbytes=\(nearLimit.count) status=\(largeResult.status.rawValue) ms=\(ms(start)) rssBytes=\(rss())")
        guard largeResult.entries.allSatisfy({$0.parsed}) else {throw BenchmarkError.failed}
        let strength = PasswordStrengthWorker()
        for (name,input) in [("cold-short","synthetic-password"),("warm-256-repeat",String(repeating:"a",count:256)),("warm-256-pattern",String(repeating:"qWeRtY123!",count:25)+"abcdef")] {
            start = Date();let result = await strength.estimate(.init(password:input));print("T031_BENCH name=\(name) units=\(input.utf16.count) status=\(result.status.rawValue) ms=\(ms(start)) rssBytes=\(rss())")
        }
        let secret = Data(String(repeating:"synthetic-key-",count:4).utf8)
        let payload = #"{"text":""#+String(repeating:"a",count:190000)+#""}"#
        let message = JWTSigningProvider.base64URL(Data(#"{"alg":"HS256"}"#.utf8))+"."+JWTSigningProvider.base64URL(Data(payload.utf8))
        let token = message+"."+JWTSigningProvider.base64URL(Data(HMAC<SHA256>.authenticationCode(for:Data(message.utf8),using:SymmetricKey(data:secret))))
        let request = JWTVerifierRequest(token:token,key:String(decoding:secret,as:UTF8.self),algorithm:.hs256,format:.secretUTF8)
        start = Date();let verified = await Task.detached {JWTVerifierProcessor.process(request)}.value
        print("T032_BENCH tokenBytes=\(token.utf8.count) signature=\(verified.signature.rawValue) ms=\(ms(start)) rssBytes=\(rss())")
        guard verified.signature == .matches,cert.entries.count == 64 else {throw BenchmarkError.failed}
        print("SECURITY_TOOLS_BENCH_PASSED")
    }
    enum BenchmarkError:Error {case failed}
}
