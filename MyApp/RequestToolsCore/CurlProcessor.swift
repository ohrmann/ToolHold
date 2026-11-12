import Foundation
public struct RequestHeader:Sendable,Equatable {public let name:String,value:String;public let removed:Bool}
public struct RequestPart:Sendable,Equatable {public let name:String,value:String,filename:String?,contentType:String?;public let file:Bool}
public struct HTTPRequestSpec:Sendable {
    public var url="",method="GET",headers:[RequestHeader]=[],body:String?=nil,parts:[RequestPart]=[]
    public var methodWasExplicit=false
    public var followRedirects=false,maxRedirects:Int?=nil,totalTimeout:Double?=nil,connectTimeout:Double?=nil,compressed=false
    public var issues:[String]=[],needsValues=false
}
public enum CurlProcessor {
    public static func parse(_ source:String)throws->HTTPRequestSpec {
        let tokens=try CurlTokenizer.tokenize(source)
        guard let first=tokens.first,["curl","/usr/bin/curl"].contains(first.value) else{throw RequestIssue("Start with curl. Shell scripts and PowerShell are not supported.")}
        var request=HTTPRequestSpec(),i=1,positional=false,urls:[String]=[],data:[String]=[],json=false,formBody=false,get=false,head=false,explicitMethod:String?,globoff=false
        let short:[String:String] = ["X":"request","I":"head","G":"get","g":"globoff","H":"header","A":"user-agent","e":"referer","u":"user","b":"cookie","d":"data","F":"form","L":"location","m":"max-time","s":"silent","S":"show-error","v":"verbose","i":"include"]
        let flags:Set<String>=["head","get","globoff","basic","location","compressed","silent","show-error","verbose","include","no-progress-meter"]
        let valued:Set<String>=["url","request","header","user-agent","referer","user","cookie","data","data-raw","data-binary","data-urlencode","json","form","form-string","max-redirs","max-time","connect-timeout"]
        func error(_ message:String,_ token:CurlToken)->RequestIssue {RequestIssue(message,range:token.range)}
        func header(_ name:String,_ value:String,_ removed:Bool=false)throws {
            guard !name.isEmpty,name.unicodeScalars.allSatisfy({$0.isASCII && (CharacterSet.alphanumerics.contains($0)||"!#$%&'*+-.^_`|~".unicodeScalars.contains($0))}),value.unicodeScalars.allSatisfy({$0.value>=32 && $0.value != 127 || $0.value==9}) else {throw RequestIssue("Invalid HTTP header name or newline in value.")}
            request.headers.append(RequestHeader(name:name,value:value,removed:removed))
        }
        func encoded(_ s:String)->String {s.utf8.map{((65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||[45,46,95,126].contains($0)) ? String(UnicodeScalar($0)) : String(format:"%%%02X",$0)}.joined()}
        func apply(_ name:String,_ value:String?,_ token:CurlToken)throws {
            let v=value ?? ""
            switch name {
            case "url":urls.append(v)
            case "request":guard !v.isEmpty,v.unicodeScalars.allSatisfy({$0.isASCII && (CharacterSet.alphanumerics.contains($0)||"!#$%&'*+-.^_`|~".unicodeScalars.contains($0))}) else {throw error("Invalid HTTP method.",token)};explicitMethod=v
            case "head":head=true
            case "get":get=true
            case "globoff":globoff=true
            case "header":
                if let colon=v.firstIndex(of:":") {let name=String(v[..<colon]),value=String(v[v.index(after:colon)...]).trimmingCharacters(in:.whitespaces);try header(name,value,value.isEmpty)}
                else if v.hasSuffix(";"){try header(String(v.dropLast()),"")}
                else{throw error("Expected a header with ':' or an empty header ending in ';'.",token)}
            case "user-agent":try header("User-Agent",v)
            case "referer":guard !v.hasSuffix(";auto") else{throw error("Automatic redirect Referer is not supported.",token)};try header("Referer",v)
            case "user":guard v.contains(":") else{throw error("Provide explicit username:password. Interactive password prompts are unsupported.",token)};try header("Authorization","Basic "+Data(v.utf8).base64EncodedString())
            case "basic":break
            case "cookie":guard v.contains("="),!v.hasPrefix("@") else{throw error("Only literal Cookie values are supported; cookie files are never read.",token)};try header("Cookie",v)
            case "data","data-raw","data-binary","data-urlencode","json":
                if name == "json" {json=true} else {formBody=true}
                if name != "data-raw",v.hasPrefix("@") || (name == "data-urlencode" && v.contains("@") && !v.contains("=")) {
                    request.needsValues=true;request.issues.append("File/stdin body is unresolved; provide its content explicitly.");data.append("REPLACE_WITH_FILE_CONTENT")
                } else if name == "data-urlencode" {
                    if let equal=v.firstIndex(of:"="){let key=String(v[..<equal]);data.append(key+(key.isEmpty ? "" : "=")+encoded(String(v[v.index(after:equal)...])))}else{data.append(encoded(v))}
                } else {data.append(v)}
            case "form","form-string":
                guard let equal=v.firstIndex(of:"=") else{throw error("Multipart field requires name=value.",token)}
                let key=String(v[..<equal]),raw=String(v[v.index(after:equal)...]);var value=raw,filename:String?,type:String?,file=false
                if name == "form" {
                    guard !raw.hasPrefix("("),raw != ")",!raw.hasPrefix("\""),!(raw.hasPrefix("@") && raw.contains(",")) else{throw error("Nested/quoted or multiple-file multipart syntax is unsupported. Use literal --form-string or one simple file placeholder.",token)}
                    let fields=raw.components(separatedBy:";");value=fields[0]
                    for field in fields.dropFirst(){if field.hasPrefix("type="){type=String(field.dropFirst(5))}else if field.hasPrefix("filename="){filename=String(field.dropFirst(9))}else{throw error("Unsupported multipart modifier.",token)}}
                    if value.hasPrefix("@") || value.hasPrefix("<") {file=true;request.needsValues=true;value="REPLACE_WITH_FILE_CONTENT";request.issues.append("Multipart file is a placeholder; no file was read.")}
                }
                guard !key.isEmpty,!key.contains("\r"),!key.contains("\n") else{throw error("Invalid multipart field name.",token)}
                request.parts.append(RequestPart(name:key,value:value,filename:filename,contentType:type,file:file))
            case "location":request.followRedirects=true
            case "compressed":request.compressed=true
            case "max-redirs":guard let n=Int(v),n>=0,n<=10000 else{throw error("Use a nonnegative redirect limit up to 10000.",token)};request.maxRedirects=n
            case "max-time","connect-timeout":guard let n=Double(v),n.isFinite,n>=0,n<=86400 else{throw error("Timeout must be 0–86400 seconds.",token)};if name == "max-time"{request.totalTimeout=n==0 ? nil:n}else{request.connectTimeout=n==0 ? nil:n}
            default:request.issues.append("CLI display option --\(name) does not change the generated request.")
            }
        }
        while i<tokens.count {
            try Task.checkCancellation();let token=tokens[i],arg=token.value;i+=1
            if arg == "--" && !positional {positional=true;continue}
            if positional || !arg.hasPrefix("-") || arg == "-" {urls.append(arg);continue}
            if arg.hasPrefix("--") {
                let components=String(arg.dropFirst(2)).split(separator:"=",maxSplits:1,omittingEmptySubsequences:false).map(String.init),name=components[0]
                guard flags.contains(name)||valued.contains(name) else{throw error("Unsupported cURL option. No snippet was generated.",token)}
                var v=components.count==2 ? components[1] : nil
                if valued.contains(name) && v == nil {guard i<tokens.count else{throw error("Missing option value.",token)};v=tokens[i].value;i+=1}
                if flags.contains(name),v != nil{throw error("This option does not accept a value.",token)}
                try apply(name,v,token)
            } else {
                let chars=Array(arg.dropFirst());var c=0
                while c<chars.count {guard let name=short[String(chars[c])] else{throw error("Unsupported short cURL option.",token)};c+=1;var v:String?
                    if valued.contains(name){if c<chars.count{v=String(chars[c...]);c=chars.count}else{guard i<tokens.count else{throw error("Missing option value.",token)};v=tokens[i].value;i+=1}}
                    try apply(name,v,token)
                }
            }
            guard request.headers.count+data.count+request.parts.count<=1024 else{throw RequestIssue("Resource limit: more than 1024 headers/body parts.")}
        }
        guard urls.count==1,let raw=urls.first,raw.hasPrefix("https://")||raw.hasPrefix("http://"),let components=URLComponents(string:raw),components.host?.isEmpty==false,components.user==nil,components.password==nil else{throw RequestIssue("Provide exactly one HTTP(S) URL without embedded credentials.")}
        let urlBytes=Array(raw.utf8)
        guard raw.unicodeScalars.allSatisfy({$0.value>32 && $0.value != 127}) else{throw RequestIssue("URL whitespace/control characters must be percent-encoded.")}
        for n in urlBytes.indices where urlBytes[n]==37 {
            guard n+2<urlBytes.count,UInt8(String(decoding:urlBytes[n+1...n+2],as:UTF8.self),radix:16) != nil else{throw RequestIssue("Invalid percent escape in URL.")}
        }
        if !globoff {
            let withoutIPv6=raw.replacingOccurrences(of:#"\[[0-9A-Fa-f:.%]+\]"#,with:"",options:.regularExpression)
            if withoutIPv6.contains("{")||withoutIPv6.contains("["){throw RequestIssue("URL globbing is unsupported. Use --globoff for a literal URL.")}
        }
        guard request.parts.isEmpty || data.isEmpty else{throw RequestIssue("Do not mix multipart and data body options.")}
        guard !head || (data.isEmpty && request.parts.isEmpty || get) else{throw RequestIssue("HEAD combined with body data is not supported by this profile.")}
        guard !(json && formBody) else{throw RequestIssue("Mixing --json with other data modes has ambiguous body joining; choose one mode.")}
        request.url=raw
        if components.fragment != nil {request.issues.append("URL fragment is not transmitted in HTTP.")}
        if !data.isEmpty {
            let body=data.joined(separator:json ? "" : "&")
            if get {
                guard body.unicodeScalars.allSatisfy({$0.value>32 && $0.value<127}), !body.contains("#"), body.removingPercentEncoding != nil else {throw RequestIssue("-G requires valid URL-encoded data. Use --data-urlencode for literal text.")}
                let parts=raw.split(separator:"#",maxSplits:1,omittingEmptySubsequences:false)
                request.url=String(parts[0])+(parts[0].contains("?") ? "&":"?")+body+(parts.count==2 ? "#"+parts[1]:"")
            } else {request.body=body}
            if !get && !request.headers.contains(where:{$0.name.lowercased()=="content-type"}) {try header("Content-Type",json ? "application/json" : "application/x-www-form-urlencoded")}
            if json && !request.headers.contains(where:{$0.name.lowercased()=="accept"}){try header("Accept","application/json")}
        }
        request.methodWasExplicit=explicitMethod != nil
        request.method=explicitMethod ?? (head ? "HEAD" : get ? "GET" : request.body != nil || !request.parts.isEmpty ? "POST":"GET")
        return request
    }
}
