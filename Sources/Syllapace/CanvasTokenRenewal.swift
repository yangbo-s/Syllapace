import Foundation
import Observation
import CryptoKit
import SyllapaceKit

@Observable final class CanvasTokenRenewal {
    enum Status { case idle, checking, valid, renewed, unidentified, notExtended, unavailable, expired, retrying, missing }
    private(set) var enabled = UserDefaults.standard.object(forKey: "canvasAutoRenewToken") as? Bool ?? true
    private(set) var status = Status.idle
    private(set) var lease: CanvasTokenLease?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var context: String?
    @ObservationIgnored private var generation = UUID()

    var statusText: String {
        guard enabled else { return L10n.string("Token renewal is off.") }
        switch status {
        case .idle: return L10n.string("Save your connection to check token expiry.")
        case .checking: return L10n.string("Checking token expiry…")
        case .valid, .renewed:
            guard let expiry = lease?.expiresAt else { return L10n.string("This token has no expiration date.") }
            let date = expiry.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.locale))
            return L10n.format(status == .renewed ? "Token renewed until %@." : "Token expires %@.", date)
        case .unavailable: return L10n.string("Automatic renewal is unavailable for this token. Replace it before it expires.")
        case .unidentified: return L10n.string("Canvas token metadata could not be matched safely. No renewal was attempted.")
        case .notExtended: return L10n.string("Canvas did not confirm a later expiration date. Replace the token before it expires.")
        case .expired: return L10n.string("The token is expired or invalid. Generate a new token in Canvas and save it here.")
        case .retrying: return L10n.string("Token expiry could not be checked. Syllapace will retry while open.")
        case .missing: return L10n.string("Save a Canvas token to enable automatic renewal.")
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "canvasAutoRenewToken")
        if !value { cancel() }
    }

    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil; context = nil
        status = .idle; lease = nil
    }

    func start(host: String, account: String, force: Bool = false) {
        guard enabled, !host.isEmpty else { return }
        let newContext = host + "\n" + account
        if !force, task != nil, context == newContext { return }
        cancel()
        context = newContext
        let run = generation
        task = Task {
            defer { if generation == run { task = nil } }
            do {
                guard let token = try await CredentialStore.readAsync(account), !token.isEmpty else { if generation == run { status = .missing }; return }
                guard !Task.isCancelled, generation == run, enabled else { return }
                let origin = try ConnectorURL.canvasOrigin(host)
                let key = "canvasTokenLease." + Self.digest(origin.absoluteString)
                let fingerprint = Self.digest(token)
                if let data = UserDefaults.standard.data(forKey: key),
                   let cached = try? JSONDecoder().decode(CachedLease.self, from: data), cached.fingerprint == fingerprint {
                    lease = cached.lease
                }
                let client = try CanvasClient(host: host, token: token)
                while !Task.isCancelled, enabled, generation == run {
                    status = .checking
                    var delay: TimeInterval = 15 * 60
                    do {
                        let result = try await client.maintainAccessToken(previousLease: lease)
                        guard !Task.isCancelled, enabled, generation == run else { return }
                        lease = result.lease
                        status = result.renewed ? .renewed : .valid
                        if let data = try? JSONEncoder().encode(CachedLease(fingerprint: fingerprint, lease: result.lease)) {
                            UserDefaults.standard.set(data, forKey: key)
                        }
                        delay = Self.nextCheckDelay(lease: result.lease)
                    } catch is CancellationError { return }
                    catch {
                        guard !Task.isCancelled, enabled, generation == run else { return }
                        switch error {
                        case ConnectorError.http(401), CanvasTokenRenewalError.expired:
                            status = .expired; delay = 24 * 60 * 60
                        case CanvasTokenRenewalError.unverifiable:
                            status = .unidentified; delay = 24 * 60 * 60
                        case CanvasTokenRenewalError.notExtended:
                            status = .notExtended; delay = 24 * 60 * 60
                        case ConnectorError.http(400), ConnectorError.http(403), ConnectorError.http(404), ConnectorError.http(405), ConnectorError.http(422):
                            status = .unavailable; delay = 24 * 60 * 60
                        default: status = .retrying
                        }
                    }
                    try await Task.sleep(for: .seconds(delay))
                }
            } catch is CancellationError { }
            catch {
                guard generation == run, enabled else { return }
                status = .retrying
                do { try await Task.sleep(for: .seconds(15 * 60)) } catch { return }
                if generation == run, enabled { start(host: host, account: account, force: true) }
            }
        }
    }

    private static func nextCheckDelay(lease: CanvasTokenLease) -> TimeInterval {
        guard let expiry = lease.expiresAt, let interval = lease.renewalInterval else { return 6 * 60 * 60 }
        return min(6 * 60 * 60, max(60, expiry.timeIntervalSinceNow - min(7 * 24 * 60 * 60, interval / 4)))
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private struct CachedLease: Codable {
        let fingerprint: String
        let lease: CanvasTokenLease
    }
}
