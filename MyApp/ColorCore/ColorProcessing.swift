import Foundation

public struct ColorInputError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Explicit encoded sRGB, never a device-dependent NSColor. Constructed through validated input.
public struct SRGBA: Sendable, Equatable {
    public let r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) throws {
        guard [r,g,b,a].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ColorInputError("Channels must be finite and within their allowed range.") }
        self.r=r; self.g=g; self.b=b; self.a=a
    }
    public static let black = try! SRGBA(0,0,0)
    public static let white = try! SRGBA(1,1,1)
    public func over(_ backdrop: SRGBA) -> SRGBA {
        let alpha = a + backdrop.a * (1-a)
        guard alpha > 0 else { return try! SRGBA(0,0,0,0) }
        return try! SRGBA((r*a+backdrop.r*backdrop.a*(1-a))/alpha, (g*a+backdrop.g*backdrop.a*(1-a))/alpha, (b*a+backdrop.b*backdrop.a*(1-a))/alpha, alpha)
    }
    public var hsl: (h:Double,s:Double,l:Double) {
        let lo=min(r,g,b), hi=max(r,g,b), d=hi-lo, l=(hi+lo)/2
        guard d > 0 else { return (0,0,l) }
        var h: Double
        if hi == r { h=(g-b)/d } else if hi == g { h=(b-r)/d+2 } else { h=(r-g)/d+4 }
        h=(h*60+360).truncatingRemainder(dividingBy:360)
        return (h,min(1,max(0,d/(1-abs(2*l-1)))),l)
    }
    public static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double, _ alpha: Double = 1) throws -> Self {
        guard hue.isFinite, [saturation, lightness, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ColorInputError("Saturation, lightness and alpha must be within 0–100%.") }
        let h=(hue.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)/60
        let c=(1-abs(2*lightness-1))*saturation, x=c*(1-abs(h.truncatingRemainder(dividingBy:2)-1)), m=lightness-c/2
        let v: (Double,Double,Double)
        switch h {case ..<1:v=(c,x,0);case ..<2:v=(x,c,0);case ..<3:v=(0,c,x);case ..<4:v=(0,x,c);case ..<5:v=(x,0,c);default:v=(c,0,x)}
        return try SRGBA(min(1,max(0,v.0+m)),min(1,max(0,v.1+m)),min(1,max(0,v.2+m)),alpha)
    }
    public var hex: String {
        let bytes = [r,g,b] + (a == 1 ? [] : [a])
        return "#" + bytes.map { String(format:"%02X",Int(($0*255).rounded())) }.joined()
    }
    public func representations(precision:Int = 3) -> [(String,String)] {
        func f(_ v:Double)->String {
            let p=min(6,max(0,precision)), scale=pow(10.0,Double(min(6,max(0,precision))))
            let rounded=(v*scale).rounded()/scale
            var s=String(format:"%.*f",locale:Locale(identifier:"en_US_POSIX"),p,rounded == 0 ? 0 : rounded)
            if s.contains(".") { while s.last == "0" {s.removeLast()};if s.last == "." {s.removeLast()} }
            return s
        }
        let h=hsl, alpha=a == 1 ? "" : " / \(f(a))"
        return [("HEX",hex),("RGB","rgb(\(f(r*255)) \(f(g*255)) \(f(b*255))\(alpha))"),("HSL","hsl(\(f(h.h)) \(f(h.s*100))% \(f(h.l*100))%\(alpha))")]
    }
}

public enum ColorParser {
    public static func parse(_ source:String) throws -> SRGBA {
        guard source.utf16.count <= 4096 else {throw ColorInputError("Resource limit: color input exceeds 4096 characters.")}
        let s=source.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        if s == "transparent" {return try SRGBA(0,0,0,0)}
        let hex=s.hasPrefix("#") ? String(s.dropFirst()) : s
        if [3,4,6,8].contains(hex.count),hex.unicodeScalars.allSatisfy({("0123456789abcdef").unicodeScalars.contains($0)}) {
            let expanded=hex.count < 5 ? hex.map{String(repeating:String($0),count:2)}.joined() : hex
            let chars=Array(expanded);var channels:[Double]=[]
            for i in stride(from:0,to:chars.count,by:2) { channels.append(Double(Int(String(chars[i...i+1]),radix:16)!)/255) }
            return try SRGBA(channels[0],channels[1],channels[2],channels.count == 4 ? channels[3] : 1)
        }
        guard let open=s.firstIndex(of:"("),s.last == ")", !s[s.index(after:open)..<s.index(before:s.endIndex)].contains("(") else {throw ColorInputError("Use HEX, rgb(), hsl() or transparent. Other CSS color syntax is not supported.")}
        let name=String(s[..<open]), body=String(s[s.index(after:open)..<s.index(before:s.endIndex)])
        guard ["rgb","rgba","hsl","hsla"].contains(name) else {throw ColorInputError("Unsupported color syntax. Use sRGB HEX, RGB or HSL.")}
        var fields:[String];let legacy=body.contains(",")
        if legacy {
            guard !body.contains("/") else {throw ColorInputError("Do not mix comma and slash syntax.")}
            fields=body.components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
            guard fields.count == 3 || fields.count == 4 else {throw ColorInputError("Expected three channels and optional alpha.")}
        } else {
            let slash=body.components(separatedBy:"/")
            guard slash.count <= 2 else {throw ColorInputError("Only one alpha separator is allowed.")}
            fields=slash[0].split(whereSeparator:{$0.isWhitespace}).map(String.init)
            guard fields.count == 3 else {throw ColorInputError("Expected three color channels.")}
            if slash.count == 2 {fields.append(slash[1].trimmingCharacters(in:.whitespacesAndNewlines))}
        }
        func number(_ token:String) throws -> Double {
            guard token.range(of:#"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,options:.regularExpression) != nil,let v=Double(token),v.isFinite else {throw ColorInputError("Expected a finite decimal number (decimal point: '.').")}
            return v
        }
        func channel(_ token:String, scale:Double, percentOnly:Bool = false)throws->Double {
            let percent=token.hasSuffix("%")
            if percentOnly && !percent {throw ColorInputError("Saturation and lightness require percent units.")}
            let n=try number(percent ? String(token.dropLast()) : token)/(percent ? 100 : scale)
            guard (0...1).contains(n) else {throw ColorInputError("Channel outside its allowed range.")};return n
        }
        let a=fields.count == 4 ? try channel(fields[3],scale:1) : 1
        if name.hasPrefix("rgb") {
            if legacy && Set(fields.prefix(3).map{$0.hasSuffix("%")}).count != 1 {throw ColorInputError("Legacy RGB channels must use the same units.")}
            return try SRGBA(channel(fields[0],scale:255),channel(fields[1],scale:255),channel(fields[2],scale:255),a)
        }
        var hue=fields[0],factor=1.0
        for (suffix,f) in [("grad",0.9),("turn",360.0),("rad",180/Double.pi),("deg",1.0)] where hue.hasSuffix(suffix) {hue=String(hue.dropLast(suffix.count));factor=f;break}
        return try .hsl(number(hue)*factor,channel(fields[1],scale:100,percentOnly:true),channel(fields[2],scale:100,percentOnly:true),a)
    }
}

public struct ContrastResult: Sendable {
    public let foreground:SRGBA, background:SRGBA, ratio:Double
    public var checks:[(String,Bool)] {[("AA · regular text",ratio >= 4.5),("AA · large text",ratio >= 3),("AAA · regular text",ratio >= 7),("AAA · large text",ratio >= 4.5),("Non-text pair (advisory)",ratio >= 3)]}
}
public enum ContrastCalculator {
    public static func luminance(_ c:SRGBA)->Double {
        func linear(_ x:Double)->Double {x <= 0.04045 ? x/12.92 : pow((x+0.055)/1.055,2.4)}
        return 0.2126*linear(c.r)+0.7152*linear(c.g)+0.0722*linear(c.b)
    }
    public static func evaluate(foreground:SRGBA,background:SRGBA,backdrop:SRGBA = .white)throws->ContrastResult {
        guard backdrop.a == 1 else {throw ColorInputError("Backdrop must be opaque.")}
        let bg=background.over(backdrop),fg=foreground.over(bg),l1=luminance(fg),l2=luminance(bg)
        return ContrastResult(foreground:fg,background:bg,ratio:(max(l1,l2)+0.05)/(min(l1,l2)+0.05))
    }
}
