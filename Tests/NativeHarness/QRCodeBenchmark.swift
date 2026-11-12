import Foundation
import Darwin
import CoreGraphics
@testable import Developer_Toolbox
@main struct QRCodeBenchmark {
    @MainActor final class Pulse { var times:[Double]=[]; var running=true }
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        for (level,count) in [(QRCorrection.l,2953),(.m,2331),(.q,1663),(.h,1273)] {
            let p = Pulse()
            let heartbeat=Task { @MainActor in while p.running { p.times.append(ProcessInfo.processInfo.systemUptime); try? await Task.sleep(for:.milliseconds(5)) } }
            let start=ProcessInfo.processInfo.systemUptime
            let result=await Task.detached { () -> Result<QRArtifact,Error> in
                do { var settings=QRPreferences();settings.correction=level;return .success(try QRCodeProcessor.generate(source:String(repeating:"x",count:count),preferences:settings,logo:nil)) } catch { return .failure(error) }
            }.value
            p.running=false;await heartbeat.value
            var usage=rusage();getrusage(RUSAGE_SELF,&usage)
            print("QR_STRESS correction=\(level.rawValue) bytes=\(count) ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) peakRSS=\(usage.ru_maxrss) heartbeatMaxMs=\(zip(p.times.dropFirst(),p.times).map { ($0-$1)*1000 }.max() ?? 0)")
            switch result {
            case .success(let a): print("QR_STRESS version=\(a.matrix.version) status=\(a.verification)")
            case .failure(let e): print("QR_STRESS_ERROR \(e)")
            }
        }
        var settings=QRPreferences();settings.style = .rounded;settings.exportSize=4096
        let c=CGContext(data:nil,width:2048,height:1024,bitsPerComponent:8,bytesPerRow:8192,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(QRColor(0.2,0.3,0.5).cg());c.fill(CGRect(x:0,y:0,width:2048,height:1024))
        let logo=QRLogo(image:c.makeImage()!,png:try QRCodeRenderer.png(c.makeImage()!))
        let start=ProcessInfo.processInfo.systemUptime
        let export=try await Task.detached { let a=try QRCodeProcessor.generate(source:"https://example.com/stress",preferences:settings,logo:logo);return try QRCodeProcessor.export(a,format:.png) }.value
        var usage=rusage();getrusage(RUSAGE_SELF,&usage)
        print("QR_STRESS_EXPORT pixels=\(export.side) bytes=\(export.data.count) ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) peakRSS=\(usage.ru_maxrss)")
        let suite="qr-stress-"+UUID().uuidString, defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let session=QRCodeWorkspaceSession(defaults:defaults);session.input="https://example.com/latest";session.generate()
        for i in 0..<20 { session.preferences.rounding=Double(i%11)/20;session.preferences.style = .rounded;session.generate() }
        for _ in 0..<500 where session.busy { try await Task.sleep(for:.milliseconds(10)) }
        guard session.canOutput && session.artifact?.preferences.rounding == session.preferences.rounding else { fatalError("latest request failed") }
        print("QR_STRESS_RACE latest-of-20 passed")
    }
}
