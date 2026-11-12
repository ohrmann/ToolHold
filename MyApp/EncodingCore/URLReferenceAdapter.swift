import Foundation

/// Source-preserving delimiter capture + system syntax/IDNA. No URL serialization is used as original text.
enum URLReferenceAdapter {
    static func capture(_ source: String, limits: URLQueryLimits = .init()) throws -> URLQueryReference {
        var length = 0
        for _ in source.utf16 {
            if length & 4095 == 0 { try Task.checkCancellation() }
            guard length < limits.input else { throw URLQueryFailure("inputLimit", "Input exceeds the UTF-16 processing limit.", resource:true) }
            length += 1
        }
        let units = Array(source.utf16)
        func range(_ a: Int, _ b: Int) -> NSRange { .init(location:a,length:b-a) }
        func find(_ c: UInt16, _ a: Int, _ b: Int) -> Int? { units[a..<b].firstIndex(of:c) }
        var c = URLQueryComponents(), issues: [URLQueryIssue] = []
        let fragmentMark = find(35,0,length), beforeFragment = fragmentMark ?? length
        let queryMark = find(63,0,beforeFragment), beforeQuery = queryMark ?? beforeFragment
        c.fragment = fragmentMark.map { range($0+1,length) }; c.query = queryMark.map { range($0+1,beforeFragment) }
        var pathStart = 0
        let firstSlash = find(47,0,beforeQuery) ?? beforeQuery
        if let colon = find(58,0,min(firstSlash,beforeQuery)) {
            let scheme = String(decoding:units[0..<colon],as:UTF16.self)
            guard let first = scheme.utf8.first, (65...90).contains(first) || (97...122).contains(first),
                scheme.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [43,45,46].contains($0) }) else {
                throw URLQueryFailure("scheme", "Expected an ASCII URI scheme before ':'.", range:range(0,colon),region:true)
            }
            c.scheme = range(0,colon); pathStart = colon+1; c.kind = "Absolute URI"
        }
        let scheme = c.scheme.map { (source as NSString).substring(with:$0).lowercased() }
        if pathStart+1 < beforeQuery && units[pathStart] == 47 && units[pathStart+1] == 47 {
            let a = pathStart+2, b = find(47,a,beforeQuery) ?? beforeQuery
            c.authority = range(a,b); pathStart = b
            var hostStart = a
            if let at = units[a..<b].lastIndex(of:64) { c.userinfo = range(a,at); hostStart = at+1 }
            if hostStart < b && units[hostStart] == 91 {
                guard let close = find(93,hostStart+1,b) else { throw URLQueryFailure("ipLiteral", "Expected ']' after IP literal.", range:range(b,b)) }
                c.host = range(hostStart,close+1)
                if close+1 < b {
                    guard units[close+1] == 58 else { throw URLQueryFailure("authority", "Unexpected text after IP literal.", range:range(close+1,b),region:true) }
                    c.port = range(close+2,b)
                }
            } else if let colon = find(58,hostStart,b) { c.host = range(hostStart,colon); c.port = range(colon+1,b) }
            else { c.host = range(hostStart,b) }
            c.dnsHost = (scheme == nil || scheme == "http" || scheme == "https") && c.host.map { $0.length > 0 && units[$0.location] != 91 } == true
        }
        c.path = range(pathStart,beforeQuery)
        if scheme == "http" || scheme == "https" {
            guard let host = c.host, host.length > 0 else { throw URLQueryFailure("host", "HTTP(S) requires a nonempty host.", range:range(pathStart,pathStart)) }
        }
        if let port = c.port {
            let raw = (source as NSString).substring(with:port)
            guard raw.utf8.allSatisfy({ (48...57).contains($0) }) else { throw URLQueryFailure("port", "Port must contain decimal digits.", range:port,region:true) }
            let significant = raw.drop(while: { $0 == "0" })
            if significant.count > 5 || (!significant.isEmpty && (Int(significant) ?? 65536) > 65535) {
                issues.append(.init(code:"portRange", message:"Port is outside the usual network range 0…65535. Original spelling is preserved.", severity:.note,range:port,region:true))
            }
        }
        // Validate in component ranges, so an incomplete escape anchors before the next delimiter, including EOF.
        var parts: [(NSRange,Bool)] = [(c.path,false)]
        for part in [c.scheme,c.userinfo,c.host,c.port,c.fragment] { if let part { parts.append((part,false)) } }
        if let query = c.query { parts.append((query,true)) }
        for (part,privateAllowed) in parts { try preflight(source,range:part,privateAllowed:privateAllowed) }
        var hostReplacement: String?
        if c.dnsHost, let host = c.host {
            let raw = (source as NSString).substring(with:host)
            let decoded = try decodeHost(raw,range:host)
            // Conversion is confined to an isolated hostname; no path/query repair can escape this adapter.
            guard let system = URLComponents(string:"http://" + decoded + "/",encodingInvalidCharacters:true),
                  let unicode = system.host, let url = system.url, let ascii = url.host(percentEncoded:true),
                  !ascii.isEmpty, ascii.utf8.allSatisfy({ $0 < 128 }), !ascii.contains("%"),
                  system.user == nil, system.password == nil, system.port == nil,
                  system.path == "/", system.query == nil, system.fragment == nil else {
                throw URLQueryFailure("idna", "Hostname cannot be represented by the system IDNA profile.",range:host,region:true)
            }
            // Foundation can accept malformed A-labels in syntax parsing while failing to decode host.
            guard let roundtrip = URLComponents(string:"http://"+unicode+"/",encodingInvalidCharacters:true)?.url?.host(percentEncoded:true),
                  roundtrip.lowercased() == ascii.lowercased() else {
                throw URLQueryFailure("idna", "Invalid internationalized hostname.",range:host,region:true)
            }
            c.asciiHost = ascii; c.unicodeHost = unicode
            if raw.unicodeScalars.contains(where: { $0.value > 127 }) || decoded.unicodeScalars.contains(where: { $0.value > 127 }) { hostReplacement = ascii }
            if !raw.utf16.elementsEqual(ascii.utf16) {
                issues.append(.init(code:"idnaMapping",message:"ASCII host uses the system IDNA mapping. Source spelling is preserved in Preserve output.",severity:.note,range:host,region:true))
            }
        } else if let host = c.host {
            let raw = (source as NSString).substring(with:host)
            var encoded = ""
            for scalar in raw.unicodeScalars {
                encoded += scalar.value < 128 ? String(scalar) : String(scalar).utf8.map { String(format:"%%%02X",$0) }.joined()
            }
            c.asciiHost = encoded
        }
        if scheme != nil && scheme != "http" && scheme != "https", c.query != nil {
            issues.append(.init(code:"queryConvention",message:"Query rows use '&' and the first '='. A custom scheme may interpret its query differently.",severity:.note))
        }
        var ascii = "", maps: [URLQuerySourceMap] = [], sourceOffset = 0, derivedOffset = 0
        let scalars = source.unicodeScalars; var index = scalars.startIndex, processed = 0
        func append(_ value: String, sourceRange: NSRange, exact: Bool) throws {
            let size = value.utf8.count
            guard derivedOffset <= limits.validation - size else { throw URLQueryFailure("validationLimit", "Encoded validation reference exceeds the processing limit.",resource:true) }
            ascii += value
            if exact, let last = maps.last, last.exact, NSMaxRange(last.source) == sourceRange.location {
                maps[maps.count-1].derived.length += size
                let old = maps.removeLast()
                maps.append(.init(source:.init(location:old.source.location,length:old.source.length+sourceRange.length),derived:old.derived,exact:true))
            } else { maps.append(.init(source:sourceRange,derived:.init(location:derivedOffset,length:size),exact:exact)) }
            derivedOffset += size
        }
        while index < scalars.endIndex {
            if processed & 4095 == 0 { try Task.checkCancellation() }; processed += 1
            if let host = c.host, let replacement = hostReplacement, sourceOffset == host.location {
                try append(replacement,sourceRange:host,exact:false)
                while sourceOffset < NSMaxRange(host) { sourceOffset += scalars[index].utf16.count; index = scalars.index(after:index) }
                continue
            }
            let scalar = scalars[index], count = scalar.utf16.count
            let value = scalar.value < 128 ? String(scalar) : String(scalar).utf8.map { String(format:"%%%02X",$0) }.joined()
            try append(value,sourceRange:range(sourceOffset,sourceOffset+count),exact:scalar.value < 128)
            sourceOffset += count; index = scalars.index(after:index)
        }
        try Task.checkCancellation()
        guard URLComponents(string:ascii,encodingInvalidCharacters:false) != nil else {
            throw URLQueryFailure("structure", "The reference does not satisfy the system URI syntax rules. No repair was applied.")
        }
        if source.unicodeScalars.contains(where: { $0.value > 127 }) { c.kind = c.scheme == nil ? "IRI reference" : "Absolute IRI" }
        return .init(ascii:ascii,mapping:maps,components:c,issues:issues)
    }
    private static func preflight(_ text: String, range: NSRange, privateAllowed: Bool) throws {
        let part = (text as NSString).substring(with:range), scalars = Array(part.unicodeScalars)
        var i = 0, offset = range.location
        while i < scalars.count {
            if i & 4095 == 0 { try Task.checkCancellation() }
            let scalar = scalars[i], n = scalar.value
            if scalar == "%" {
                var available = 1
                while available < 3 && i+available < scalars.count {
                    let n = scalars[i+available].value
                    guard (48...57).contains(n) || (65...70).contains(n) || (97...102).contains(n) else {
                        throw URLQueryFailure("escape", "Expected two hexadecimal digits after '%'.",range:.init(location:offset,length:scalars[i...min(i+2,scalars.count-1)].reduce(0){$0+$1.utf16.count}),region:true)
                    }
                    available += 1
                }
                if available < 3 { throw URLQueryFailure("escapeEOF", "Incomplete percent escape at the end of this component.",range:.init(location:NSMaxRange(range),length:0)) }
                i += 3; offset += 3; continue
            }
            let unicodeAllowed = (0xA0...0xD7FF).contains(n) || (0xF900...0xFDCF).contains(n) || (0xFDF0...0xFFEF).contains(n) ||
                ((0x10000...0xDFFFD).contains(n) && n & 0xFFFF <= 0xFFFD) || (0xE1000...0xEFFFD).contains(n)
            let privateOK = privateAllowed && ((0xE000...0xF8FF).contains(n) || (0xF0000...0xFFFFD).contains(n) || (0x100000...0x10FFFD).contains(n))
            if n <= 32 || n == 92 || (127...159).contains(n) || (n > 127 && !unicodeAllowed && !privateOK) {
                throw URLQueryFailure("character", "This character is not allowed here. Encode it explicitly; the input was not repaired.",range:.init(location:offset,length:scalar.utf16.count))
            }
            offset += scalar.utf16.count; i += 1
        }
    }
    private static func decodeHost(_ raw: String, range: NSRange) throws -> String {
        let result = URLPercentProcessor.process(raw,options:.init(direction:.decode,profile:.component))
        guard let text = result.artifact?.text, !text.contains(where: { "/?#@:[]\\".contains($0) }) else {
            throw URLQueryFailure("idna", "Hostname contains invalid UTF-8 or a reserved authority delimiter.",range:range,region:true)
        }
        return text
    }
}
