import Foundation

public enum QRDecodedPresentation {
    /// Display escapes never replace the original payload used by explicit Copy/Export.
    public static func safeText(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0: result += "\\0"
            case 9: result += "⇥"
            case 10: result += "\n"
            case 13: result += "\\r"
            case 0..<32,127...159,0x061C,0x200B,0x200E...0x200F,0x2028...0x202E,0x2060...0x206F,0xFEFF:
                result += String(format:"\\u{%04X}",scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
    public static func hex(_ data: Data) -> String { data.map { String(format:"%02X",$0) }.joined() }
    public static func hexDump(_ data: Data) -> String {
        let bytes = [UInt8](data)
        return stride(from:0,to:bytes.count,by:16).map { offset in
            let slice = bytes[offset..<min(offset+16,bytes.count)]
            let hex = slice.map { String(format:"%02X",$0) }.joined(separator:" ")
            let ascii = String(slice.map { Character(UnicodeScalar($0 >= 32 && $0 < 127 ? $0 : 46)) })
            return String(format:"%04X  ",offset) + hex.padding(toLength:47,withPad:" ",startingAt:0) + "  " + ascii
        }.joined(separator:"\n")
    }
    public static func preview(_ item: QRDecodedItem) -> String {
        guard item.readable else { return "Possible QR code · content could not be decoded" }
        if let text = item.text { return safeText(String(text.prefix(90))).replacingOccurrences(of:"\n",with:" ↵ ") }
        return "Binary · \(item.bytes?.count ?? 0) bytes"
    }
    public static func copy(_ item: QRDecodedItem, as format: QRDecodeOutput) -> String? {
        guard let bytes = item.bytes else { return nil }
        switch format {
        case .text: return item.text
        case .hex: return hex(bytes)
        case .base64: return bytes.base64EncodedString()
        case .bytes: return nil
        }
    }
}
