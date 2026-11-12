import Foundation
import zlib

/// One system codec, stable C state address, bounded buffers. No file or UI knowledge.
final class GZipStreamCodec {
    private let stream: UnsafeMutablePointer<z_stream>
    private var header: UnsafeMutablePointer<gz_header>?
    private let direction: GZipDirection
    private let operation: GZipOperation
    private let outputLimit: Int64
    private let blockSize: Int
    private var initialized = false
    private var atMemberEnd = false
    private var finished = false
    private(set) var inputBytes: Int64 = 0
    private(set) var outputBytes: Int64 = 0
    private(set) var members = 0

    init(options: GZipOptions, limits: GZipLimits, operation: GZipOperation) throws {
        direction = options.direction; self.operation = operation
        outputLimit = direction == .compress ? limits.compressedOutput : min(options.maxOutput.bytes, limits.decompressedOutput)
        blockSize = limits.chunk
        stream = .allocate(capacity: 1); stream.initialize(to: z_stream())
        let status: Int32
        if direction == .compress {
            status = deflateInit2_(stream, Int32(options.level.rawValue), Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        } else {
            status = inflateInit2_(stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard status == Z_OK else { throw GZipFailure(.internalFailure, .engine, "The system gzip codec could not be initialized.") }
        initialized = true
        if direction == .compress {
            let h = UnsafeMutablePointer<gz_header>.allocate(capacity: 1); h.initialize(to: gz_header())
            h.pointee.time = 0; h.pointee.os = 255; header = h
            guard deflateSetHeader(stream, h) == Z_OK else { throw GZipFailure(.internalFailure, .engine, "The gzip header could not be initialized.") }
        }
    }
    deinit {
        if initialized { if direction == .compress { deflateEnd(stream) } else { inflateEnd(stream) } }
        header?.deinitialize(count: 1); header?.deallocate()
        stream.deinitialize(count: 1); stream.deallocate()
    }
    func consume(_ data: Data, emit: (Data) throws -> Void) throws {
        guard !finished else { throw GZipFailure(.internalFailure, .engine, "The gzip operation has already finished.") }
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { input in
            stream.pointee.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.pointee.avail_in = uInt(data.count)
            defer { stream.pointee.next_in = nil; stream.pointee.avail_in = 0 }
            repeat {
                if direction == .decompress && atMemberEnd {
                    guard inflateReset2(stream, 31) == Z_OK else { throw GZipFailure(.internalFailure, .engine, "The gzip codec could not continue to the next member.") }
                    atMemberEnd = false
                }
                try step(flush: Z_NO_FLUSH, emit: emit)
            } while stream.pointee.avail_in > 0 || (direction == .decompress && !atMemberEnd && stream.pointee.avail_out == 0)
        }
    }
    func finish(emit: (Data) throws -> Void) throws {
        try operation.check()
        if direction == .compress {
            while !atMemberEnd { try step(flush: Z_FINISH, emit: emit) }
        } else if !atMemberEnd {
            var failure = GZipFailure(.invalidGZip, inputBytes == 0 ? .empty : .truncated,
                inputBytes == 0 ? "No gzip member found." : "Gzip input ended before the member was complete.", offset: inputBytes)
            failure.exact = true; failure.member = members + 1; throw failure
        }
        finished = true
    }
    private func step(flush: Int32, emit: (Data) throws -> Void) throws {
        try operation.check()
        let before = stream.pointee.avail_in, start = inputBytes
        var block = Data(count: blockSize)
        let code = block.withUnsafeMutableBytes { output -> Int32 in
            stream.pointee.next_out = output.bindMemory(to: Bytef.self).baseAddress!
            stream.pointee.avail_out = uInt(blockSize)
            defer { stream.pointee.next_out = nil }
            return direction == .compress ? deflate(stream, flush) : inflate(stream, flush)
        }
        let consumed = Int64(before - stream.pointee.avail_in), produced = blockSize - Int(stream.pointee.avail_out)
        inputBytes = try Self.add(inputBytes, consumed)
        if code == Z_DATA_ERROR || code == Z_NEED_DICT {
            var error = GZipFailure(.invalidGZip, members > 0 ? .trailingData : .invalidData,
                members > 0 ? "Invalid gzip member or trailing data after a complete member. Only gzip members are allowed." : "Invalid gzip data or integrity check failed.", offset: start)
            error.length = Int(consumed); error.member = members + 1
            throw error
        }
        guard code == Z_OK || code == Z_STREAM_END || code == Z_BUF_ERROR else {
            throw GZipFailure(code == Z_MEM_ERROR ? .resourceLimit : .internalFailure, code == Z_MEM_ERROR ? .budget : .engine,
                code == Z_MEM_ERROR ? "The system gzip codec ran out of memory." : "The system gzip codec could not continue.")
        }
        let total = try Self.add(outputBytes, Int64(produced))
        guard total <= outputLimit else { throw GZipFailure(.resourceLimit, .budget, "Output exceeds the \(outputLimit / 1_024 / 1_024) MiB processing limit. No partial result was published.") }
        outputBytes = total
        if produced > 0 { block.count = produced; try emit(block) }
        if code == Z_STREAM_END { atMemberEnd = true; members += 1 }
        else if consumed == 0 && produced == 0 && (before > 0 || flush == Z_FINISH) {
            throw GZipFailure(.internalFailure, .engine, "The gzip codec made no progress.")
        }
        try operation.check()
    }
    static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (n, overflow) = a.addingReportingOverflow(b)
        guard !overflow && n >= 0 else { throw GZipFailure(.resourceLimit, .budget, "The byte count exceeds the supported range.") }
        return n
    }
}
