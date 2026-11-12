import Foundation

/// Flat tree projections preserve arena/preorder order. A linear merge supplies
/// native insert/delete indices without an expensive UI-thread diff or moves.
struct JSONTreeRowChanges: Sendable {
    let baseVersion: Int
    let removed: IndexSet
    let inserted: IndexSet
    var count: Int { removed.count + inserted.count }

    static func between(_ old: [Int], _ new: [Int], baseVersion: Int) throws -> Self {
        var removed = IndexSet(), inserted = IndexSet(), a = 0, b = 0
        while a < old.count || b < new.count {
            if (a + b) & 255 == 0 { try Task.checkCancellation() }
            if a == old.count { inserted.insert(integersIn: b..<new.count); break }
            if b == new.count { removed.insert(integersIn: a..<old.count); break }
            if old[a] == new[b] { a += 1; b += 1 }
            else if old[a] < new[b] { removed.insert(a); a += 1 }
            else { inserted.insert(b); b += 1 }
        }
        return Self(baseVersion: baseVersion, removed: removed, inserted: inserted)
    }
}
