import Foundation
import Observation
import CoreGraphics
private struct RasterUIPreferences:Codable {
    var format:RasterFormat
    var quality:Double
    var lockAspect:Bool
}
/// Serial actor shared by the three image workspaces: at most one synchronous codec call at a time.
public actor RasterWorker {
    public static let shared=RasterWorker()
    public func preview(data:Data)throws->CGImage {try ImagePipeline.fullPreview(data)}
    public func load(data:Data)throws->RasterSource {try ImagePipeline.load(data)}
    public func load(url:URL)throws->RasterSource {try ImagePipeline.load(LocalImageFile.read(url))}
    public func transform(_ source:RasterSource,_ options:ImageOptions,gps:Bool)throws->ImageArtifact {try Task.checkCancellation();return try gps ? ImagePipeline.removeGPS(source) : ImagePipeline.transform(source,options:options)}
}
@MainActor @Observable public final class ImageWorkspace {
    public private(set) var source:RasterSource?
    public private(set) var result:ImageArtifact?
    public private(set) var busy=false
    public private(set) var status="Ready"
    public private(set) var revision=0
    public var options=ImageOptions(){didSet{if options != oldValue && !installingSource {invalidate();savePreferences()}}}
    public var showAfter=true
    public var revealGPS=false
    public var search=""
    public var keepSourceFormat=true{didSet{if oldValue != keepSourceFormat{invalidate()}}}
    @ObservationIgnored private var task:Task<Void,Never>?
    @ObservationIgnored private var installingSource=false
    private let defaults:UserDefaults
    private let preferenceKey:String
    public init(resize:Bool = false,defaults:UserDefaults = .standard){
        self.defaults=defaults;preferenceKey=resize ? "raster.resize.options":"raster.convert.options"
        if let data=defaults.data(forKey:preferenceKey),let p=try? JSONDecoder().decode(RasterUIPreferences.self,from:data){options.format=p.format;options.quality=p.quality.isFinite ? min(1,max(0,p.quality)):0.9;options.lockAspect=p.lockAspect}
        if resize{options.mode = .dimensions}
    }
    private func savePreferences(){if let data=try? JSONEncoder().encode(RasterUIPreferences(format:options.format,quality:options.quality,lockAspect:options.lockAspect)){defaults.set(data,forKey:preferenceKey)}}
    private func invalidate(){revision+=1;task?.cancel();task=nil;result=nil;busy=false;status=source == nil ? "Ready" : "Not processed"}
    public func clear(){invalidate();source=nil;status="Ready";search="";revealGPS=false}
    public func cancel(){revision+=1;task?.cancel();task=nil;busy=false;status="Cancelled"}
    public func load(data:Data){loadOperation{try await RasterWorker.shared.load(data:data)}}
    public func load(url:URL){loadOperation{try await RasterWorker.shared.load(url:url)}}
    private func loadOperation(_ operation:@escaping @Sendable ()async throws->RasterSource){
        revision+=1;let rev=revision;task?.cancel();busy=true;status="Opening…"
        task=Task {do{let new=try await operation();try Task.checkCancellation();guard revision==rev else{return};installingSource=true;source=new;result=nil;showAfter=false
                options.width=new.orientedWidth;options.height=new.orientedHeight
                if options.mode != .original && keepSourceFormat,let format=RasterFormat.available.first(where:{$0.uti==new.type}) {options.format=format}
                installingSource=false;busy=false;status="Ready"}catch{guard revision==rev else{return};busy=false;status=error is CancellationError ? "Cancelled" : (error as? LocalizedError)?.errorDescription ?? "Could not open the image."}}
    }
    public func run(gps:Bool = false){
        guard let source else{return};revision+=1;let rev=revision;task?.cancel();busy=true;status="Processing…";let options=options
        task=Task{do{let artifact=try await RasterWorker.shared.transform(source,options,gps:gps);try Task.checkCancellation();guard revision==rev else{return};result=artifact;showAfter=true;busy=false;status=artifact.targetReached ? "Completed" : "Target not reached — smallest result available"}catch{guard revision==rev else{return};busy=false;status=error is CancellationError ? "Cancelled" : (error as? LocalizedError)?.errorDescription ?? "Processing failed."}}
    }
}
@MainActor @Observable public final class SVGWorkspace {
    public var input=""{didSet{if !input.utf16.elementsEqual(oldValue.utf16){revision+=1;task?.cancel();result=nil;busy=false;status="Not processed"}}}
    public var base64=false
    public var style="Data URI"
    public private(set) var result:SVGResult?
    public private(set) var status="Ready"
    public private(set) var busy=false
    private var revision=0
    @ObservationIgnored private var task:Task<Void,Never>?
    public init(){}
    public private(set) var decoded=false
    public var output:String{guard let result else{return ""};return decoded ? result.source:result.output(base64:base64,style:style)}
    public func run(decode:Bool = false){revision+=1;let rev=revision,source=input;task?.cancel();busy=true;status="Processing…";task=Task {let worker=Task.detached{try SVGDataURIProcessor.process(source,decode:decode)};do{let value=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard rev==revision,!Task.isCancelled else{return};result=value;decoded=decode;busy=false;status=decode ? "Decoded SVG":"Completed"}catch{guard rev==revision else{return};busy=false;status=(error as? LocalizedError)?.errorDescription ?? "Cancelled"}}}
    public func cancel(){revision+=1;task?.cancel();busy=false;status="Cancelled"}
}
