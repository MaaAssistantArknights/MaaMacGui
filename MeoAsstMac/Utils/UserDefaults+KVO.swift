//
//  UserDefaults+KVO.swift
//  MAA
//
//  Created by hguandl on 2026/8/13.
//

import Foundation
import os

@propertyWrapper struct Defaults<Value: Equatable & Sendable> {
    private let observer: UserDefaultsObserver<Value>
    var wrappedValue: Value {
        get {
            observer.value
        }
        nonmutating set {
            observer.value = newValue
        }
    }
}

extension Defaults {
    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == Bool {
        observer = .init(key: key, store: store, value: wrappedValue, converter: nil)
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == Int {
        observer = .init(key: key, store: store, value: wrappedValue, converter: nil)
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == Double {
        observer = .init(key: key, store: store, value: wrappedValue, converter: nil)
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == String {
        observer = .init(key: key, store: store, value: wrappedValue, converter: nil)
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == URL {
        let converter = UserDefaultsObserver.Converter { store, key in
            store.url(forKey: key)
        } write: { store, key, value in
            store.set(value, forKey: key)
        }
        observer = .init(key: key, store: store, value: wrappedValue, converter: converter)
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == Date {
        observer = .init(key: key, store: store, value: wrappedValue, converter: nil)
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value == Data {
        observer = .init(key: key, store: store, value: wrappedValue, converter: nil)
    }
}

extension Defaults where Value: RawRepresentable {
    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value.RawValue == Int {
        observer = .init(key: key, store: store, value: wrappedValue, converter: .init())
    }

    init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) where Value.RawValue == String {
        observer = .init(key: key, store: store, value: wrappedValue, converter: .init())
    }
}

extension Defaults where Value: ExpressibleByNilLiteral {
    init(_ key: String, store: UserDefaults = .standard) where Value == Bool? {
        observer = .init(key: key, store: store, value: nil, converter: nil)
    }

    init(_ key: String, store: UserDefaults = .standard) where Value == Int? {
        observer = .init(key: key, store: store, value: nil, converter: nil)
    }

    init(_ key: String, store: UserDefaults = .standard) where Value == Double? {
        observer = .init(key: key, store: store, value: nil, converter: nil)
    }

    init(_ key: String, store: UserDefaults = .standard) where Value == String? {
        observer = .init(key: key, store: store, value: nil, converter: nil)
    }

    init(_ key: String, store: UserDefaults = .standard) where Value == URL? {
        let converter = UserDefaultsObserver.Converter { store, key in
            store.url(forKey: key) as URL??
        } write: { store, key, value in
            store.set(value, forKey: key)
        }
        observer = .init(key: key, store: store, value: nil, converter: converter)
    }

    init(_ key: String, store: UserDefaults = .standard) where Value == Date? {
        observer = .init(key: key, store: store, value: nil, converter: nil)
    }

    init(_ key: String, store: UserDefaults = .standard) where Value == Data? {
        observer = .init(key: key, store: store, value: nil, converter: nil)
    }
}

extension Defaults {
    init<R: RawRepresentable>(_ key: String, store: UserDefaults = .standard) where Value == R?, R.RawValue == Int {
        observer = .init(key: key, store: store, value: nil, converter: .init(R.self))
    }

    init<R: RawRepresentable>(_ key: String, store: UserDefaults = .standard) where Value == R?, R.RawValue == String {
        observer = .init(key: key, store: store, value: nil, converter: .init(R.self))
    }
}

private final class UserDefaultsObserver<Value: Equatable & Sendable>: NSObject, nonisolated Observable {
    private let defaultValue: Value
    private let key: String
    private let store: UserDefaults

    var value: Value {
        get {
            registrar.access(self, keyPath: \.value)
            return _value.withLock { $0 }
        }
        set {
            guard _value.withLock({ $0 != newValue }) else { return }
            registrar.withMutation(of: self, keyPath: \.value) {
                _value.withLock { $0 = newValue }
            }
            if let converter {
                converter.write(store, key, newValue)
            } else {
                store.set(newValue, forKey: key)
            }
        }
    }

    private let _value: OSAllocatedUnfairLock<Value>

    struct Converter {
        let read: ((UserDefaults, String) -> Value?)
        let write: ((UserDefaults, String, Value) -> Void)
    }

    private let converter: Converter?

    init(key: String, store: UserDefaults, value: Value, converter: Converter?) {
        defaultValue = value
        self.key = key
        self.store = store
        if let converter {
            _value = .init(initialState: converter.read(store, key) ?? value)
        } else {
            _value = .init(initialState: store.object(forKey: key) as? Value ?? value)
        }
        self.converter = converter
        super.init()
        store.addObserver(self, forKeyPath: key, context: nil)
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard object as AnyObject? === store, keyPath == key else { return }
        let newValue: Value
        if let converter {
            newValue = converter.read(store, key) ?? defaultValue
        } else {
            newValue = store.object(forKey: key) as? Value ?? defaultValue
        }
        guard _value.withLock({ $0 != newValue }) else { return }
        registrar.withMutation(of: self, keyPath: \.value) {
            _value.withLock { $0 = newValue }
        }
    }

    deinit {
        store.removeObserver(self, forKeyPath: key)
    }

    private let registrar = ObservationRegistrar()
}

extension UserDefaultsObserver.Converter where Value: RawRepresentable {
    init() {
        self.init { store, key in
            guard let value = store.object(forKey: key) as? Value.RawValue else { return nil }
            return Value(rawValue: value)
        } write: { store, key, value in
            store.set(value.rawValue, forKey: key)
        }
    }
}

extension UserDefaultsObserver.Converter {
    init<R: RawRepresentable>(_ type: R.Type) where Value == R? {
        self.init { store, key in
            guard let value = store.object(forKey: key) as? R.RawValue else { return nil }
            return R(rawValue: value)
        } write: { store, key, value in
            store.set(value?.rawValue, forKey: key)
        }
    }
}
