import Foundation

public enum CredentialStorage: String, Codable, CaseIterable, Sendable {
    case local, keychain
    public var label: String { self == .local ? "Local file" : "macOS Keychain" }
}

protocol CredentialKeychain: Sendable {
    func accounts() throws -> [String]
    func read(_ account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(_ account: String) throws
}

/// Actor isolation keeps blocking Security.framework calls off the UI actor and
/// serializes concurrent credential requests. It never awaits inside a transaction.
public actor CredentialRepository {
    private let file: LocalCredentialFile
    private let keychain: any CredentialKeychain
    private var cachedRevision: UUID?
    private var cache: [String: String] = [:]

    public init(url: URL) { file = LocalCredentialFile(url: url); keychain = SystemCredentialKeychain() }
    init(url: URL, keychain: any CredentialKeychain) { file = LocalCredentialFile(url: url); self.keychain = keychain }
    nonisolated static func validAccount(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 4096 }
    nonisolated static func validValue(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 16_384 }

    public func storage() throws -> CredentialStorage { try transaction { $0.storage } }
    public func read(_ account: String) throws -> String? {
        guard Self.validAccount(account) else { throw CredentialStorageError.invalidValue }
        return try transaction { document in
            guard !document.excludedImports.contains(account) else { return nil }
            if document.storage == .local { return document.values[account] }
            if let value = cache[account] { return value }
            let value = try keychain.read(account)
            cache[account] = value
            return value
        }
    }
    public func save(_ value: String, account: String) throws {
        guard Self.validAccount(account) else { throw CredentialStorageError.invalidValue }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try delete(account); return }
        guard Self.validValue(value) else { throw CredentialStorageError.invalidValue }
        try transaction { document in
            if document.storage == .local { document.values[account] = value }
            else { try keychain.save(value, account: account) }
            document.excludedImports.remove(account)
            document.revision = UUID()
        }
        cache.removeValue(forKey: account)
    }
    public func delete(_ account: String) throws {
        guard Self.validAccount(account) else { throw CredentialStorageError.invalidValue }
        try transaction { document in
            if document.storage == .local { document.values.removeValue(forKey: account) }
            else { try keychain.delete(account) }
            // A later bulk import must not resurrect an explicitly cleared key.
            document.excludedImports.insert(account)
            document.revision = UUID()
        }
        cache.removeValue(forKey: account)
    }
    public func setStorage(_ target: CredentialStorage) throws {
        try transaction { document in
            guard document.storage != target else { return }
            if target == .keychain {
                // Keep every local value until all writes succeed and the new
                // envelope is committed. A denied prompt never loses a secret.
                for account in document.values.keys.sorted() {
                    try keychain.save(document.values[account]!, account: account)
                }
            }
            document.values = [:]
            document.storage = target
            // Switching to Local is always possible without accessing Keychain.
            // Importing old keys is a separate, explicitly requested operation.
        }
        cache = [:]
    }
    public func importFromKeychain() throws -> Int {
        try transaction { document in
            guard document.storage == .local else { throw CredentialStorageError.localRequired }
            let accounts = try keychain.accounts()
            guard accounts.count <= 512 else { throw CredentialStorageError.invalidValue }
            var count = 0
            for account in Set(accounts).sorted() where document.values[account] == nil && !document.excludedImports.contains(account) {
                guard Self.validAccount(account) else { throw CredentialStorageError.invalidValue }
                if let value = try keychain.read(account) {
                    guard Self.validValue(value) else { throw CredentialStorageError.invalidValue }
                    document.values[account] = value; count += 1
                }
            }
            return count
        }
    }
    private func transaction<T>(_ operation: (inout CredentialDocument) throws -> T) throws -> T {
        try Task.checkCancellation()
        return try file.withLock {
            try Task.checkCancellation()
            var document = try file.load()
            let before = document
            if cachedRevision != document.revision { cache = [:]; cachedRevision = document.revision }
            let result = try operation(&document)
            try Task.checkCancellation()
            if document != before {
                document.revision = UUID()
                try file.save(document)
                cache = [:]; cachedRevision = document.revision
            }
            return result
        }
    }
}
