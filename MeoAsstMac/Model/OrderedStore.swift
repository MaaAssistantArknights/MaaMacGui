//
//  OrderedStore.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct OrderedStore<Value> {
    private var store = [UUID: Value]()
    private var order = [UUID]()
}

extension OrderedStore: RandomAccessCollection {
    typealias Element = Value

    var startIndex: Int {
        0
    }

    var endIndex: Int {
        order.count
    }

    func index(before i: Int) -> Int {
        i - 1
    }

    func index(after i: Int) -> Int {
        i + 1
    }
}

extension OrderedStore: MutableCollection {
    subscript(position: Int) -> Value {
        get {
            store[order[position]]!
        } set {
            store[order[position]] = newValue
        }
    }
}

extension OrderedStore: RangeReplaceableCollection {
    mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C: Collection, Value == C.Element {
        order[subrange].forEach { store.removeValue(forKey: $0) }

        let newRange = newElements.map { newElement in
            let id = UUID()
            store[id] = newElement
            return id
        }

        order.replaceSubrange(subrange, with: newRange)
    }
}

extension OrderedStore: Codable where Value: Codable {}
extension OrderedStore: Equatable where Value: Equatable {}
extension OrderedStore: Hashable where Value: Hashable {}

extension OrderedStore {
    subscript(id: UUID) -> Value? {
        get { store[id] } set {
            store[id] = newValue
        }
    }

    var keys: [UUID] {
        get { order } set {
            order = newValue
        }
    }

    var values: [Value] {
        order.map { store[$0]! }
    }

    var items: [(id: UUID, item: Value)] {
        order.map { ($0, store[$0]!) }
    }

    init(_ items: [Value]) {
        append(contentsOf: items)
    }

    mutating func remove(id: UUID) {
        order.removeAll { $0 == id }
        store.removeValue(forKey: id)
    }

    func firstIndex(id: UUID) -> Int? {
        order.firstIndex(of: id)
    }
}
