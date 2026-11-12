import Foundation
import FileProvider

/// Only these fixed messages reach UI. Provider errors may contain filenames or sensitive data.
public enum PKIExportOutcome: Equatable, Sendable {
    case success, cancelled, permissionDenied, unavailable, existingDirectory, failed
    public init(_ result: Result<URL, Error>) {
        switch result {
        case .success: self = .success
        case .failure(let error): self = Self.classify(error, depth: 0)
        }
    }
    private static func classify(_ error: Error, depth: Int) -> Self {
        if error is CancellationError { return .cancelled }
        #if os(macOS)
        if let failure = error as? PKISecureLocalExport.Failure {
            switch failure { case .permissions: return .permissionDenied; case .existingDirectory: return .existingDirectory; default: break }
        }
        #endif
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain {
            if value.code == NSUserCancelledError { return .cancelled }
            if [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(value.code) { return .permissionDenied }
        }
        if value.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(value.code) { return .permissionDenied }
        if depth < 4, let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            let result = classify(underlying, depth: depth + 1)
            if result != .failed { return result }
        }
        if value.domain == NSFileProviderErrorDomain { return .unavailable }
        return .failed
    }
    public var message: String {
        switch self {
        case .success: "Export completed."
        case .cancelled: "Export cancelled; result is unchanged."
        case .permissionDenied: "Export failed: access denied. Choose a writable destination and retry."
        case .unavailable: "Export failed: file provider unavailable. Retry or choose another destination."
        case .existingDirectory: "Export failed: choose a new folder name. Existing folders are unchanged."
        case .failed: "Export failed: unable to save safely. Choose another destination and retry."
        }
    }
}
