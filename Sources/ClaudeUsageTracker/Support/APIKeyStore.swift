import Foundation
import Security

/// The user's LiteLLM key in the login Keychain.
enum APIKeyStore {
    enum LoadResult: Equatable {
        case found(String)
        case notFound
        /// The user refused macOS's Keychain access prompt (or it could not be shown).
        case denied
    }

    private static let service = "com.claudeusage.tracker.litellm"
    private static let account = "litellm-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> LoadResult {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return .notFound }
            return .found(key)
        case errSecItemNotFound:
            return .notFound
        default:
            return .denied
        }
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrLabel as String] = "Claude Usage Tracker – LiteLLM key"
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // The old item may belong to a previous (differently signed) build; update it in place instead.
            status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
        }
        return status == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
