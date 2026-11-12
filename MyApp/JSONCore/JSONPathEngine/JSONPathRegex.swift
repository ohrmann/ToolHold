import Foundation

/// RFC 9485 §5 mapping to ICU. This is a non-checking mapping, not a second
/// regular-expression parser. Known ICU-only extensions are rejected. See spec.
enum JSONPathRegex {
    static func map(_ pattern: String) -> String? {
        let scalars = Array(pattern.unicodeScalars)
        var output = "", index = 0, inClass = false
        let categories = Set(["L","Ll","Lm","Lo","Lt","Lu","M","Mc","Me","Mn","N","Nd","Nl","No",
                              "P","Pc","Pd","Pe","Pf","Pi","Po","Ps","Z","Zl","Zp","Zs","S","Sc","Sk","Sm","So","C","Cc","Cf","Cn","Co"])
        while index < scalars.count {
            let scalar = scalars[index]; index += 1
            switch scalar {
            case "\\":
                guard index < scalars.count else { return nil }
                let next = scalars[index]; index += 1
                if next == "p" || next == "P" {
                    guard index < scalars.count, scalars[index] == "{" else { return nil }; index += 1
                    var category = ""
                    while index < scalars.count, scalars[index] != "}" { category.unicodeScalars.append(scalars[index]); index += 1 }
                    guard index < scalars.count, categories.contains(category) else { return nil }; index += 1
                    output += "\\" + String(next) + "{" + category + "}"
                } else {
                    guard "()*+-.?[]^nrt{}\\|".unicodeScalars.contains(next) else { return nil }
                    output += "\\" + String(next)
                }
            case "[":
                guard !inClass else { return nil }; inClass = true; output += "["
            case "]":
                guard inClass else { return nil }; inClass = false; output += "]"
            case "&" where inClass: output += "\\&"
            case "." where !inClass: output += "[^\\n\\r]"
            case "^" where !inClass, "$" where !inClass: output += "\\" + String(scalar)
            case "?" where !inClass:
                if index >= 2, "(?*+?}".unicodeScalars.contains(scalars[index - 2]) { return nil }
                output += "?"
            case "+" where !inClass:
                if index >= 2, "*+?}".unicodeScalars.contains(scalars[index - 2]) { return nil }
                output += "+"
            default: output.unicodeScalars.append(scalar)
            }
        }
        return inClass ? nil : output
    }
}
