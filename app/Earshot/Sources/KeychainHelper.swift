import Foundation
import os.log
import Security

/// macOS Keychain-based secret storage using Security.framework.
/// Same API surface as the previous file-based implementation.
enum KeychainHelper {
    private static let service = AppPaths.logSubsystem
    /// The service before the rename to Earshot; `read` moves an item found
    /// only there to `service`.
    private static let legacyService = "com.meetingtranscriber"
    private static let logger = Logger(subsystem: AppPaths.logSubsystem, category: "KeychainHelper")

    private static func baseQuery(for key: String, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    /// Store or update a value in the Keychain.
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            if updateStatus != errSecSuccess {
                logger.error("Failed to update \(key): \(updateStatus)")
            }
        } else if addStatus != errSecSuccess {
            logger.error("Failed to save \(key): \(addStatus)")
        }
    }

    /// Read a value from the Keychain. Returns `nil` if not found.
    static func read(key: String) -> String? {
        if let value = read(key: key, service: service) { return value }
        guard let legacy = read(key: key, service: legacyService) else { return nil }
        save(key: key, value: legacy)
        SecItemDelete(baseQuery(for: key, service: legacyService) as CFDictionary)
        return legacy
    }

    private static func read(key: String, service: String) -> String? {
        var query = baseQuery(for: key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    static func delete(key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Check whether a value exists in the Keychain.
    static func exists(key: String) -> Bool {
        read(key: key) != nil
    }
}
