import SwiftUI
import UniformTypeIdentifiers

struct CertificateExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data,.plainText] }
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:bytes) }
}
