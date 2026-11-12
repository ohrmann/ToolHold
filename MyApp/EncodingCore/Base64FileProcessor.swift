import Foundation
import CryptoKit
import Darwin

struct Base64FileDestination: Sendable { let directory: URL; let name: String }

/// Sequential bounded reads/transforms/writes. No automatic staging or whole-file Data.
enum Base64FileProcessor {
    static func run(source: Base64FileSource, options: Base64FileOptions, intent: Base64Intent = .convert,
                    destination: Base64FileDestination? = nil, expectedDigest: Data? = nil,
                    operation: Base64FileOperation = .init(), chunkSize: Int = Base64FileBudget.chunk,
                    progress: @escaping @Sendable (Base64FileProgress) -> Void = { _ in }) -> Base64FileResult {
        autoreleasepool {
            process(source: source, options: options, intent: intent, destination: destination,
                    expectedDigest: expectedDigest, operation: operation, chunkSize: chunkSize, progress: progress)
        }
    }
    private static func process(source: Base64FileSource, options: Base64FileOptions, intent: Base64Intent,
                                destination: Base64FileDestination?, expectedDigest: Data?, operation: Base64FileOperation,
                                chunkSize: Int, progress: @escaping @Sendable (Base64FileProgress) -> Void) -> Base64FileResult {
        var result = Base64FileResult()
        do {
            try operation.check()
            let options = options.effective
            guard chunkSize > 0 && chunkSize <= Base64FileBudget.chunk else { throw Base64FileFailure(.resourceLimit, "Unsupported I/O block size.") }
            if case let .text(text) = source {
                guard text.utf16.prefix(Base64FileBudget.textInput + 1).count <= Base64FileBudget.textInput else {
                    throw Base64FileFailure(.resourceLimit, "Text Input exceeds 262,144 UTF-16 units. Import a Base64 file instead.")
                }
            }
            let process: (FileHandle?, Int64?) throws -> Base64FileResult = { input, total in
                var stamp: FileStamp?
                if let input { stamp = try FileStamp(input.fileDescriptor) }
                var offset = 0
                var textBytes: Data?
                if case let .text(text) = source { textBytes = Data(text.utf8) }
                let read: () throws -> Data = {
                    try operation.check()
                    if let input { return try input.read(upToCount: chunkSize) ?? Data() }
                    guard let bytes = textBytes, offset < bytes.count else { return Data() }
                    let count = min(chunkSize, bytes.count - offset)
                    defer { offset += count }; return Data(bytes[offset..<(offset + count)])
                }
                let body: (FileHandle?) throws -> Base64FileResult = { output in
                    var pipeline = Pipeline(options: options, collect: intent == .convert)
                    var digest = SHA256()
                    var context = Context()
                    var lastProgress = ProcessInfo.processInfo.systemUptime
                    do {
                        while true {
                            let hasBlock = try autoreleasepool { () throws -> Bool in
                                let block = try read()
                                if block.isEmpty { return false }
                                context.set(block, at: pipeline.inputCount)
                                digest.update(data: block)
                                let bytes = try pipeline.consume(block)
                                if let output, !bytes.isEmpty { try output.write(contentsOf: bytes) }
                                try operation.check()
                                let now = ProcessInfo.processInfo.systemUptime
                                if now - lastProgress >= 0.1 {
                                    progress(.init(bytes: pipeline.inputCount, total: total)); lastProgress = now
                                }
                                return true
                            }
                            if !hasBlock { break }
                        }
                        let final = try pipeline.finish()
                        if let output, !final.isEmpty { try output.write(contentsOf: final) }
                        try operation.check()
                    } catch let scan as Base64ScanFailure {
                        var failure = Base64FileFailure(.invalidBase64, scan.message, byteOffset: scan.offset, length: scan.length)
                        failure.context = context.snippet(at: scan.offset, length: scan.length)
                        throw failure
                    } catch var failure as Base64FileFailure {
                        if let position = failure.byteOffset { failure.context = context.snippet(at: position, length: failure.length) }
                        throw failure
                    }
                    if let input, let stamp {
                        guard try FileStamp(input.fileDescriptor) == stamp else { throw Base64FileFailure(.sourceChanged, "The source file changed during processing. Choose or check it again.") }
                        if case let .file(url) = source {
                            var current = stat()
                            guard stat(url.path, &current) == 0 && stamp == FileStamp(current) else {
                                throw Base64FileFailure(.sourceChanged, "The source file was replaced or removed. Choose it again.")
                            }
                        }
                    }
                    let hash = Data(digest.finalize())
                    if let expectedDigest, hash != expectedDigest { throw Base64FileFailure(.sourceChanged, "The source differs from the last checked result. Check it again before exporting.") }
                    var value = pipeline.result()
                    value.sourceDigest = hash
                    progress(.init(bytes: value.inputBytes, total: value.inputBytes))
                    return value
                }
                if let destination { return try export(destination, source: source, operation: operation, body: body) }
                return try body(nil)
            }
            switch source {
            case .text: result = try process(nil, nil)
            case .file(let url):
                guard url.isFileURL else { throw Base64FileFailure(.unsupportedFormat, "Choose a local file URL. Network URLs are not opened.") }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                var loaded: Base64FileResult?, thrown: Error?, coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                    do {
                        // NONBLOCK prevents hanging if the selected regular file is replaced by a FIFO.
                        let fd = open(coordinated.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                        guard fd >= 0 else { throw Base64FileFailure(.ioFailure, "The selected file cannot be opened. Check that it is available locally and access is allowed.") }
                        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                        defer { try? handle.close() }
                        let stamp = try FileStamp(fd)
                        guard stamp.regular else { throw Base64FileFailure(.unsupportedFormat, "Choose one regular file, not a folder or special device.") }
                        loaded = try process(handle, stamp.size)
                    } catch { thrown = error }
                }
                if let thrown { throw thrown }
                guard coordinationError == nil, let loaded else { throw Base64FileFailure(.ioFailure, "The file provider could not grant access. Choose an available local file.") }
                result = loaded
            }
        } catch is CancellationError {
            result = .init(status: .cancelled)
        } catch var failure as Base64FileFailure {
            if case let .text(text) = source, let byte = failure.byteOffset {
                let position = textPosition(text, byte: byte, length: failure.length)
                failure.textRange = position.0; failure.line = position.1; failure.column = position.2
                if failure.status == .invalidBase64, let range = Range(position.0, in: text),
                   let scalar = text[range].unicodeScalars.first, scalar.value > 127 {
                    failure.message = "U+" + String(format: "%04X", scalar.value) + " is not allowed in Base64 text. Input is unchanged."
                }
            }
            result = .init(status: failure.status, failure: failure)
        } catch {
            result = .init(status: .ioFailure, failure: .init(.ioFailure, "Reading or writing failed. Check permissions, available space and the selected file provider."))
        }
        return result
    }

    static func validFilename(_ name: String) -> Bool {
        guard !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 180 else { return false }
        return name.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && ![47,58,92,0x200e,0x200f,0x061c,0x2028,0x2029].contains($0.value)
                && !(0x202a...0x202e).contains($0.value) && !(0x2066...0x2069).contains($0.value)
        }
    }
    private static func export(_ destination: Base64FileDestination, source: Base64FileSource,
                               operation: Base64FileOperation, body: (FileHandle?) throws -> Base64FileResult) throws -> Base64FileResult {
        guard validFilename(destination.name) else { throw Base64FileFailure(.unsupportedFormat, "Enter a plain filename without path separators, control or directional characters.") }
        let directory = destination.directory
        guard directory.isFileURL else { throw Base64FileFailure(.unsupportedFormat, "Choose a local export folder URL. Network URLs are not opened.") }
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let target = directory.appendingPathComponent(destination.name)
        if case let .file(input) = source, input.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL {
            throw Base64FileFailure(.ioFailure, "The output must be a new file. The source will not be replaced.")
        }
        var outcome: Base64FileResult?, thrown: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: directory, options: .forMerging, error: &coordinationError) { folder in
            let target = folder.appendingPathComponent(destination.name)
            // Visible in Files as well as Finder, so a crash residue can be removed by the user.
            let partial = folder.appendingPathComponent("DeveloperToolbox-\(UUID().uuidString).partial")
            var fd: Int32 = -1
            var identity: FileStamp?
            var committed = false
            do {
                try operation.check()
                var existing = stat()
                guard lstat(target.path, &existing) != 0 && errno == ENOENT else { throw Base64FileFailure(.ioFailure, "That filename already exists or is unavailable. Choose a different name; existing files are never replaced.") }
                fd = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
                guard fd >= 0 else { throw Base64FileFailure(.ioFailure, "A new export file could not be created in this folder.") }
                identity = try FileStamp(fd)
                let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                fd = -1
                defer { try? output.close() }
                var value = try body(output)
                try output.synchronize()
                try operation.check()
                try output.close()
                // RENAME_EXCL is atomic/no-clobber on supported local filesystems. No unsafe fallback.
                try operation.commit(name: destination.name) {
                    var current = stat()
                    guard lstat(partial.path, &current) == 0, identity?.sameIdentity(FileStamp(current)) == true else {
                        throw Base64FileFailure(.ioFailure, "The partial export was replaced. Export was not published.")
                    }
                    guard renameatx_np(AT_FDCWD, partial.path, AT_FDCWD, target.path, UInt32(RENAME_EXCL)) == 0 else {
                        throw Base64FileFailure(.ioFailure, "The export could not be published safely. Choose a new filename or a local folder; this provider may not support safe export.")
                    }
                    committed = true
                }
                value.exportedName = destination.name; outcome = value
            } catch {
                if fd >= 0 { close(fd) }
                var failure = (error as? Base64FileFailure) ?? (error is CancellationError
                    ? Base64FileFailure(.cancelled, "Export cancelled.")
                    : Base64FileFailure(.ioFailure, "Export failed. Check permissions and available space."))
                if !committed, let identity {
                    var current = stat()
                    if lstat(partial.path, &current) == 0 {
                        if identity.sameIdentity(FileStamp(current)) && unlink(partial.path) == 0 { /* removed our file */ }
                        else { failure.cleanupPath = partial.path; failure.message += " The partial export could not be removed. Remove it manually if it is still present." }
                    } else if errno != ENOENT { failure.cleanupPath = partial.path }
                }
                thrown = failure
            }
        }
        if let thrown { throw thrown }
        guard coordinationError == nil, let outcome else { throw Base64FileFailure(.ioFailure, "The destination provider could not authorize export. Choose a local folder.") }
        return outcome
    }

    private struct FileStamp: Equatable {
        let device: Int32; let inode: UInt64; let size: Int64
        let seconds: Int; let nanos: Int; let changed: Int; let changedNanos: Int; let regular: Bool
        init(_ fd: Int32) throws {
            var s = stat(); guard fstat(fd, &s) == 0 else { throw Base64FileFailure(.ioFailure, "The selected file is unavailable.") }
            self.init(s)
        }
        init(_ s: stat) {
            device = s.st_dev; inode = s.st_ino; size = s.st_size
            seconds = s.st_mtimespec.tv_sec; nanos = s.st_mtimespec.tv_nsec
            changed = s.st_ctimespec.tv_sec; changedNanos = s.st_ctimespec.tv_nsec
            regular = s.st_mode & S_IFMT == S_IFREG
        }
        func sameIdentity(_ other: Self) -> Bool { device == other.device && inode == other.inode }
    }
    private struct Context {
        var previous = Data(), current = Data(); var start: Int64 = 0
        mutating func set(_ bytes: Data, at offset: Int64) {
            previous = Data((previous + current).suffix(96)); current = bytes; start = offset
        }
        func snippet(at offset: Int64, length: Int) -> String {
            let base = start - Int64(previous.count), data = previous + current
            guard offset >= base && offset <= base + Int64(data.count) else { return "Position is outside the retained preview. Use the byte offset above." }
            let index = Int(offset - base), lower = max(0, index - 32), upper = min(data.count, index + max(1, length) + 32)
            func escaped(_ slice: Data.SubSequence) -> String {
                slice.map { byte in byte >= 33 && byte <= 126 && byte != 92 ? String(UnicodeScalar(byte)) : String(format: "\\x%02X", byte) }.joined()
            }
            return (base + Int64(lower) > 0 ? "…" : "") + escaped(data[lower..<index]) + " ⟦" +
                (length == 0 ? "EOF" : escaped(data[index..<min(upper, index + length)])) + "⟧ " +
                escaped(data[min(upper, index + length)..<upper]) + (upper < data.count ? "…" : "")
        }
    }
    private static func textPosition(_ source: String, byte: Int64, length: Int) -> (NSRange, Int, Int) {
        var bytes: Int64 = 0, offset = 0, line = 1, column = 1, cr = false
        for scalar in source.unicodeScalars {
            if bytes >= byte { return (.init(location: offset, length: length == 0 ? 0 : scalar.utf16.count), line, column) }
            bytes += Int64(scalar.utf8.count); offset += scalar.utf16.count
            if scalar.value == 13 { line += 1; column = 1 }
            else if scalar.value == 10 { if !cr { line += 1 }; column = 1 }
            else { column += scalar.utf16.count }
            cr = scalar.value == 13
        }
        return (.init(location: offset, length: 0), line, column)
    }
}

private struct Pipeline {
    let options: Base64FileOptions
    let collect: Bool
    var inputCount: Int64 = 0
    var outputCount: Int64 = 0
    var encoder: Base64StreamEncoder
    var scanner: Base64PolicyScanner
    var header = Data()
    var headerComplete = false
    var started = false
    var rawPrefix = Data()
    var mediaType: String?
    var notes: [String] = []
    var textBuffer = Data()
    var fullText = true
    var binaryPrefix = Data()
    var imageBuffer: Data? = Data()
    init(options: Base64FileOptions, collect: Bool) {
        self.options = options; self.collect = collect
        encoder = .init(alphabet: options.alphabet, padded: options.alphabet == .standard || options.urlPadding)
        scanner = .init(alphabet: options.alphabet, mode: options.decodeMode)
    }
    mutating func consume(_ block: Data) throws -> Data {
        var output = Data()
        if options.direction == .encode {
            if !started { if options.format == .dataURL { output.append(try Base64DataURL.header(mime: options.mimeType)); mediaType = options.mimeType }; started = true }
            output.append(encoder.consume(block))
            if collect { collectImage(block) }
        } else {
            if options.format == .raw && rawPrefix.count < 5 {
                rawPrefix.append(block.prefix(5 - rawPrefix.count))
                if String(decoding: rawPrefix, as: UTF8.self).lowercased() == "data:" {
                    throw Base64FileFailure(.unsupportedFormat, "Choose Data URL format to decode a data: URL.", byteOffset: 4)
                }
            }
            for (index, byte) in block.enumerated() {
                if index & 4095 == 0 { try Task.checkCancellation() }
                let offset = try Base64StreamSize.add(inputCount, Int64(index))
                if options.format == .dataURL && !headerComplete {
                    if byte == 44 { mediaType = try Base64DataURL.parse(header); headerComplete = true }
                    else {
                        guard header.count < Base64FileBudget.header else { throw Base64FileFailure(.resourceLimit, "The Data URL header exceeds 4 KiB.", byteOffset: offset) }
                        header.append(byte)
                    }
                } else {
                    if byte == 37 && options.format == .dataURL { throw Base64FileFailure(.unsupportedFormat, "Percent-encoded Data URL payloads are not supported.", byteOffset: offset) }
                    if byte >= 128 {
                        throw Base64ScanFailure(code: .invalidSymbol, message: String(format: "Expected ASCII Base64 text; byte 0x%02X is not allowed. BOM and UTF-16 text files are not converted automatically.", byte), offset: offset, length: 1)
                    }
                    try scanner.consume(UInt32(byte), at: offset)
                }
            }
            output = try decode(scanner.drain())
            if collect { collectImage(output); binaryPrefix.append(output.prefix(max(0, 64 - binaryPrefix.count))) }
        }
        inputCount = try Base64StreamSize.add(inputCount, Int64(block.count))
        try account(output); return output
    }
    mutating func finish() throws -> Data {
        var output = Data()
        if options.direction == .encode {
            if !started && options.format == .dataURL { output.append(try Base64DataURL.header(mime: options.mimeType)); mediaType = options.mimeType }
            output.append(encoder.finish())
        } else {
            if options.format == .dataURL && !headerComplete { throw Base64FileFailure(.unsupportedFormat, "Expected ',' after the Data URL header.", byteOffset: inputCount, length: 0) }
            notes = try scanner.finish(at: inputCount).map(\.message)
            output = try decode(scanner.drain())
            if collect { collectImage(output); binaryPrefix.append(output.prefix(max(0, 64 - binaryPrefix.count))) }
        }
        try account(output); return output
    }
    private func decode(_ normalized: Data) throws -> Data {
        guard !normalized.isEmpty else { return Data() }
        guard let decoded = Data(base64Encoded: normalized, options: []) else { throw Base64FileFailure(.ioFailure, "The system decoder could not process the validated block.") }
        return decoded
    }
    private mutating func account(_ output: Data) throws {
        outputCount = try Base64StreamSize.add(outputCount, Int64(output.count))
        guard collect && options.direction == .encode else { return }
        if fullText && outputCount <= Base64FileBudget.copyText { textBuffer.append(output) }
        else {
            if fullText { textBuffer = Data(textBuffer.prefix(Base64FileBudget.previewText)); fullText = false }
            if textBuffer.count < Base64FileBudget.previewText { textBuffer.append(output.prefix(Base64FileBudget.previewText - textBuffer.count)) }
        }
    }
    private mutating func collectImage(_ data: Data) {
        guard let count = imageBuffer?.count else { return }
        if data.count <= Base64FileBudget.imageBytes - count { imageBuffer?.append(data) }
        else { imageBuffer = nil }
    }
    func result() -> Base64FileResult {
        let text = String(decoding: textBuffer, as: UTF8.self)
        return .init(notes: notes, inputBytes: inputCount, outputBytes: outputCount,
            copyText: collect && options.direction == .encode && fullText ? text : nil,
            textPreview: text, hexPreview: binaryPrefix.map { String(format: "%02X", $0) }.joined(separator: " "),
            imageBytes: collect ? imageBuffer : nil, mediaType: mediaType)
    }
}
