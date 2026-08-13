//
//  UserDefaults+KVO.swift
//  MAA
//
//  Created by hguandl on 2026/8/13.
//

import Foundation

extension UserDefaults {
    func observeKey<V>(of type: V.Type = V.self, _ key: String, mutation: @escaping (V?) -> Void)
        -> UserDefaultsObserver<V>
    {
        let observer = UserDefaultsObserver(mutation: mutation)
        addObserver(observer, forKeyPath: key, options: .new, context: nil)
        return observer
    }
}

final class UserDefaultsObserver<V>: NSObject {
    private let mutation: (V?) -> Void

    fileprivate init(mutation: @escaping (V?) -> Void) {
        self.mutation = mutation
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let change else { return }
        let newValue = change[.newKey] as? V
        mutation(newValue)
    }
}
