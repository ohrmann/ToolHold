import Foundation
import ImageIO
import CoreGraphics
import CoreImage

public enum ImagePipeline {
    public static let inputTypes:Set<String>=["public.png","public.jpeg","public.heic","public.heif","public.tiff","com.microsoft.bmp","com.compuserve.gif","org.webmproject.webp"]
    public static func load(_ data:Data)throws->RasterSource {
        try Task.checkCancellation()
        guard !data.isEmpty,data.count<=32*1024*1024 else {throw ImageToolError(.resource,"Choose an image up to 32 MiB.")}
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),let type=CGImageSourceGetType(source) as String?,inputTypes.contains(type) else {throw ImageToolError(.unsupported,"Choose PNG, JPEG, HEIC, TIFF, BMP, GIF or WebP supported by this OS.")}
        guard CGImageSourceGetStatus(source) == .statusComplete,let p=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],let w=p[kCGImagePropertyPixelWidth as String] as? Int,let h=p[kCGImagePropertyPixelHeight as String] as? Int,w>0,h>0,w<=32768,h<=32768,w<=40_000_000/h else {throw ImageToolError(.resource,"Incomplete image or dimensions exceed 40 MP / 32768 px.")}
        let n=CGImageSourceGetCount(source)
        guard n<=100 else {throw ImageToolError(.resource,"Metadata inspection supports up to 100 frames.")}
        guard let thumb=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {throw ImageToolError(.invalid,"Image could not be decoded.")}
        var notices=["Output uses 8-bit sRGB. Descriptive metadata is removed when re-encoding."]
        if p[kCGImagePropertyProfileName as String] == nil {notices.append("Untagged color: sRGB assumed.")} else {notices.append("Source profile: \(p[kCGImagePropertyProfileName as String]!) → sRGB; out-of-gamut colors may change.")}
        if (p[kCGImagePropertyDepth as String] as? Int ?? 8)>8 {notices.append("Source precision will be reduced to 8 bits per channel.")}
        if n>1 {notices.append("Multi-frame source: inspect only. Conversion never silently takes the first frame.")}
        return RasterSource(id:UUID(),data:data,type:type,width:w,height:h,orientation:p[kCGImagePropertyOrientation as String] as? Int ?? 1,frames:n,hasAlpha:p[kCGImagePropertyHasAlpha as String] as? Bool ?? false,thumbnail:thumb,metadata:try metadata(source),notices:notices)
    }
    public static func metadata(_ source:CGImageSource)throws->[MetadataRow] {
        var rows:[MetadataRow]=[],bytes=0,binaryBytes=0
        func visit(_ value:Any,_ path:String,_ depth:Int)throws {
            guard depth<=32,rows.count<10000,bytes<2*1024*1024 else {throw ImageToolError(.resource,"Metadata exceeds the inspection budget.")}
            if let dict=value as? [String:Any] {for key in dict.keys.sorted(){try visit(dict[key]!,path+"/"+key,depth+1)}}
            else if let array=value as? [Any] {for(i,v) in array.enumerated(){try visit(v,path+"[\(i)]",depth+1)}}
            else {
                let text:String,type:String
                if let d=value as? Data {binaryBytes+=d.count;guard binaryBytes<=32*1024*1024 else{throw ImageToolError(.resource,"Metadata blobs exceed 32 MiB.")};text="Binary data · \(d.count) bytes (Copy as Base64)";type="Data"}
                else if let n=value as? NSNumber {text=n.stringValue;type=String(cString:n.objCType)}
                else {text=String(describing:value);type="String"}
                bytes += text.utf8.count + path.utf8.count
                guard bytes<=2*1024*1024 else {throw ImageToolError(.resource,"Metadata text exceeds 2 MiB.")}
                rows.append(MetadataRow(id:rows.count,path:path,value:text,type:type,isGPS:path.lowercased().contains("gps") || path.lowercased().contains("location"),binary:value as? Data))
            }
        }
        if let all=CGImageSourceCopyProperties(source,nil){try visit(all,"Container",0)}
        for i in 0..<min(100,CGImageSourceGetCount(source)) {
            try Task.checkCancellation()
            if let props=CGImageSourceCopyPropertiesAtIndex(source,i,nil){try visit(props,"Frame \(i+1)",0)}
            if let meta=CGImageSourceCopyMetadataAtIndex(source,i,nil),let tags=CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] {
                for tag in tags {if let name=CGImageMetadataTagCopyName(tag),let v=CGImageMetadataTagCopyValue(tag){let prefix=CGImageMetadataTagCopyPrefix(tag) as String? ?? "";try visit(v,"Frame \(i+1)/XMP/\(prefix):\(name)",0)}}
            }
        }
        return rows
    }
    public static func fullPreview(_ data:Data)throws->CGImage {
        try Task.checkCancellation()
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),let p=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],let w=p[kCGImagePropertyPixelWidth as String] as? Int,let h=p[kCGImagePropertyPixelHeight as String] as? Int,w>0,h>0,w<=32768,h<=32768,w<=40_000_000/h else{throw ImageToolError(.resource,"Full preview exceeds the pixel budget.")}
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max(w,h),kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else{throw ImageToolError(.invalid,"Full preview could not be decoded.")}
        try Task.checkCancellation();return image
    }
    public static func transform(_ source:RasterSource,options:ImageOptions)throws->ImageArtifact {
        try Task.checkCancellation()
        guard source.frames==1 else {throw ImageToolError(.unsupported,"Animated and multi-page images are inspection-only.")}
        guard RasterFormat.available.contains(options.format) else {throw ImageToolError(.unsupported,"This encoder is unavailable on this OS.")}
        guard options.quality.isFinite,(0...1).contains(options.quality),options.matte.count==3,options.matte.allSatisfy({$0.isFinite && (0...1).contains($0)}) else {throw ImageToolError(.invalid,"Invalid quality or matte channels.")}
        guard let input=CGImageSourceCreateWithData(source.data as CFData,nil) else {throw ImageToolError(.invalid,"Could not open source.")}
        // Do not silently discard an HDR gain map / depth image into a misleading SDR conversion.
        for kind in [kCGImageAuxiliaryDataTypeHDRGainMap,kCGImageAuxiliaryDataTypeDepth,kCGImageAuxiliaryDataTypeDisparity] {
            if CGImageSourceCopyAuxiliaryDataInfoAtIndex(input,0,kind) != nil {throw ImageToolError(.unsupported,"Auxiliary HDR/depth data requires a dedicated conversion policy.")}
        }
        if #available(macOS 15,iOS 18,*) {
            if CGImageSourceCopyAuxiliaryDataInfoAtIndex(input,0,kCGImageAuxiliaryDataTypeISOGainMap) != nil {throw ImageToolError(.unsupported,"ISO HDR gain maps require a dedicated conversion policy.")}
        }
        // Inspect source color space before thumbnail APIs can tone-map an HDR source.
        do {
            guard let headerImage=CGImageSourceCreateImageAtIndex(input,0,[kCGImageSourceShouldCache:false] as CFDictionary),!headerImage.bitmapInfo.contains(.floatComponents),headerImage.colorSpace?.isHDR() != true,headerImage.colorSpace.map({CGColorSpaceUsesExtendedRange($0)}) != true else{throw ImageToolError(.unsupported,"HDR / floating-point sources are not converted to SDR implicitly.")}
        }
        let (w,h)=try options.dimensions(source)
        let scale=min(1,max(Double(w)/Double(source.orientedWidth),Double(h)/Double(source.orientedHeight)))
        let downsample=options.mode != .original && scale<0.75
        let decodedPixels=downsample ? Int64(ceil(Double(source.width)*scale))*Int64(ceil(Double(source.height)*scale)):Int64(source.width)*Int64(source.height)
        // Allow room for decoder internals even when an explicit resize can downsample before Core Image.
        let estimate=Int64(source.width)*Int64(source.height)*(downsample ? 4:8)+decodedPixels*(downsample ? 8:0)+Int64(w)*Int64(h)*8+Int64(source.data.count)
        guard estimate<=384*1024*1024 else {throw ImageToolError(.resource,"Estimated image buffers exceed 384 MiB. Choose a smaller output or source.")}
        let decoded:CGImage?
        if downsample {
            decoded=CGImageSourceCreateThumbnailAtIndex(input,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:Int(ceil(Double(max(source.width,source.height))*scale)),kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
        } else {decoded=CGImageSourceCreateImageAtIndex(input,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary)}
        guard let decoded,!decoded.bitmapInfo.contains(.floatComponents),decoded.colorSpace?.isHDR() != true,decoded.colorSpace.map({CGColorSpaceUsesExtendedRange($0)}) != true else {throw ImageToolError(.unsupported,"Floating-point / unsupported raster.")}
        let cs=CGColorSpace(name:CGColorSpace.sRGB)!
        let oriented=downsample ? CIImage(cgImage:decoded):CIImage(cgImage:decoded).oriented(forExifOrientation:Int32(source.orientation))
        let extent=oriented.extent
        let normalized=oriented.transformed(by:CGAffineTransform(translationX:-extent.minX,y:-extent.minY))
        let sx=Double(w)/extent.width,sy=Double(h)/extent.height
        let scaled:CIImage
        if options.mode == .fill {
            let scale=max(sx,sy)
            scaled=normalized.transformed(by:CGAffineTransform(scaleX:scale,y:scale)).transformed(by:CGAffineTransform(translationX:-(extent.width*scale-Double(w))/2,y:-(extent.height*scale-Double(h))/2))
        } else {scaled=normalized.transformed(by:CGAffineTransform(scaleX:sx,y:sy))}
        let render:CIImage
        if options.format.preservesAlpha {render=scaled}
        else {render=scaled.composited(over:CIImage(color:CIColor(red:options.matte[0],green:options.matte[1],blue:options.matte[2],alpha:1)))}
        let context=CIContext(options:[.workingColorSpace:cs,.outputColorSpace:cs,.cacheIntermediates:false])
        guard let pixels=context.createCGImage(render,from:CGRect(x:0,y:0,width:w,height:h),format:.RGBA8,colorSpace:cs) else {throw ImageToolError(.invalid,"Could not transform image.")}
        try Task.checkCancellation()
        var quality=options.quality
        var best=try encode(pixels,format:options.format,quality:quality)
        if let target=options.targetBytes {
            guard target>0,options.format.lossy else {throw ImageToolError(.invalid,"Target file size requires JPEG or HEIC and a positive byte count.")}
            var smallest=best,smallestQuality=quality,passing:Data?=best.count<=target ? best : nil,passingQuality=quality
            // Fixed grid: do not assume the codec's byte count is monotonic in quality.
            for i in 1...11 {
                try Task.checkCancellation();let q=options.quality * Double(11-i)/11
                let candidate=try encode(pixels,format:options.format,quality:q)
                if candidate.count<smallest.count {smallest=candidate;smallestQuality=q}
                if candidate.count<=target && (passing == nil || q>passingQuality) {passing=candidate;passingQuality=q}
            }
            best=passing ?? smallest;quality=passing == nil ? smallestQuality : passingQuality
        }
        try Task.checkCancellation()
        var changes=["Re-encoded to 8-bit sRGB; recognized descriptive metadata removed.","Orientation normalized once; original file unchanged."]
        if source.hasAlpha && !options.format.preservesAlpha {changes.append("Transparency flattened onto the selected matte.")}
        if options.mode == .fill {changes.append("Center crop applied.")}
        return try artifact(best,format:options.format,quality:quality,target:options.targetBytes,changes:changes,expected:(w,h))
    }
    private final class Sink {var data=Data();var exceeded=false}
    public static func encode(_ image:CGImage,format:RasterFormat,quality:Double)throws->Data {
        let sink=Sink()
        var callbacks=CGDataConsumerCallbacks(putBytes:{ ptr,buffer,count in
            guard let ptr else{return 0};let sink=Unmanaged<Sink>.fromOpaque(ptr).takeUnretainedValue()
            guard count<=64*1024*1024-sink.data.count else {sink.exceeded=true;return 0}
            sink.data.append(buffer.assumingMemoryBound(to:UInt8.self),count:count);return count
        },releaseConsumer:nil)
        guard let consumer=CGDataConsumer(info:Unmanaged.passUnretained(sink).toOpaque(),cbks:&callbacks),let dest=CGImageDestinationCreateWithDataConsumer(consumer,format.uti as CFString,1,nil) else {throw ImageToolError(.unsupported,"Encoder unavailable.")}
        CGImageDestinationAddImage(dest,image,[kCGImageDestinationLossyCompressionQuality:quality,kCGImagePropertyOrientation:1] as CFDictionary)
        let ok=CGImageDestinationFinalize(dest)
        guard ok,!sink.exceeded else {throw ImageToolError(sink.exceeded ? .resource : .invalid,"Encoding failed or exceeded 64 MiB.")}
        return sink.data
    }
    public static func artifact(_ data:Data,format:RasterFormat,quality:Double,target:Int?,changes:[String],expected:(Int,Int))throws->ImageArtifact {
        guard let output=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetType(output) as String? == format.uti,
              let properties=CGImageSourceCopyPropertiesAtIndex(output,0,nil) as? [String:Any],properties[kCGImagePropertyPixelWidth as String] as? Int == expected.0,properties[kCGImagePropertyPixelHeight as String] as? Int == expected.1,
              let preview=CGImageSourceCreateThumbnailAtIndex(output,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1600] as CFDictionary) else {throw ImageToolError(.invalid,"Output verification failed.")}
        return ImageArtifact(data:data,format:format,width:expected.0,height:expected.1,preview:preview,metadata:try metadata(output),changes:changes,quality:quality,targetReached:target.map{data.count<=$0} ?? true)
    }
    /// Selective metadata-only path. Never falls back to a lossy re-encode.
    public static func removeGPS(_ source:RasterSource)throws->ImageArtifact {
        guard source.frames==1,["public.jpeg","public.tiff"].contains(source.type),let format=RasterFormat.allCases.first(where:{$0.uti==source.type}) else {throw ImageToolError(.unsupported,"GPS-only copying is verified for single-frame JPEG and TIFF. PNG ImageIO can retain EXIF GPS tags; Create a clean re-encoded copy instead.")}
        try Task.checkCancellation()
        let data=NSMutableData()
        guard let input=CGImageSourceCreateWithData(source.data as CFData,nil),let dest=CGImageDestinationCreateWithData(data,source.type as CFString,1,nil) else {throw ImageToolError(.invalid,"Could not open metadata copy.")}
        let cleanMetadata=CGImageSourceCopyMetadataAtIndex(input,0,nil).flatMap{CGImageMetadataCreateMutableCopy($0)} ?? CGImageMetadataCreateMutable()
        var paths:[String]=[]
        CGImageMetadataEnumerateTagsUsingBlock(cleanMetadata,nil,[kCGImageMetadataEnumerateRecursively:true] as CFDictionary){path,_ in
            let name=(path as String).lowercased()
            if name.contains("gps") || name.contains("location"){paths.append(path as String)}
            return true
        }
        for path in paths {CGImageMetadataRemoveTagWithPath(cleanMetadata,nil,path as CFString)}
        var error:Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest,input,[kCGImageDestinationMetadata:cleanMetadata,kCGImageDestinationMergeMetadata:false,kCGImageMetadataShouldExcludeGPS:true] as CFDictionary,&error) else {throw ImageToolError(.unsupported,"This codec could not copy metadata without re-encoding.")}
        guard data.length<=64*1024*1024,let out=CGImageSourceCreateWithData(data,nil) else {throw ImageToolError(.resource,"Metadata copy exceeded its budget.")}
        let rows=try metadata(out)
        guard !rows.contains(where:{$0.isGPS}) else {throw ImageToolError(.unsupported,"GPS tags remain after copying. Use Create clean copy; no successful artifact was published.")}
        let p=CGImageSourceCopyPropertiesAtIndex(out,0,nil) as? [String:Any]
        guard (p?[kCGImagePropertyOrientation as String] as? Int ?? 1)==source.orientation else {throw ImageToolError(.invalid,"Orientation verification failed.")}
        return try artifact(data as Data,format:format,quality:1,target:nil,changes:["Recognized GPS tags removed without raster re-encoding.","Exposed non-location metadata is retained where supported; proprietary metadata is not guaranteed. Information inside pixels remains."],expected:(source.width,source.height))
    }
}
