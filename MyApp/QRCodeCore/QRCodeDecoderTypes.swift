import Foundation
import CoreGraphics

public enum QRDecodeBudget {
    public static let encodedBytes = 32 * 1024 * 1024
    public static let pixels: Int64 = 40_000_000
    public static let sourceSide: Int64 = 32_768
    public static let scanSide = 4096
    public static let results = 100
}
public struct QRDecodeIssue: Error, Sendable, Equatable {
    public enum Kind: Sendable { case unsupported, resource, loading, reader }
    public let kind: Kind
    public let message: String
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
}
public enum QRScanSurface: String, CaseIterable, Sendable { case white = "White", dark = "Dark" }
public struct QRDecodeSource: @unchecked Sendable, Identifiable {
    public let id: UUID
    public let image: CGImage
    public let originalWidth: Int
    public let originalHeight: Int
    public let format: String
    public let hasAlpha: Bool
    public init(image: CGImage, width: Int? = nil, height: Int? = nil, format: String = "Image", id: UUID = UUID()) {
        self.id = id; self.image = image; originalWidth = width ?? image.width; originalHeight = height ?? image.height; self.format = format
        hasAlpha = [.first,.last,.premultipliedFirst,.premultipliedLast,.alphaOnly].contains(image.alphaInfo)
    }
    public var dimensions: String { "\(originalWidth) × \(originalHeight) · \(format)" }
    public var scanDimensions: String { "Scanned at \(image.width) × \(image.height)" }
}
public struct QRDecodedItem: Identifiable, Sendable {
    public let id: Int
    /// Oriented prepared-image pixel coordinates; origin top-left. Never source EXIF coordinates.
    public let corners: [CGPoint]
    public let bytes: Data?
    public let text: String?
    public let interpretation: String
    public let contentType: Int
    public let hasECI: Bool
    public let sequenceIndex: Int
    public let sequenceCount: Int
    public let sequenceID: String
    public let version: String
    public let correction: String
    public let mirrored: Bool
    public let inverted: Bool
    public var readable: Bool { bytes != nil }
    public var bounds: CGRect {
        guard let first = corners.first else { return .zero }
        return corners.dropFirst().reduce(CGRect(origin:first,size:.zero)) { rect,point in
            CGRect(x:min(rect.minX,point.x),y:min(rect.minY,point.y),width:max(rect.maxX,point.x)-min(rect.minX,point.x),height:max(rect.maxY,point.y)-min(rect.minY,point.y))
        }
    }
    public var kind: String {
        guard readable else { return "Unreadable" }
        guard let text else { return "Binary" }
        if sequenceCount >= 0 { return "Sequence segment" }
        if contentType == 3 { return "GS1" }
        if contentType == 4 { return "ISO 15434" }
        if text.hasPrefix("WIFI:") { return "Wi-Fi" }
        if text.hasPrefix("BEGIN:VCARD") { return "Contact card" }
        if ["https://","http://"].contains(where:{ text.lowercased().hasPrefix($0) }) { return "URL" }
        for (prefix,name) in [("mailto:","Email"),("tel:","Phone"),("sms:","SMS")] where text.lowercased().hasPrefix(prefix) { return name }
        return "Text"
    }
}
public struct QRDecodeSnapshot: @unchecked Sendable {
    public let source: QRDecodeSource
    public let image: CGImage
    public let surface: QRScanSurface
    public let items: [QRDecodedItem]
    public let limited: Bool
}
public enum QRDecodePhase: Sendable { case empty, loading, scanning, ready, noCodes, failed, cancelled }
public enum QRDecodeOutput: String, CaseIterable, Sendable { case text = "Text", hex = "Hex", base64 = "Base64", bytes = "Bytes" }
public struct QRDecodedExport: Sendable {
    public let data: Data
    public let isText: Bool
    public let filename: String
    public init?(item: QRDecodedItem, text: Bool) {
        guard let bytes = item.bytes else { return nil }
        if text { guard let value = item.text else { return nil }; data = Data(value.utf8) } else { data = bytes }
        isText = text; filename = "qr-result-\(item.id+1)." + (text ? "txt" : "bin")
    }
}
