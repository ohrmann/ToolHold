import Foundation

/// Tolerant presentation only. No grammar validation or inferred bracket pairs.
enum MarkupSyntaxLexer {
    static func scan(_ source: String, syntax: EditorSyntax, limit: Int) -> JSONSyntaxSnapshot? {
        let u=Array(source.utf16.prefix(limit+1))
        guard u.count<=limit else{return nil}
        let keywords=Set("select from where join left right inner outer on as insert into values update set delete create table drop alter with union all order by group having limit offset null true false and or not case when then else end distinct asc desc const let var function return class extends new if for while do switch break continue import export default async await throw try catch finally typeof instanceof void yield this super static get in of media supports layer important".split(separator:" ").map(String.init))
        var tokens:[JSONSyntaxToken]=[],i=0,inTag=false
        func begins(_ s:String,_ at:Int)->Bool{u[at...].starts(with:s.utf16)}
        func append(_ start:Int,_ kind:JSONSyntaxKind){tokens.append(.init(range:.init(location:start,length:i-start),kind:kind))}
        while i<u.count {
            if Task.isCancelled || tokens.count>=16384{return nil}
            let start=i,c=u[i]
            if syntax == .markup {
                if begins("<!--",i) {i += 4;while i<u.count && !begins("-->",i){i += 1};i=min(u.count,i+3);append(start,.comment);continue}
                if c==60 {inTag=true;i += 1;append(start,.bracket);continue}
                if c==62 {inTag=false;i += 1;append(start,.bracket);continue}
                if !inTag {i += 1;continue}
            }
            if syntax == .markdown {
                if (i==0 || u[i-1]==10) && c==35 {while i<u.count && u[i] != 10{i += 1};append(start,.key);continue}
                if begins("```",i) {i += 3;while i<u.count && !begins("```",i){i += 1};i=min(u.count,i+3);append(start,.string);continue}
            }
            if begins("/*",i) {i += 2;while i<u.count && !begins("*/",i){i += 1};i=min(u.count,i+2);append(start,.comment);continue}
            if (syntax == .sql && begins("--",i)) || (syntax == .javascript && begins("//",i)) {while i<u.count && u[i] != 10{i += 1};append(start,.comment);continue}
            if c==34 || c==39 || c==96 {
                i += 1
                while i<u.count {if u[i]==92 {i=min(u.count,i+2);continue};if u[i]==c {i += 1;if syntax == .sql && i<u.count && u[i]==c{i += 1;continue};break};i += 1}
                append(start,.string);continue
            }
            if c>=48 && c<=57 {i += 1;while i<u.count && ((48...57).contains(u[i]) || u[i]==46){i += 1};append(start,.number);continue}
            if (65...90).contains(c)||(97...122).contains(c)||c==95||c==36 {
                i += 1;while i<u.count && ((65...90).contains(u[i])||(97...122).contains(u[i])||(48...57).contains(u[i])||u[i]==95||u[i]==45||u[i]==36){i += 1}
                let value=String(decoding:u[start..<i],as:UTF16.self)
                if inTag {append(start,.key)}else if keywords.contains(value.lowercased()){append(start,.literal)}
                continue
            }
            i += 1
            if [123,125,91,93,40,41].contains(c){append(start,.bracket)}else if [44,58,59,61].contains(c){append(start,.separator)}
        }
        return .init(utf16Length:u.count,tokens:tokens,partners:[:])
    }
}
