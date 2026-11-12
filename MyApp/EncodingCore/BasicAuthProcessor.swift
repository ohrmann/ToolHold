import Foundation

/// A byte builder, not an authentication client. Never guesses a server's encoding.
enum BasicAuthProcessor {
    static func inputIssue(_ text: String, field: BasicAuthField) -> BasicAuthIssue? {
        guard text.utf16.prefix(262_145).count <= 262_144 else {
            return .init(code: .inputLimit, field: field, message: "This field exceeds the input limit.")
        }
        var offset = 0
        for scalar in text.unicodeScalars {
            if scalar.value < 32 || scalar.value == 127 {
                return .init(code: .control, field: field, message: "Control characters are not allowed.", originalUTF16Range: .init(location: offset, length: scalar.utf16.count))
            }
            if field == .username && scalar.value == 58 {
                return .init(code: .colon, field: field, message: "Username cannot contain a colon (:).", originalUTF16Range: .init(location: offset, length: 1))
            }
            offset += scalar.utf16.count
        }
        return nil
    }
    static func build(_ request: BasicAuthRequest, limits: BasicAuthLimits = .init()) -> BasicAuthResult {
        do {
            try Task.checkCancellation()
            guard limits.inputUTF16 >= 1, limits.bytes >= 1, limits.fullHeaderUTF16 >= 21 else { return limit(.inputLimit) }
            let usernameCount = request.username.utf16.prefix(limits.inputUTF16).count
            guard usernameCount < limits.inputUTF16,
                  request.password.utf16.prefix(limits.inputUTF16 - usernameCount).count < limits.inputUTF16 - usernameCount else { return limit(.inputLimit) }
            var issues: [BasicAuthIssue] = []
            for (field, source) in [(BasicAuthField.username, request.username), (.password, request.password)] {
                if let issue = inputIssue(source, field: field) { issues.append(issue) }
            }
            guard issues.isEmpty else { return .init(status: .invalidCredentials, issues: issues) }
            let options = request.options.effective
            var bytes = Data()
            for (field, source) in [(BasicAuthField.username, request.username), (.password, request.password)] {
                try Task.checkCancellation()
                let text = options.normalizeNFC ? source.precomposedStringWithCanonicalMapping : source
                if !source.utf16.elementsEqual(text.utf16) {
                    issues.append(.init(code: .normalized, field: field, message: "NFC normalization applied.", isError: false))
                }
                if let first = source.unicodeScalars.first, let last = source.unicodeScalars.last,
                   CharacterSet.whitespaces.contains(first) || CharacterSet.whitespaces.contains(last) {
                    issues.append(.init(code: .boundarySpaces, field: field, message: "Leading or trailing spaces are preserved.", isError: false))
                }
                if source.unicodeScalars.contains(where: { isInvisible($0.value) }) {
                    issues.append(.init(code: .invisible, field: field, message: "Invisible or directional characters are preserved.", isError: false))
                }
                do {
                    let data = try Base64TextCodec.encode(text, encoding: options.encoding == .utf8 ? .utf8 : .latin1, limit: limits.bytes - bytes.count)
                    bytes.append(data)
                } catch let error as Base64Failure {
                    if error.status == .resourceLimit { return limit(.byteLimit) }
                    return .init(status: .unrepresentableText, issues: [.init(code: .unrepresentable, field: field,
                        message: "This field contains a character unavailable in Latin-1. Choose UTF-8.", originalUTF16Range: error.range)])
                }
                if field == .username {
                    guard bytes.count < limits.bytes else { return limit(.byteLimit) }
                    bytes.append(58)
                }
            }
            // Division before multiplication makes the budget check overflow-safe.
            let groups = bytes.count / 3 + (bytes.count % 3 == 0 ? 0 : 1)
            guard groups <= (limits.fullHeaderUTF16 - 21) / 4 else { return limit(.outputLimit) }
            try Task.checkCancellation()
            let value = "Basic " + bytes.base64EncodedString()
            try Task.checkCancellation()
            if request.username.isEmpty && request.password.isEmpty {
                issues.append(.init(code: .empty, field: .options, message: "Both credentials are empty.", isError: false))
            }
            return .init(status: .success, issues: issues, artifact: .init(headerValue: value), credentialByteCount: bytes.count)
        } catch is CancellationError { return .init(status: .cancelled) }
        catch { return .init(status: .processingFailure, issues: [.init(code: .failure, field: .options, message: "Header could not be built.")]) }
    }
    private static func limit(_ code: BasicAuthIssue.Code) -> BasicAuthResult {
        .init(status: .resourceLimit, issues: [.init(code: code, field: .options, message: "Credentials exceed the processing limit. Input has been preserved.")])
    }
    static func isInvisible(_ value: UInt32) -> Bool {
        (128...159).contains(value) || [0xAD,0x61C,0x200B,0x200C,0x200D,0x200E,0x200F,0x2060,0xFEFF].contains(value) ||
        (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value)
    }
    /// Bounded inspection only; never used as the input to encoding or Copy.
    static func passwordPreview(_ source: String) -> String {
        var result = "", units = 0
        for scalar in source.unicodeScalars {
            guard units + scalar.utf16.count <= 512 else { result += "…"; break }
            if scalar.value < 32 || scalar.value == 127 || isInvisible(scalar.value) {
                result += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            } else { result.unicodeScalars.append(scalar) }
            units += scalar.utf16.count
        }
        return result
    }
}
