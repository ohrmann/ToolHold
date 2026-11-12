import Foundation
import Observation

/// Independent memory-only texts and snapshots. Preferences use the existing UI-only allowlist.
@MainActor @Observable final class JSONSchemaWorkspaceSession {
    let instance = JSONDiffInput()
    let schema = JSONDiffInput()
    var preferences: JSONToolPreferences { didSet { repository.save(preferences) } }
    var validateFormats: Bool {
        get { preferences.schemaValidateFormats }
        set { guard preferences.schemaValidateFormats != newValue else { return }; preferences.schemaValidateFormats = newValue; invalidate(schemaChanged: true) }
    }
    var assumedDialect: Dialect {
        get { Dialect(rawValue: preferences.schemaAssumedDialect) ?? .draft2020_12 }
        set { guard assumedDialect != newValue else { return }; preferences.schemaAssumedDialect = newValue.rawValue; invalidate(schemaChanged: true) }
    }
    var options: JSONSchemaOptions { .init(validateFormats: validateFormats, assumedDialect: assumedDialect) }
    private(set) var referenced: [JSONSchemaReferencedInput] = []
    var activeResource: UUID?
    private(set) var importMessage: String?
    private(set) var importing = false
    @ObservationIgnored private var importRevision = UUID()
    @ObservationIgnored private var importWork: Task<Void, Never>?
    var displayedSchema: JSONDiffInput { referenced.first { $0.id == activeResource }?.input ?? schema }
    var displayedSchemaName: String { referenced.first { $0.id == activeResource }?.name ?? "Schema" }
    var profile: String {
        let declared = schema.document.flatMap { doc in doc.nodes[0].children.first { doc.nodes[$0].key == "$schema" }.flatMap { doc.nodes[$0].scalar } }.flatMap { Dialect(uri: $0) }
        return (declared ?? assumedDialect).title + " · Local refs only · format: " + (validateFormats ? "validate supported" : "annotation")
    }
    var instanceCollapsed = false
    var schemaCollapsed = false
    var inputFraction = 0.62
    var splitFraction = 0.5
    var selection: Int? { didSet { if selection != oldValue { refreshContexts() } } }
    private(set) var jsonContext: JSONDiagnosticContext?
    private(set) var schemaContext: JSONDiagnosticContext?
    @ObservationIgnored private var contextTask: Task<Void, Never>?
    private(set) var report: JSONSchemaReport?
    private(set) var busy = false
    private(set) var wasCancelled = false
    private(set) var version = 0
    private(set) var scrollRequest = 0
    private(set) var rows: [Int] = []
    private(set) var rowNumbers: [Int: Int] = [:]
    @ObservationIgnored private let runner = JSONSchemaWorker()
    @ObservationIgnored private var compiled: JSONSchemaCompiled?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private let repository: JSONPreferencesRepository
    init(repository: JSONPreferencesRepository = .init()) {
        self.repository = repository; preferences = repository.load()
        instance.changed = { [weak self] in self?.invalidate(schemaChanged: false) }
        schema.changed = { [weak self] in self?.invalidate(schemaChanged: true) }
    }
    var selectedIssue: JSONSchemaIssue? {
        guard let report, let selection, report.issues.indices.contains(selection) else { return nil }
        return report.issues[selection]
    }
    var status: String {
        if busy { return "Validating…" }
        if wasCancelled { return "Cancelled" }
        if let report { return report.status.rawValue }
        for input in [instance, schema] + referenced.map(\.input) {
            if case .resourceLimit = input.result?.status { return "Resource limit reached" }
        }
        if instance.result?.status == .invalid { return "Check JSON syntax" }
        if displayedSchema.result?.status == .invalid { return "Check Schema syntax" }
        return instance.source.isEmpty && schema.source.isEmpty ? "Ready" : "Not checked"
    }
    func refreshPreferences() {
        let old = options; preferences = repository.load()
        if old != options { invalidate(schemaChanged: true) }
    }
    /// Explicit file selection only. Bounded reads and parsing stay off the main actor.
    @discardableResult func importResources(_ urls: [URL], replacing: UUID? = nil) -> Task<Void, Never> {
        importWork?.cancel()
        importRevision = UUID(); let request = importRevision
        importMessage = nil; importing = true
        let allowance = max(0, 8 * 262_144 - referenced.filter { $0.id != replacing }.reduce(schema.source.utf16.count, { $0 + $1.input.source.utf16.count }))
        let task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> [(String, String)]? in
                var result: [(String, String)] = []
                var total = 0
                for url in urls {
                    guard !Task.isCancelled else { return nil }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                        let data = try file.read(upToCount: 262_144 * 4 + 1) ?? Data()
                        guard data.count <= 262_144 * 4, let text = String(data: data, encoding: .utf8), text.utf16.count <= 262_144 else { return nil }
                        total += text.utf16.count
                        guard total <= allowance else { return nil }
                        result.append((url.lastPathComponent, text))
                    } catch { return nil }
                }
                return result
            }
            let loaded = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, self.importRevision == request, !Task.isCancelled else { return }
            self.importing = false
            guard let loaded else { self.importMessage = "Could not read schema. Choose UTF-8 JSON within 262,144 UTF-16 per file and 2,097,152 for the schema set."; return }
            let old = replacing.flatMap { id in self.referenced.first { $0.id == id } }
            let retained = self.referenced.filter { $0.id != replacing }
            guard retained.reduce(self.schema.source.utf16.count, { $0 + $1.input.source.utf16.count }) + loaded.reduce(0, { $0 + $1.1.utf16.count }) <= 8 * 262_144 else {
                self.importMessage = "Referenced schema set exceeds the 2,097,152 UTF-16 session budget."; return
            }
            self.invalidate(schemaChanged: true)
            var additions: [JSONSchemaReferencedInput] = []
            for (name, text) in loaded {
                let uri = old?.retrievalURI ?? URL(string: "https://developer-toolbox.invalid/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "schema.json"))!
                let resource = JSONSchemaReferencedInput(id: old?.id ?? UUID(), name: name, retrievalURI: uri)
                resource.input.source = text; additions.append(resource)
            }
            self.referenced = retained + additions
            // Retain invalid input for inspection/correction by replacing the explicit file.
            for resource in additions {
                guard self.importRevision == request, !Task.isCancelled else { return }
                await resource.input.inspect().value
            }
            self.importWork = nil
        }
        importWork = task; return task
    }
    func importFailed() { importMessage = "The selected schema could not be opened." }
    func cancelImport() { importRevision = UUID(); importing = false; importWork?.cancel(); importWork = nil }
    func removeResource(_ id: UUID) {
        cancelImport()
        referenced.first { $0.id == id }?.input.cancel()
        referenced.removeAll { $0.id == id }
        if activeResource == id { activeResource = nil }
        invalidate(schemaChanged: true)
    }
    func retrievalURI(for resource: JSONSchemaReferencedInput) -> URL {
        guard let document = schema.document else { return resource.retrievalURI }
        let root = document.nodes[0]
        let declared = root.children.first { document.nodes[$0].key == "$schema" }.flatMap { document.nodes[$0].scalar }.flatMap { Dialect(uri: $0) } ?? assumedDialect
        if declared == .draft7, root.children.contains(where: { document.nodes[$0].key == "$ref" }) { return resource.retrievalURI }
        guard let id = root.children.first(where: { document.nodes[$0].key == "$id" }),
              let text = document.nodes[id].scalar, let base = URL(string: text, relativeTo: JSONSchemaRegistry.base)?.absoluteURL else { return resource.retrievalURI }
        let name = resource.retrievalURI.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "schema.json"
        return URL(string: name, relativeTo: base)?.absoluteURL ?? resource.retrievalURI
    }
    func schemaDocument(for issue: JSONSchemaIssue) -> JSONStructureDocument? {
        if let id = issue.schemaDocumentID { return referenced.first { $0.id == id }?.input.document }
        return schema.document
    }
    func revealSchema(for issue: JSONSchemaIssue) { activeResource = issue.schemaDocumentID }

    private func invalidate(schemaChanged: Bool) {
        contextTask?.cancel(); contextTask = nil; jsonContext = nil; schemaContext = nil
        work?.cancel(); work = nil; revision = UUID(); busy = false; report = nil
        rows = []; rowNumbers = [:]; selection = nil; wasCancelled = false; version += 1
        if schemaChanged { compiled = nil }
    }
    func cancel() {
        wasCancelled = busy || instance.busy || schema.busy
        work?.cancel(); work = nil; revision = UUID(); busy = false
        instance.cancel(); schema.cancel(); referenced.forEach { $0.input.cancel() }; cancelImport()
    }
    @discardableResult func didPaste(schema: Bool) -> Task<Void, Never>? {
        preferences.validateOnPaste ? (schema ? self.schema : instance).inspect() : nil
    }
    @discardableResult func validate() -> Task<Void, Never> {
        guard !instance.source.isEmpty, !schema.source.isEmpty else { return Task {} }
        if report?.isComplete == true, !busy, !wasCancelled { return Task {} }
        work?.cancel(); revision = UUID(); let request = revision
        busy = true; wasCancelled = false
        let resourceInputs = referenced
        let options = self.options
        let task = Task { [weak self] in
            guard let self else { return }
            let first = self.instance.inspect(), second = self.schema.inspect()
            await first.value; await second.value
            for resource in resourceInputs { await resource.input.inspect().value }
            guard resourceInputs.allSatisfy({ $0.input.document != nil }) else {
                guard self.revision == request, !Task.isCancelled else { return }
                self.activeResource = resourceInputs.first { $0.input.document == nil }?.id
                self.busy = false; self.work = nil; return
            }
            let resources = resourceInputs.compactMap { item in item.input.document.map { JSONSchemaResource(id: item.id, name: item.name, retrievalURI: item.retrievalURI, document: $0) } }
            guard self.revision == request, !Task.isCancelled else { return }
            guard let instance = self.instance.document, let schema = self.schema.document else {
                self.busy = false; self.work = nil; return
            }
            let cached = self.compiled
            let runner = self.runner
            let worker = Task.detached(priority: .userInitiated) {
                await runner.evaluate(instance: instance, schema: schema, cached: cached, options: options, resources: resources)
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard self.revision == request, !Task.isCancelled else { return }
            self.compiled = result.compiled; self.report = result.report
            self.rows = result.report.issues.filter { $0.depth == 0 }.map(\.id)
            self.rowNumbers = Dictionary(uniqueKeysWithValues: self.rows.enumerated().map { ($0.element, $0.offset + 1) })
            self.version += 1; self.selection = nil; self.selection = self.rows.first
            self.busy = false; self.work = nil
        }
        work = task; return task
    }
    func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = rows[min(rows.count - 1, max(0, (selection.flatMap { rows.firstIndex(of: $0) } ?? (delta > 0 ? -1 : rows.count)) + delta))]
        scrollRequest += 1
    }
    private func refreshContexts() {
        contextTask?.cancel(); contextTask = nil; jsonContext = nil; schemaContext = nil
        guard let issue = selectedIssue else { return }
        let jsonRange = sourceRange(issue, schemaSide: false), ruleRange = sourceRange(issue, schemaSide: true)
        let json = instance.source, rule = schemaDocument(for: issue)?.source ?? "", revision = self.revision, selected = selection
        contextTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                (jsonRange.map { JSONDiagnosticContext.make(source: json, range: $0) },
                 ruleRange.map { JSONDiagnosticContext.make(source: rule, range: $0) })
            }
            let pair = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.revision == revision, self.selection == selected else { return }
            self.jsonContext = pair.0; self.schemaContext = pair.1
        }
    }
    func sourceRange(_ issue: JSONSchemaIssue, schemaSide: Bool) -> NSRange? {
        guard let document = schemaSide ? schemaDocument(for: issue) : instance.document,
              let id = schemaSide ? issue.schemaNode : issue.instanceNode,
              document.nodes.indices.contains(id) else { return nil }
        let node = document.nodes[id]
        let range = !schemaSide && issue.instanceKey ? node.keyRange ?? node.range : node.range
        return range.length > 80 ? NSRange(location: range.location, length: 0) : range
    }
}

/// Serializes engine contexts even when an earlier cancelled task is still unwinding.
private actor JSONSchemaWorker {
    func evaluate(instance: JSONStructureDocument, schema: JSONStructureDocument, cached: JSONSchemaCompiled?, options: JSONSchemaOptions, resources: [JSONSchemaResource]) -> JSONSchemaEvaluation {
        JSONSchemaValidation.evaluate(instance: instance, schema: schema, cached: cached, options: options, resources: resources)
    }
}

@MainActor final class JSONSchemaReferencedInput: Identifiable {
    let id: UUID
    let name: String
    let retrievalURI: URL
    let input = JSONDiffInput()
    init(id: UUID, name: String, retrievalURI: URL) { self.id = id; self.name = name; self.retrievalURI = retrievalURI }
}
