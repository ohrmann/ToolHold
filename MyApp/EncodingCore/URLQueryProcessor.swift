import Foundation

enum URLQueryProcessor {
    static func inspect(_ source: String, profile: URLQueryProfile = .percent, limits: URLQueryLimits = .init()) -> URLQueryInspection {
        do {
            try Task.checkCancellation()
            if source.isEmpty { return .init(status:.ready) }
            let reference = try URLReferenceAdapter.capture(source,limits:limits)
            let original = source as NSString
            var rows: [URLQueryRow] = [], rawOnly = 0
            if let query = reference.components.query, query.length > 0 {
                let units = Array(original.substring(with:query).utf16)
                var start = 0, equals: Int?
                for i in 0...units.count {
                    if i & 4095 == 0 { try Task.checkCancellation() }
                    if i < units.count && units[i] == 61 && equals == nil { equals = i }
                    if i == units.count || units[i] == 38 {
                        let nameRange = NSRange(location:query.location+start,length:(equals ?? i)-start)
                        let valueRange = equals.map { NSRange(location:query.location+$0+1,length:i-$0-1) }
                        let rawName = original.substring(with:nameRange), rawValue = valueRange.map { original.substring(with:$0) }
                        let name = try decode(rawName,profile:profile,limits:limits)
                        let value = try rawValue.map { try decode($0,profile:profile,limits:limits) } ?? nil
                        if name == nil || (rawValue != nil && value == nil) { rawOnly += 1 }
                        rows.append(.init(id:rows.count,sourceRange:.init(location:query.location+start,length:i-start),nameRange:nameRange,valueRange:valueRange,
                                          rawName:rawName,rawValue:rawValue,name:name,value:value))
                        start = i+1; equals = nil
                    }
                }
            }
            var issues = reference.issues
            if rawOnly > 0 { issues.append(.init(code:"rawOnly",message:"\(rawOnly) parameter(s) contain bytes that are not valid UTF-8. They remain raw-only; no replacement text was created.",severity:.note)) }
            return .init(status:.parsed,snapshot:.init(source:source,profile:profile,components:reference.components,rows:rows,issues:issues),issues:issues)
        } catch is CancellationError { return .init(status:.cancelled) }
        catch let failure as URLQueryFailure { return .init(status:failure.status,issues:[failure.issue]) }
        catch { return .init(status:.processingFailure,issues:[.init(code:"internal",message:"Unable to inspect this reference.")]) }
    }
    static func build(_ snapshot: URLQuerySnapshot, draft: URLQueryDraft, limits: URLQueryLimits = .init()) -> URLQueryBuildResult {
        do {
            try Task.checkCancellation()
            let original = snapshot.source as NSString, c = snapshot.components
            let prefixEnd = c.query.map { $0.location-1 } ?? c.fragment.map { $0.location-1 } ?? original.length
            var text = original.substring(to:prefixEnd), total = text.utf16.count
            func append(_ string: String) throws {
                let count = string.utf16.count
                guard count <= limits.output - total else { throw URLQueryFailure("outputLimit", "Result exceeds the UTF-16 output limit.",resource:true) }
                text += string; total += count
            }
            guard total <= limits.output else { throw URLQueryFailure("outputLimit", "Result exceeds the UTF-16 output limit.",resource:true) }
            guard draft.queryPresent || draft.rows.isEmpty else { throw URLQueryFailure("draft", "A nonempty query must include '?'.") }
            if draft.queryPresent {
                try append("?")
                for (index,row) in draft.rows.enumerated() {
                    if index & 255 == 0 { try Task.checkCancellation() }
                    if index > 0 { try append("&") }
                    try append(try row.changedName.map { try encode($0,profile:snapshot.profile,limits:limits) } ?? row.rawName)
                    if let value = row.rawValue {
                        try append("=")
                        try append(try row.changedValue.map { try encode($0,profile:snapshot.profile,limits:limits) } ?? value)
                    }
                }
            }
            if let fragment = c.fragment { try append("#"); try append(original.substring(with:fragment)) }
            try Task.checkCancellation()
            // Capture is reused, not a separate parser/formatter. It validates the generated reference and maps Unicode/IDN.
            let reference = try URLReferenceAdapter.capture(text,limits:.init(input:limits.output,output:limits.output,bytes:limits.bytes,validation:limits.validation))
            let fits = reference.ascii.utf16.count <= limits.output
            return .init(status:.parsed,artifact:.init(preserve:text,ascii:fits ? reference.ascii : nil,
                asciiIssue:fits ? nil : .init(code:"asciiLimit",message:"ASCII URI exceeds the output limit. Preserve output remains available.",severity:.note)))
        } catch is CancellationError { return .init(status:.cancelled) }
        catch let failure as URLQueryFailure { return .init(status:failure.status,issues:[failure.issue]) }
        catch { return .init(status:.processingFailure,issues:[.init(code:"internal",message:"Unable to build this reference.")]) }
    }
    private static func decode(_ raw: String, profile: URLQueryProfile, limits: URLQueryLimits) throws -> String? {
        if !raw.contains("%") && (profile == .percent || !raw.contains("+")) { return raw }
        let result = URLPercentProcessor.process(raw,options:.init(direction:.decode,profile:profile.codec),
            limits:.init(inputUTF16:limits.input,outputUTF16:limits.input,bytes:limits.bytes))
        if result.status == .cancelled { throw CancellationError() }
        if result.status == .resourceLimit { throw URLQueryFailure("decodedLimit", "Decoded query exceeds the processing limit.",resource:true) }
        return result.artifact?.text
    }
    private static func encode(_ value: String, profile: URLQueryProfile, limits: URLQueryLimits) throws -> String {
        let result = URLPercentProcessor.process(value,options:.init(direction:.encode,profile:profile.codec),
            limits:.init(inputUTF16:limits.input,outputUTF16:limits.output,bytes:limits.bytes))
        if result.status == .cancelled { throw CancellationError() }
        guard let text = result.artifact?.text else { throw URLQueryFailure("encodedLimit", "Encoded field exceeds the processing limit.",resource:true) }
        return text
    }
}
