import Foundation
import Darwin

struct CredentialDocument: Codable, Equatable {
    var schemaVersion = 1
    var revision = UUID()
    var storage = CredentialStorage.local
    var values: [String: String] = [:]
    var excludedImports: Set<String> = []
}

/// A separate file keeps secrets out of course backups, exports and web snapshots.
struct LocalCredentialFile: Sendable {
    let url: URL
    static let maxBytes = 512 * 1024

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              chmod(folder.path, 0o700) == 0 else { throw CredentialStorageError.unsafeFile }
        let fd = open(folder.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw CredentialStorageError.unavailable }
        defer { close(fd) }
        try validate(fd)
        guard flock(fd, LOCK_EX) == 0 else { throw CredentialStorageError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }

    func load() throws -> CredentialDocument {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0, errno == ENOENT { return CredentialDocument() }
        guard fd >= 0 else { throw CredentialStorageError.unsafeFile }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try validate(fd)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size <= Self.maxBytes else { throw CredentialStorageError.invalidFile }
        var data = Data()
        while let chunk = try handle.read(upToCount: Self.maxBytes + 1 - data.count), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= Self.maxBytes else { throw CredentialStorageError.invalidFile }
        }
        guard let document = try? JSONDecoder().decode(CredentialDocument.self, from: data) else { throw CredentialStorageError.invalidFile }
        try validate(document)
        return document
    }

    func save(_ document: CredentialDocument) throws {
        try validate(document)
        let data = try JSONEncoder().encode(document)
        guard data.count <= Self.maxBytes else { throw CredentialStorageError.invalidFile }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CredentialStorageError.unavailable }
        defer { close(fd); unlink(temporary.path) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw CredentialStorageError.unavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw CredentialStorageError.unavailable }
    }

    private func validate(_ document: CredentialDocument) throws {
        guard document.schemaVersion == 1,
              document.values.count <= 512, document.excludedImports.count <= 512,
              document.values.allSatisfy({ CredentialRepository.validAccount($0.key) && CredentialRepository.validValue($0.value) }),
              document.excludedImports.allSatisfy(CredentialRepository.validAccount),
              document.storage != .keychain || document.values.isEmpty else { throw CredentialStorageError.invalidFile }
    }

    private func validate(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1,
              fchmod(fd, 0o600) == 0 else { throw CredentialStorageError.unsafeFile }
    }
}

public enum CredentialStorageError: Error, LocalizedError, Sendable {
    case invalidFile, unsafeFile, unavailable, invalidValue, localRequired
    public var errorDescription: String? {
        switch self {
        case .invalidFile: L10n.string("The local credential file is invalid or unsupported. It has not been replaced.")
        case .unsafeFile: L10n.string("The local credential file has unsafe ownership or links. It has not been read or replaced.")
        case .unavailable: L10n.string("Could not access local credential storage. Check folder permissions and try again.")
        case .invalidValue: L10n.string("The credential is empty or too large to save.")
        case .localRequired: L10n.string("Select local storage before importing from Keychain.")
        }
    }
}
