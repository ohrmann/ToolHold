import Foundation
import CQuickJS

final class MarkupCancellation: @unchecked Sendable {
    let pointer: OpaquePointer
    init() { pointer = tb_script_cancellation_create()! }
    var isCancelled: Bool { tb_script_is_cancelled(pointer) != 0 }
    func cancel() { tb_script_cancel(pointer) }
    deinit { tb_script_cancellation_free(pointer) }
}
/// Only this serial scheduler can create runtimes. Each C call owns a sufficiently sized native stack.
enum MarkupProcessor {
    private final class Scheduler: @unchecked Sendable {
        struct Job: Sendable {let request: MarkupRequest;let token: MarkupCancellation;let complete: @Sendable (MarkupResult)->Void}
        let lock=NSLock()
        let queue=DispatchQueue(label:"toolbox.code-markup",qos:.userInitiated)
        var jobs:[Job]=[]
        var running=false
        func submit(_ job: Job) {
            lock.lock()
            let obsolete=jobs.filter{$0.token.isCancelled};jobs.removeAll{$0.token.isCancelled};jobs.append(job)
            let start = !running;running=true;lock.unlock()
            for old in obsolete {old.complete(.init(status:"cancelled"))}
            if start {queue.async{self.drain()}}
        }
        func drain() {
            while true {
                lock.lock()
                if jobs.isEmpty {running=false;lock.unlock();return}
                let job=jobs.removeFirst();lock.unlock()
                if job.token.isCancelled {job.complete(.init(status:"cancelled"));continue}
                let done=DispatchSemaphore(value:0)
                let thread=Thread {job.complete(processSynchronously(job.request,cancellation:job.token));done.signal()}
                thread.stackSize=4*1024*1024;thread.name="Toolbox language worker";thread.start();done.wait()
            }
        }
    }
    private static let scheduler=Scheduler()
    static func process(_ request: MarkupRequest, cancellation: MarkupCancellation = .init()) async -> MarkupResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                scheduler.submit(.init(request:request,token:cancellation,complete:{continuation.resume(returning:$0)}))
            }
        } onCancel: { cancellation.cancel() }
    }
    static func processSynchronously(_ request: MarkupRequest, cancellation: MarkupCancellation) -> MarkupResult {
        if cancellation.isCancelled {return .init(status:"cancelled")}
        if request.source.utf16.count > 262144 { return .failure("resourceLimit", "Input exceeds 262144 UTF-16 units.") }
        if request.source.isEmpty { return .init(status: "ready") }
        if request.tool == .xml { return XMLMarkupProcessor.process(request, cancellation: cancellation) }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "code-markup", withExtension: "js"),
              let code = try? Data(contentsOf: url),
              let input = try? JSONEncoder().encode(request) else { return .failure("engineUnavailable", "Local engine resources are unavailable.") }
        var extra = Data()
        if request.tool == .mjml {
            guard let url = bundle.url(forResource: "code-mjml", withExtension: "js"), let data = try? Data(contentsOf: url) else { return .failure("engineUnavailable", "Local MJML engine is unavailable.") }; extra = data
        }
        var status: Int32 = 0, length = 0
        let result = code.withUnsafeBytes { b in extra.withUnsafeBytes { e in input.withUnsafeBytes { i in
            tb_script_run(b.bindMemory(to: CChar.self).baseAddress, b.count, e.bindMemory(to: CChar.self).baseAddress, e.count, i.bindMemory(to: CChar.self).baseAddress, i.count, cancellation.pointer, &status, &length)
        } } }
        defer { tb_script_free(result) }
        if status == 1 { return .init(status: "cancelled") }
        if status == 4 {return .failure("resourceLimit","The local engine reached its 128 MiB memory budget. No partial result was published.")}
        if status == 2 { return .failure("resourceLimit", "Processing time limit reached. No partial result was published.") }
        guard status == 0, let result,
              let decoded = try? JSONDecoder().decode(MarkupResult.self, from: Data(bytes: result, count: length)) else { return .failure("resourceLimit", "The local engine could not complete within its memory or stack budget.") }
        return decoded
    }
}
