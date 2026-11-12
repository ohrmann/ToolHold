import Foundation

/// Exact byte/scalar conversion. Never guesses encoding, inserts BOMs or repairs Unicode.
enum Base64TextCodec {
    static func encode(_ text: String, encoding: Base64TextEncoding, limit: Int) throws -> Data {
        var bytes = Data()
        func append(_ value: UInt8) throws {
            guard bytes.count < limit else { throw Base64Failure(status: .resourceLimit, code: .outputLimit, message: "Encoded output exceeds the processing limit.") }
            bytes.append(value)
        }
        switch encoding {
        case .utf8:
            for byte in text.utf8 {
                if bytes.count & 4095 == 0 { try Task.checkCancellation() }
                try append(byte)
            }
        case .ascii, .latin1:
            var offset = 0
            let maximum: UInt32 = encoding == .ascii ? 127 : 255
            for scalar in text.unicodeScalars {
                if offset & 4095 == 0 { try Task.checkCancellation() }
                guard scalar.value <= maximum else {
                    throw Base64Failure(status: .unrepresentableText, code: .unrepresentableScalar,
                        message: "U+\(String(scalar.value, radix: 16, uppercase: true)) cannot be represented in \(encoding.title).",
                        range: NSRange(location: offset, length: scalar.utf16.count))
                }
                try append(UInt8(scalar.value)); offset += scalar.utf16.count
            }
        case .utf16LE, .utf16BE:
            var count = 0
            for unit in text.utf16 {
                if count & 4095 == 0 { try Task.checkCancellation() }
                let low = UInt8(unit & 255), high = UInt8(unit >> 8)
                try append(encoding == .utf16LE ? low : high)
                try append(encoding == .utf16LE ? high : low)
                count += 1
            }
        }
        return bytes
    }
    static func decode(_ data: Data, encoding: Base64TextEncoding) throws -> String? {
        try Task.checkCancellation()
        switch encoding {
        case .utf8:
            if #available(macOS 15, iOS 18, *) { return String(validating: data, as: UTF8.self) }
            // Backport for the package's older deployment floor: never publish repaired text.
            let text = String(decoding: data, as: UTF8.self)
            return text.utf8.elementsEqual(data) ? text : nil
        case .ascii, .latin1:
            var scalars = String.UnicodeScalarView()
            for (index, byte) in data.enumerated() {
                if index & 4095 == 0 { try Task.checkCancellation() }
                if encoding == .ascii && byte > 127 { return nil }
                scalars.append(Unicode.Scalar(UInt32(byte))!)
            }
            return String(scalars)
        case .utf16LE, .utf16BE:
            guard data.count.isMultiple(of: 2) else { return nil }
            let bytes = Array(data)
            var units: [UInt16] = []; units.reserveCapacity(bytes.count / 2)
            for index in stride(from: 0, to: bytes.count, by: 2) {
                if index & 4095 == 0 { try Task.checkCancellation() }
                let first = UInt16(bytes[index]), second = UInt16(bytes[index + 1])
                units.append(encoding == .utf16LE ? first | second << 8 : first << 8 | second)
            }
            // Exact code-unit round-trip rejects any surrogate repair and preserves BOMs,
            // including on the package's older deployment floor.
            let text = String(decoding: units, as: UTF16.self)
            return text.utf16.elementsEqual(units) ? text : nil
        }
    }
    static func notes(_ text: String) throws -> [Base64Issue] {
        var notes: [Base64Issue] = []
        if text.unicodeScalars.first?.value == 0xFEFF {
            notes.append(.init(code: .leadingBOM, severity: .note, message: "Leading U+FEFF preserved."))
        }
        var count = 0, examples: [UInt32] = []
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index & 4095 == 0 { try Task.checkCancellation() }
            let value = scalar.value
            if (value < 32 && ![9,10,13].contains(value)) || (127...159).contains(value) ||
                [0x061C, 0x200E, 0x200F].contains(value) || (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value) {
                count += 1
                if examples.count < 6 && !examples.contains(value) { examples.append(value) }
            }
        }
        if count > 0 {
            let codes = examples.map { "U+" + String(format: "%04X", $0) }.joined(separator: ", ")
            notes.append(.init(code: .controls, severity: .note, message: "Contains \(count) control or directional character(s): \(codes). Text and copied data are preserved."))
        }
        return notes
    }
}
