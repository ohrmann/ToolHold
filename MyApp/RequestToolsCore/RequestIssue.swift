import Foundation
public struct RequestIssue:Error,LocalizedError,Sendable {
    public let message:String,range:NSRange?
    public init(_ message:String,range:NSRange? = nil){self.message=message;self.range=range}
    public var errorDescription:String?{message}
}
