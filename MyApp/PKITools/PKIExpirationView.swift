import SwiftUI
import UniformTypeIdentifiers

struct PKIExpirationView: View {
    @Bindable var workspace: PKIExpirationWorkspace
    @State private var importing = false
    @State private var folder = false
    @State private var exporting = false
    @State private var document = CertificateExportDocument(Data())
    @State private var filename = "certificate-expiration.csv"
    @State private var exportMessage = ""
    @FocusState private var searchFocused: Bool
    private var rows: [PKIExpirationRow] {
        let rows = (workspace.report?.rows ?? []).filter { workspace.query.isEmpty || ($0.file + " " + $0.sourcePath + " " + $0.subject + " " + $0.issuer + " " + $0.sha256).localizedCaseInsensitiveContains(workspace.query) }
        return workspace.sortByExpiry ? rows.sorted { ($0.notAfter ?? .distantFuture, $0.id) < ($1.notAfter ?? .distantFuture, $1.id) } : rows
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            ViewThatFits(in:.horizontal) {
                HStack { actions; Spacer(); settings }
                VStack(alignment:.leading) { actions; settings }
            }
            HStack { if workspace.busy { ProgressView().controlSize(.small) }; Text(workspace.busy ? "Processed \(workspace.processed) files…" : workspace.message).font(.callout); Spacer() }.frame(minHeight:26)
            Text("Validity dates only · signatures, trust and revocation are not evaluated. Files stay on this device.").font(.caption).foregroundStyle(.secondary)
            TextField("Search files, subjects, issuers and fingerprints",text:$workspace.query).textFieldStyle(.roundedBorder).focused($searchFocused)
            if let report = workspace.report {
                Text("\(report.files) files · \(report.rows.count) entries · \(report.bytes) bytes · evaluated \(CertificateDisplay.date(report.evaluatedAt)) · threshold \(report.threshold) days").font(.caption).foregroundStyle(.secondary)
                if !report.complete { Label("Partial report · \(report.note)",systemImage:"exclamationmark.triangle").font(.callout) }
                List(rows) { row in
                    VStack(alignment:.leading,spacing:5) {
                        HStack { Text(row.file).font(.headline); Spacer(); Text(row.state(at:report.evaluatedAt,threshold:report.threshold)).font(.callout.weight(.medium)) }
                        Text(row.sourcePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        if !row.subject.isEmpty { Text("\(row.entry). \(row.subject)").lineLimit(2).textSelection(.enabled) }
                        if let after = row.notAfter { Text("Expires \(CertificateDisplay.date(after))").font(.caption) }
                        if let issue = row.issue { Label(issue,systemImage:"exclamationmark.triangle").font(.caption) }
                        if !row.sha256.isEmpty { Text("SHA-256: \(row.sha256)").font(.caption2).textSelection(.enabled) }
                    }.padding(.vertical,4).accessibilityElement(children:.combine)
                }.listStyle(.plain)
            } else { ContentUnavailableView("Check certificate expiry",systemImage:"calendar.badge.clock",description:Text("Select local PEM / DER files or a folder. Bundles and duplicate occurrences are included.")) }
            if !exportMessage.isEmpty { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
        }.padding(12).navigationTitle("Batch Certificate Expiration Checker")
        .fileImporter(isPresented:$importing,allowedContentTypes:folder ? [.folder] : [.data,.plainText],allowsMultipleSelection:!folder) { result in if case .success(let urls) = result { workspace.scan(urls) } }
        .fileExporter(isPresented:$exporting,document:document,contentTypes:[.data],defaultFilename:filename,onCompletion:{ result in
            let outcome = PKIExportOutcome(result)
            exportMessage = outcome == .success ? "Report exported." : outcome.message; document = .init(Data())
        },onCancellation:{ exportMessage = PKIExportOutcome.cancelled.message; document = .init(Data()) })
        .background { Button("Find") { searchFocused = true }.keyboardShortcut("f",modifiers:.command).hidden().accessibilityHidden(true) }
    }
    private var actions: some View {
        HStack {
            Button("Open Files",systemImage:"doc") { folder = false; importing = true }.disabled(workspace.busy)
            Button("Choose Folder",systemImage:"folder") { folder = true; importing = true }.disabled(workspace.busy)
            if workspace.busy { Button("Cancel") { workspace.cancel() } }
            Button("Clear") { workspace.clear() }
            Menu("Export Report") {
                Button("CSV · all collected rows") { if let report = workspace.report { document = .init(report.csv()); filename = "certificate-expiration.csv"; exporting = true } }
                Button("JSON · all collected rows") { if let report = workspace.report, let bytes = try? report.json() { document = .init(bytes); filename = "certificate-expiration.json"; exporting = true } }
            }.disabled(workspace.report == nil || workspace.busy)
        }.buttonStyle(.bordered).controlSize(.small)
    }
    private var settings: some View {
        HStack { Stepper("Warn within \(workspace.threshold) days",value:$workspace.threshold,in:0...3650).fixedSize(); Toggle("Sort by expiry",isOn:$workspace.sortByExpiry) }.font(.callout)
    }
}
