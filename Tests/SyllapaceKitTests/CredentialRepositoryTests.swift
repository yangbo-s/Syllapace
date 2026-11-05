import Foundation
import Darwin
import Synchronization
import Testing
@testable import SyllapaceKit

private enum CredentialTestError: Error { case denied }
private final class MemoryKeychain: CredentialKeychain {
    struct State {
        var values: [String: String]
        var calls: [String] = []
        var denied: String?
    }
    private let state: Mutex<State>
    init(_ values: [String: String] = [:], denied: String? = nil) { state = Mutex(State(values: values, denied: denied)) }
    var calls: [String] { state.withLock { $0.calls } }
    var values: [String: String] { state.withLock { $0.values } }
    private func access<T>(_ name: String, _ action: (inout State) -> T) throws -> T {
        try state.withLock {
            $0.calls.append(name)
            if $0.denied == name { throw CredentialTestError.denied }
            return action(&$0)
        }
    }
    func accounts() throws -> [String] { try access("list") { Array($0.values.keys) } }
    func read(_ account: String) throws -> String? { try access("read:" + account) { $0.values[account] } }
    func save(_ value: String, account: String) throws { try access("save:" + account) { $0.values[account] = value } }
    func delete(_ account: String) throws { _ = try access("delete:" + account) { $0.values.removeValue(forKey: account) } }
}

private struct CancellingKeychain: CredentialKeychain {
    func accounts() throws -> [String] { ["a"] }
    func read(_ account: String) throws -> String? {
        withUnsafeCurrentTask { $0?.cancel() }
        return "cancelled-synthetic"
    }
    func save(_ value: String, account: String) throws { throw CredentialTestError.denied }
    func delete(_ account: String) throws { throw CredentialTestError.denied }
}

private struct CredentialFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("credential-test-" + UUID().uuidString)
    var url: URL { root.appendingPathComponent("Credentials/credentials.json") }
    func clean() { try? FileManager.default.removeItem(at: root) }
    func document() throws -> CredentialDocument { try JSONDecoder().decode(CredentialDocument.self, from: Data(contentsOf: url)) }
}

@Suite("Local and optional Keychain credentials")
struct CredentialRepositoryTests {
    @Test func defaultAndUpgradedInstallsNeverTouchKeychain() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(["canvas-token:https://school.test": "old-synthetic-token"])
        let store = CredentialRepository(url: f.url, keychain: backend)
        #expect(try await store.storage() == .local)
        #expect(try await store.read("canvas-token:https://school.test") == nil)
        try await store.save("new-synthetic-token", account: "canvas-token:https://school.test")
        #expect(try await store.read("canvas-token:https://school.test") == "new-synthetic-token")
        try await store.delete("canvas-token:https://school.test")
        #expect(try await store.read("canvas-token:https://school.test") == nil)
        #expect(backend.calls.isEmpty)
        #expect(backend.values.count == 1)
    }
    @Test func valuesAndPermissionsSurviveReload() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(), store = CredentialRepository(url: f.url, keychain: MemoryKeychain())
        try await store.save("synthetic-api-key", account: "model-key:https://provider.test/v1")
        let reloaded = CredentialRepository(url: f.url, keychain: backend)
        #expect(try await reloaded.read("model-key:https://provider.test/v1") == "synthetic-api-key")
        #expect(try await reloaded.read("model-key:https://other.test/v1") == nil)
        let file = try FileManager.default.attributesOfItem(atPath: f.url.path)
        let folder = try FileManager.default.attributesOfItem(atPath: f.url.deletingLastPathComponent().path)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(backend.calls.isEmpty)
    }
    @Test func successfulKeychainSelectionRemovesLocalCopiesAndCachesReads() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(), store = CredentialRepository(url: f.url, keychain: backend)
        try await store.save("synthetic-secret", account: "a")
        try await store.setStorage(.keychain)
        #expect(try await store.storage() == .keychain)
        #expect(try f.document().values.isEmpty)
        #expect(!String(decoding: try Data(contentsOf: f.url), as: UTF8.self).contains("synthetic-secret"))
        #expect(backend.values["a"] == "synthetic-secret")
        #expect(try await store.read("a") == "synthetic-secret")
        #expect(try await store.read("a") == "synthetic-secret")
        #expect(backend.calls.filter { $0 == "read:a" }.count == 1)
        let reloaded = CredentialRepository(url: f.url, keychain: backend)
        #expect(try await reloaded.storage() == .keychain)
        #expect(try await reloaded.read("a") == "synthetic-secret")
        try await reloaded.save("changed-synthetic", account: "a")
        #expect(try await store.read("a") == "changed-synthetic") // cross-instance cache invalidation
        try await reloaded.delete("a")
        #expect(try await store.read("a") == nil)
        #expect(backend.values.isEmpty)
    }
    @Test func deniedKeychainSelectionRetainsAllLocalCredentials() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(denied: "save:b"), store = CredentialRepository(url: f.url, keychain: backend)
        try await store.save("synthetic-a", account: "a"); try await store.save("synthetic-b", account: "b")
        let before = try Data(contentsOf: f.url)
        await #expect(throws: CredentialTestError.self) { try await store.setStorage(.keychain) }
        #expect(try Data(contentsOf: f.url) == before)
        #expect(try await store.storage() == .local)
        #expect(try await store.read("b") == "synthetic-b")
        #expect(backend.values["a"] == "synthetic-a") // copies can remain, but local is authoritative
    }
    @Test func returningToLocalDoesNotAccessKeychain() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(["a": "old-synthetic"], denied: "read:a")
        let store = CredentialRepository(url: f.url, keychain: backend)
        try await store.setStorage(.keychain)
        try await store.setStorage(.local)
        #expect(try await store.storage() == .local)
        #expect(try await store.read("a") == nil)
        #expect(backend.calls.isEmpty)
        #expect(backend.values["a"] == "old-synthetic")
    }
    @Test func explicitImportKeepsLocalValuesAndDeletedAccounts() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(["a": "old-synthetic", "b": "import-synthetic", "c": "deleted-synthetic"])
        let store = CredentialRepository(url: f.url, keychain: backend)
        try await store.save("new-synthetic", account: "a")
        try await store.delete("c")
        #expect(try await store.importFromKeychain() == 1)
        #expect(try await store.read("a") == "new-synthetic")
        #expect(try await store.read("b") == "import-synthetic")
        #expect(try await store.read("c") == nil)
        #expect(backend.calls == ["list", "read:b"])
        #expect(backend.values.count == 3)
        #expect(try await store.importFromKeychain() == 0)
        try await store.save("replacement-synthetic", account: "c")
        #expect(try await store.read("c") == "replacement-synthetic")
    }
    @Test func deniedImportCommitsNothingAndIsRetryable() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(["a": "synthetic-a", "b": "synthetic-b"], denied: "read:b")
        let store = CredentialRepository(url: f.url, keychain: backend)
        try await store.save("preserve-synthetic", account: "local")
        let before = try Data(contentsOf: f.url)
        await #expect(throws: CredentialTestError.self) { try await store.importFromKeychain() }
        #expect(try Data(contentsOf: f.url) == before)
        #expect(try await store.read("a") == nil)
        let retry = CredentialRepository(url: f.url, keychain: MemoryKeychain(backend.values))
        #expect(try await retry.importFromKeychain() == 2)
    }
    @Test func importRequiresLocalMode() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(), store = CredentialRepository(url: f.url, keychain: backend)
        try await store.setStorage(.keychain)
        await #expect(throws: CredentialStorageError.self) { try await store.importFromKeychain() }
        #expect(backend.calls.isEmpty)
    }
    @Test func blankSaveDeletesAndCannotBeResurrected() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let store = CredentialRepository(url: f.url, keychain: MemoryKeychain(["a": "old-synthetic"]))
        try await store.save("synthetic", account: "a")
        try await store.save(" \n ", account: "a")
        #expect(try await store.read("a") == nil)
        #expect(try await store.importFromKeychain() == 0)
    }
    @Test func concurrentInstancesDoNotLoseWrites() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let stores = (0..<4).map { _ in CredentialRepository(url: f.url, keychain: MemoryKeychain()) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<40 { group.addTask { try await stores[i % 4].save("synthetic-\(i)", account: "account-\(i)") } }
            try await group.waitForAll()
        }
        #expect(try f.document().values.count == 40)
        #expect(try await stores[0].read("account-39") == "synthetic-39")
    }
    @Test(arguments: ["not json", "{}", "{\"schemaVersion\":99}"])
    func malformedFilesAreNotReplaced(_ contents: String) async throws {
        let f = CredentialFixture(); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(contents.utf8); try data.write(to: f.url)
        let backend = MemoryKeychain(), store = CredentialRepository(url: f.url, keychain: backend)
        await #expect(throws: CredentialStorageError.self) { try await store.read("a") }
        await #expect(throws: CredentialStorageError.self) { try await store.save("synthetic", account: "a") }
        #expect(try Data(contentsOf: f.url) == data)
        #expect(backend.calls.isEmpty)
    }
    @Test func unknownSchemaAndOversizedFileFailClosed() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let store = CredentialRepository(url: f.url, keychain: MemoryKeychain())
        try await store.save("synthetic", account: "a")
        var document = try f.document(); document.schemaVersion = 2
        let unknown = try JSONEncoder().encode(document); try unknown.write(to: f.url)
        await #expect(throws: CredentialStorageError.self) { try await store.setStorage(.keychain) }
        #expect(try Data(contentsOf: f.url) == unknown)
        let large = Data(repeating: 32, count: LocalCredentialFile.maxBytes + 1); try large.write(to: f.url)
        await #expect(throws: CredentialStorageError.self) { try await store.read("a") }
        #expect(try Data(contentsOf: f.url) == large)
    }
    @Test(arguments: [true, false]) func unsafeFileLinksAreRejected(_ symbolic: Bool) async throws {
        let f = CredentialFixture(); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = f.root.appendingPathComponent("original")
        let data = Data("untouched-synthetic".utf8); try data.write(to: original)
        if symbolic { try FileManager.default.createSymbolicLink(at: f.url, withDestinationURL: original) }
        else { try FileManager.default.linkItem(at: original, to: f.url) }
        let store = CredentialRepository(url: f.url, keychain: MemoryKeychain())
        await #expect(throws: CredentialStorageError.self) { try await store.save("new-synthetic", account: "a") }
        #expect(try Data(contentsOf: original) == data)
    }
    @Test func namedPipeIsRejectedWithoutWaitingForAWriter() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(mkfifo(f.url.path, 0o600) == 0)
        let store = CredentialRepository(url: f.url, keychain: MemoryKeychain())
        await #expect(throws: CredentialStorageError.self) { try await store.read("a") }
    }
    @Test func unsafeDirectoryIsRejected() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let actual = f.root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: f.url.deletingLastPathComponent(), withDestinationURL: actual)
        let store = CredentialRepository(url: f.url, keychain: MemoryKeychain())
        await #expect(throws: CredentialStorageError.self) { try await store.save("synthetic", account: "a") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: actual.path).isEmpty)
    }
    @Test func invalidInputAndCapacityDoNotDamageExistingFile() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let store = CredentialRepository(url: f.url, keychain: MemoryKeychain())
        try await store.save("synthetic", account: "a")
        let before = try Data(contentsOf: f.url)
        await #expect(throws: CredentialStorageError.self) { try await store.save(String(repeating: "x", count: 16_385), account: "b") }
        await #expect(throws: CredentialStorageError.self) { try await store.save("synthetic", account: "") }
        #expect(try Data(contentsOf: f.url) == before)
        var document = try f.document()
        document.values = Dictionary(uniqueKeysWithValues: (0..<512).map { ("account-\($0)", "synthetic") })
        let full = try JSONEncoder().encode(document); try full.write(to: f.url)
        await #expect(throws: CredentialStorageError.self) { try await store.save("synthetic", account: "overflow") }
        #expect(try Data(contentsOf: f.url) == full)
    }
    @Test func cancellationAfterCredentialReadDoesNotCommitImport() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let store = CredentialRepository(url: f.url, keychain: CancellingKeychain())
        try await store.save("preserve-synthetic", account: "local")
        let before = try Data(contentsOf: f.url)
        let task = Task { try await store.importFromKeychain() }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: f.url) == before)
    }
    @Test func cancelledOperationNeverTouchesStorage() async throws {
        let f = CredentialFixture(); defer { f.clean() }
        let backend = MemoryKeychain(), store = CredentialRepository(url: f.url, keychain: backend)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await store.importFromKeychain()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(backend.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.url.path))
    }
}
