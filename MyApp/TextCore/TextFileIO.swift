import Foundation

#if canImport(Darwin)
  import Darwin
#endif

enum TextFileIO {
  static func read(_ url: URL) throws -> String {
    guard url.isFileURL else { throw TextFailure.invalid("Choose a local file URL.") }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw TextFailure.invalid("File could not be opened.") }
    defer { close(fd) }
    var st = stat()
    guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= 1_048_576 else {
      throw TextFailure.resource("Choose a regular UTF-8 file of at most 1 MiB.")
    }
    var data = Data()
    var buffer = Array(repeating: UInt8(0), count: 65536)
    while true {
      try Task.checkCancellation()
      let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, 65536) }
      guard n >= 0 else { throw TextFailure.invalid("File read failed.") }
      if n == 0 { break }
      guard data.count + n <= 1_048_576 else {
        throw TextFailure.resource("File grew beyond 1 MiB.")
      }
      data.append(contentsOf: buffer.prefix(n))
    }
    let text = String(decoding: data, as: UTF8.self)
    guard text.utf8.elementsEqual(data) else {
      throw TextFailure.invalid("File is not valid UTF-8.")
    }
    try TextBounds.check(text)
    return text  // BOM preserved as an inspectable scalar; never silent data removal.
  }
}
