import SwiftUI
import UniformTypeIdentifiers

struct QRCodeDecodedExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data,.plainText] }
    let data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
