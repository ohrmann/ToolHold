import Foundation
import Darwin
public enum LocalImageFile {
    public static func read(_ url:URL,limit:Int = 32*1024*1024)throws->Data {
        guard url.isFileURL else {throw ImageToolError(.io,"Choose a local file.")}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let info=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard info.isRegularFile == true else {throw ImageToolError(.io,"Choose a regular file.")}
        guard let size=info.fileSize,size<=limit else {throw ImageToolError(.resource,"File exceeds the input byte budget.")}
        let fd=url.withUnsafeFileSystemRepresentation{$0.map{Darwin.open($0,O_RDONLY|O_NONBLOCK|O_CLOEXEC)} ?? -1}
        guard fd>=0 else {throw ImageToolError(.io,"Could not open the file.")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? handle.close()}
        var before=stat(),after=stat()
        guard fstat(fd,&before)==0,(before.st_mode&S_IFMT)==S_IFREG,before.st_size>=0,before.st_size<=limit else {throw ImageToolError(.io,"File is unavailable or exceeds the byte budget.")}
        var data=Data()
        while true {try Task.checkCancellation();let chunk=try handle.read(upToCount:min(65536,limit-data.count+1)) ?? Data();if chunk.isEmpty{break};data.append(chunk);if data.count>limit{throw ImageToolError(.resource,"File exceeds the input byte budget.")}}
        guard fstat(fd,&after)==0,before.st_size==after.st_size,Int64(data.count)==after.st_size,before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec else {throw ImageToolError(.io,"File changed during reading. Open it again.")}
        return data
    }
}
