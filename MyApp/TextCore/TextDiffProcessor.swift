import Foundation

struct TextDiffOptions: Equatable, Codable, Sendable {
  var comparison = TextComparisonOptions(), ignoreEndings = false
}
struct TextDiffRow: Identifiable, Sendable {
  let id: Int, left: Int?, right: Int?
  var kind: String
  var leftPreview: String, rightPreview: String
  var leftInline: [NSRange] = [], rightInline: [NSRange] = []
}
struct TextDiffResult: Sendable {
  let before: TextSnapshot, after: TextSnapshot, rows: [TextDiffRow], limited: Bool, exact: Bool
  var changed: [Int] { rows.indices.filter { rows[$0].kind != "Equal" } }
  func patch() throws -> String {
    guard exact, !before.lines.contains(where: { $0.ending == "\r" }),
      !after.lines.contains(where: { $0.ending == "\r" })
    else {
      throw TextFailure.invalid(
        "Unified patch requires exact comparison and LF/CRLF. Copy the readable report instead.")
    }
    if changed.isEmpty { return "" }
    var out =
      "--- before\n+++ after\n@@ -\(before.lines.isEmpty ? 0:1),\(before.lines.count) +\(after.lines.isEmpty ? 0:1),\(after.lines.count) @@\n"
    func append(_ document: TextSnapshot, _ index: Int, _ prefix: String) {
      let l = document.lines[index]
      out += prefix + document.text(l) + (l.ending == "\r\n" ? "\r\n" : "\n")
      if l.ending.isEmpty { out += "\\ No newline at end of file\n" }
    }
    for row in rows {
      if row.kind == "Equal", let l = row.left {
        append(before, l, " ")
      } else {
        if let l = row.left { append(before, l, "-") }
        if let r = row.right { append(after, r, "+") }
      }
    }
    try TextBounds.check(out, max: TextBounds.output)
    return out
  }
  func report() throws -> String {
    var output = ""
    var units = 0
    for (i, row) in rows.enumerated() {
      try TextBounds.checkpoint(i)
      let a = row.left.map { before.text(before.lines[$0]) } ?? ""
      let b = row.right.map { after.text(after.lines[$0]) } ?? ""
      let block =
        "\(row.kind) \(row.left.map{String($0+1)} ?? "–") → \(row.right.map{String($0+1)} ?? "–")\n− \(a)\n+ \(b)\n"
      units += block.utf16.count
      guard units <= TextBounds.output else {
        throw TextFailure.resource(
          "Report output limit reached; use Unified Patch for exact comparison.")
      }
      output += block
    }
    return output
  }

}
enum TextDiffProcessor {
  struct Edit { let left: Int?, right: Int? }
  final class Engine {
    let a: [Data], b: [Data], deadline: ContinuousClock.Instant
    var steps = 0, limited = false, edits: [Edit] = []
    let maximum: Int
    init(_ a: [Data], _ b: [Data], maximum: Int = 20_000_000) {
      self.a = a
      self.b = b
      self.maximum = maximum
      deadline = ContinuousClock.now.advanced(by: .seconds(2))
    }
    func tick() throws -> Bool {
      steps += 1
      if steps & 1023 == 0 {
        try Task.checkCancellation()
        if .now > deadline { limited = true }
      }
      if steps > maximum { limited = true }
      return !limited
    }
    func coarse(_ a: Range<Int>, _ b: Range<Int>) {
      limited = true
      edits.append(contentsOf: a.map { Edit(left: $0, right: nil) })
      edits.append(contentsOf: b.map { Edit(left: nil, right: $0) })
    }
    func run(_ aa: Range<Int>, _ bb: Range<Int>, depth: Int = 0) throws {
      var l = aa.lowerBound
      var r = bb.lowerBound
      var ae = aa.upperBound
      var be = bb.upperBound
      while l < ae && r < be && a[l] == b[r] {
        try Task.checkCancellation()
        edits.append(.init(left: l, right: r))
        l += 1
        r += 1
      }
      var suffix: [Edit] = []
      while l < ae && r < be && a[ae - 1] == b[be - 1] {
        try Task.checkCancellation()
        ae -= 1
        be -= 1
        suffix.append(.init(left: ae, right: be))
      }
      defer { edits.append(contentsOf: suffix.reversed()) }
      if l == ae {
        edits.append(contentsOf: (r..<be).map { .init(left: nil, right: $0) })
        return
      }
      if r == be {
        edits.append(contentsOf: (l..<ae).map { .init(left: $0, right: nil) })
        return
      }
      guard depth < 128, try tick() else {
        coarse(l..<ae, r..<be)
        return
      }
      guard let (x, y) = try bisect(l..<ae, r..<be), !(x == l && y == r), !(x == ae && y == be)
      else {
        coarse(l..<ae, r..<be)
        return
      }
      try run(l..<x, r..<y, depth: depth + 1)
      try run(x..<ae, y..<be, depth: depth + 1)
    }
    func bisect(_ aa: Range<Int>, _ bb: Range<Int>) throws -> (Int, Int)? {
      let n = aa.count
      let m = bb.count
      let maxD = (n + m + 1) / 2
      let off = maxD + 1
      let len = 2 * maxD + 3
      let delta = n - m
      let odd = (n - m) % 2 != 0
      var f = Array(repeating: -1, count: len)
      var v = f
      f[off + 1] = 0
      v[off + 1] = 0
      for d in 0...maxD {
        for k in stride(from: -d, through: d, by: 2) {
          guard try tick() else { return nil }
          let at = off + k
          var x = (k == -d || (k != d && f[at - 1] < f[at + 1])) ? f[at + 1] : f[at - 1] + 1
          var y = x - k
          while x < n && y < m && x >= 0 && y >= 0 && a[aa.lowerBound + x] == b[bb.lowerBound + y] {
            x += 1
            y += 1
            guard try tick() else { return nil }
          }
          f[at] = x
          let rev = off + delta - k
          if odd, rev >= 0, rev < len, v[rev] >= 0, x >= n - v[rev], x >= 0, x <= n, y >= 0, y <= m
          {
            return (aa.lowerBound + x, bb.lowerBound + y)
          }
        }
        for k in stride(from: -d, through: d, by: 2) {
          guard try tick() else { return nil }
          let at = off + k
          var x = (k == -d || (k != d && v[at - 1] < v[at + 1])) ? v[at + 1] : v[at - 1] + 1
          var y = x - k
          while x < n && y < m && x >= 0 && y >= 0
            && a[aa.upperBound - x - 1] == b[bb.upperBound - y - 1]
          {
            x += 1
            y += 1
            guard try tick() else { return nil }
          }
          v[at] = x
          let forward = off + delta - k
          if !odd, forward >= 0, forward < len, f[forward] >= 0, f[forward] >= n - x {
            let fx = f[forward]
            let fy = fx - (delta - k)
            if fx >= 0 && fx <= n && fy >= 0 && fy <= m {
              return (aa.lowerBound + fx, bb.lowerBound + fy)
            }
          }
        }
      }
      return nil
    }
  }
  static func process(_ a: String, _ b: String, options o: TextDiffOptions) throws -> TextArtifact {
    try TextBounds.check(a)
    try TextBounds.check(b)
    let before = TextSnapshot(a)
    let after = TextSnapshot(b)
    func keys(_ snapshot: TextSnapshot) throws -> [Data] {
      try snapshot.lines.enumerated().map { i, l in
        try TextBounds.checkpoint(i)
        var key = try o.comparison.key(snapshot.text(l))
        if !o.ignoreEndings {
          key.append(0)
          key.append(contentsOf: l.ending.utf8)
        }
        return key
      }
    }
    let left = try keys(before)
    let right = try keys(after)
    let engine = Engine(left, right)
    // Unique common lines provide patience anchors, in increasing subsequence order.
    var positions: [Data: Int] = [:]
    var counts: [Data: Int] = [:]
    var leftCounts: [Data: Int] = [:]
    for (i, key) in right.enumerated() {
      counts[key, default: 0] += 1
      positions[key] = i
    }
    for key in left { leftCounts[key, default: 0] += 1 }
    let pairs = left.enumerated().compactMap { entry -> (Int, Int)? in
      let (i, key) = entry
      guard leftCounts[key] == 1, counts[key] == 1, let j = positions[key] else { return nil }
      return (i, j)
    }
    var tails: [Int] = []
    var previous = Array(repeating: -1, count: pairs.count)
    for (i, p) in pairs.enumerated() {
      try TextBounds.checkpoint(i)
      var lo = 0
      var hi = tails.count
      while lo < hi {
        let m = (lo + hi) / 2
        if pairs[tails[m]].1 < p.1 { lo = m + 1 } else { hi = m }
      }
      if lo > 0 { previous[i] = tails[lo - 1] }
      if lo == tails.count { tails.append(i) } else { tails[lo] = i }
    }
    var anchors: [(Int, Int)] = []
    var idx = tails.last ?? -1
    while idx >= 0 {
      anchors.append(pairs[idx])
      idx = previous[idx]
    }
    anchors.reverse()
    var x = 0
    var y = 0
    for anchor in anchors + [(left.count, right.count)] {
      try engine.run(x..<anchor.0, y..<anchor.1)
      if anchor.0 < left.count { engine.edits.append(.init(left: anchor.0, right: anchor.1)) }
      x = anchor.0 + 1
      y = anchor.1 + 1
    }
    var rows: [TextDiffRow] = []
    var deletes: [Int] = []
    var inserts: [Int] = []
    func row(_ l: Int?, _ r: Int?, kind: String) {
      rows.append(
        .init(
          id: rows.count, left: l, right: r, kind: kind,
          leftPreview: l.map { TextDisplay.safe(before.text(before.lines[$0])) } ?? "",
          rightPreview: r.map { TextDisplay.safe(after.text(after.lines[$0])) } ?? ""))
    }
    func flush() {
      for i in 0..<max(deletes.count, inserts.count) {
        let l = i < deletes.count ? deletes[i] : nil
        let r = i < inserts.count ? inserts[i] : nil
        row(l, r, kind: l == nil ? "Added" : r == nil ? "Removed" : "Changed")
      }
      deletes = []
      inserts = []
    }
    for edit in engine.edits {
      if let l = edit.left, let r = edit.right {
        flush()
        row(l, r, kind: "Equal")
      } else if let l = edit.left {
        deletes.append(l)
      } else if let r = edit.right {
        inserts.append(r)
      }
    }
    flush()
    let inlineDeadline = ContinuousClock.now.advanced(by: .seconds(1))
    for i in rows.indices where rows[i].kind == "Changed" {
      if ContinuousClock.now > inlineDeadline { break }
      try TextBounds.checkpoint(i)
      let l = Array(before.text(before.lines[rows[i].left!]))
      let r = Array(after.text(after.lines[rows[i].right!]))
      guard l.count <= 4096, r.count <= 4096,
        rows[i].leftPreview.utf16.elementsEqual(String(l).utf16),
        rows[i].rightPreview.utf16.elementsEqual(String(r).utf16)
      else { continue }
      let inline = Engine(
        l.map { Data(String($0).utf8) }, r.map { Data(String($0).utf8) }, maximum: 200000)
      try inline.run(l.indices, r.indices)
      var offsetsL = [0]
      var offsetsR = [0]
      for c in l { offsetsL.append(offsetsL.last! + c.utf16.count) }
      for c in r { offsetsR.append(offsetsR.last! + c.utf16.count) }
      for e in inline.edits {
        if e.right == nil, let n = e.left {
          rows[i].leftInline.append(
            .init(location: offsetsL[n], length: offsetsL[n + 1] - offsetsL[n]))
        }
        if e.left == nil, let n = e.right {
          rows[i].rightInline.append(
            .init(location: offsetsR[n], length: offsetsR[n + 1] - offsetsR[n]))
        }
      }
    }
    let exact =
      !o.ignoreEndings && !o.comparison.ignoreCase && !o.comparison.trim
      && !o.comparison.ignoreSpaces
    let result = TextDiffResult(
      before: before, after: after, rows: rows, limited: engine.limited, exact: exact)
    let count = result.changed.count
    var notes: [String] = []
    if engine.limited {
      notes.append(
        "Detailed comparison limited. Coarse changed blocks preserve all source content.")
    }
    if !exact { notes.append("Comparison uses ignore options; source text is unchanged.") }
    return .init(
      message: count == 0
        ? (a.utf16.elementsEqual(b.utf16) ? "Identical" : "Equivalent under selected options")
        : "\(count) changed rows", notes: notes, diff: result)
  }
}
