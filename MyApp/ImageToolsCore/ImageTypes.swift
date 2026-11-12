import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ImageToolError: Error, LocalizedError, Sendable {
    public enum Kind: String, Sendable {case invalid="Invalid input", unsupported="Unsupported", resource="Resource limit", io="File error"}
    public let kind:Kind, message:String
    public init(_ kind:Kind = .invalid,_ message:String){self.kind=kind;self.message=message}
    public var errorDescription:String? {"\(kind.rawValue): \(message)"}
}
public enum RasterFormat:String,CaseIterable,Sendable,Identifiable,Codable {
    case png,jpeg,heic,tiff,bmp
    public var id:String {rawValue}
    public var uti:String {switch self {case .png:"public.png";case .jpeg:"public.jpeg";case .heic:"public.heic";case .tiff:"public.tiff";case .bmp:"com.microsoft.bmp"}}
    public var lossy:Bool {self == .jpeg || self == .heic}
    public var preservesAlpha:Bool {self == .png || self == .tiff}
    public var fileExtension:String {self == .jpeg ? "jpg" : rawValue}
    public static var available:[Self] {let supported=CGImageDestinationCopyTypeIdentifiers() as! [String];return allCases.filter{supported.contains($0.uti)}}
}
public struct MetadataRow:Identifiable,Sendable,Equatable {
    public let id:Int,path:String,value:String,type:String,isGPS:Bool
    public let binary:Data?
    public var copyValue:String{binary?.base64EncodedString() ?? value}
}
/// CGImage is immutable. Source data and metadata are value snapshots, never mutated across jobs.
public struct RasterSource: @unchecked Sendable {
    public let id:UUID,data:Data,type:String,width:Int,height:Int,orientation:Int,frames:Int,hasAlpha:Bool,thumbnail:CGImage,metadata:[MetadataRow],notices:[String]
    public var orientedWidth:Int {(5...8).contains(orientation) ? height : width}
    public var orientedHeight:Int {(5...8).contains(orientation) ? width : height}
}
public enum ResizeMode:String,CaseIterable,Sendable,Codable {case original="Original",dimensions="Dimensions",percentage="Percentage",fit="Fit within box",fill="Fill box (center crop)"}
public struct ImageOptions:Sendable,Equatable,Codable {
    public var format:RasterFormat = .png, mode:ResizeMode = .original
    public var width=1024,height=1024,percent=50.0,quality=0.9,lockAspect=true,allowUpscale=false,widthIsAuthority=true
    public var matte:[Double]=[1,1,1]
    public var targetBytes:Int?=nil
    public init(){}
    public func dimensions(_ source:RasterSource)throws->(Int,Int) {
        if [.dimensions,.fit,.fill].contains(mode) && (width<=0 || height<=0){throw ImageToolError(.invalid,"Width and height must be positive pixel counts.")}
        let w=Double(source.orientedWidth),h=Double(source.orientedHeight)
        var x=w,y=h
        switch mode {
        case .original:break
        case .percentage:
            guard percent.isFinite,percent > 0 else {throw ImageToolError(.invalid,"Percentage must be positive.")}
            let scale=allowUpscale ? percent/100 : min(1,percent/100);x=w*scale;y=h*scale
        case .dimensions:
            x=Double(width);y=Double(height)
            if lockAspect {if widthIsAuthority {y=x*h/w} else {x=y*w/h}}
            if !allowUpscale {let scale=min(1,w/x,h/y);x *= scale;y *= scale}
        case .fit:
            let scale=min(Double(width)/w,Double(height)/h,allowUpscale ? Double.greatestFiniteMagnitude : 1);x=floor(w*scale);y=floor(h*scale)
        case .fill:
            x=Double(width);y=Double(height)
            if !allowUpscale && (x>w || y>h) {throw ImageToolError(.invalid,"Fill would upscale the source. Enable upscaling or choose a smaller box.")}
        }
        guard x.isFinite,y.isFinite,x>0,y>0,x<=32768,y<=32768,x*y<=40_000_000 else {throw ImageToolError(.resource,"Output must be positive, at most 32768 px per side and 40 megapixels.")}
        return (max(1,Int(x.rounded())),max(1,Int(y.rounded())))
    }
}
public struct ImageArtifact:@unchecked Sendable {
    public let data:Data,format:RasterFormat,width:Int,height:Int,preview:CGImage,metadata:[MetadataRow],changes:[String],quality:Double,targetReached:Bool
}
