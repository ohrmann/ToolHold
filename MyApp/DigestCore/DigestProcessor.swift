import Foundation
import CryptoKit
import zlib
#if SWIFT_PACKAGE
import EncodingCore
#endif

private enum DigestState {
    case sha256(SHA256), sha384(SHA384), sha512(SHA512), md5(Insecure.MD5), sha1(Insecure.SHA1)
    case crc(uLong), adler(uLong)
    case h256(HMAC<SHA256>), h384(HMAC<SHA384>), h512(HMAC<SHA512>)
    init(_ algorithm: DigestAlgorithm, key: Data?) {
        if let key {
            let symmetric = SymmetricKey(data: key)
            switch algorithm { case .sha256: self = .h256(HMAC(key: symmetric)); case .sha384: self = .h384(HMAC(key: symmetric)); default: self = .h512(HMAC(key: symmetric)) }
        } else {
            switch algorithm { case .sha256: self = .sha256(SHA256()); case .sha384: self = .sha384(SHA384()); case .sha512: self = .sha512(SHA512()); case .md5: self = .md5(Insecure.MD5()); case .sha1: self = .sha1(Insecure.SHA1()); case .crc32: self = .crc(crc32(0, nil, 0)); case .adler32: self = .adler(adler32(0, nil, 0)) }
        }
    }
    mutating func update(_ data: Data) {
        switch self {
        case .sha256(var v): v.update(data: data); self = .sha256(v)
        case .sha384(var v): v.update(data: data); self = .sha384(v)
        case .sha512(var v): v.update(data: data); self = .sha512(v)
        case .md5(var v): v.update(data: data); self = .md5(v)
        case .sha1(var v): v.update(data: data); self = .sha1(v)
        case .h256(var v): v.update(data: data); self = .h256(v)
        case .h384(var v): v.update(data: data); self = .h384(v)
        case .h512(var v): v.update(data: data); self = .h512(v)
        case .crc(let v): self = .crc(data.withUnsafeBytes { crc32(v, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)) })
        case .adler(let v): self = .adler(data.withUnsafeBytes { adler32(v, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)) })
        }
    }
    func finish() -> Data {
        switch self {
        case .sha256(var v): Data(v.finalize()); case .sha384(var v): Data(v.finalize()); case .sha512(var v): Data(v.finalize())
        case .md5(var v): Data(v.finalize()); case .sha1(var v): Data(v.finalize())
        case .h256(var v): Data(v.finalize()); case .h384(var v): Data(v.finalize()); case .h512(var v): Data(v.finalize())
        case .crc(let v), .adler(let v): Data([UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)])
        }
    }
}
enum DigestProcessor {
    static func run(_ request: DigestRequest, chunkSize: Int = 65_536, progress: @Sendable (DigestProgress) -> Void = { _ in }) -> DigestResult {
        do {
            try Task.checkCancellation()
            guard !request.algorithms.isEmpty, Set(request.algorithms).count == request.algorithms.count else { throw DigestIssue(status: .invalidInput, message: "Choose at least one algorithm, without duplicates.") }
            var key: Data?
            if request.isHMAC {
                guard request.algorithms.count == 1, DigestAlgorithm.hmac.contains(request.algorithms[0]) else { throw DigestIssue(status: .invalidInput, message: "Choose HMAC-SHA-256, SHA-384 or SHA-512.") }
                do { key = try ExactByteInputDecoder.decode(request.key, profile: request.keyProfile, inputLimit: 65_536, byteLimit: 16_384) }
                catch let failure as ExactByteFailure { throw DigestIssue(status: failure.resourceLimit ? .resourceLimit : .invalidInput, message: failure.message, field: "key", range: failure.range) }
                if key!.isEmpty && !request.allowEmptyKey { throw DigestIssue(status: .invalidInput, message: "Enter a secret key, or explicitly allow an empty key for test vectors.", field: "key") }
            }
            var states = request.algorithms.map { DigestState($0, key: key) }
            let consume: (Data) throws -> Void = { block in
                try Task.checkCancellation()
                for index in states.indices { states[index].update(block); try Task.checkCancellation() }
            }
            let count: Int64
            if request.mode == .file {
                guard let url = request.file else { throw DigestIssue(status: .invalidInput, message: "Choose a file.") }
                count = try DigestFileReader.read(url, chunkSize: chunkSize, progress: progress, consume: consume)
            } else {
                let bytes: Data
                do { bytes = try ExactByteInputDecoder.decode(request.text, profile: request.mode.profile) }
                catch let failure as ExactByteFailure { throw DigestIssue(status: failure.resourceLimit ? .resourceLimit : .invalidInput, message: failure.message, range: failure.range) }
                guard (1...65_536).contains(chunkSize) else { throw DigestIssue(status: .resourceLimit, message: "Unsupported processing buffer size.") }
                for start in stride(from: 0, to: bytes.count, by: chunkSize) { try consume(Data(bytes[start..<min(start + chunkSize, bytes.count)])) }
                count = Int64(bytes.count)
            }
            try Task.checkCancellation()
            let values = Dictionary(uniqueKeysWithValues: zip(request.algorithms, states.map { $0.finish() }))
            try Task.checkCancellation()
            return .init(artifact: .init(values: values, bytes: count, keyBytes: key?.count, isHMAC: request.isHMAC))
        } catch is CancellationError { return .init(issue: .init(status: .cancelled, message: "Cancelled")) }
        catch let issue as DigestIssue { return .init(issue: issue) }
        catch { return .init(issue: .init(status: .ioFailure, message: "Processing failed. Check file access and try again.")) }
    }
}
