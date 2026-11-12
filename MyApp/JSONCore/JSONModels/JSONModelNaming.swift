import Foundation

enum JSONModelNaming {
    // Union across the supported language profiles, plus generated/runtime symbols.
    static let reserved = Set(("""
    abstract as assert associatedtype async await base bool boolean break byte case catch char checked class companion const continue constructor convenience copy data decimal default defer deinit delegate do double dynamic else enum event explicit extension extern false file fileprivate final finally fixed float for foreach from fun func get goto guard if implicit import in indirect infix init inline inout instanceof int interface internal is late lateinit let lock long mutating namespace native new nil noinline nonmutating null object open operator out override package params partial private protected protocol public readonly record ref reified repeat required rethrows return sbyte sealed self set short sizeof some stackalloc static string struct subscript super suspend switch synchronized tailrec this throw throws transient true try typealias typeof uint ulong unchecked unowned unsafe ushort using val var virtual void volatile weak when where while with yield
    String Int Int64 Double Float Bool Boolean Long Decimal Number Object Any Self Codable CodingKey CodingKeys Decodable Encodable Foundation List Array JsonElement JsonNode BigInteger BigDecimal JsonPropertyName JsonProperty SerialName Serializable ToolboxJSONValue ToolboxJSONValueSerializer Data TypeReference ObjectMapper JsonSerializer Json RootModelJson ModelUnknown JSONDecoder JSONEncoder Decoder Encoder SerialDescriptor KSerializer ExperimentalSerializationApi JsonPrimitive JsonArray JsonObject JsonNull JsonDecoder JsonEncoder JsonUnquotedLiteral
    """).split(whereSeparator: \.isWhitespace).map(String.init))

    static func validRoot(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        return (1...64).contains(bytes.count) && bytes.first.map { (65...90).contains($0) } == true
            && bytes.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }
            && !reserved.contains(name)
    }

    static func stem(_ key: String, upper: Bool) -> String {
        var words: [String] = [], word = "", previous: UInt32?
        let scalars = Array(key.unicodeScalars)
        for (i, scalar) in scalars.enumerated() {
            let v = scalar.value
            if v > 127 {
                if !word.isEmpty { words.append(word); word = "" }
                words.append(String(format: "u%04X", v)); previous = nil
            } else if (48...57).contains(v) || (65...90).contains(v) || (97...122).contains(v) {
                if (65...90).contains(v), !word.isEmpty {
                    let nextLower = i + 1 < scalars.count && (97...122).contains(scalars[i + 1].value)
                    if previous.map({ (97...122).contains($0) || (48...57).contains($0) || ((65...90).contains($0) && nextLower) }) == true {
                        words.append(word); word = ""
                    }
                }
                word.append(Character(scalar)); previous = v
            } else {
                if !word.isEmpty { words.append(word); word = "" }
                previous = nil
            }
        }
        if !word.isEmpty { words.append(word) }
        if words.isEmpty { return upper ? "Model" : "field" }
        func capitalized(_ s: String) -> String { String(s.prefix(1)).uppercased() + s.dropFirst().lowercased() }
        var value = words.enumerated().map { i, word in i == 0 && !upper ? word.lowercased() : capitalized(word) }.joined()
        if value.first?.isNumber == true { value = (upper ? "Model" : "field") + value }
        value = String(value.prefix(80))
        if reserved.contains(value) { value += upper ? "Model" : "Value" }
        return value
    }

    struct Scope {
        var used = JSONModelNaming.reserved
        mutating func allocate(_ stem: String) -> String {
            let stem = String(stem.prefix(80))
            var candidate = stem, suffix = 2
            while used.contains(candidate) { candidate = stem + String(suffix); suffix += 1 }
            used.insert(candidate)
            return candidate
        }
    }

    static func literal(_ value: String, language: JSONModelLanguage) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 9: result += "\\t"
            case 36 where language == .kotlin: result += "\\$"
            case 0...31, 127...159, 0x061C, 0x200E...0x200F, 0x2028...0x202E, 0x2066...0x2069:
                if language == .swift { result += String(format: "\\u{%X}", scalar.value) }
                else if language == .java && scalar.value < 32 { result += String(format: "\\%03o", scalar.value) }
                else { result += String(format: "\\u%04X", scalar.value) }
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func modifiedUTF8Length(_ key: String) -> Int {
        key.utf16.reduce(0) { $0 + ($1 == 0 ? 2 : $1 <= 127 ? 1 : $1 <= 2047 ? 2 : 3) }
    }
}
