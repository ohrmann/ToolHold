import Foundation

public enum CertificateProcessor {
    public static func inspect(_ bytes: Data, now: Date = .now) -> CertificateResult {
        do {
            try Task.checkCancellation()
            guard !bytes.isEmpty else { throw CertificateFailure("Enter a PEM certificate or import a DER file.") }
            guard bytes.count <= CertificateLimits.file else { throw CertificateFailure(.resource, "File exceeds 4 MiB.") }
            let blocks: [(Data, NSRange?)]
            if let text = String(data: bytes, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-----") {
                blocks = try PEMEnvelopeReader.read(text, allowed: ["CERTIFICATE"], maximumCount: CertificateLimits.count).map { ($0.der, $0.range) }
            } else {
                guard bytes.count <= CertificateLimits.certificate else { throw CertificateFailure(.resource, "DER certificate exceeds 256 KiB.") }
                blocks = [(bytes, nil)]
            }
            var entries: [CertificateEntry] = []
            for (index, block) in blocks.enumerated() {
                try Task.checkCancellation()
                entries.append(CertificateDER.inspect(block.0, id: index, sourceRange: block.1))
            }
            try Task.checkCancellation()
            let parsed = entries.filter(\.parsed).count
            let clean = parsed == entries.count && entries.allSatisfy { $0.issues.isEmpty }
            return .init(status: clean ? .completed : .completedWithIssues, entries: entries, message: "\(parsed) of \(entries.count) inspected", evaluatedAt: now)
        } catch is CancellationError { return .init(status: .cancelled, entries: [], message: "Cancelled", evaluatedAt: now) }
        catch let e as CertificateFailure { return .init(status: e.kind == .resource ? .resourceLimit : .failed, entries: [], message: e.message, evaluatedAt: now) }
        catch { return .init(status: .failed, entries: [], message: "The certificate could not be inspected.", evaluatedAt: now) }
    }
}
