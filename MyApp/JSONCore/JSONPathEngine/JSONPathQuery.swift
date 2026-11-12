//
//  JSONPathQuery.swift
//  DynamicJSON
//
//  Created by Matthias Zenger on 13/02/2024.
//  Copyright © 2024 Matthias Zenger. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

///
/// Enumeration `JSONPathQuery` represents JSONPathQuery queries based on RFC 9535
/// (JSONPathQuery: Query Expressions for JSON). JSONPathQuery defines a syntax
/// for selecting and extracting JSON (RFC 8259) values from within a given
/// JSON value.
///
indirect enum JSONPathQuery: Codable,
                               Hashable,
                               Sendable,
                               CustomStringConvertible {
  // Modified for Developer Toolbox: query-only module, original number lexemes,
  // no JSON value model or JSON parser. See ThirdPartyNotices/DynamicJSON.
  static func escape(_ text: String) -> String {
    text.unicodeScalars.map { scalar in
      switch scalar.value {
      case 39: return "\\'"
      case 92: return "\\\\"
      case 0...31: return String(format: "\\u%04x", scalar.value)
      default: return String(scalar)
      }
    }.joined()
  }
  case `self`
  case current
  case select(JSONPathQuery, Segment)
  
  /// Syntactic sugar for appending a single selector to the JSONPathQuery query `path`.
  static func children(_ path: JSONPathQuery, _ selector: Selector) -> JSONPathQuery {
    return .select(path, .children([selector]))
  }
  
  /// Syntactic sugar for appending a single descendant to the JSONPathQuery query `path`.
  static func descendants(_ path: JSONPathQuery, _ selector: Selector) -> JSONPathQuery {
    return .select(path, .descendants([selector]))
  }
  
  /// Creates a `JSONPathQuery` representation of the JSONPathQuery query represented
  /// using the syntax as specified by RFC 9535. An error is thrown if `query`
  /// is not compliant with JSONPathQuery syntax. If parameter `strict` is set to
  /// false, the syntax and semantics of JSONPathQuery are slighly relaxed. For
  /// instance, non-singular queries are supported in query filters.
  init(query: String, strict: Bool = true) throws {
    var parser = JSONPathQueryParser(string: query, strict: strict)
    self = try parser.parse()
  }
  
  /// Initialize a `JSONPathQuery` reference using a decoder.
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(query: try container.decode(String.self))
  }
  
  /// Encode a `JSONPathQuery` reference using the given encoder.
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }
  
  /// Returns true if this JSONPathQuery value represents a singular query.
  var isSingular: Bool {
    switch self {
      case .self:
        return true
      case .current:
        return true
      case .select(let path, let segment):
        return path.isSingular && segment.isSingular
    }
  }
  
  /// Returns true if this query is a relative JSONPathQuery query, i.e. it does not start
  /// with "$'.
  var isRelative: Bool {
    switch self {
      case .self:
        return false
      case .current:
        return true
      case .select(let path, _):
        return path.isRelative
    }
  }
  
  /// Returns the sequence of segments of this JSONPathQuery query.
  var segments: [Segment] {
    var res: [Segment] = []
    self.insert(into: &res)
    return res
  }
  
  private func insert(into segments: inout [Segment]) {
    switch self {
      case .self, .current:
        break
      case .select(let path, let segment):
        path.insert(into: &segments)
        segments.append(segment)
    }
  }
  
  /// Returns the JSONPathQuery query as a string.
  var description: String {
    switch self {
      case .self:
        return "$"
      case .current:
        return "@"
      case .select(let path, let segment):
        return "\(path)\(segment)"
    }
  }
  
  /// Representation of JSONPathQuery query segments. There are two different segment types:
  /// children and descendants.
  enum Segment: Hashable, Sendable, CustomStringConvertible {
    case children([Selector])
    case descendants([Selector])
    
    /// Returns true if this segment is a descendant segment.
    var isDescendant: Bool {
      switch self {
        case .children(_):
          return false
        case .descendants(_):
          return true
      }
    }
    
    /// Returns true if this segment is singular, i.e. it refers to at most one value.
    var isSingular: Bool {
      switch self {
        case .children(let selectors):
          return selectors.count == 1 && selectors[0].isSingular
        case .descendants(_):
          return false
      }
    }
    
    /// Returns the selectors encapsulated by this segment.
    var selectors: [Selector] {
      switch self {
        case .children(let selectors):
          return selectors
        case .descendants(let selectors):
          return selectors
      }
    }
    
    /// Returns true if this segment can be represented using a shorthand form avoiding
    /// the usage of brackets.
    private func canUseShorthand(for member: String) -> Bool {
      var first = true
      for ch in member {
        let scalars = ch.unicodeScalars
        guard ch.isLetter
              || !first && ch.isHexDigit
              || ch == "_"
              || !first && ch == "-"
              || scalars.allSatisfy({ c in c.value >= 0x80 && c.value <= 0xD7FF })
              || scalars.allSatisfy({ c in c.value >= 0xE000 && c.value <= 0x10FFFF }) else {
          return false
        }
        first = false
      }
      return true
    }
    
    /// Returns a string representation of this segment.
    var description: String {
      var res = ""
      var selectors: [Selector]
      switch self {
        case .children(let sel):
          selectors = sel
        case .descendants(let sel):
          selectors = sel
          res.append(".")
      }
      if selectors.count == 0 {
        return "\(res)[]"
      } else if selectors.count == 1 {
        switch selectors[0] {
          case .wildcard:
            return "\(res).*"
          case .member(let member):
            if self.canUseShorthand(for: member) {
              return "\(res).\(member)"
            } else if res.isEmpty {
              return "['\(JSONPathQuery.escape(member))']"
            } else {
              return "..['\(JSONPathQuery.escape(member))']"
            }
          default:
            if res.isEmpty {
              return "[\(selectors[0])]"
            } else {
              return "..[\(selectors[0])]"
            }
        }
      } else {
        if res.isEmpty {
          return "[\(selectors.map { x in x.description }.joined(separator: ", "))]"
        } else {
          return "..[\(selectors.map { x in x.description }.joined(separator: ", "))]"
        }
      }
    }
  }
  
  /// Representation of JSONPathQuery query path selectors. Selectors are either child or
  /// descendant selectors. Supported are:
  ///   - wildcard selectors,
  ///   - member selectors,
  ///   - index selectors,
  ///   - slice selectors, and
  ///   - filter selectors.
  enum Selector: Hashable, Sendable, CustomStringConvertible {
    case wildcard
    case member(String)
    case index(Int)
    case slice(Int?, Int?, Int?)
    case filter(Expression)
    
    /// Returns true if this selector is singular, i.e. it refers to at most one value.
    var isSingular: Bool {
      switch self {
        case .wildcard:
          return false
        case .member(_):
          return true
        case .index(_):
          return true
        case .slice(_, _, _):
          return false
        case .filter(_):
          return false
      }
    }
    
    /// Returns a string representation of this selector when used within a segment
    /// delimited by brackets.
    var description: String {
      switch self {
        case .wildcard:
          return "*"
        case .member(let member):
          return "'\(JSONPathQuery.escape(member))'"
        case .index(let n):
          return String(n)
        case .slice(nil, nil, nil):
          return ":"
        case .slice(.some(let start), nil, nil):
          return "\(start):"
        case .slice(nil, .some(let end), nil):
          return ":\(end)"
        case .slice(nil, nil, .some(let step)):
          return "::\(step)"
        case .slice(.some(let start), .some(let end), nil):
          return "\(start):\(end)"
        case .slice(.some(let start), nil, .some(let step)):
          return "\(start)::\(step)"
        case .slice(nil, .some(let end), .some(let step)):
          return ":\(end):\(step)"
        case .slice(.some(let start), .some(let end), .some(let step)):
          return "\(start):\(end):\(step)"
        case .filter(let condition):
          return "? \(condition)"
      }
    }
  }
  
  /// Representation of JSONPathQuery query filter expressions.
  indirect enum Expression: Hashable, Sendable, CustomStringConvertible {
    case `null`
    case `true`
    case `false`
    case number(String)
    case string(String)
    case variable(String)
    case query(JSONPathQuery)
    case singularQuery(JSONPathQuery)
    case call(String, [Expression])
    case prefix(UnaryOperator, Expression)
    case operation(Expression, BinaryOperator, Expression)
    
    /// Return a string representation of this expression if nested within another expression.
    func description(within context: Expression) -> String {
      switch (self, context) {
        case (.null, _), (.true, _), (.false, _),
             (.number(_), _), (.string(_), _),
             (.variable(_), _), (.query(_), _), (.call(_, _), _):
          return self.description
        case (.operation(_, _, _), .prefix(_, _)):
          return "(\(self))"
        case (.operation(_, let op, _), .operation(_, let cop, _)):
          if cop.precedence > op.precedence {
            return "(\(self))"
          }
          fallthrough
        default:
          return self.description
      }
    }
    
    /// Returns a string representation of this expression assuming it is not
    /// embedded in another expression.
    var description: String {
      switch self {
        case .null:
          return "null"
        case .true:
          return "true"
        case .false:
          return "false"
        case .number(let x):
          return x
        case .string(let str):
          return "'\(str)'"
        case .variable(let ident):
          return ident
        case .query(let path):
          return path.description
        case .singularQuery(let path):
          return path.description
        case .call(let ident, let args):
          return "\(ident)(\(args.map { x in x.description }.joined(separator: ", ")))"
        case .prefix(let op, let oper):
          return "\(op)\(oper.description(within: self))"
        case .operation(let lhs, let op, let rhs):
          return "\(lhs.description(within: self)) \(op) \(rhs.description(within: self))"
      }
    }
  }
  
  /// Representation of a unary operator. Supported are currently "-" and "!".
  enum UnaryOperator: Hashable, Sendable, CustomStringConvertible {
    case not
    case negate
    
    var description: String {
      switch self {
        case .not:
          return "!"
        case .negate:
          return "-"
      }
    }
  }
  
  /// Representation of a binary operator. Supported are currently "==", "!=", "<",
  /// ">", "<=", ">=", "||", "&&", "+", "-", "*", and "/".
  enum BinaryOperator: Hashable, Sendable, CustomStringConvertible {
    case equals
    case notEquals
    case lessThan
    case lessThanEquals
    case greaterThan
    case greaterThanEquals
    case or
    case and
    case plus
    case minus
    case mult
    case divide
    
    var precedence: Int {
      switch self {
        case .or:
          return 0
        case .and:
          return 1
        case .equals:
          return 2
        case .notEquals:
          return 2
        case .lessThan:
          return 2
        case .lessThanEquals:
          return 2
        case .greaterThan:
          return 2
        case .greaterThanEquals:
          return 2
        case .plus:
          return 3
        case .minus:
          return 3
        case .mult:
          return 4
        case .divide:
          return 4
      }
    }
    
    var description: String {
      switch self {
        case .equals:
          return "=="
        case .notEquals:
          return "!="
        case .lessThan:
          return "<"
        case .lessThanEquals:
          return "<="
        case .greaterThan:
          return ">"
        case .greaterThanEquals:
          return ">="
        case .or:
          return "||"
        case .and:
          return "&&"
        case .plus:
          return "+"
        case .minus:
          return "-"
        case .mult:
          return "*"
        case .divide:
          return "/"
      }
    }
  }
}
