import Foundation

struct ListComparisonOptions: Codable, Equatable, Sendable {
  var operation = "Intersection", multiset = false, ignoreEmpty = false,
    comparison = TextComparisonOptions(), ending = "\n", terminal = false
}
enum ListComparisonProcessor {
  static func process(_ a: String, _ b: String, options o: ListComparisonOptions) throws
    -> TextArtifact
  {
    try TextBounds.check(a)
    try TextBounds.check(b)
    let left = TextSnapshot(a)
    let right = TextSnapshot(b)
    func entries(_ d: TextSnapshot) throws -> [(TextLine, String, Data)] {
      try d.lines.enumerated().compactMap { i, l in
        try TextBounds.checkpoint(i)
        let s = d.text(l)
        let k = try o.comparison.key(s)
        return o.ignoreEmpty && k.isEmpty ? nil : (l, s, k)
      }
    }
    let aa = try entries(left)
    let bb = try entries(right)
    var ac: [Data: Int] = [:]
    var bc: [Data: Int] = [:]
    var aFirst: [Data: NSRange] = [:]
    var bFirst: [Data: NSRange] = [:]
    for e in aa {
      ac[e.2, default: 0] += 1
      if aFirst[e.2] == nil { aFirst[e.2] = e.0.range }
    }
    for e in bb {
      bc[e.2, default: 0] += 1
      if bFirst[e.2] == nil { bFirst[e.2] = e.0.range }
    }
    var selected: [(TextLine, String, Data, Bool)] = []
    var seen: [Data: Int] = [:]
    for (i, e) in aa.enumerated() {
      try TextBounds.checkpoint(i)
      let n = seen[e.2, default: 0]
      seen[e.2] = n + 1
      let keep: Bool
      switch o.operation {
      case "Intersection": keep = o.multiset ? n < bc[e.2, default: 0] : n == 0 && bc[e.2] != nil
      case "A only", "Symmetric difference":
        keep = o.multiset ? n >= bc[e.2, default: 0] : n == 0 && bc[e.2] == nil
      case "Union": keep = o.multiset || n == 0
      default: keep = false
      }
      if keep { selected.append((e.0, e.1, e.2, true)) }
    }
    seen = [:]
    for (i, e) in bb.enumerated() {
      try TextBounds.checkpoint(i)
      let n = seen[e.2, default: 0]
      seen[e.2] = n + 1
      let keep: Bool
      switch o.operation {
      case "B only", "Symmetric difference", "Union":
        keep = o.multiset ? n >= ac[e.2, default: 0] : n == 0 && ac[e.2] == nil
      default: keep = false
      }
      if keep { selected.append((e.0, e.1, e.2, false)) }
    }
    let out = TextDisplay.lines(selected.map { $0.1 }, ending: o.ending, terminal: o.terminal)
    try TextBounds.check(out, max: TextBounds.output)
    return .init(
      output: out,
      message:
        "\(selected.count) results · A \(aa.count) (\(ac.count) distinct) · B \(bb.count) (\(bc.count) distinct)",
      rows: selected.enumerated().map { i, e in
        .init(
          id: i, label: "Item \(i+1)", value: e.1.isEmpty ? "Empty item" : TextDisplay.safe(e.1),
          detail: "A count: \(ac[e.2,default:0]) · B count: \(bc[e.2,default:0])",
          left: e.3 ? e.0.range : aFirst[e.2], right: e.3 ? bFirst[e.2] : e.0.range)
      })
  }
}
struct LineSortOptions: Codable, Equatable, Sendable {
  var operation = "Sort & Deduplicate", order = "Ordinal", descending = false, last = false,
    ignoreEmpty = false, trimOutput = false
  var comparison = TextComparisonOptions(), locale = "en_US_POSIX", ending = "Preserve"
}
enum LineSortProcessor {
  static func process(_ source: String, options o: LineSortOptions) throws -> TextArtifact {
    try TextBounds.check(source)
    let d = TextSnapshot(source)
    var entries: [(Int, String, Data)] = []
    for (i, l) in d.lines.enumerated() {
      try TextBounds.checkpoint(i)
      let text = d.text(l)
      let key = try o.comparison.key(text)
      if !o.ignoreEmpty || !key.isEmpty { entries.append((i, text, key)) }
    }
    if o.operation != "Sort" {
      var representatives: [Data: Int] = [:]
      for e in entries { if o.last || representatives[e.2] == nil { representatives[e.2] = e.0 } }
      entries.removeAll { representatives[$0.2] != $0.0 }
    }
    if o.operation != "Deduplicate" {
      entries = try stableSort(entries) { a, b in
        let order: ComparisonResult
        if o.order == "Locale-aware" {
          order = String(decoding: a.2, as: UTF8.self).compare(
            String(decoding: b.2, as: UTF8.self), options: [], range: nil,
            locale: Locale(identifier: o.locale))
        } else if o.order == "Natural numeric" {
          order = natural(Array(a.2), Array(b.2))
        } else {
          order =
            a.2 == b.2
            ? .orderedSame
            : a.2.lexicographicallyPrecedes(b.2) ? .orderedAscending : .orderedDescending
        }
        return o.descending ? order == .orderedDescending : order == .orderedAscending
      }
    }
    let endings = Set(d.lines.map(\.ending).filter { !$0.isEmpty })
    let eol = o.ending == "Preserve" ? (endings.count == 1 ? endings.first! : "\n") : o.ending
    let result = TextDisplay.lines(
      entries.map { o.trimOutput ? $0.1.trimmingCharacters(in: .init(charactersIn: " \t")) : $0.1 },
      ending: eol, terminal: !(d.lines.last?.ending.isEmpty ?? true))
    try TextBounds.check(result, max: TextBounds.output)
    return .init(
      output: result, message: "\(d.lines.count) input records → \(entries.count) output records",
      notes: endings.count > 1 && o.ending == "Preserve"
        ? ["Mixed line endings normalized to LF."] : [])
  }
  static func stableSort<T>(_ input: [T], by less: (T, T) -> Bool) throws -> [T] {
    var a = input
    var b = input
    var width = 1
    var steps = 0
    while width < a.count {
      var start = 0
      while start < a.count {
        let mid = min(start + width, a.count)
        let end = min(start + 2 * width, a.count)
        var l = start
        var r = mid
        var k = start
        while k < end {
          steps += 1
          try TextBounds.checkpoint(steps)
          if l < mid && (r >= end || !less(a[r], a[l])) {
            b[k] = a[l]
            l += 1
          } else {
            b[k] = a[r]
            r += 1
          }
          k += 1
        }
        start = end
      }
      swap(&a, &b)
      width *= 2
    }
    return a
  }
  static func natural(_ a: [UInt8], _ b: [UInt8]) -> ComparisonResult {
    var i = 0
    var j = 0
    while i < a.count && j < b.count {
      if (48...57).contains(a[i]) && (48...57).contains(b[j]) {
        var x = i
        var y = j
        while x < a.count && (48...57).contains(a[x]) { x += 1 }
        while y < b.count && (48...57).contains(b[y]) { y += 1 }
        var aa = i
        var bb = j
        while aa < x && a[aa] == 48 { aa += 1 }
        while bb < y && b[bb] == 48 { bb += 1 }
        if x - aa != y - bb { return x - aa < y - bb ? .orderedAscending : .orderedDescending }
        if !a[aa..<x].elementsEqual(b[bb..<y]) {
          return a[aa..<x].lexicographicallyPrecedes(b[bb..<y])
            ? .orderedAscending : .orderedDescending
        }
        i = x
        j = y
      } else {
        if a[i] != b[j] { return a[i] < b[j] ? .orderedAscending : .orderedDescending }
        i += 1
        j += 1
      }
    }
    return i == a.count && j == b.count
      ? .orderedSame : i == a.count ? .orderedAscending : .orderedDescending
  }
}
