import Foundation
import Vision
import CoreML
import CoreGraphics

public enum QRCodeVerifier {
    private static func observation(_ image: CGImage, matrix: QRMatrix) throws -> VNBarcodeObservation? {
        try Task.checkCancellation()
        #if targetEnvironment(simulator)
        let revisions = [VNDetectBarcodesRequestRevision2]
        #else
        let revisions = VNDetectBarcodesRequest.defaultRevision == VNDetectBarcodesRequestRevision2 ? [VNDetectBarcodesRequestRevision2] : [VNDetectBarcodesRequest.defaultRevision,VNDetectBarcodesRequestRevision2]
        #endif
        let ratio = Double(matrix.size)/Double(matrix.size+8)
        for revision in revisions {
            try Task.checkCancellation()
            let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]; request.revision = revision
            if revision == VNDetectBarcodesRequestRevision2 {
                // Simulator's default revision cannot create an inference context. The
                // same system revision also covers dense symbols missed by newer Vision.
                for (stage,devices) in try request.supportedComputeStageDevices {
                    if let cpu = devices.first(where:{ if case .cpu = $0 { return true }; return false }) { request.setComputeDevice(cpu,for:stage) }
                }
            }
            do { try VNImageRequestHandler(cgImage:image).perform([request]) }
            catch {
                try Task.checkCancellation()
                if revision != revisions.last { continue }
                throw QRIssue(.generation,"The system QR reader is unavailable. Try again on this device.")
            }
            try Task.checkCancellation()
            let candidates = (request.results ?? []).filter {
                abs($0.boundingBox.midX-0.5) < 0.12 && abs($0.boundingBox.midY-0.5) < 0.12 &&
                $0.boundingBox.width > ratio*0.8 && $0.boundingBox.height > ratio*0.8
            }
            if candidates.count == 1 { return candidates[0] }
            if candidates.count > 1 { return nil }
        }
        return nil
    }
    public static func reference(_ matrix: QRMatrix) throws -> QRReference {
        let plain = QRPreferences()
        let geometry = try QRGeometry(matrix:matrix,preferences:plain,hasLogo:false)
        // Dense version-40 symbols may exceed Vision's detection threshold at 1024 px.
        // A larger pristine reference does not change the user's output size or content.
        for target in [1024,2048,4096] {
            let image = try QRCodeRenderer.image(geometry,logo:nil,target:target)
            if let obs = try observation(image,matrix:matrix) {
                // Current Vision QR payloadData contains corrected codewords, not message bytes.
                return QRReference(codewords:obs.payloadData,text:obs.payloadStringValue.map { Data($0.utf8) })
            }
        }
        throw QRIssue(.generation,"The system could not read the original QR. Try shorter input or another correction level.")
    }
    public static func verify(_ image: CGImage, matrix: QRMatrix, preferences: QRPreferences, reference: QRReference) throws -> QRVerification {
        let conditional = preferences.opacity < 1
        let checked: CGImage
        if conditional {
            guard let c = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw QRIssue(.resource,"Could not allocate the scan surface.") }
            c.setFillColor(preferences.surfaceColor.cg()); c.fill(CGRect(x:0,y:0,width:image.width,height:image.height))
            c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            guard let surface = c.makeImage() else { throw QRIssue(.rendering,"Could not prepare the scan surface.") }
            checked = surface
        } else { checked = image }
        guard let obs = try observation(checked,matrix:matrix) else { return .unavailable }
        if let original = reference.codewords, let actual = obs.payloadData {
            return original == actual ? .readable(conditional:conditional) : .mismatch
        }
        // Only exact text that matches the ORIGINAL input can serve as a fallback.
        if let original = reference.text, original == matrix.payload,
           let actual = obs.payloadStringValue.map({Data($0.utf8)}) {
            return actual == original ? .readable(conditional:conditional) : .mismatch
        }
        return .unavailable
    }
}
public enum QRCodeProcessor {
    public static func generate(source: String, preferences: QRPreferences, logo: QRLogo?, previous: QRArtifact? = nil) throws -> QRArtifact {
        guard preferences.valid else { throw QRIssue(.rendering,"Invalid QR settings.") }
        let level = preferences.correction(hasLogo:logo != nil)
        let matrix: QRMatrix, reference: QRReference
        if let old = previous, old.matrix.payload == Data(source.utf8), old.matrix.correction == level {
            matrix = old.matrix; reference = old.reference
        } else { matrix = try QRCodeEncoder.encode(source,correction:level); reference = try QRCodeVerifier.reference(matrix) }
        let geometry = try QRGeometry(matrix:matrix,preferences:preferences,hasLogo:logo != nil)
        let image = try QRCodeRenderer.image(geometry,logo:logo,target:min(1024,preferences.exportSize))
        var check = try QRCodeVerifier.verify(image,matrix:matrix,preferences:preferences,reference:reference)
        var verifiedSide = image.width
        if check == .unavailable && preferences.exportSize > 1024 {
            let final = try QRCodeRenderer.image(geometry,logo:logo,target:preferences.exportSize)
            check = try QRCodeVerifier.verify(final,matrix:matrix,preferences:preferences,reference:reference)
            verifiedSide = final.width
        }
        return QRArtifact(matrix:matrix,preferences:preferences,logo:logo,reference:reference,image:image,verification:check,verifiedSide:verifiedSide,geometry:geometry)
    }
    public static func export(_ artifact: QRArtifact, format: QRExportFormat) throws -> QRExport {
        let geometry = artifact.geometry
        let image = try QRCodeRenderer.image(geometry,logo:artifact.logo,target:artifact.preferences.exportSize)
        let check = try QRCodeVerifier.verify(image,matrix:artifact.matrix,preferences:artifact.preferences,reference:artifact.reference)
        guard check.passed else { throw QRIssue(.rendering,check.message) }
        try Task.checkCancellation()
        let data = try format == .png ? QRCodeRenderer.png(image) : QRCodeRenderer.svg(geometry,logo:artifact.logo)
        return QRExport(data:data,format:format,side:image.width)
    }
}
