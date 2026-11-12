import Foundation

// Narrow vendored-engine collection shim. String keys use decoded scalar identity,
// never Swift String's canonical equivalence. No user values go through Foundation DOM.
private struct ScalarHash<Key: Hashable>: Hashable {
    let value: Key
    static func == (a: Self, b: Self) -> Bool {
        if let a = a.value as? String, let b = b.value as? String { return a.utf8.elementsEqual(b.utf8) }
        return a.value == b.value
    }
    func hash(into h: inout Hasher) {
        if let value = value as? String { h.combine(Data(value.utf8)) } else { h.combine(value) }
    }
}

public struct OrderedDictionary<Key: Hashable, Value>: Sequence, ExpressibleByDictionaryLiteral {
    private var order: [Key] = []
    private var storage: [ScalarHash<Key>: Value] = [:]
    public init() {}
    public init(dictionaryLiteral elements: (Key, Value)...) { self.init(uniqueKeysWithValues: elements) }
    public init<S: Sequence>(uniqueKeysWithValues pairs: S) where S.Element == (Key, Value) {
        for (key, value) in pairs { self[key] = value }
    }
    public init<S: Sequence>(_ pairs: S, uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows where S.Element == (Key, Value) {
        for (key, value) in pairs { self[key] = try self[key].map { try combine($0, value) } ?? value }
    }
    public subscript(_ key: Key) -> Value? {
        get { storage[ScalarHash(value: key)] }
        set {
            let k = ScalarHash(value: key)
            if let newValue {
                if storage[k] == nil { order.append(key) }
                storage[k] = newValue
            } else {
                storage[k] = nil
                order.removeAll { ScalarHash(value: $0) == k }
            }
        }
    }
    @discardableResult public mutating func removeValue(forKey key: Key) -> Value? { let old = self[key]; self[key] = nil; return old }
    public var count: Int { order.count }
    public var isEmpty: Bool { order.isEmpty }
    public var keys: Keys { Keys(order: order, storage: storage) }
    public var values: [Value] { order.compactMap { self[$0] } }
    public mutating func reserveCapacity(_ n: Int) { order.reserveCapacity(n); storage.reserveCapacity(n) }
    public func makeIterator() -> AnyIterator<(key: Key, value: Value)> {
        var i = 0
        return AnyIterator { guard i < order.count else { return nil }; defer { i += 1 }; let key = order[i]; return (key, self[key]!) }
    }
    public func mapValues<T>(_ body: (Value) throws -> T) rethrows -> OrderedDictionary<Key, T> {
        var result = OrderedDictionary<Key, T>(); for (k, v) in self { result[k] = try body(v) }; return result
    }
    public func compactMapValues<T>(_ body: (Value) throws -> T?) rethrows -> OrderedDictionary<Key, T> {
        var result = OrderedDictionary<Key, T>(); for (k, v) in self { if let x = try body(v) { result[k] = x } }; return result
    }
    public struct Keys: RandomAccessCollection {
        public typealias Index = Int
        fileprivate let order: [Key]
        fileprivate let storage: [ScalarHash<Key>: Value]
        public var startIndex: Int { order.startIndex }
        public var endIndex: Int { order.endIndex }
        public subscript(_ i: Int) -> Key { order[i] }
        public func contains(_ key: Key) -> Bool { storage[ScalarHash(value: key)] != nil }
    }
}
extension OrderedDictionary: Sendable where Key: Sendable, Value: Sendable {}
extension ScalarHash: Sendable where Key: Sendable {}

public struct OrderedSet<Element: Hashable>: Sequence, ExpressibleByArrayLiteral {
    private var map = OrderedDictionary<Element, Bool>()
    public init() {}
    public init(arrayLiteral elements: Element...) { for x in elements { append(x) } }
    public init<S: Sequence>(_ elements: S) where S.Element == Element { for x in elements { append(x) } }
    public mutating func append(_ x: Element) { map[x] = true }
    public func contains(_ x: Element) -> Bool { map[x] != nil }
    public var count: Int { map.count }
    public var isEmpty: Bool { map.isEmpty }
    public func makeIterator() -> IndexingIterator<[Element]> { Array(map.keys).makeIterator() }
    public func union(_ other: Self) -> Self { var result = self; result.formUnion(other); return result }
    public mutating func formUnion<S: Sequence>(_ other: S) where S.Element == Element { for x in other { append(x) } }
}
extension OrderedSet: Sendable where Element: Sendable {}
extension OrderedDictionary: Equatable where Value: Equatable {
    public static func == (a: Self, b: Self) -> Bool {
        a.count == b.count && a.allSatisfy { b[$0.key] == $0.value }
    }
}
extension OrderedDictionary {
    public func merging(_ other: Self, uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows -> Self {
        var result = self
        for (key, value) in other { result[key] = try result[key].map { try combine($0, value) } ?? value }
        return result
    }
}
extension OrderedSet: Equatable {
    public static func == (a: Self, b: Self) -> Bool { a.map == b.map }
}
