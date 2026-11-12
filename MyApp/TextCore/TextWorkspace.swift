import Foundation
import Observation

/// Only transport/lifetime is shared. Every tool owns its typed options and processor.
@MainActor @Observable final class TextWorkspace<Options: Codable & Equatable & Sendable> {
  var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
  var second = "" { didSet { if !second.utf16.elementsEqual(oldValue.utf16) { invalidate() } } }
  var options: Options {
    didSet {
      saveOptions()
      invalidate()
    }
  }
  var wordWrap: Bool { didSet { defaults.set(wordWrap, forKey: key + ".wrap") } }
  var automatic: Bool {
    didSet {
      defaults.set(automatic, forKey: key + ".auto")
      if automatic { schedule() }
    }
  }
  var collapsed = false
  var fraction = 0.45
  var selection: Int? {
    didSet {
      captureMarker = nil
      publication = UUID()
    }
  }
  var captureMarker: NSRange? { didSet { publication = UUID() } }
  private(set) var artifact: TextArtifact?
  private(set) var status = "Ready"
  private(set) var busy = false
  private(set) var showProgress = false
  @ObservationIgnored private var progressTask: Task<Void, Never>?
  private(set) var isError = false
  private(set) var revision = UUID()
  private(set) var publication = UUID()
  private(set) var target: NSRange?
  private(set) var secondTarget: NSRange?
  private(set) var jumpRequest = 0
  @ObservationIgnored let defaults: UserDefaults
  @ObservationIgnored let key: String
  typealias Worker =
    @Sendable (String, String, Options, TextRegexCancellation, Bool) throws -> TextArtifact
  @ObservationIgnored private let worker: Worker
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var active: Task<TextArtifact, Error>?
  @ObservationIgnored private var debounce: Task<Void, Never>?
  @ObservationIgnored private var cancellation: TextRegexCancellation?
  private struct Job {
    let id: UUID, revision: UUID, input: String, second: String, options: Options, automatic: Bool
  }
  @ObservationIgnored private var pending: Job?
  @ObservationIgnored private var request = UUID()
  init(
    id: String, options: Options, automatic: Bool = false, defaults: UserDefaults = .standard,
    worker: @escaping Worker
  ) {
    self.options = options
    self.key = "developerToolbox.text." + id
    self.defaults = defaults
    self.worker = worker
    wordWrap = defaults.object(forKey: key + ".wrap") as? Bool ?? true
    self.automatic = defaults.object(forKey: key + ".auto") as? Bool ?? automatic
    restoreOptions()
  }
  private static var storedKeys: Set<String> {
    [
      "mode", "perLine", "operation", "multiset", "ignoreEmpty", "comparison", "ending", "terminal",
      "order", "descending", "last", "trimOutput", "normalization", "filter", "regex",
      "literalReplacement", "ignoreEndings", "unit", "start", "format", "nullText",
      "spreadsheetSafe",
    ]
  }
  private func saveOptions() {
    guard let data = try? JSONEncoder().encode(options),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    let allowed = object.filter { Self.storedKeys.contains($0.key) }
    if let data = try? JSONSerialization.data(withJSONObject: allowed) {
      defaults.set(data, forKey: key + ".options")
    }
  }
  private func restoreOptions() {
    guard let data = defaults.data(forKey: key + ".options"),
      let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let original = try? JSONEncoder().encode(options),
      var merged = try? JSONSerialization.jsonObject(with: original) as? [String: Any]
    else { return }
    for (k, v) in stored where Self.storedKeys.contains(k) { merged[k] = v }
    if let data = try? JSONSerialization.data(withJSONObject: merged),
      let decoded = try? JSONDecoder().decode(Options.self, from: data)
    {
      options = decoded
    }
  }
  deinit {
    progressTask?.cancel()
    task?.cancel()
    active?.cancel()
    debounce?.cancel()
    cancellation?.cancel()
  }
  func invalidate() {
    cancel()
    revision = UUID()
    artifact = nil
    publication = UUID()
    status = "Not checked"
    isError = false
    selection = nil
    target = nil
    secondTarget = nil
    captureMarker = nil
    schedule()
  }
  func cancel() {
    progressTask?.cancel()
    showProgress = false
    pending = nil
    debounce?.cancel()
    active?.cancel()
    cancellation?.cancel()
    request = UUID()
    if busy { status = "Cancelled" }
    busy = false
  }
  func clear() {
    input = ""
    second = ""
    cancel()
    artifact = nil
    status = "Ready"
    isError = false
  }
  func schedule() {
    guard automatic else { return }
    debounce?.cancel()
    let rev = revision
    debounce = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      guard let self, self.revision == rev else { return }
      guard self.input.utf16.count <= 32768, self.second.utf16.count <= 32768 else {
        self.status = "Run to process this larger input"
        return
      }
      self.run(automatic: true)
    }
  }
  func paste() { if automatic { run(automatic: true) } }
  func run(automatic: Bool = false) {
    debounce?.cancel()
    cancellation?.cancel()
    active?.cancel()
    request = UUID()
    busy = true
    progressTask?.cancel()
    showProgress = false
    let progressID = request
    progressTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
      guard let self, self.request == progressID, self.busy else { return }
      self.showProgress = true
    }
    isError = false
    pending = Job(
      id: request, revision: revision, input: input, second: second, options: options,
      automatic: automatic)
    guard task == nil else { return }
    task = Task { [weak self] in
      while let self, let job = self.pending {
        self.pending = nil
        let cancel = TextRegexCancellation()
        self.cancellation = cancel
        let worker = self.worker
        let work = Task.detached(priority: .userInitiated) {
          try worker(job.input, job.second, job.options, cancel, job.automatic)
        }
        self.active = work
        let result = await work.result
        if self.request == job.id && self.revision == job.revision && self.options == job.options {
          self.busy = false
          self.progressTask?.cancel()
          self.showProgress = false
          self.active = nil
          self.cancellation = nil
          switch result {
          case .success(let artifact):
            self.artifact = artifact
            self.status = artifact.message
            self.publication = UUID()
            self.isError = false
          case .failure(let error):
            let cancelled = error is CancellationError || (error as? TextFailure) == .cancelled
            self.status =
              cancelled ? "Cancelled" : (error as? TextFailure)?.message ?? "Processing failed."
            self.isError = !cancelled
          }
        }
      }
      self?.task = nil
    }
  }
  var canCopy: Bool { artifact?.output != nil && !busy }
  func navigate(_ left: NSRange?, _ right: NSRange? = nil) {
    collapsed = false
    target = left
    secondTarget = right
    jumpRequest += 1
  }
  func select(_ index: Int, navigate: Bool = false) {
    selection = index
    if navigate, let r = artifact?.rows.first(where: { $0.id == index }) {
      self.navigate(r.left, r.right)
    }
  }
}
struct RegexWorkspaceOptions: Codable, Equatable, Sendable {
  var pattern = "", replacement = "", regex = TextRegexOptions(), literalReplacement = false,
    current: Int?
}
struct UnicodeWorkspaceOptions: Codable, Equatable, Sendable {
  var filter = "All", normalization = "Original"
}
struct StatisticsOptions: Codable, Equatable, Sendable {}
enum TextWorkspaces {
  @MainActor static func diff() -> TextWorkspace<TextDiffOptions> {
    .init(id: "033", options: .init()) { a, b, o, _, _ in
      try TextDiffProcessor.process(a, b, options: o)
    }
  }
  @MainActor static func lists() -> TextWorkspace<ListComparisonOptions> {
    .init(id: "034", options: .init()) { a, b, o, _, _ in
      try ListComparisonProcessor.process(a, b, options: o)
    }
  }
  @MainActor static func regex(replace: Bool = false) -> TextWorkspace<RegexWorkspaceOptions> {
    .init(id: replace ? "042" : "035", options: .init(), automatic: true) { source, _, o, c, auto in
      if auto && o.pattern.isEmpty {
        return .init(message: "Enter a pattern, or Run explicitly for empty-pattern matching.")
      }
      let result = try TextRegexProcessor.run(
        source, pattern: o.pattern, options: o.regex, automatic: auto, cancellation: c)
      var artifact = TextRegexProcessor.artifact(result)
      if replace {
        artifact.output = try TextReplacement.replace(
          result, template: o.replacement, literal: o.literalReplacement, current: o.current)
      }
      return artifact
    }
  }
  @MainActor static func casing() -> TextWorkspace<TextCaseOptions> {
    .init(id: "036", options: .init(), automatic: true) { s, _, o, _, _ in
      try TextCaseProcessor.process(s, options: o)
    }
  }
  @MainActor static func sort() -> TextWorkspace<LineSortOptions> {
    .init(id: "037", options: .init()) { s, _, o, _, _ in
      try LineSortProcessor.process(s, options: o)
    }
  }
  @MainActor static func unicode() -> TextWorkspace<UnicodeWorkspaceOptions> {
    .init(id: "038", options: .init(), automatic: true) { s, _, o, _, _ in
      try TextUnicodeInspector.inspect(s, filter: o.filter, normalization: o.normalization)
    }
  }
  @MainActor static func lorem() -> TextWorkspace<LoremOptions> {
    .init(id: "039", options: .init()) { _, _, o, _, _ in try LoremProcessor.process(o) }
  }
  @MainActor static func mock() -> TextWorkspace<MockOptions> {
    .init(id: "040", options: .init()) { _, _, o, _, _ in
      let data = try MockDataProcessor.generate(o)
      var a = TextArtifact(
        message: "\(data.rows.count) rows · \(data.fields.count) fields",
        notes: ["Seed: \(data.seed) · Generator v1 · Synthetic samples; not secrets"], mock: data,
        filename: "sample." + o.format.lowercased())
      do {
        a.output = try data.serialize(
          format: o.format, nullText: o.nullText, spreadsheetSafe: o.spreadsheetSafe)
      } catch { a.notes.append((error as? TextFailure)?.message ?? "Serialization failed.") }
      return a
    }
  }
  @MainActor static func statistics() -> TextWorkspace<StatisticsOptions> {
    .init(id: "041", options: .init(), automatic: true) { s, _, _, _, _ in
      try TextStatisticsProcessor.process(s)
    }
  }
}
