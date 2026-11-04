import Foundation

/// Non-secret metadata. The credential remains unchanged in Keychain when renewed.
public struct CanvasTokenLease: Codable, Sendable, Equatable {
    public let tokenID: Int64
    public let createdAt: Date
    public var expiresAt: Date?
    public let renewalInterval: TimeInterval?

    public init(tokenID: Int64, createdAt: Date, expiresAt: Date?, previous: CanvasTokenLease? = nil, acceptedInterval: TimeInterval? = nil) throws {
        guard tokenID > 0, expiresAt.map({ $0 > createdAt }) ?? true else {
            throw CanvasTokenRenewalError.unverifiable
        }
        self.tokenID = tokenID; self.createdAt = createdAt; self.expiresAt = expiresAt
        let maximum: TimeInterval = 30 * 24 * 60 * 60
        let limit = acceptedInterval.map { $0.isFinite && $0 > 0 ? min($0, maximum) : maximum } ?? maximum
        if let previous, previous.tokenID == tokenID, previous.createdAt == createdAt,
           let interval = previous.renewalInterval, interval.isFinite, interval > 0, interval <= maximum {
            renewalInterval = min(interval, limit)
        } else {
            renewalInterval = expiresAt.map { min($0.timeIntervalSince(createdAt), limit) }
        }
    }

    public func renewalDate(now: Date) throws -> Date? {
        guard let expiresAt, let renewalInterval else { return nil }
        guard expiresAt > now else { throw CanvasTokenRenewalError.expired }
        guard expiresAt.timeIntervalSince(now) <= min(7 * 24 * 60 * 60, renewalInterval / 4) else { return nil }
        return now.addingTimeInterval(renewalInterval)
    }
}

public struct CanvasTokenMaintenance: Sendable {
    public let lease: CanvasTokenLease
    public let renewed: Bool
}

public enum CanvasTokenRenewalError: Error, Sendable, Equatable {
    case unverifiable, expired, notExtended
}
