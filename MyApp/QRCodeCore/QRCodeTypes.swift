import Foundation
import CoreGraphics

public enum QRCorrection: String, CaseIterable, Codable, Sendable { case l = "L", m = "M", q = "Q", h = "H" }
public enum QRModuleStyle: String, CaseIterable, Codable, Sendable { case square = "Square", rounded = "Rounded", dots = "Dots" }
public enum QRExportFormat: String, CaseIterable, Codable, Sendable { case png = "PNG", svg = "SVG" }
public enum QRSurface: String, CaseIterable, Codable, Sendable { case white = "White", dark = "Dark", custom = "Custom" }
public struct QRColor: Codable, Equatable, Sendable {
    public var r: Double; public var g: Double; public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public static let black = Self(0,0,0), white = Self(1,1,1)
    public var valid: Bool { [r,g,b].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    public func cg(_ alpha: Double = 1) -> CGColor { CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r,g,b,alpha])! }
    public var hex: String { String(format: "#%02X%02X%02X", Int((r*255).rounded()), Int((g*255).rounded()), Int((b*255).rounded())) }
    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.utf8.count == 6, s.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }), let n = UInt32(s, radix: 16) else { return nil }
        self.init(Double(n >> 16)/255, Double((n >> 8)&255)/255, Double(n&255)/255)
    }
}
public struct QRPreferences: Codable, Equatable, Sendable {
    public var correction: QRCorrection = .m
    public var style: QRModuleStyle = .square
    public var rounding: Double = 0.25
    public var foreground: QRColor = .black
    public var background: QRColor = .white
    public var opacity: Double = 1
    public var logoBackground: QRColor = .white
    public var logoBackgroundOpacity: Double = 1
    public var logoSize: Double = 0.15
    public var logoPadding: Int = 1
    public var exportSize: Int = 1024
    public var format: QRExportFormat = .png
    public var surface: QRSurface = .white
    public var customSurface: QRColor = .white
    public var appearanceExpanded = true
    public var logoExpanded = false
    public var exportExpanded = false
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case correction,style,rounding,foreground,background,opacity,logoBackground,logoBackgroundOpacity,logoSize,logoPadding,exportSize,format,surface,customSurface,appearanceExpanded,logoExpanded,exportExpanded
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        correction = try c.decode(QRCorrection.self,forKey:.correction)
        style = try c.decode(QRModuleStyle.self,forKey:.style)
        rounding = try c.decode(Double.self,forKey:.rounding)
        foreground = try c.decode(QRColor.self,forKey:.foreground)
        background = try c.decode(QRColor.self,forKey:.background)
        opacity = try c.decode(Double.self,forKey:.opacity)
        logoBackground = try c.decode(QRColor.self,forKey:.logoBackground)
        // Older v1 preferences have no logo opacity; preserve all their settings.
        logoBackgroundOpacity = try c.decodeIfPresent(Double.self,forKey:.logoBackgroundOpacity) ?? 1
        logoSize = try c.decode(Double.self,forKey:.logoSize)
        logoPadding = try c.decode(Int.self,forKey:.logoPadding)
        exportSize = try c.decode(Int.self,forKey:.exportSize)
        format = try c.decode(QRExportFormat.self,forKey:.format)
        surface = try c.decode(QRSurface.self,forKey:.surface)
        customSurface = try c.decode(QRColor.self,forKey:.customSurface)
        appearanceExpanded = try c.decode(Bool.self,forKey:.appearanceExpanded)
        logoExpanded = try c.decode(Bool.self,forKey:.logoExpanded)
        exportExpanded = try c.decode(Bool.self,forKey:.exportExpanded)
    }
    public var valid: Bool {
        foreground.valid && background.valid && logoBackground.valid && customSurface.valid &&
        rounding.isFinite && (0...0.5).contains(rounding) && opacity.isFinite && (0...1).contains(opacity) &&
        logoBackgroundOpacity.isFinite && (0...1).contains(logoBackgroundOpacity) &&
        logoSize.isFinite && (0.1...0.2).contains(logoSize) && (1...2).contains(logoPadding) && [512,1024,2048,4096].contains(exportSize)
    }
    public var surfaceColor: QRColor { surface == .white ? .white : surface == .dark ? QRColor(0.08,0.08,0.08) : customSurface }
    public func correction(hasLogo: Bool) -> QRCorrection { hasLogo ? .h : correction }
    public var design: Self { var p = self; p.appearanceExpanded = true; p.logoExpanded = false; p.exportExpanded = false; p.format = .png; return p }
    public var contrastWarning: Bool {
        func luminance(_ c: QRColor) -> Double {
            func channel(_ x: Double) -> Double { x <= 0.04045 ? x/12.92 : pow((x+0.055)/1.055,2.4) }
            return 0.2126*channel(c.r)+0.7152*channel(c.g)+0.0722*channel(c.b)
        }
        let s = surfaceColor
        let bg = QRColor(background.r*opacity+s.r*(1-opacity),background.g*opacity+s.g*(1-opacity),background.b*opacity+s.b*(1-opacity))
        let a = luminance(foreground), b = luminance(bg)
        return a >= b || (b+0.05)/(a+0.05) < 4.5 // Advisory heuristic, not a QR standard threshold.
    }
}
public struct QRIssue: Error, Equatable, Sendable {
    public enum Kind: Sendable { case content, resource, generation, logo, rendering }
    public let kind: Kind; public let message: String
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
}
public struct QRMatrix: Sendable {
    public let size: Int
    public let dark: [Bool]
    public let functional: [Bool]
    public let payload: Data
    public let correction: QRCorrection
    public var version: Int { (size-17)/4 }
    public func pixelSide(target: Int) -> Int { let total = size+8; return total * max(1,(target+total-1)/total) }
}
public struct QRLogo: @unchecked Sendable {
    public let id: UUID
    public let image: CGImage
    public let png: Data
    public init(image: CGImage, png: Data) { self.id = UUID(); self.image = image; self.png = png }
}
public enum QRVerification: Equatable, Sendable {
    case readable(conditional: Bool), unavailable, mismatch
    public var passed: Bool { if case .readable = self { true } else { false } }
    public var message: String {
        switch self {
        case .readable(let conditional): conditional ? "Readable on selected surface" : "Readable · local check"
        case .unavailable: "Could not verify — try Square, stronger contrast, a smaller logo or a larger image."
        case .mismatch: "Content mismatch — the rendered code did not match the original QR."
        }
    }
}
public struct QRReference: Sendable { let codewords: Data?; let text: Data? }
public struct QRArtifact: @unchecked Sendable {
    public let matrix: QRMatrix
    public let preferences: QRPreferences
    public let logo: QRLogo?
    public let reference: QRReference
    public let image: CGImage
    public let verification: QRVerification
    public let verifiedSide: Int
    public let geometry: QRGeometry
    public var logoMoved: Bool { geometry.logoMoved }
    public var logoReduced: Bool { geometry.logoReduced }
    public var logoWidthFraction: Double? { geometry.plate.map { $0.width/Double(matrix.size) } }
    public var enlargesLogo: Bool {
        guard let logo, let rect = geometry.logoRect(logo.image) else { return false }
        return rect.width * CGFloat(side) / CGFloat(matrix.size+8) > CGFloat(logo.image.width)
    }
    public var side: Int { matrix.pixelSide(target: preferences.exportSize) }
}
public struct QRExport: Sendable {
    public let data: Data
    public let format: QRExportFormat
    public let side: Int
    public var filename: String { format == .png ? "qr-code.png" : "qr-code.svg" }
}
