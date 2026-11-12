import Foundation

enum JSONModelLanguage: String, CaseIterable, Codable, Sendable {
    case swift, typeScript, cSharp, java, kotlin
    var title: String {
        switch self { case .swift: "Swift"; case .typeScript: "TypeScript"; case .cSharp: "C#"; case .java: "Java"; case .kotlin: "Kotlin" }
    }
    var fileExtension: String {
        switch self { case .swift: "swift"; case .typeScript: "ts"; case .cSharp: "cs"; case .java: "java"; case .kotlin: "kt" }
    }
    var profile: String {
        switch self {
        case .swift: "Swift · Foundation Codable"
        case .typeScript: "TypeScript · plain types"
        case .cSharp: "C# 12 · System.Text.Json"
        case .java: "Java 17 · Jackson 2"
        case .kotlin: "Kotlin 2 · kotlinx.serialization"
        }
    }
    var note: String {
        switch self {
        case .swift: "Optional fields combine missing and null. Decimal values have finite precision. JSON spelling is not retained by Codable."
        case .typeScript: "Types do not validate JSON at runtime. JavaScript numbers use binary floating point; unsafe sample numbers are rejected."
        case .cSharp: "Required checks presence, not non-null values. JsonElement preserves numbers that do not fit decimal."
        case .java: "POJOs combine missing and null. Use the included Jackson 2 decoder for exact untyped numeric values."
        case .kotlin: "Double uses binary floating point. JsonElement-backed ToolboxJSONValue preserves other numbers. Missing fields use nullable defaults."
        }
    }
}

struct JSONModelOptions: Equatable, Sendable {
    var language: JSONModelLanguage = .swift
    var rootName = "RootModel"
    var indentation: JSONIndentation = .two
}

struct JSONModelIssue: Sendable, Identifiable {
    let id: Int
    let code: String
    let severity: JSONDiagnostic.Severity
    let message: String
    let range: NSRange?
    var related: NSRange? = nil
}

enum JSONModelStatus: Sendable, Equatable {
    case success, invalidJSON, unsupported, invalidOptions, resourceLimit, cancelled
}

struct JSONModelArtifact: Sendable {
    let fileName: String
    let text: String
    let rootType: String
    let usage: String
}

struct JSONModelResult: Sendable {
    let status: JSONModelStatus
    let parseResult: JSONResult
    let issues: [JSONModelIssue]
    let issueCount: Int
    let artifact: JSONModelArtifact?
}

/// An arena shape represents one structural position, including all array samples.
struct JSONModelShape: Sendable {
    let path: [String]
    let sourceNode: Int
    var nullable = false
    var boolean = false
    var string = false
    var numbers: [Int] = []
    var object: Int?
    var element: Int?
    var alternativeCount: Int { (boolean ? 1 : 0) + (string ? 1 : 0) + (numbers.isEmpty ? 0 : 1) + (object == nil ? 0 : 1) + (element == nil ? 0 : 1) }
}

struct JSONModelField: Sendable {
    let key: String
    let shape: Int
    let sourceNode: Int
    var presentCount: Int
}

struct JSONModelObject: Sendable {
    let shape: Int
    var sampleCount = 0
    var fields: [JSONModelField] = []
    var keyIndices: [Data: Int] = [:]
}

struct JSONModelGraph: Sendable {
    let document: JSONStructureDocument
    let shapes: [JSONModelShape]
    let objects: [JSONModelObject]
}

struct JSONModelFailure: Error, Sendable {
    let status: JSONModelStatus
    let code: String
    let message: String
    var range: NSRange? = nil
    var related: NSRange? = nil
}
