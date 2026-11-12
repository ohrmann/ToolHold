import Foundation
import CoreGraphics
import Darwin
@testable import Developer_Toolbox

@main struct QRCodeDecoderBenchmark {
    @MainActor final class Pulse { var active=true;var times:[Double]=[] }
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/QRCodeCoreTests/DecoderFixtures/numeric.png")
        let data=try Data(contentsOf:root)
        for profile in ["ordinary","dense-v40","photo12MP","photo40MP","no-code4096"] {
            let pulse=Pulse()
            let beat=Task { @MainActor in while pulse.active { pulse.times.append(ProcessInfo.processInfo.systemUptime);try? await Task.sleep(for:.milliseconds(5)) } }
            let start=ProcessInfo.processInfo.systemUptime
            let result=try await Task.detached { () throws -> (Int,Int,Int,Double,Double) in
                let source:QRDecodeSource
                let before=ProcessInfo.processInfo.systemUptime
                switch profile {
                case "ordinary":source=try QRCodeDecoderImageLoader.decode(data)
                case "dense-v40":
                    let matrix=try QRCodeEncoder.encode(String(repeating:"x",count:2953),correction:.l)
                    source=try QRCodeDecoderImageLoader.decode(QRCodeRenderer.png(QRCodeRenderer.image(QRGeometry(matrix:matrix,preferences:QRPreferences(),hasLogo:false),logo:nil,target:4096)))
                default:
                    let width=profile == "photo40MP" ? 8000 : profile == "photo12MP" ? 4000 : 4096
                    let height=profile == "photo40MP" ? 5000 : profile == "photo12MP" ? 3000 : 4096
                    let bytes:Data=try autoreleasepool {
                        let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
                        if profile != "no-code4096" {
                            let qr=try QRCodeDecoderImageLoader.decode(data).image
                            context.interpolationQuality = .none;context.draw(qr,in:CGRect(x:width/3,y:height/3,width:1400,height:1400))
                        }
                        return try QRCodeRenderer.png(context.makeImage()!)
                    }
                    source=try QRCodeDecoderImageLoader.decode(bytes)
                }
                let prepared=ProcessInfo.processInfo.systemUptime
                let snapshot=try QRCodeDecoderProcessor.scan(source)
                return(source.originalWidth,source.originalHeight,snapshot.items.filter(\.readable).count,(prepared-before)*1000,(ProcessInfo.processInfo.systemUptime-prepared)*1000)
            }.value
            pulse.active=false;await beat.value
            var usage=rusage();getrusage(RUSAGE_SELF,&usage)
            print("T029_BENCH profile=\(profile) original=\(result.0)x\(result.1) readable=\(result.2) prepareMs=\(result.3) scanMs=\(result.4) wallMs=\((ProcessInfo.processInfo.systemUptime-start)*1000) peakRSS=\(usage.ru_maxrss) heartbeatMaxMs=\(zip(pulse.times.dropFirst(),pulse.times).map { ($0-$1)*1000 }.max() ?? 0)")
        }
    }
}
