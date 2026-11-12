import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
public struct SVGResult:Sendable {
    public let source:String,percentURI:String,base64URI:String,notices:[String]
    public func output(base64:Bool,style:String)->String {
        let uri=base64 ? base64URI : percentURI
        switch style {case "Background":return "background-image: url(\"\(uri)\");";case "Mask":return "mask-image: url(\"\(uri)\");\n-webkit-mask-image: url(\"\(uri)\");\nbackground-color: currentColor;";default:return uri}
    }
}
public enum SVGDataURIProcessor {
    public static func process(_ input:String,decode:Bool = false)throws->SVGResult {
        guard input.utf16.count<=262144 else {throw ImageToolError(.resource,"Input exceeds 262144 UTF-16 units.")}
        try Task.checkCancellation()
        var source=input
        if decode {
            guard let comma=input.firstIndex(of:",") else {throw ImageToolError(.invalid,"Missing Data URI delimiter.")}
            let header=input[..<comma].lowercased(),body=String(input[input.index(after:comma)...])
            let data:Data
            if header == "data:image/svg+xml;base64" || header == "data:image/svg+xml;charset=utf-8;base64" {
                guard let d=Data(base64Encoded:body),d.base64EncodedString()==body else {throw ImageToolError(.invalid,"Use canonical, padded Base64.")};data=d
            } else if header == "data:image/svg+xml" || header == "data:image/svg+xml;charset=utf-8" {
                var bytes:[UInt8]=[];let raw=Array(body.utf8);var i=0
                while i<raw.count {if raw[i]==37 {guard i+2<raw.count,let n=UInt8(String(decoding:raw[i+1...i+2],as:UTF8.self),radix:16) else {throw ImageToolError(.invalid,"Invalid percent escape.")};bytes.append(n);i+=3}else{bytes.append(raw[i]);i+=1}}
                data=Data(bytes)
            } else {throw ImageToolError(.unsupported,"Expected an image/svg+xml Data URI.")}
            guard let s=String(data:data,encoding:.utf8) else {throw ImageToolError(.invalid,"SVG must be valid UTF-8.")};source=s
        }
        try rejectDeclarations(source)
        let delegate=SVGDelegate(),parser=XMLParser(data:Data(source.utf8))
        parser.shouldProcessNamespaces=true;parser.shouldResolveExternalEntities=false;parser.externalEntityResolvingPolicy = .never;parser.delegate=delegate
        guard parser.parse(),delegate.validRoot,delegate.failure == nil else {throw ImageToolError(.invalid,delegate.failure ?? "Expected well-formed SVG with xmlns=\"http://www.w3.org/2000/svg\".")}
        try Task.checkCancellation()
        let data=Data(source.utf8)
        let percent=data.map{b in ((65...90).contains(b)||(97...122).contains(b)||(48...57).contains(b)||[45,46,95,126].contains(b)) ? String(UnicodeScalar(b)) : String(format:"%%%02X",b)}.joined()
        return SVGResult(source:source,percentURI:"data:image/svg+xml,"+percent,base64URI:"data:image/svg+xml;base64,"+data.base64EncodedString(),notices:["Encoding is not sanitization. Scripts and URLs remain data; this tool never renders or executes them.","CSS masks use a single color; they do not reproduce original SVG colors."])
    }
    private static func rejectDeclarations(_ s:String)throws {
        // Skip literal CDATA/comments before testing declarations. Do not mistake displayed text for a DTD.
        var i=s.startIndex
        while i<s.endIndex {
            let tail=s[i...]
            if tail.hasPrefix("<!--") || tail.hasPrefix("<![CDATA[") {
                let end=tail.hasPrefix("<!--") ? "-->" : "]]>"
                guard let r=tail.range(of:end) else {throw ImageToolError(.invalid,"Unterminated XML comment or CDATA.")};i=r.upperBound
            } else if tail.hasPrefix("<!DOCTYPE") || tail.hasPrefix("<!ENTITY") {throw ImageToolError(.unsupported,"DTD and entity declarations are disabled.")}
            else {i=s.index(after:i)}
        }
    }
}
private final class SVGDelegate:NSObject,XMLParserDelegate {
    var depth=0,validRoot=false,failure:String?
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        depth+=1
        if depth==1 {validRoot=elementName=="svg" && namespaceURI=="http://www.w3.org/2000/svg";if !validRoot{failure="Root must be svg in http://www.w3.org/2000/svg. Add the namespace explicitly.";parser.abortParsing()}}
        if depth>128{failure="XML depth exceeds 128.";parser.abortParsing()}
        if elementName=="include" && namespaceURI=="http://www.w3.org/2001/XInclude" {failure="XML includes are not supported.";parser.abortParsing()}
        if Task.isCancelled{failure="Cancelled";parser.abortParsing()}
    }
    func parser(_ parser:XMLParser,didEndElement:String,namespaceURI:String?,qualifiedName:String?){depth-=1}
}
