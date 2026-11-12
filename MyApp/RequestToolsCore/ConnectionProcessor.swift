import Foundation
public enum ConnectionProfile:String,CaseIterable,Sendable,Codable,Identifiable {
    case automatic="Auto",postgresURI="PostgreSQL URI",postgresKV="PostgreSQL libpq",sqlServer="SQL Server ADO.NET",mysql="MySQL Connector/J",mongo="MongoDB URI",redis="Redis URI"
    public var id:String{rawValue}
}
public enum ConnectionEncoding:Sendable {case percent,plain,libpq,ado}
public struct ConnectionField:Sendable,Identifiable {
    public let id:Int,name:String,value:String,range:NSRange,encoding:ConnectionEncoding,sensitive:Bool,unknown:Bool
    public var role:String {
        switch name.lowercased() {
        case "server","data source":return "host"
        case "initial catalog","dbname","db":return "database"
        case "uid","user id","username":return "user"
        case "pwd":return "password"
        default:return name.lowercased()
        }
    }
}
public struct ConnectionDocument:Sendable {
    public let source:String,profile:ConnectionProfile,fields:[ConnectionField],issues:[String]
    public func redacted(hideAll:Bool = false)throws->String {
        var text=source as NSString
        for f in fields.reversed() where hideAll || f.sensitive || f.unknown {
            text=text.replacingCharacters(in:f.range,with:ConnectionProcessor.encode("REDACTED",as:f.encoding)) as NSString
        }
        // The source was strictly parsed before spans were produced. Placeholders are
        // intentionally not connectable (for example a redacted numeric port).
        return text as String
    }
    public func editing(_ id:Int,value:String)throws->ConnectionDocument {
        guard let field=fields.first(where:{$0.id==id}),!value.unicodeScalars.contains(where:{$0.value==0}) else{throw RequestIssue("Invalid edited value.")}
        let source=(source as NSString).replacingCharacters(in:field.range,with:ConnectionProcessor.encode(value,as:field.encoding))
        return try ConnectionProcessor.parse(source,profile:profile)
    }
}
public enum ConnectionProcessor {
    private static let known:Set<String>=["host","port","database","db","dbname","username","user","uid","user id","password","pwd","server","data source","initial catalog","sslmode","ssl","tls","sslcert","sslkey","sslrootcert","connect_timeout","connecttimeout","connection timeout","timeout","application_name","application name","integrated security","trusted_connection","encrypt","trustservercertificate","authentication","authsource","authmechanism","replicaset","retrywrites","w","readpreference","maxpoolsize","minpoolsize","charset","characterencoding","usessl","servertimezone","allowpublickeyretrieval"]
    public static func isSensitive(_ name:String)->Bool {let key=name.lowercased();return ["password","pwd","secret","token","credential","sslkey","apikey","api_key","accesskey"].contains(where:key.contains)}
    public static func parse(_ source:String,profile requested:ConnectionProfile)throws->ConnectionDocument {
        guard source.utf16.count<=262144 else{throw RequestIssue("Resource limit: connection string exceeds 262144 UTF-16 units.")}
        guard !source.isEmpty,!source.unicodeScalars.contains(where:{$0.value<32 && $0.value != 9 && $0.value != 10 && $0.value != 13}) else{throw RequestIssue("Enter a connection string without control characters.")}
        var profile=requested
        if profile == .automatic {
            if source.hasPrefix("postgresql://")||source.hasPrefix("postgres://"){profile = .postgresURI}
            else if source.hasPrefix("mongodb://")||source.hasPrefix("mongodb+srv://"){profile = .mongo}
            else if source.hasPrefix("redis://")||source.hasPrefix("rediss://"){profile = .redis}
            else if source.hasPrefix("jdbc:mysql://"){profile = .mysql}
            else{throw RequestIssue("Choose PostgreSQL libpq or SQL Server ADO.NET for a key/value connection string.")}
        }
        var fields:[ConnectionField]=[],issues:[String]=[]
        func add(_ name:String,_ value:String,_ range:NSRange,_ encoding:ConnectionEncoding)throws {
            guard fields.count<4096 else{throw RequestIssue("Resource limit: more than 4096 connection fields.")}
            fields.append(ConnectionField(id:fields.count,name:name,value:value,range:range,encoding:encoding,sensitive:isSensitive(name),unknown:!known.contains(name.lowercased())))
        }
        let u=Array(source.utf16)
        if profile == .postgresKV || profile == .sqlServer {
            let ado=profile == .sqlServer;var i=0
            while i<u.count {
                try Task.checkCancellation()
                while i<u.count && ([9,10,13,32].contains(u[i]) || (ado && u[i]==59)){i+=1}
                if i==u.count{break};let keyStart=i
                while i<u.count && u[i] != 61 && (!ado || u[i] != 59){i+=1}
                guard i<u.count,u[i]==61 else{throw RequestIssue("Expected key=value.",range:NSRange(location:keyStart,length:max(0,i-keyStart)))}
                let key=String(decoding:u[keyStart..<i],as:UTF16.self).trimmingCharacters(in:.whitespacesAndNewlines)
                guard !key.isEmpty,ado || !key.contains(where:{$0.isWhitespace}),!key.contains("\"") && !key.contains("'") else{throw RequestIssue("Invalid connection option name.")}
                i+=1;while i<u.count && [9,10,13,32].contains(u[i]){i+=1};let start=i;var value:[UInt16]=[]
                if i<u.count && (u[i]==39 || (ado && u[i]==34)) {
                    let quote=u[i];i+=1;var closed=false
                    while i<u.count {
                        if u[i]==quote {
                            if ado && i+1<u.count && u[i+1]==quote{value.append(quote);i+=2;continue}
                            i+=1;closed=true;break
                        }
                        if !ado && u[i]==92{i+=1;guard i<u.count else{throw RequestIssue("Unterminated libpq escape.")}}
                        value.append(u[i]);i+=1
                    }
                    guard closed else{throw RequestIssue("Unterminated quoted connection value.",range:NSRange(location:start,length:u.count-start))}
                    let end=i;while i<u.count && [9,10,13,32].contains(u[i]){i+=1}
                    if ado {guard i==u.count || u[i]==59 else{throw RequestIssue("Expected ';' after a quoted value.")}}
                    else {guard i==u.count || i>end else{throw RequestIssue("Separate libpq options with whitespace.")}}
                    try add(key,String(decoding:value,as:UTF16.self),NSRange(location:start,length:end-start),ado ? .ado:.libpq)
                } else {
                    while i<u.count && (ado ? u[i] != 59 : ![9,10,13,32].contains(u[i])) {
                        if !ado && u[i]==92{i+=1;guard i<u.count else{throw RequestIssue("Unterminated libpq escape.")}}
                        value.append(u[i]);i+=1
                    }
                    var end=i
                    if ado{while end>start && [9,10,13,32].contains(u[end-1]){end-=1};value=Array(u[start..<end])}
                    try add(key,String(decoding:value,as:UTF16.self),NSRange(location:start,length:end-start),ado ? .ado:.libpq)
                }
            }
            guard !fields.isEmpty else{throw RequestIssue("No connection options found.")}
        } else {
            let prefixes:[String]
            switch profile{case .postgresURI:prefixes=["postgresql://","postgres://"];case .mongo:prefixes=["mongodb://","mongodb+srv://"];case .redis:prefixes=["redis://","rediss://"];case .mysql:prefixes=["jdbc:mysql://"];default:prefixes=[]}
            guard let prefix=prefixes.first(where:source.hasPrefix) else{throw RequestIssue("Connection prefix does not match the selected profile.")}
            guard !source.contains("#"),!source.contains(where:{$0.isWhitespace}) else{throw RequestIssue("URI whitespace and fragments are unsupported. Percent-encode literal values.")}
            let start=prefix.utf16.count;var end=start
            while end<u.count && u[end] != 47 && u[end] != 63{end+=1}
            var hostStart=start
            let ats=(start..<end).filter{u[$0]==64}
            guard ats.count<=1 else{throw RequestIssue("Percent-encode '@' inside credentials.")}
            if let at=ats.first {
                guard profile != .mysql else{throw RequestIssue("Use MySQL user/password query options, not URI userinfo.")}
                let colon=(start..<at).first{u[$0]==58}
                if let colon{try add("user",decode(u,start,colon),NSRange(location:start,length:colon-start),.percent);try add("password",decode(u,colon+1,at),NSRange(location:colon+1,length:at-colon-1),.percent)}
                else{try add("user",decode(u,start,at),NSRange(location:start,length:at-start),.percent)}
                hostStart=at+1
            }
            var segment=hostStart,brackets=0,hosts=0
            for j in hostStart...end {
                if j<end,u[j]==91{brackets+=1};if j<end,u[j]==93{brackets-=1};guard (0...1).contains(brackets) else{throw RequestIssue("Invalid IPv6 host brackets.")}
                if j==end || (u[j]==44 && brackets==0) {
                    guard j>segment else{throw RequestIssue("Host cannot be empty.")};hosts+=1
                    var hostEnd=j,portStart:Int?
                    if u[segment]==91 {guard let close=(segment..<j).first(where:{u[$0]==93}),close>segment+1 else{throw RequestIssue("Unterminated IPv6 host.")};hostEnd=close+1;if close+1<j{guard u[close+1]==58 else{throw RequestIssue("Expected ':' after IPv6 host.")};portStart=close+2}}
                    else if let colon=(segment..<j).first(where:{u[$0]==58}){hostEnd=colon;portStart=colon+1}
                    guard hostEnd>segment else{throw RequestIssue("Host cannot be empty.")}
                    try add("host",decode(u,segment,hostEnd),NSRange(location:segment,length:hostEnd-segment),.percent)
                    if let p=portStart{let value=String(decoding:u[p..<j],as:UTF16.self);guard !value.isEmpty,value.allSatisfy({$0.isASCII && $0.isNumber}),let n=Int(value),(1...65535).contains(n) else{throw RequestIssue("Port must be 1–65535; no default was substituted.")};try add("port",value,NSRange(location:p,length:j-p),.plain)}
                    segment=j+1
                }
            }
            guard brackets==0 else{throw RequestIssue("Unterminated host brackets.")}
            if [.mysql,.redis].contains(profile),hosts != 1{throw RequestIssue("Selected profile supports a single host.")}
            if prefix == "mongodb+srv://",hosts != 1 || fields.contains(where:{$0.name=="port"}){throw RequestIssue("MongoDB SRV requires one hostname without an explicit port.")}
            var i=end
            if i<u.count && u[i]==47 {
                i+=1;let pathStart=i;while i<u.count && u[i] != 63{i+=1}
                let db=try decode(u,pathStart,i)
                if profile == .redis && !db.isEmpty {guard db.allSatisfy({$0.isASCII && $0.isNumber}),Int(db) != nil else{throw RequestIssue("Redis database must be a nonnegative integer.")}}
                if db.contains("/"){throw RequestIssue("Use one database path segment.")}
                try add("database",db,NSRange(location:pathStart,length:i-pathStart),.percent)
            }
            if i<u.count && u[i]==63 {
                i+=1
                while i<u.count {let begin=i;while i<u.count && u[i] != 38{i+=1};let end=i
                    guard let equal=(begin..<end).first(where:{u[$0]==61}),equal>begin else{throw RequestIssue("Query options require name=value.")}
                    let key=try decode(u,begin,equal),value=try decode(u,equal+1,end)
                    try add(key,value,NSRange(location:equal+1,length:end-equal-1),.percent);i+=1
                }
            }
            if prefix == "mongodb+srv://"{issues.append("SRV syntax only: no DNS lookups were made.")}
        }
        for field in fields where field.role == "port" {
            let ports=profile == .postgresKV ? field.value.components(separatedBy:","):[field.value]
            guard ports.allSatisfy({$0.isEmpty && profile == .postgresKV || (!$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber}) && Int($0).map{(1...65535).contains($0)} == true)}) else{throw RequestIssue("Port must be 1–65535; no default was substituted.",range:field.range)}
        }
        let duplicates=Dictionary(grouping:fields,by:{$0.role}).values.contains{$0.count>1}
        if duplicates {issues.append("Repeated options/aliases/hosts retained in source order. Provider precedence is not inferred.")}
        if fields.contains(where:{["sslmode","encrypt","usessl","ssl","tls"].contains($0.name.lowercased()) && ["disable","false","no","0"].contains($0.value.lowercased())}){issues.append("Explicit TLS-disabled option detected. This is an advisory, not a server security audit.")}
        issues.append("Syntax inspection only. Credentials, connectivity and TLS certificates were not checked.")
        return ConnectionDocument(source:source,profile:profile,fields:fields,issues:issues)
    }
    private static func decode(_ u:[UInt16],_ a:Int,_ b:Int)throws->String {
        let raw=String(decoding:u[a..<b],as:UTF16.self)
        guard let result=raw.removingPercentEncoding else{throw RequestIssue("Invalid percent escape or UTF-8 in URI.",range:NSRange(location:a,length:b-a))}
        guard !result.unicodeScalars.contains(where:{$0.value==0}) else{throw RequestIssue("NUL is not supported in connection values.")}
        return result // '+' is a literal plus, never form-decoded.
    }
    public static func encode(_ value:String,as encoding:ConnectionEncoding)->String {
        switch encoding {
        case .plain:return value
        case .percent:return value.utf8.map{((65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||[45,46,95,126].contains($0)) ? String(UnicodeScalar($0)) : String(format:"%%%02X",$0)}.joined()
        case .libpq:return "'"+value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"'",with:"\\'")+"'"
        case .ado:return "\""+value.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }
    }
}
