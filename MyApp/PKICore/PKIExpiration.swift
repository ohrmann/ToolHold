import Foundation
import Observation
import Darwin
#if canImport(CertificateCore)
import CertificateCore
#endif

public struct PKIExpirationRow: Identifiable, Sendable, Codable {
    public let id: Int, file: String, entry: Int, subject: String, issuer: String, sha256: String
    public let notBefore: Date?, notAfter: Date?, sourceBytes: Int
    public let issue: String?
    public var sourcePath = ""
    public func state(at now: Date, threshold: Int) -> String {
        guard issue == nil, let before = notBefore, let after = notAfter, before <= after else { return "Unreadable" }
        if now < before { return "Not yet valid" }; if now > after { return "Expired" }
        return after.timeIntervalSince(now) <= Double(threshold) * 86400 ? "Expiring soon" : "Within validity"
    }
}
public struct PKIExpirationReport: Sendable, Codable {
    public var rows: [PKIExpirationRow] = []
    public var files = 0, bytes = 0, visited = 0
    public var evaluatedAt = Date(), threshold = 30
    public var complete = true, note = "Completed"
    public func csv() -> Data {
        func field(_ s: String) -> String { let safe = ["=","+","-","@"].contains(String(s.drop(while: { $0.isWhitespace }).prefix(1))) ? "'" + s : s; return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let header = "File,SourcePath,Entry,Subject,Issuer,NotBeforeUTC,NotAfterUTC,State,SHA256,Issue,ReportComplete,EvaluatedAtUTC,ThresholdDays"
        let body = rows.map { row in [row.file,row.sourcePath,String(row.entry),row.subject,row.issuer,row.notBefore.map { CertificateDisplay.date($0) } ?? "",row.notAfter.map { CertificateDisplay.date($0) } ?? "",row.state(at:evaluatedAt,threshold:threshold),row.sha256,row.issue ?? "",String(complete),CertificateDisplay.date(evaluatedAt),String(threshold)].map(field).joined(separator:",") }
        return Data(([header] + body).joined(separator:"\r\n").utf8)
    }
    public func json() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted,.sortedKeys]; e.dateEncodingStrategy = .iso8601; return try e.encode(self) }
}
public enum PKIExpirationScanner {
    public static func scan(_ urls: [URL], at now: Date = .now, threshold: Int = 30, progress: @Sendable (Int) -> Void = { _ in }) -> PKIExpirationReport {
        var report = PKIExpirationReport(evaluatedAt: now, threshold: max(0,min(3650,threshold)))
        guard urls.count <= 1000 else { report.complete = false; report.note = "Select at most 1,000 files/folders per report"; return report }
        var seen = Set<String>(), occurrences = 0
        func append(_ row: PKIExpirationRow, _ url: URL) { var copy = row; copy.sourcePath = CertificateDisplay.safe(url.path,limit:2048); report.rows.append(copy) }
        func issue(_ url: URL, _ message: String) { append(.init(id:report.rows.count,file:CertificateDisplay.safe(url.lastPathComponent,limit:200),entry:0,subject:"",issuer:"",sha256:"",notBefore:nil,notAfter:nil,sourceBytes:0,issue:message),url) }
        func file(_ url: URL) throws {
            try Task.checkCancellation()
            guard seen.insert(url.standardizedFileURL.path).inserted else { return }
            guard report.files < 1000 else { throw PKIFailure("Stopped at 1,000 files",status:.resourceLimit) }
            report.files += 1; defer { progress(report.files) }
            let info = try url.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey,.fileSizeKey])
            guard info.isSymbolicLink != true, info.isRegularFile == true else { issue(url,"Skipped non-regular file or symbolic link"); return }
            if info.isUbiquitousItem == true && info.ubiquitousItemDownloadingStatus != .current { issue(url,"Cloud placeholder skipped; download explicitly first"); return }
            guard let size = info.fileSize, size <= PKILimits.file, size >= 0 else { issue(url,"File exceeds 4 MiB"); return }
            guard report.bytes + size <= 256 * 1024 * 1024 else { throw PKIFailure("Stopped at 256 MiB cumulative input",status:.resourceLimit) }
            // No-follow open prevents replacing an enumerated file with a symlink before reading.
            let fd = url.withUnsafeFileSystemRepresentation { $0.map { Darwin.open($0,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1 }
            guard fd >= 0 else { issue(url,"File could not be opened"); return }
            let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true); defer { try? handle.close() }
            var a = stat(), b = stat(); guard fstat(fd,&a) == 0, a.st_mode & S_IFMT == S_IFREG, a.st_size <= PKILimits.file else { issue(url,"File changed or is not regular"); return }
            var data = Data()
            while true { try Task.checkCancellation(); let chunk = try handle.read(upToCount:min(65536,PKILimits.file-data.count+1)) ?? Data(); if chunk.isEmpty { break }; data.append(chunk); report.bytes += chunk.count; if report.bytes > 256 * 1024 * 1024 { throw PKIFailure("Stopped at 256 MiB cumulative input",status:.resourceLimit) }; if data.count > PKILimits.file { issue(url,"File grew beyond import limit"); return } }
            guard fstat(fd,&b) == 0, a.st_size == b.st_size, Int64(data.count) == b.st_size, a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec, a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec, a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec, a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec else { issue(url,"File changed during reading"); return }
            let result = CertificateProcessor.inspect(data,now:now)
            if result.status == .cancelled { throw CancellationError() }
            if result.entries.isEmpty { issue(url,result.message); return }
            guard occurrences + result.entries.count <= 4096 else { throw PKIFailure("Stopped at 4,096 certificate occurrences",status:.resourceLimit) }
            occurrences += result.entries.count
            for c in result.entries { append(.init(id:report.rows.count,file:CertificateDisplay.safe(url.lastPathComponent,limit:200),entry:c.id+1,subject:CertificateDisplay.safe(c.subject,limit:512),issuer:CertificateDisplay.safe(c.issuer,limit:512),sha256:c.sha256,notBefore:c.notBefore,notAfter:c.notAfter,sourceBytes:data.count,issue:c.parsed && c.notBefore != nil && c.notAfter != nil ? nil : "Certificate or validity could not be decoded"),url) }
        }
        do {
            for url in urls {
                try Task.checkCancellation(); guard url.isFileURL else { continue }
                let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
                let info = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                guard info.isSymbolicLink != true else { issue(url,"Symbolic link skipped"); continue }
                if info.isDirectory == true {
                    var directoryError = false
                    guard let iterator = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[],errorHandler:{ _,_ in directoryError = true; return true }) else { issue(url,"Folder could not be enumerated"); continue }
                    for case let child as URL in iterator {
                        try Task.checkCancellation(); report.visited += 1
                        guard report.visited <= 10000 else { throw PKIFailure("Stopped at 10,000 directory entries",status:.resourceLimit) }
                        if iterator.level > 16 { iterator.skipDescendants(); report.complete = false; report.note = "Some folders exceed depth 16"; continue }
                        let v = try child.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                        if v.isSymbolicLink == true { iterator.skipDescendants(); issue(child,"Symbolic link skipped"); continue }
                        if v.isDirectory == true { continue }
                        do { try file(child) } catch let e as PKIFailure where e.status == .resourceLimit { throw e } catch is CancellationError { throw CancellationError() } catch { issue(child,"File could not be read") }
                    }
                    if directoryError { issue(url,"Some folder entries could not be read"); report.complete = false }
                } else { do { try file(url) } catch let e as PKIFailure where e.status == .resourceLimit { throw e } catch is CancellationError { throw CancellationError() } catch { issue(url,"File could not be read") } }
            }
        } catch is CancellationError { report.complete = false; report.note = "Cancelled · partial report" }
        catch let e as PKIFailure { report.complete = false; report.note = e.message + " · partial report" }
        catch { report.complete = false; report.note = "Enumeration stopped · partial report" }
        return report
    }
}
@MainActor @Observable public final class PKIExpirationWorkspace {
    public var threshold = 30 { didSet { if threshold != oldValue { report?.threshold = max(0,min(3650,threshold)) } } }
    public var query = ""
    public var sortByExpiry = true
    public private(set) var report: PKIExpirationReport?
    public private(set) var busy = false
    public private(set) var processed = 0
    public private(set) var message = "Choose certificate files or a folder"
    @ObservationIgnored private var worker: Task<PKIExpirationReport,Never>?
    @ObservationIgnored private var revision = 0
    public init() {}
    deinit { worker?.cancel() }
    public func clear() { revision += 1; worker?.cancel(); report = nil; busy = false; processed = 0; message = "Ready" }
    public func cancel() { worker?.cancel(); message = "Cancelling…" }
    public func scan(_ urls: [URL]) {
        revision += 1; worker?.cancel(); let rev = revision, days = threshold
        busy = true; processed = 0; report = nil; message = "Inspecting files…"
        let owner = PKIExpirationOwner(self)
        let task = Task.detached(priority:.userInitiated) { PKIExpirationScanner.scan(urls,threshold:days) { count in Task { @MainActor in if owner.workspace?.revision == rev { owner.workspace?.processed = count } } } }
        worker = task
        Task { var result = await task.value; guard revision == rev else { return }; result.threshold = max(0,min(3650,threshold)); report = result; busy = false; message = result.note; worker = nil }
    }
}

@MainActor private final class PKIExpirationOwner { weak var workspace: PKIExpirationWorkspace?; init(_ workspace: PKIExpirationWorkspace) { self.workspace = workspace } }
