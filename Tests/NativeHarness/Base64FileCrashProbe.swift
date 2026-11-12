import Foundation
import Darwin

/// Separate child process: simulate a hard exit during an explicitly requested synthetic export.
@main struct Base64FileCrashProbe {
    static func main() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/T013CrashFixture",isDirectory:true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { print("T013_CRASH_FIXTURE_ALREADY_EXISTS"); exit(2) }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories:true)
        let source = directory.appendingPathComponent("synthetic-source.bin")
        try Data(repeating:7,count:2_000_000).write(to:source)
        _ = Base64FileProcessor.run(source:.file(source),options:.init(),destination:.init(directory:directory,name:"should-not-be-published.txt"),chunkSize:5,progress:{ _ in _exit(77) })
        print("T013_CRASH_NOT_TRIGGERED"); exit(1)
    }
}
