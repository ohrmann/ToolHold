import SwiftUI
import UniformTypeIdentifiers

struct QRCodeExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png,.svg] }
    let data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
