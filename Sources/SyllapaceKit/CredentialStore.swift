import Foundation
import Security

public enum CredentialStore {
    public static let canvasToken = "canvas-token"
    public static let modelKey = "model-key"
    public static let localURL: URL = {
        if let isolated = ProcessInfo.processInfo.environment["APP_STORE"] {
            return URL(fileURLWithPath: isolated).deletingLastPathComponent().appendingPathComponent("Credentials/credentials.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Syllapace/Credentials/credentials.json")
    }()
    private static let repository = CredentialRepository(url: localURL)
    public static func readAsync(_ account: String) async throws -> String? { try await repository.read(account) }
    public static func saveAsync(_ value: String, account: String) async throws { try await repository.save(value, account: account) }
    public static func deleteAsync(_ account: String) async throws { try await repository.delete(account) }
    public static func storage() async throws -> CredentialStorage { try await repository.storage() }
    public static func setStorage(_ value: CredentialStorage) async throws { try await repository.setStorage(value) }
    public static func importFromKeychain() async throws -> Int { try await repository.importFromKeychain() }
}

struct SystemCredentialKeychain: CredentialKeychain {
    private let service = "app.syllapace.credentials"
    func accounts() throws -> [String] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let items = result as? [[String: Any]] else { throw KeychainError(status: errSecDecode) }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
    func read(_ account: String) throws -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw KeychainError(status: errSecDecode) }
        return value
    }
    func save(_ value: String, account: String) throws {
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base(account)
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    func delete(_ account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
public struct KeychainError: Error, LocalizedError, Sendable {
    public var status: OSStatus
    public var errorDescription: String? {
        if status == errSecUserCanceled { return L10n.string("Keychain access was cancelled. Your storage selection was not changed.") }
        return L10n.format("Keychain access failed (%d). Unlock your keychain and try again.", status)
    }
}
