import Foundation

public enum ArchiveError: LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case corrupt(backupAvailable: Bool)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This library was saved by a newer Syllapace version (schema \(version)). Update the app before opening it."
        case .corrupt(let available): available ? "The library could not be read. A backup is available; your files have not been changed." : "The library could not be read. Your file has been preserved."
        }
    }
}

public struct ArchiveStore: Sendable {
    public let url: URL
    public var backupURL: URL { url.appendingPathExtension("backup") }
    public init(url: URL) { self.url = url }

    public func load() throws -> AppArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppArchive() }
        return try decode(from: url)
    }

    public func loadBackup() throws -> AppArchive { try decode(from: backupURL) }

    private func decode(from location: URL) throws -> AppArchive {
        let data = try Data(contentsOf: location)
        let archive: AppArchive
        do { archive = try JSONDecoder().decode(AppArchive.self, from: data) }
        catch { throw ArchiveError.corrupt(backupAvailable: FileManager.default.fileExists(atPath: backupURL.path)) }
        guard archive.schemaVersion == 1 else { throw ArchiveError.unsupportedVersion(archive.schemaVersion) }
        return archive
    }

    public func save(_ archive: AppArchive) throws {
        guard archive.schemaVersion == 1 else { throw ArchiveError.unsupportedVersion(archive.schemaVersion) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            // Never replace the last good backup with a corrupt archive.
            _ = try load()
            try Data(contentsOf: url).write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
