import Foundation
import Observation

/// Window-owned, memory-only request runner. At most one worker and one replaceable pending request.
@MainActor @Observable public final class CalculationWorkspace<Request: Sendable> {
  public var request: Request { didSet { invalidate() } }
  public var automatic = true
  public private(set) var report: CalculationReport?
  public private(set) var issue: CalculationIssue?
  public private(set) var status = "Ready"
  public private(set) var busy = false
  public private(set) var showProgress = false
  public private(set) var revision = UUID()
  @ObservationIgnored private let process: @Sendable (Request) throws -> CalculationReport
  @ObservationIgnored private var active: Task<CalculationReport, Error>?
  @ObservationIgnored private var driver: Task<Void, Never>?
  @ObservationIgnored private var debounce: Task<Void, Never>?
  @ObservationIgnored private var progress: Task<Void, Never>?
  private struct Job {
    let revision: UUID
    let input: Request
  }
  @ObservationIgnored private var pending: Job?
  public init(
    _ request: Request, automatic: Bool = true,
    process: @escaping @Sendable (Request) throws -> CalculationReport
  ) {
    self.request = request
    self.automatic = automatic
    self.process = process
  }
  deinit {
    active?.cancel()
    driver?.cancel()
    debounce?.cancel()
    progress?.cancel()
  }
  public func invalidate() {
    revision = UUID()
    active?.cancel()
    pending = nil
    debounce?.cancel()
    progress?.cancel()
    report = nil
    issue = nil
    status = "Not checked"
    busy = false
    showProgress = false
    if automatic {
      let rev = revision
      debounce = Task { [weak self] in
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        guard let self, self.revision == rev else { return }
        self.run()
      }
    }
  }
  public func cancel() {
    revision = UUID()
    pending = nil
    active?.cancel()
    debounce?.cancel()
    progress?.cancel()
    busy = false
    showProgress = false
    status = "Cancelled"
  }
  public func run() {
    debounce?.cancel()
    active?.cancel()
    revision = UUID()
    issue = nil
    pending = Job(revision: revision, input: request)
    busy = true
    status = "Processing"
    showProgress = false
    progress?.cancel()
    let rev = revision
    progress = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
      guard let self, self.revision == rev, self.busy else { return }
      self.showProgress = true
    }
    if driver == nil { driver = Task { [weak self] in await self?.drain() } }
  }
  private func drain() async {
    while let job = pending {
      pending = nil
      let worker = process
      let task = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let result = try worker(job.input)
        try Task.checkCancellation()
        return result
      }
      active = task
      let result = await task.result
      active = nil
      guard revision == job.revision else { continue }
      busy = false
      showProgress = false
      progress?.cancel()
      switch result {
      case .success(let output):
        report = output
        issue = nil
        status = output.status
      case .failure(is CancellationError): status = "Cancelled"
      case .failure(let error):
        issue =
          error as? CalculationIssue ?? .init(.resource, "Unable to complete the calculation.")
        status =
          switch issue!.kind {
          case .invalid: "Invalid input"
          case .unsupported: "Unsupported"
          case .resource: "Resource limit"
          case .notReady: "Not ready"
          case .needsChoice: "Choose an occurrence"
          }
      }
    }
    driver = nil
  }
}
