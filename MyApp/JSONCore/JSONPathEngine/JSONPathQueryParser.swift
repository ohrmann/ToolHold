//
//  JSONPathQueryParser.swift
//  DynamicJSON
//
//  Created by Matthias Zenger on 15/02/2024.
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
/// Parser for JSONPathQuery syntax according to RFC 9535. The parser operates in
/// two different modes: in _strict_ mode, all limitations imposed by RFC 9535
/// are implemented; if _strict_ mode is disabled, there is more flexibility
/// in filter expressions, e.g. also non-singular queries are supported.
///
struct JSONPathQueryParser {
  
  /// Is strict mode enabled?
  private let strict: Bool
  
  /// Was there trailing space (determined initially)?
  private let trailingSpace: Bool
  
  /// Next character to parse
  private var ch: Character?
  
  /// Remaining characters to parse
  private var iterator: IndexingIterator<[Character]>
  private(set) var position = 0
  private var nesting = 0
  private var segments = 0
  
  /// Collection of errors raised by functionality provided by enum `JSONPathQueryParser`.
  enum Error: LocalizedError, CustomStringConvertible {
    case expectedCharacter(Character, Character?)
    case illegalIntLiteral(String)
    case illegalNumberLiteral(String)
    case expectedStringLiteral(Character?)
    case malformedStringLiteralEscape(String)
    case notASingularQuery(JSONPathQuery)
    case expectedMemberName(Character?)
    case invalidSelectorCharacter(Character?)
    case invalidSegmentCharacter(Character?)
    case emptySegment
    case invalidQueryPrefix
    case invalidQuerySuffix(Character?)
    
    var description: String {
      switch self {
        case .expectedCharacter(let exp, let found):
          if let found {
            return "expected character \(exp), but found \(found)"
          } else {
            return "expected character \(exp), but reached end of input"
          }
        case .illegalIntLiteral(let str):
          return "cannot parse integer literal from '\(str)'"
        case .illegalNumberLiteral(let str):
          return "cannot parse number literal from '\(str)'"
        case .expectedStringLiteral(let ch):
          if let ch {
            return "expected string literal, but found character '\(ch)'"
          } else {
            return "expected string literal, but reached end of input"
          }
        case .malformedStringLiteralEscape(let str):
          return "string literal escape sequence following '\(str)' is malformed"
        case .notASingularQuery(let path):
          return "not a singular query: \(path)"
        case .expectedMemberName(let ch):
          if let ch {
            return "expected member name, but '\(ch)' is not a valid initial character"
          } else {
            return "expected member name, but reached end of input"
          }
        case .invalidSelectorCharacter(let ch):
          if let ch {
            return "unable to parse selector at character '\(ch)'"
          } else {
            return "invalid selector"
          }
        case .invalidSegmentCharacter(let ch):
          if let ch {
            return "unable to parse segment at character '\(ch)'"
          } else {
            return "invalid segment"
          }
        case .emptySegment:
          return "invalid empty segment"
        case .invalidQueryPrefix:
          return "invalid query start; must start with '$' or '@'"
        case .invalidQuerySuffix(let ch):
          if let ch {
            return "superfluous character '\(ch)' at end of query"
          } else {
            return "superfluous character at end of query"
          }
      }
    }
    
    var errorDescription: String? {
      return self.description
    }
    
    var failureReason: String? {
      switch self {
        case .expectedCharacter(_, _):
          return "parsing error"
        case .illegalIntLiteral(_), .illegalNumberLiteral(_):
          return "error parsing integer literal"
        case .expectedStringLiteral(_), .malformedStringLiteralEscape(_):
          return "error parsing string literal"
        case .notASingularQuery(_):
          return "error parsing singular query"
        case .expectedMemberName(_):
          return "error parsing member name"
        case .invalidSelectorCharacter(_):
          return "error parsing selector"
        case .invalidSegmentCharacter(_), .emptySegment:
          return "error parsing segment"
        case .invalidQueryPrefix, .invalidQuerySuffix(_):
          return "error parsing query"
      }
    }
  }
  
  /// Initializes a new parser for parsing `string`. Parser structs can only be used
  /// once for parsing the string given at initialization time.
  init(string: String, strict: Bool = true) {
    self.strict = strict
    switch string.last {
      case " ", "\t", "\n", "\r":
        self.trailingSpace = true
      default:
        self.trailingSpace = false
    }
    self.ch = nil
    self.iterator = string.unicodeScalars.map { Character(String($0)) }.makeIterator()
    self.next()
  }
  
  @discardableResult
  private mutating func next() -> Character? {
    if let ch = self.ch { self.position += String(ch).utf16.count }
    self.ch = self.iterator.next()
    return self.ch
  }
  
  @discardableResult
  private mutating func skipSpaces() -> Character? {
    while let ch = self.ch {
      switch ch {
        case " ", "\t", "\n", "\r":
          self.next()
        default:
          return ch
      }
    }
    return nil
  }
  
  @discardableResult
  private mutating func skipSpacesIfNonStrict() -> Character? {
    guard !self.strict else {
      return self.ch
    }
    while let ch = self.ch {
      switch ch {
        case " ", "\t", "\n", "\r":
          self.next()
        default:
          return ch
      }
    }
    return nil
  }
  
  @discardableResult
  private mutating func nextSkipSpaces() -> Character? {
    self.next()
    return self.skipSpaces()
  }
  
  @discardableResult
  private mutating func nextSkipSpacesIfNonStrict() -> Character? {
    self.next()
    return self.skipSpacesIfNonStrict()
  }
  
  private mutating func accept(_ ch: Character) throws {
    if case .some(ch) = self.ch {
      self.next()
    } else {
      throw Error.expectedCharacter(ch, self.ch)
    }
  }
  
  private var nextIsDigit: Bool {
    if let ch = self.ch, ch.isASCII, ch.isNumber {
      return true
    } else {
      return false
    }
  }
  
  private mutating func int() throws -> Int {
    var negative = false
    if self.ch == "-" {
      self.next()
      negative = true
    }
    var num = ""
    while self.nextIsDigit {
      num.append(self.ch!)
      self.next()
    }
    guard let res = Int(num),
          !self.strict || (num == "0" && !negative) || (num.first != "0" && res <= 9_007_199_254_740_991) else {
      throw Error.illegalIntLiteral(num)
    }
    return negative ? -res : res
  }
  
  private mutating func number(forceFloat: Bool = false) throws -> JSONPathQuery.Expression {
    var num = ""
    while self.nextIsDigit { num.append(self.ch!); self.next() }
    guard !num.isEmpty, num == "0" || num.first != "0" else { throw Error.illegalNumberLiteral(num) }
    if self.ch == "." {
      num.append("."); self.next()
      guard self.nextIsDigit else { throw Error.illegalNumberLiteral(num) }
      while self.nextIsDigit { num.append(self.ch!); self.next() }
    }
    if self.ch == "e" || self.ch == "E" {
      num.append(self.ch!); self.next()
      if self.ch == "-" || self.ch == "+" { num.append(self.ch!); self.next() }
      guard self.nextIsDigit else { throw Error.illegalNumberLiteral(num) }
      while self.nextIsDigit { num.append(self.ch!); self.next() }
    }
    return .number(num)
  }

  // Strict scalar decoding; never repair an invalid surrogate or normalize names.
  private mutating func string() throws -> String {
    guard let quote = self.ch, quote == "'" || quote == "\"" else { throw Error.expectedStringLiteral(self.ch) }
    self.next()
    var result = ""
    func hex(_ c: Character?) -> UInt32? { c.flatMap { UInt32(String($0), radix: 16) } }
    while let c = self.ch, c != quote {
      guard c.unicodeScalars.allSatisfy({ $0.value >= 32 }) else { throw Error.malformedStringLiteralEscape(result) }
      if c != "\\" { result.append(c); self.next(); continue }
      self.next()
      guard let escape = self.ch else { throw Error.malformedStringLiteralEscape(result) }
      self.next()
      switch escape {
      case "b": result.append("\u{8}")
      case "f": result.append("\u{c}")
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "t": result.append("\t")
      case "/", "\\": result.append(escape)
      case quote: result.append(escape)
      case "u":
        func unit(_ parser: inout JSONPathQueryParser) throws -> UInt32 {
          var n: UInt32 = 0
          for _ in 0..<4 {
            guard let h = hex(parser.ch) else { throw Error.malformedStringLiteralEscape(result) }
            n = n * 16 + h; parser.next()
          }
          return n
        }
        let high = try unit(&self)
        var scalar = high
        if (0xD800...0xDBFF).contains(high) {
          try self.accept("\\"); try self.accept("u")
          let low = try unit(&self)
          guard (0xDC00...0xDFFF).contains(low) else { throw Error.malformedStringLiteralEscape(result) }
          scalar = 0x10000 + (high - 0xD800) * 1024 + low - 0xDC00
        }
        guard let value = Unicode.Scalar(scalar) else { throw Error.malformedStringLiteralEscape(result) }
        result.unicodeScalars.append(value)
      default: throw Error.malformedStringLiteralEscape(result)
      }
    }
    try self.accept(quote)
    return result
  }

  private mutating func memberName() throws -> String {
    guard let ch = self.ch else {
      throw Error.expectedMemberName(nil)
    }
    var scalars = ch.unicodeScalars
    guard ch.isLetter
           || ch == "_"
           || scalars.allSatisfy({ c in c.value >= 0x80 && c.value <= 0xD7FF })
           || scalars.allSatisfy({ c in c.value >= 0xE000 && c.value <= 0x10FFFF }) else {
      throw Error.expectedMemberName(ch)
    }
    var member = String(ch)
    while let ch = self.next() {
      scalars = ch.unicodeScalars
      guard ch.isLetter
              || ch.isHexDigit
              || ch == "_"
              || scalars.allSatisfy({ c in c.value >= 0x80 && c.value <= 0xD7FF })
              || scalars.allSatisfy({ c in c.value >= 0xE000 && c.value <= 0x10FFFF }) else {
        return member
      }
      member.append(ch)
    }
    return member
  }
  
  private mutating func functionName() throws -> String {
    return try self.memberName()
  }
  
  private mutating func expression() throws -> JSONPathQuery.Expression {
    var exprs: [JSONPathQuery.Expression] = []
    var opers: [JSONPathQuery.BinaryOperator] = []
    func reduce() throws {
      let rhs = exprs.removeLast()
      if self.strict, opers.last != .and, opers.last != .or, case .query(let path) = rhs {
        throw Error.notASingularQuery(path)
      }
      let lhs = exprs.removeLast()
      if self.strict, opers.last != .and, opers.last != .or, case .query(let path) = lhs {
        throw Error.notASingularQuery(path)
      }
      exprs.append(.operation(lhs, opers.removeLast(), rhs))
    }
    func push(op: JSONPathQuery.BinaryOperator, rhs: JSONPathQuery.Expression) throws {
      while let top = opers.last, top.precedence >= op.precedence {
        try reduce()
      }
      opers.append(op)
      exprs.append(rhs)
    }
    exprs.append(try self.operand())
    loop: while let ch = self.skipSpaces() {
      switch ch {
        case "=":
          self.next()
          try self.accept("=")
          self.skipSpaces()
          try push(op: .equals, rhs: try self.operand())
        case "!":
          self.next()
          try self.accept("=")
          self.skipSpaces()
          try push(op: .notEquals, rhs: try self.operand())
        case "<":
          if let ch = self.next(), ch == "=" {
            self.next()
            self.skipSpaces()
            try push(op: .lessThanEquals, rhs: try self.operand())
          } else {
            self.skipSpaces()
            try push(op: .lessThan, rhs: try self.operand())
          }
        case ">":
          if let ch = self.next(), ch == "=" {
            self.next()
            self.skipSpaces()
            try push(op: .greaterThanEquals, rhs: try self.operand())
          } else {
            self.skipSpaces()
            try push(op: .greaterThan, rhs: try self.operand())
          }
        case "|":
          self.next()
          try self.accept("|")
          self.skipSpaces()
          try push(op: .or, rhs: try self.operand())
        case "&":
          self.next()
          try self.accept("&")
          self.skipSpaces()
          try push(op: .and, rhs: try self.operand())
        case "+":
          throw Error.invalidSelectorCharacter(ch)
        case "-":
          throw Error.invalidSelectorCharacter(ch)
        case "*":
          throw Error.invalidSelectorCharacter(ch)
        case "/":
          throw Error.invalidSelectorCharacter(ch)
        default:
          break loop
      }
    }
    while !opers.isEmpty {
      try reduce()
    }
    return exprs.removeLast()
  }
  
  private mutating func operand() throws -> JSONPathQuery.Expression {
    nesting += 1
    defer { nesting -= 1 }
    guard nesting <= 64 else { throw JSONPathFailure.limit("Query nesting exceeds 64 levels.") }
    switch self.ch {
    case "!":
      self.nextSkipSpaces()
      return .prefix(.not, try self.atomic())
    case "-":
      self.next()
      guard self.nextIsDigit else { throw Error.illegalNumberLiteral("-") }
      guard case .number(let text) = try self.number() else { throw Error.illegalNumberLiteral("-") }
      return .number("-" + text)
    default: return try self.atomic()
    }
  }

  private mutating func atomic() throws -> JSONPathQuery.Expression {
    switch self.ch {
      case "'", "\"":
        return .string(try self.string())
      case "$", "@":
        let path = try self.absolutePath()
        return path.isSingular ? .singularQuery(path) : .query(path)
      case "(":
        self.nextSkipSpaces()
        let expr = try self.expression()
        self.skipSpaces()
        try self.accept(")")
        return expr
      case "1", "2", "3", "4", "5", "6", "7", "8", "9":
        return try self.number()
      case "0":
        guard self.strict else {
          return try self.number()
        }
        return try self.number()
      default:
        let ident = try self.functionName()
        switch ident {
          case "null":
            return .null
          case "true":
            return .true
          case "false":
            return .false
          default:
            if let ch = self.skipSpacesIfNonStrict(), ch == "(" {
              var arguments: [JSONPathQuery.Expression] = []
              if let ch = self.nextSkipSpaces(), ch != ")" {
                arguments.append(try self.expression())
              }
              while let ch = self.skipSpaces(), ch == "," {
                self.nextSkipSpaces()
                arguments.append(try self.expression())
              }
              try self.accept(")")
              return .call(ident, arguments)
            } else {
              return .variable(ident)
            }
        }
    }
  }
  
  private mutating func selector() throws -> JSONPathQuery.Selector {
    guard let ch = self.ch else {
      throw Error.invalidSelectorCharacter(nil)
    }
    switch ch {
      case "*":
        self.next()
        return .wildcard
      case "'", "\"":
        return .member(try self.string())
      case ":", "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
        let start: Int? = ch == ":" ? nil : try self.int()
        self.skipSpaces()
        if self.ch == ":" {
          self.nextSkipSpaces()
          let end = self.ch == "-" || self.nextIsDigit ? try self.int() : nil
          self.skipSpaces()
          if self.ch == ":", let ch = self.nextSkipSpaces() {
            let step = ch == "-" || self.nextIsDigit ? try self.int() : nil
            return .slice(start, end, step)
          } else {
            return .slice(start, end, nil)
          }
        } else if let n = start {
          return .index(n)
        } else {
          throw Error.invalidSelectorCharacter(self.ch)
        }
      case "?":
        self.nextSkipSpaces()
        let expr = try self.expression()
        return .filter(expr)
      default:
        throw Error.invalidSelectorCharacter(ch)
    }
  }
  
  private mutating func segment() throws -> [JSONPathQuery.Selector] {
    switch self.ch {
      case .none:
        throw Error.invalidSegmentCharacter(self.ch)
      case "*":
        self.next()
        return [.wildcard]
      case "[":
        guard let ch = self.nextSkipSpaces() else {
          throw Error.invalidSegmentCharacter("[")
        }
        guard ch != "]" else {
          self.next()
          guard self.strict else {
            return []
          }
          throw Error.emptySegment
        }
        var segment: [JSONPathQuery.Selector] = []
        segment.append(try self.selector())
        while let ch = self.skipSpaces(), ch != "]" {
          try self.accept(",")
          self.skipSpaces()
          segment.append(try self.selector())
        }
        try self.accept("]")
        return segment
      default:
        return [.member(try self.memberName())]
    }
  }
  
  private mutating func childSegment() throws -> [JSONPathQuery.Selector] {
    switch self.ch {
      case .none:
        throw Error.invalidSegmentCharacter(self.ch)
      case "*":
        self.next()
        return [.wildcard]
      default:
        return [.member(try self.memberName())]
    }
  }
  
  private mutating func relativePath(to root: JSONPathQuery) throws -> JSONPathQuery {
    var path = root
    while let ch = self.skipSpaces() {
      switch ch {
        case ".":
          segments += 1
          guard segments <= 256 else { throw JSONPathFailure.limit("Query exceeds 256 segments.") }
          if self.nextSkipSpacesIfNonStrict() == "." {
            self.nextSkipSpacesIfNonStrict()
            path = .select(path, .descendants(try self.segment()))
          } else {
            path = .select(path, .children(try self.childSegment()))
          }
        case "[":
          segments += 1
          guard segments <= 256 else { throw JSONPathFailure.limit("Query exceeds 256 segments.") }
          path = .select(path, .children(try self.segment()))
        default:
          return path
      }
    }
    return path
  }
  
  private mutating func absolutePath() throws -> JSONPathQuery {
    switch self.ch {
      case "$":
        self.next()
        return try self.relativePath(to: .self)
      case "@":
        self.next()
        return try self.relativePath(to: .current)
      default:
        throw Error.invalidQueryPrefix
    }
  }
  
  /// Parses the string provided in the initializer. Parameter `ignoreRemaining` determines
  /// if trailing whitespace yields an error in strict mode or not.
  mutating func parse(ignoreRemaining: Bool = false) throws -> JSONPathQuery {
    if !self.strict {
      self.skipSpaces()
    }
    try self.accept("$")
    let res = try self.relativePath(to: .self)
    guard ignoreRemaining
            || (self.strict && self.ch == nil && !self.trailingSpace)
            || (!self.strict && self.skipSpaces() == nil) else {
      throw Error.invalidQuerySuffix(self.ch)
    }
    return res
  }
}
