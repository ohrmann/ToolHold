import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import ImageToolsCore
@Test func svgRoundTrip() throws {
 let source="<svg xmlns=\"http://www.w3.org/2000/svg\"><!-- <!DOCTYPE not real> --><text>é 🐱 # %</text></svg>\r\n"
 let result=try SVGDataURIProcessor.process(source)
 #expect(try SVGDataURIProcessor.process(result.percentURI,decode:true).source == source)
 #expect(try SVGDataURIProcessor.process(result.base64URI,decode:true).source == source)
 for input in ["<svg/>","<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><svg xmlns='http://www.w3.org/2000/svg'>&x;</svg>"] {#expect(throws:ImageToolError.self){try SVGDataURIProcessor.process(input)}}
}
@Test func rasterOutputsAndOrientation() throws {
 let c=CGContext(data:nil,width:32,height:24,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.setFillColor(CGColor(red:0.6,green:0.2,blue:0.1,alpha:0.5));c.fill(CGRect(x:0,y:0,width:32,height:24))
 let input=try ImagePipeline.load(ImagePipeline.encode(c.makeImage()!,format:.png,quality:1))
 for format in RasterFormat.available {var o=ImageOptions();o.format=format;let result=try ImagePipeline.transform(input,options:o);#expect(result.width==32);#expect(result.height==24);#expect(result.data.count>0)}
 var o=ImageOptions();o.mode = .fit;o.width=17;o.height=17
 #expect(try o.dimensions(input).0 == 17);#expect(try o.dimensions(input).1 == 12)
}

private func fixture(width:Int=40,height:Int=24,orientation:Int=1,format:RasterFormat = .png,gps:Bool=false) throws -> Data {
 let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.setFillColor(CGColor(red:0.8,green:0.2,blue:0.1,alpha:1));c.fill(CGRect(x:0,y:0,width:width/2,height:height))
 c.setFillColor(CGColor(red:0.1,green:0.8,blue:0.2,alpha:0.5));c.fill(CGRect(x:width/2,y:0,width:width-width/2,height:height))
 let data=NSMutableData(),dest=CGImageDestinationCreateWithData(data,format.uti as CFString,1,nil)!
 var properties:[CFString:Any]=[kCGImagePropertyOrientation:orientation]
 if gps{properties[kCGImagePropertyGPSDictionary]=[kCGImagePropertyGPSLatitude:50.1,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:14.4,kCGImagePropertyGPSLongitudeRef:"E"];properties[kCGImagePropertyExifDictionary]=[kCGImagePropertyExifUserComment:"synthetic private comment"]}
 CGImageDestinationAddImage(dest,c.makeImage()!,properties as CFDictionary)
 #expect(CGImageDestinationFinalize(dest));return data as Data
}
@Test func allOrientationsAndMetadata() throws {
 for orientation in 1...8 {
    let source=try ImagePipeline.load(fixture(orientation:orientation,format:.tiff,gps:true))
    let result=try ImagePipeline.transform(source,options:ImageOptions())
    #expect(result.width == (orientation>=5 ? 24:40));#expect(result.height == (orientation>=5 ? 40:24))
    #expect(!result.metadata.contains{$0.isGPS || $0.value.contains("synthetic private comment")})
    let reopened=try ImagePipeline.load(result.data);#expect(reopened.orientation==1)
 }
 let png=try ImagePipeline.load(fixture(format:.png,gps:true))
 #expect(throws:ImageToolError.self){try ImagePipeline.removeGPS(png)}
 for format in [RasterFormat.jpeg,.tiff] {
    let source=try ImagePipeline.load(fixture(format:format,gps:true))
    let result=try ImagePipeline.removeGPS(source)
    #expect(!result.metadata.contains{$0.isGPS})
    #expect(result.data != source.data)
    #expect(result.metadata.contains{$0.value.contains("synthetic private comment")})
    // Compare decoded pixel bytes, not merely metadata keys.
    let a=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(source.data as CFData,nil)!,0,nil)!
    let b=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(result.data as CFData,nil)!,0,nil)!
    #expect(a.width==b.width && a.height==b.height)
    #expect(a.dataProvider?.data as Data? == b.dataProvider?.data as Data?)
 }
}
@Test func resizeBoundsAndTarget() throws {
 let source=try ImagePipeline.load(fixture())
 var o=ImageOptions();o.mode = .fill;o.width=20;o.height=20
 let cropped=try ImagePipeline.transform(source,options:o);#expect(cropped.width==20 && cropped.height==20)
 o.mode = .dimensions;o.width=80;o.height=80
 #expect(try o.dimensions(source).0==40)
 o.allowUpscale=true;#expect(try o.dimensions(source).0==80)
 o.width = -20;#expect(throws:ImageToolError.self){try o.dimensions(source)}
 o.mode = .percentage;o.percent = .infinity
 #expect(throws:ImageToolError.self){try o.dimensions(source)}
 o=ImageOptions();o.format = .jpeg;o.targetBytes=1
 let failed=try ImagePipeline.transform(source,options:o);#expect(!failed.targetReached);#expect(!failed.data.isEmpty)
}
@Test func imageInvalidAndAnimation() throws {
 #expect(throws:ImageToolError.self){try ImagePipeline.load(Data())}
 #expect(throws:ImageToolError.self){try ImagePipeline.load(Data("not an image".utf8))}
 let data=NSMutableData(),dest=CGImageDestinationCreateWithData(data,"com.compuserve.gif" as CFString,2,nil)!
 let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(try fixture() as CFData,nil)!,0,nil)!
 for _ in 0..<2{CGImageDestinationAddImage(dest,image,nil)};#expect(CGImageDestinationFinalize(dest))
 let source=try ImagePipeline.load(data as Data);#expect(source.frames==2)
 #expect(throws:ImageToolError.self){try ImagePipeline.transform(source,options:ImageOptions())}
}
@Test func svgMalformedAndEscapes() throws {
 for input in ["data:image/svg+xml,%ZZ","data:text/html,<svg/>","data:image/svg+xml;base64,____","data:image/svg+xml,%FF"]{#expect(throws:ImageToolError.self){try SVGDataURIProcessor.process(input,decode:true)}}
 let source="<svg xmlns='http://www.w3.org/2000/svg'><script>alert('secret')</script><text><![CDATA[<!ENTITY not-a-declaration>]]></text></svg>"
 #expect(try SVGDataURIProcessor.process(source).source==source)
 #expect(throws:ImageToolError.self){try SVGDataURIProcessor.process("<svg xmlns='http://www.w3.org/2000/svg'>"+String(repeating:"<g>",count:129)+String(repeating:"</g>",count:129)+"</svg>")}
}
@Test func imageStress12MP() throws {
 let clock=ContinuousClock(),start=clock.now
 let data=try fixture(width:4000,height:3000),source=try ImagePipeline.load(data)
 var o=ImageOptions();o.mode = .fit;o.width=1600;o.height=1600;o.format = .jpeg
 let output=try ImagePipeline.transform(source,options:o)
 #expect(output.width==1600 && output.height==1200)
 print("IMAGE_STRESS_12MP source_bytes=\(data.count) output_bytes=\(output.data.count) duration=\(start.duration(to:clock.now))")
}
@MainActor @Test func svgDecodeWorkspaceOutput() async throws {
 let source="<svg xmlns='http://www.w3.org/2000/svg'/>"
 let w=SVGWorkspace();w.input=try SVGDataURIProcessor.process(source).percentURI;w.run(decode:true)
 for _ in 0..<100{if !w.busy{break};try await Task.sleep(for:.milliseconds(10))}
 #expect(w.output==source)
 w.input="changed";#expect(w.output.isEmpty)
}
@Test func nearPixelBudgetAndCancellation() async throws {
 let start=ContinuousClock.now,data=try fixture(width:8000,height:5000),source=try ImagePipeline.load(data)
 #expect(throws:ImageToolError.self){try ImagePipeline.transform(source,options:ImageOptions())}
 var small=ImageOptions();small.mode = .fit;small.width=1000;small.height=1000
 let result=try ImagePipeline.transform(source,options:small);#expect(result.width==1000 && result.height==625)
 print("IMAGE_STRESS_40MP source_bytes=\(data.count) output_bytes=\(result.data.count) duration=\(start.duration(to:.now)); full-resolution buffers rejected by 384 MiB estimate")
 let task=Task{try Task.checkCancellation();return try ImagePipeline.transform(source,options:small)};task.cancel()
 do{_=try await task.value;Issue.record("Cancelled image task published a result")}catch is CancellationError{}catch{Issue.record("Unexpected cancellation status")}
}
@MainActor @Test func imageSettingsDoNotContainSource() async throws {
 let name="color-files-image-settings-"+UUID().uuidString,defaults=UserDefaults(suiteName:name)!
 defer{defaults.removePersistentDomain(forName:name)}
 let w=ImageWorkspace(defaults:defaults);w.options.quality=0.73;w.load(data:try fixture())
 for _ in 0..<100{if !w.busy{break};try await Task.sleep(for:.milliseconds(10))}
 #expect(w.source != nil)
 let data=defaults.data(forKey:"raster.convert.options")!,json=try JSONSerialization.jsonObject(with:data) as! [String:Any]
 #expect(Set(json.keys)==["format","quality","lockAspect"])
 let new=ImageWorkspace(defaults:defaults);#expect(new.source==nil && new.result==nil);#expect(new.options.quality==0.73)
}
private func rgba(_ data:Data)throws->[UInt8]{
 let source=CGImageSourceCreateWithData(data as CFData,nil)!,image=CGImageSourceCreateImageAtIndex(source,0,nil)!
 let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
 return Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
}
@Test func alphaColorProfilesAndExactPNG() throws {
 let input=try fixture(),source=try ImagePipeline.load(input),output=try ImagePipeline.transform(source,options:ImageOptions())
 let a=try rgba(input),b=try rgba(output.data);#expect(a.count==b.count)
 #expect(zip(a,b).allSatisfy{abs(Int($0)-Int($1))<=1})
 var opaque=ImageOptions();opaque.format = .jpeg;opaque.quality=1
 let jpg=try ImagePipeline.transform(source,options:opaque),pixels=try rgba(jpg.data)
 #expect(stride(from:3,to:pixels.count,by:4).allSatisfy{pixels[$0]==255})
 for space in [CGColorSpace(name:CGColorSpace.displayP3)!,CGColorSpaceCreateDeviceCMYK()] {
    let alpha=space.model == .cmyk ? CGImageAlphaInfo.none:CGImageAlphaInfo.premultipliedLast
    let context=CGContext(data:nil,width:20,height:10,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:alpha.rawValue)!
    context.setFillColor(CGColor(red:0.8,green:0.2,blue:0.1,alpha:1));context.fill(CGRect(x:0,y:0,width:20,height:10))
    let bytes=try ImagePipeline.encode(context.makeImage()!,format:.tiff,quality:1)
    let converted=try ImagePipeline.transform(ImagePipeline.load(bytes),options:ImageOptions())
    #expect(converted.width==20);#expect(converted.metadata.contains{$0.path.contains("ProfileName") && $0.value.lowercased().contains("srgb")})
 }
}

@Test func webPAndRasterInputMatrix() throws {
 let webp=Data(base64Encoded:"UklGRh4AAABXRUJQVlA4TBEAAAAvD8ACEAdQ1S7VvL6BiOh/AAA=")!
 let input=try ImagePipeline.load(webp);#expect(input.type=="org.webmproject.webp")
 let source=try ImagePipeline.load(fixture())
 var sources=[input]
 for format in RasterFormat.available {var o=ImageOptions();o.format=format;let result=try ImagePipeline.transform(source,options:o);sources.append(try ImagePipeline.load(result.data))}
 for input in sources {for format in RasterFormat.available {var o=ImageOptions();o.format=format;let result=try ImagePipeline.transform(input,options:o);#expect(result.width==input.orientedWidth && result.height==input.orientedHeight)}}
}
