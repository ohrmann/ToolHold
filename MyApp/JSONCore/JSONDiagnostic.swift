import Foundation

public enum JSONExpectedToken: String, Sendable, Equatable {
    case value = "JSON value", fieldName = "quoted field name", colon = "':'", comma = "','"
    case objectEnd = "'}'", arrayEnd = "']'", quote = "closing double quote"
    case digit = "digit", hexDigit = "hexadecimal digit", escape = "JSON escape"
    case endOfDocument = "end of input", trueLiteral = "true", falseLiteral = "false", nullLiteral = "null"
    case numberContinuation = "decimal point, exponent or end of number", stringContent = "string character or escape"
}
public enum JSONResourceLimit: Sendable, Equatable { case inputSize, nestingDepth }
public enum JSONProcessingStatus: Sendable, Equatable {
    case valid, invalid, resourceLimit(JSONResourceLimit), cancelled
}
public struct JSONRelatedLocation: Sendable, Equatable {
    public enum Role: String, Sendable {
        case containerStart = "Container start", stringStart = "String start", separator = "Preceding separator"
        case fieldName = "Field name", valueStart = "Value start", firstOccurrence = "First occurrence", escapeStart = "Escape start"
    }
    public let role: Role
    public let range: NSRange
    public init(_ role: Role, _ range: NSRange) { self.role = role; self.range = range }
}
public struct JSONDiagnostic: Error, Sendable, Equatable {
    public enum Severity: Sendable { case error, warning }
    public enum Precision: Sendable { case exact, region }
    public enum Kind: Sendable, Equatable { case syntax, unicodePolicy, resourceLimit(JSONResourceLimit) }
    public let severity: Severity
    public let code: String
    public let message: String
    /// Canonical UTF-16 detection anchor. Missing characters / EOF use zero length.
    /// `region` explicitly means a precise offending code unit was not established.
    public let range: NSRange
    public let line: Int
    public let column: Int
    public let expected: [JSONExpectedToken]
    public let related: [JSONRelatedLocation]
    public let precision: Precision
    public let kind: Kind
    public init(severity: Severity, code: String, message: String, range: NSRange, line: Int, column: Int,
                expected: [JSONExpectedToken] = [], related: [JSONRelatedLocation] = [],
                precision: Precision = .exact, kind: Kind = .syntax) {
        self.severity = severity; self.code = code; self.message = message; self.range = range
        self.line = line; self.column = column; self.expected = expected; self.related = related
        self.precision = precision; self.kind = kind
    }
}

/// Source coordinates only, independent of soft wrapping. Never persisted.
public struct JSONSourceCoordinates: Sendable {
    public let lineStarts: [Int]
    public let utf16Length: Int
    public init(_ source: String) {
        let units = Array(source.utf16)
        utf16Length = units.count
        var starts = [0], index = 0
        while index < units.count {
            if units[index] == 13 {
                if index + 1 < units.count, units[index + 1] == 10 { index += 1 }
                starts.append(index + 1)
            } else if units[index] == 10 { starts.append(index + 1) }
            index += 1
        }
        lineStarts = starts
    }
    public func location(at offset: Int) -> (line: Int, column: Int) {
        let offset = min(utf16Length, max(0, offset))
        var low = 0, high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        let index = max(0, low - 1)
        return (index + 1, offset - lineStarts[index] + 1)
    }
}
