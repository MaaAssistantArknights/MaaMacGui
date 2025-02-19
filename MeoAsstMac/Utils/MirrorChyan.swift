//
//  MirrorChyan.swift
//  MAA
//
//  Created by hguandl on 2025/2/5.
//

import Foundation
import Security

public struct MirrorChyan: Sendable {
    private let rid: String
    private let cdk: String?
    private let userAgent = "com.hguandl.MeoAsstMac"

    public init(rid: String, cdk: String?) {
        self.rid = rid
        self.cdk = cdk
    }

    public init(rid: String) {
        self.init(rid: rid, cdk: Self.getCDK())
    }

    public struct Error: Swift.Error {
        public let code: Int
        public let msg: String
    }

    public struct Version: Decodable {
        public let version_name: String
        public let version_number: Int
        public let url: URL?
    }
}

private struct MirrorChyanResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T?

    func get() throws -> T {
        guard let data else {
            throw MirrorChyan.Error(code: code, msg: msg)
        }
        return data
    }
}

extension MirrorChyan {
    public func query(currentVersion: String? = nil) async throws -> Version {
        var queryItems = [URLQueryItem(name: "user_agent", value: userAgent)]
        if let currentVersion {
            queryItems.append(URLQueryItem(name: "current_version", value: currentVersion))
        }
        if let cdk {
            queryItems.append(URLQueryItem(name: "cdk", value: cdk))
        }

        var urlComps = URLComponents(string: "https://mirrorchyan.com/api/resources/\(rid)/latest")!
        if !queryItems.isEmpty {
            urlComps.queryItems = queryItems
        }

        let (data, _) = try await URLSession.shared.data(from: urlComps.url!)
        let response = try JSONDecoder().decode(MirrorChyanResponse<Version>.self, from: data)
        return try response.get()
    }
}

extension MirrorChyan {
    public static func getCDK() -> String? {
        let query = keychainQuery(merging: [
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ])

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }

        guard let existingItem = item as? [String: Any],
            let data = existingItem[kSecValueData as String] as? Data,
            let cdk = String(data: data, encoding: .utf8),
            !cdk.isEmpty
        else {
            return nil
        }
        return cdk
    }

    public static func setCDK(_ cdk: String) -> OSStatus {
        let query = keychainQuery()

        guard !cdk.isEmpty else {
            return SecItemDelete(query as CFDictionary)
        }

        let data = cdk.data(using: .utf8)!
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            return addCDK(data: data)
        }
        return status
    }

    private static func addCDK(data: Data) -> OSStatus {
        let query = keychainQuery(merging: [
            kSecValueData as String: data
        ])
        let status = SecItemAdd(query as CFDictionary, nil)
        return status
    }

    private static func keychainQuery(merging other: [String: Any] = [:]) -> [String: Any] {
        #if RELEASE
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "MAA MirrorChyan CDK",
            kSecAttrAccount as String: "mirrorchyan",
            kSecAttrAccessGroup as String: "29V29Y67P2.com.hguandl.MeoAsstMac",
            kSecAttrSynchronizable as String: true,
        ]
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "MAA MirrorChyan CDK",
            kSecAttrAccount as String: "mirrorchyan",
        ]
        #endif
        return query.merging(other, uniquingKeysWith: { $1 })
    }
}

extension MirrorChyan.Error: LocalizedError {
    public var errorDescription: String? {
        return self.msg
    }
}
