import Foundation
public struct CurlToken:Sendable,Equatable {
    public let value:String,range:NSRange
}
/// A literal argument scanner, not a shell. Never executes expansions or reads files.
public enum CurlTokenizer {
    public static func tokenize(_ source:String)throws->[CurlToken] {
        guard source.utf16.count<=262144 else {throw RequestIssue("Resource limit: input exceeds 262144 UTF-16 units.")}
        let u=Array(source.utf16);var i=0,tokens:[CurlToken]=[]
        func fail(_ message:String,_ start:Int)->RequestIssue {RequestIssue(message,range:NSRange(location:start,length:min(1,u.count-start)))}
        func decodeANSI(_ bytes:[UInt8],_ start:Int)throws->String {guard !bytes.contains(0),let s=String(bytes:bytes,encoding:.utf8) else {throw fail("ANSI-C bytes must be non-NUL valid UTF-8.",start)};return s}
        while i<u.count {
            try Task.checkCancellation()
            while i<u.count && [9,10,13,32].contains(u[i]) {
                if !tokens.isEmpty,[10,13].contains(u[i]),u[(i+1)...].contains(where:{![9,10,13,32].contains($0)}) {throw fail("Unescaped newline starts another shell command. Use a backslash line continuation.",i)}
                i+=1
            }
            if i==u.count{break}
            guard tokens.count<8192 else {throw RequestIssue("Resource limit: more than 8192 arguments.")}
            let start=i;var out=""
            while i<u.count && ![9,10,13,32].contains(u[i]) {
                let c=u[i]
                if c==39 {
                    i+=1;let begin=i;while i<u.count && u[i] != 39{i+=1};guard i<u.count else{throw fail("Unterminated single quote.",start)}
                    out+=String(decoding:u[begin..<i],as:UTF16.self);i+=1
                } else if c==34 {
                    i+=1;var units:[UInt16]=[]
                    while i<u.count && u[i] != 34 {
                        if u[i]==36 || u[i]==96{throw fail("Unsupported shell expansion in double quotes.",i)}
                        if u[i]==92 {
                            i+=1;guard i<u.count else{throw fail("Unterminated escape.",start)}
                            if u[i]==10{i+=1;continue}
                            if ![36,96,34,92].contains(u[i]){units.append(92)}
                        }
                        units.append(u[i]);i+=1
                    }
                    guard i<u.count else{throw fail("Unterminated double quote.",start)};out+=String(decoding:units,as:UTF16.self);i+=1
                } else if c==36 && i+1<u.count && u[i+1]==39 {
                    i+=2;var bytes:[UInt8]=[]
                    while i<u.count && u[i] != 39 {
                        if u[i] != 92 {
                            let begin=i;while i<u.count && u[i] != 39 && u[i] != 92{i+=1};bytes+=String(decoding:u[begin..<i],as:UTF16.self).utf8;continue
                        }
                        i+=1;guard i<u.count else{throw fail("Unterminated ANSI-C escape.",start)}
                        let c=u[i];i+=1
                        let simple:[UInt16:UInt8]=[97:7,98:8,101:27,102:12,110:10,114:13,116:9,118:11,92:92,39:39,34:34,63:63]
                        if let b=simple[c]{bytes.append(b)}
                        else if c==120 || c==117 || c==85 {
                            let maxDigits=c==120 ? 2 : c==117 ? 4 : 8;let begin=i
                            while i<u.count && i-begin<maxDigits && ((48...57).contains(u[i])||(65...70).contains(u[i])||(97...102).contains(u[i])){i+=1}
                            guard i>begin,let n=UInt32(String(decoding:u[begin..<i],as:UTF16.self),radix:16) else{throw fail("Invalid ANSI-C hex escape.",start)}
                            if c==120{bytes.append(UInt8(n))}else{guard let scalar=UnicodeScalar(n) else{throw fail("Invalid Unicode scalar escape.",start)};bytes+=String(scalar).utf8}
                        } else if (48...55).contains(c) {
                            var digits=[c];while i<u.count && digits.count<3 && (48...55).contains(u[i]){digits.append(u[i]);i+=1}
                            guard let n=UInt16(String(decoding:digits,as:UTF16.self),radix:8),n<=255 else{throw fail("Invalid ANSI-C octal escape.",start)};bytes.append(UInt8(n))
                        } else {throw fail("Unsupported ANSI-C escape.",start)}
                    }
                    guard i<u.count else{throw fail("Unterminated ANSI-C string.",start)};out+=try decodeANSI(bytes,start);i+=1
                } else if c==92 {
                    i+=1;guard i<u.count else{throw fail("Unterminated escape.",start)}
                    if u[i]==10 {i+=1;continue}
                    let begin=i;i+=1;if (0xD800...0xDBFF).contains(u[begin]),i<u.count{ i+=1 }
                    out+=String(decoding:u[begin..<i],as:UTF16.self)
                } else {
                    if [36,96,124,38,59,60,62,40,41,94].contains(c){throw fail("Unsupported shell operator or expansion. Only literal arguments are supported.",i)}
                    let begin=i;i+=1;if (0xD800...0xDBFF).contains(c),i<u.count{i+=1};out+=String(decoding:u[begin..<i],as:UTF16.self)
                }
            }
            guard !out.unicodeScalars.contains(where:{$0.value==0}) else{throw fail("NUL is not supported in shell arguments.",start)}
            tokens.append(CurlToken(value:out,range:NSRange(location:start,length:i-start)))
        }
        return tokens
    }
}
