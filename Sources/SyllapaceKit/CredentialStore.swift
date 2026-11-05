import Foundation
import Security

public enum CredentialStore {
    public static let canvasToken = "canvas-token"
    public static let modelKey = "model-key"
    private static let service = "app.syllapace.credentials"
    /// Security.framework can wait for a system authorization dialog. Keep that
    /// blocking operation off the UI actor, including when the user cancels.
    public static func readAsync(_ account: String) async throws -> String? {
        try await offMain { try read(account) }
    }
    public static func saveAsync(_ value: String, account: String) async throws {
        try await offMain { try save(value, account: account) }
    }
    public static func deleteAsync(_ account: String) async throws {
        try await offMain { try delete(account) }
    }
    private static func offMain<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler {
            let value = try await work.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            work.cancel()
        }
    }
    public static func read(_ account: String) throws -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return value
    }
    public static func save(_ value: String, account: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { try delete(account); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(base(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = base(account)
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    public static func delete(_ account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
public struct KeychainError: Error, LocalizedError, Sendable {
    public var status: OSStatus
    public var errorDescription: String? { L10n.format("Keychain access failed (%d). Unlock your keychain and try again.", status) }
}
