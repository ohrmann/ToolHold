import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Foundation owns the XML grammar. This scanner only preserves raw spelling and places indentation.
enum XMLMarkupProcessor {
    private struct Token { let raw: String; let offset: Int; let kind: Int } // 0 text,1 start,2 end,3 other
    static func process(_ request: MarkupRequest, cancellation: MarkupCancellation) -> MarkupResult {
        do {
            if cancellation.isCancelled { return .init(status:"cancelled") }
            let tokens = try scan(request.source)
            if let declaration=tokens.first(where:{$0.raw.hasPrefix("<?xml ")}),
               let range=declaration.raw.range(of:#"encoding\s*=\s*(['"])([^'"]+)\1"#,options:.regularExpression),
               !declaration.raw[range].lowercased().contains("utf-8") { return .failure("unsupported","Open supports UTF-8 XML only; update the encoding declaration explicitly.") }
            if let declaration=tokens.first(where:{$0.raw.hasPrefix("<?xml ")}), declaration.raw.range(of:#"version\s*=\s*(['"])1\.1\1"#,options:.regularExpression) != nil {return .failure("unsupported","Only XML 1.0 is supported.")}
            let check = Reader(cancellation)
            guard let data = request.source.data(using: .utf8) else { return .failure("invalid", "Input is not valid Unicode.") }
            let parser = XMLParser(data: data); parser.delegate = check
            parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never
            parser.shouldProcessNamespaces = true; parser.shouldReportNamespacePrefixes = true
            let valid = parser.parse()
            if cancellation.isCancelled { return .init(status:"cancelled") }
            if let issue = check.issue { return .init(status: check.limited ? "resourceLimit" : "invalid", diagnostics: [issue]) }
            guard valid else { return .failure("invalid", "XML is not well-formed.") }
            if request.operation == "validate" { return .init(status: "success") }
            if request.options.preserveXMLText { return checkedOutput(tokens.map { $0.kind == 1 ? Self.attributeLayout($0.raw, indent: request.options.indent) : $0.raw }.joined(), cancellation:cancellation, notices: ["Text nodes preserved; only attribute layout was changed."]) }
            var startIndex = 0
            var stack: [Int] = [], parent = Array<Int?>(repeating: nil, count: tokens.count), mixed = Set<Int>(), preserve = Set<Int>()
            for (i,t) in tokens.enumerated() {
                parent[i] = stack.last
                if t.kind == 0, !isXMLWhitespace(t.raw), let p = stack.last { mixed.insert(p) }
                if t.raw.hasPrefix("<![CDATA["), let p = stack.last { mixed.insert(p) }
                if t.kind == 1 {
                    // XMLParser owns attribute decoding and namespace spelling; never
                    // recognize xml:space by matching text inside another attribute value.
                    let space = check.spaces[startIndex]; startIndex += 1
                    let explicit = space == "preserve", reset = space == "default"
                    if explicit || (!reset && stack.last.map { preserve.contains($0) } == true) { preserve.insert(i) }
                    if !t.raw.hasSuffix("/>") { stack.append(i) }
                } else if t.kind == 2 { _ = stack.popLast() }
            }
            let nl = request.source.contains("\r\n") ? "\r\n" : "\n"
            var output = "", depth = 0
            for (i,t) in tokens.enumerated() {
                if t.kind == 2 { depth = max(0, depth-1) }
                let p = parent[i]
                let protected = p.map { mixed.contains($0) || preserve.contains($0) } ?? false
                if t.kind == 0, !protected, isXMLWhitespace(t.raw) { continue }
                let textOnlyEnd = t.kind == 2 && i > 0 && tokens[i-1].kind == 1
                if t.kind != 0, !protected, !output.isEmpty, output != "\u{FEFF}", !textOnlyEnd { output += nl + String(repeating: " ", count: depth*request.options.indent) }
                output += t.raw
                if t.kind == 1, !t.raw.hasSuffix("/>") { depth += 1 }
            }
            if output.utf8.count > 4*1024*1024 { return .failure("resourceLimit", "Output exceeds 4 MiB.") }
            return checkedOutput(output, cancellation:cancellation, notices: ["Indentation changes whitespace between elements. Use Preserve Text Nodes when those spaces are significant."])
        } catch let e as Failure { return .init(status: e.status, diagnostics: [.init(message: e.message, offset: e.offset)]) }
        catch { return .failure("invalid", "Unable to read XML.") }
    }
    private static func isXMLWhitespace(_ text: String) -> Bool {text.utf16.allSatisfy{[9,10,13,32].contains($0)}}
    private static func checkedOutput(_ output: String, cancellation: MarkupCancellation, notices: [String]) -> MarkupResult {
        if cancellation.isCancelled {return .init(status:"cancelled")}
        let parser=XMLParser(data:Data(output.utf8)),reader=Reader(cancellation)
        parser.delegate=reader;parser.shouldProcessNamespaces=true
        parser.shouldResolveExternalEntities=false;parser.externalEntityResolvingPolicy = .never
        let valid=parser.parse()
        if cancellation.isCancelled {return .init(status:"cancelled")}
        guard valid,reader.issue == nil else {return .failure("unsupported","Formatting could not preserve well-formed XML. No output was published.")}
        return .init(status:"success",output:output,notices:notices)
    }
    private static func attributeLayout(_ raw: String, indent: Int) -> String {
        let u=Array(raw.utf16);var i=0,quote:UInt16=0,out=""
        while i<u.count {
            let c=u[i]
            if quote != 0 {let width=(0xD800...0xDBFF).contains(c)&&i+1<u.count ? 2 : 1;out+=String(decoding:u[i..<i+width],as:UTF16.self);if c==quote{quote=0};i+=width;continue}
            if c==34 || c==39 {quote=c}
            if [9,10,13,32].contains(c) {
                let start=i;while i<u.count && [9,10,13,32].contains(u[i]){i+=1}
                var j=i;while j<u.count && ![9,10,13,32,61,62,47].contains(u[j]){j+=1}
                while j<u.count && [9,10,13,32].contains(u[j]){j+=1}
                if j<u.count && u[j]==61 {out+="\n"+String(repeating:" ",count:indent)}
                else {out+=String(decoding:u[start..<i],as:UTF16.self)}
                continue
            }
            // Append a full scalar rather than splitting surrogate pairs.
            let width=(0xD800...0xDBFF).contains(c)&&i+1<u.count ? 2 : 1
            out+=String(decoding:u[i..<i+width],as:UTF16.self);i+=width
        };return out
    }
    private struct Failure: Error { let status: String; let message: String; let offset: Int }
    private static func scan(_ source: String) throws -> [Token] {
        let u = Array(source.utf16); var i = 0, result: [Token] = []
        func has(_ s: String, _ at: Int) -> Bool { u[at...].starts(with: s.utf16) }
        while i < u.count {
            let start = i
            if u[i] != 60 { while i < u.count, u[i] != 60 { i += 1 }; result.append(.init(raw: String(decoding: u[start..<i], as: UTF16.self), offset: start, kind: 0)); continue }
            if has("<!DOCTYPE",i) || has("<!ENTITY",i) { throw Failure(status: "unsupported", message: "DTD and custom entities are disabled. No files or network resources are resolved.", offset: i) }
            let end: String? = has("<!--",i) ? "-->" : has("<![CDATA[",i) ? "]]>" : has("<?",i) ? "?>" : nil
            if let end { i += 2; while i < u.count, !has(end,i) { i += 1 }; i = min(u.count,i+end.utf16.count) }
            else { i += 1; var quote: UInt16 = 0; while i < u.count { let c=u[i];i += 1;if quote != 0 { if c==quote {quote=0} } else if c==34 || c==39 {quote=c} else if c==62 {break} } }
            let raw=String(decoding:u[start..<i],as:UTF16.self)
            result.append(.init(raw:raw,offset:start,kind:end != nil ? 3 : raw.hasPrefix("</") ? 2 : 1))
        }
        return result
    }
    private final class Reader: NSObject, XMLParserDelegate {
        var issue: MarkupDiagnostic?, depth = 0, limited = false
        var spaces: [String?] = []
        let cancellation: MarkupCancellation
        init(_ cancellation: MarkupCancellation) { self.cancellation=cancellation }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String:String]) {
            if cancellation.isCancelled {parser.abortParsing();return}
            spaces.append(attributeDict["xml:space"])
            depth += 1; if depth > 128 { limited=true;issue = .init(message:"XML nesting exceeds 128 levels.",line:parser.lineNumber);parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
        func parser(_ parser: XMLParser, parseErrorOccurred error: Error) { if issue == nil { issue = .init(message:"XML is not well-formed. Check tags, attributes, namespaces and character references.",line:parser.lineNumber) } }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { issue = .init(message:"External entities are disabled.",line:parser.lineNumber);parser.abortParsing();return nil }
    }
}
