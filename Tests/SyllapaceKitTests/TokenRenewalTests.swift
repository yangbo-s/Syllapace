import Foundation
import Testing
@testable import SyllapaceKit

private actor TokenTransport: HTTPTransport {
    var replies: [HTTPReply]
    var requests: [URLRequest] = []
    init(_ replies: [HTTPReply]) { self.replies = replies }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        try Task.checkCancellation()
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        return replies.removeFirst()
    }
}

@Suite("Canvas token renewal") struct TokenRenewalTests {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_793_750_400)
    private let token = "abcde-synthetic-credential"

    private func record(id: Int = 42, expiry: Date?, hint: String = "abcde", created: Date? = nil) -> [String: Any] {
        ["id": id, "created_at": (created ?? now.addingTimeInterval(-25 * day)).ISO8601Format(),
         "expires_at": expiry.map { $0.ISO8601Format() } as Any? ?? NSNull(),
         "workflow_state": "active", "visible_token": hint + "..."]
    }
    private func reply(_ object: Any, status: Int = 200, headers: [String: String] = [:]) throws -> HTTPReply {
        HTTPReply(data: try JSONSerialization.data(withJSONObject: object), status: status, headers: headers)
    }
    private func client(_ transport: TokenTransport) throws -> CanvasClient {
        try CanvasClient(host: "https://canvas.example.edu", token: token, transport: transport)
    }

    @Test func extendsOnlyCurrentTokenNearExpiryWithoutRotatingCredentials() async throws {
        let old = now.addingTimeInterval(5 * day), extended = now.addingTimeInterval(30 * day)
        let transport = try TokenTransport([reply([record(id: 9, expiry: old, hint: "other"), record(expiry: old)]), reply(record(expiry: extended))])
        let result = try await client(transport).maintainAccessToken(now: now)
        #expect(result.renewed)
        #expect(result.lease.expiresAt == extended)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].httpMethod == "PUT")
        #expect(requests[1].url?.absoluteString == "https://canvas.example.edu/api/v1/users/self/tokens/42")
        let data = try #require(requests[1].httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        #expect(body == ["token": ["expires_at": extended.ISO8601Format()]])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" })
    }
    @Test func leavesDistantAndNonExpiringTokensAlone() async throws {
        for expiry in [now.addingTimeInterval(20 * day), nil] {
            let transport = try TokenTransport([reply([record(expiry: expiry)])])
            let result = try await client(transport).maintainAccessToken(now: now)
            #expect(!result.renewed)
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func expiredTokenCannotRenewItself() async throws {
        let transport = try TokenTransport([reply([record(expiry: now.addingTimeInterval(-1))])])
        await #expect(throws: CanvasTokenRenewalError.expired) { try await client(transport).maintainAccessToken(now: now) }
        #expect(await transport.requests.count == 1)
    }
    @Test func doesNotGuessWhenHintsAreMissingOrAmbiguous() async throws {
        for records in [[], [record(expiry: now, hint: "other")], [record(expiry: now), record(id: 43, expiry: now)]] {
            let transport = try TokenTransport([reply(records)])
            await #expect(throws: CanvasTokenRenewalError.unverifiable) { try await client(transport).maintainAccessToken(now: now) }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func preservesShortRenewalPeriodAcrossReloads() throws {
        let created = now.addingTimeInterval(-day)
        var original = try CanvasTokenLease(tokenID: 42, createdAt: created, expiresAt: created.addingTimeInterval(2 * day))
        original.expiresAt = now.addingTimeInterval(2 * day)
        let cached = try JSONDecoder().decode(CanvasTokenLease.self, from: JSONEncoder().encode(original))
        let fetched = try CanvasTokenLease(tokenID: 42, createdAt: created, expiresAt: cached.expiresAt, previous: cached)
        #expect(fetched.renewalInterval == 2 * day)
        let later = now.addingTimeInterval(1.75 * day)
        #expect(try fetched.renewalDate(now: later) == later.addingTimeInterval(2 * day))
    }
    @Test func capsRequestedPeriodAndDiscardsDifferentTokenMetadata() throws {
        let original = try CanvasTokenLease(tokenID: 1, createdAt: now, expiresAt: now.addingTimeInterval(day))
        let lease = try CanvasTokenLease(tokenID: 42, createdAt: now, expiresAt: now.addingTimeInterval(365 * day), previous: original)
        #expect(lease.renewalInterval == 30 * day)
    }
    @Test func adoptsAShorterServerApprovedPeriod() async throws {
        let transport = try TokenTransport([reply([record(expiry: now.addingTimeInterval(day))]), reply(record(expiry: now.addingTimeInterval(2 * day)))])
        let result = try await client(transport).maintainAccessToken(now: now)
        #expect(result.renewed)
        #expect(result.lease.renewalInterval == 2 * day)
        #expect(try result.lease.renewalDate(now: now) == nil)
    }
    @Test func permissionAndAuthenticationFailuresDoNotWrite() async throws {
        for status in [401, 403, 404, 405, 500] {
            let transport = try TokenTransport([reply([:], status: status)])
            await #expect(throws: ConnectorError.http(status)) { try await client(transport).maintainAccessToken(now: now) }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func refusesRedirectedPaginationAndDoesNotSendCredentialElsewhere() async throws {
        let transport = try TokenTransport([reply([], headers: ["Link": "<https://other.example/api/v1/users/self/user_generated_tokens?page=2>; rel=\"next\""])])
        await #expect(throws: ConnectorError.unsafeRedirect) { try await client(transport).maintainAccessToken(now: now) }
        #expect(await transport.requests.count == 1)
    }
    @Test func refusesUnconfirmedOrWrongTokenRenewalResponse() async throws {
        let old = now.addingTimeInterval(5 * day)
        for response in [record(expiry: old), record(id: 43, expiry: now.addingTimeInterval(30 * day)), record(expiry: nil), record(expiry: now.addingTimeInterval(90 * day))] {
            let transport = try TokenTransport([reply([record(expiry: old)]), reply(response)])
            await #expect(throws: CanvasTokenRenewalError.notExtended) { try await client(transport).maintainAccessToken(now: now) }
        }
    }
    @Test func rejectedRenewalNeverRetriesWithLongerOrUnlimitedLifetime() async throws {
        for status in [400, 403, 422] {
            let transport = try TokenTransport([reply([record(expiry: now.addingTimeInterval(5 * day))]), reply([:], status: status)])
            await #expect(throws: ConnectorError.http(status)) { try await client(transport).maintainAccessToken(now: now) }
            #expect(await transport.requests.count == 2)
        }
    }
    @Test func interruptedResponseIsRecoverableWithoutChangingCredential() async throws {
        let transport = try TokenTransport([reply([record(expiry: now.addingTimeInterval(5 * day))])])
        await #expect(throws: URLError.self) { try await client(transport).maintainAccessToken(now: now) }
        let retry = try TokenTransport([reply([record(expiry: now.addingTimeInterval(30 * day))])])
        #expect(try await !client(retry).maintainAccessToken(now: now).renewed)
        #expect(await retry.requests.count == 1)
    }
    @Test func rateLimitRetriesOnlyTheSameAuthorizedEndpoint() async throws {
        let transport = try TokenTransport([reply([:], status: 429, headers: ["Retry-After": "0"]), reply([record(expiry: now.addingTimeInterval(5 * day))]), reply(record(expiry: now.addingTimeInterval(30 * day)))])
        #expect(try await client(transport).maintainAccessToken(now: now).renewed)
        let requests = await transport.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PUT"])
        #expect(requests[0].url == requests[1].url)
    }
    @Test func missingOrMalformedExpiryIsNotTreatedAsUnlimited() async throws {
        var missing = record(expiry: now); missing.removeValue(forKey: "expires_at")
        var invalid = record(expiry: now); invalid["expires_at"] = "not-a-date"
        for object in [missing, invalid] {
            let transport = try TokenTransport([reply([object])])
            await #expect(throws: (any Error).self) { try await client(transport).maintainAccessToken(now: now) }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func cancellationAfterMetadataReadDoesNotSendRenewal() async throws {
        actor SuspendedTransport: HTTPTransport {
            let reply: HTTPReply
            var calls = 0
            init(_ reply: HTTPReply) { self.reply = reply }
            func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
                calls += 1
                // Deliberately return metadata even after cancellation, to test
                // the client's guard immediately before the remote write.
                try? await Task.sleep(for: .seconds(60))
                return reply
            }
        }
        let transport = try SuspendedTransport(reply([record(expiry: now.addingTimeInterval(5 * day))]))
        let client = try CanvasClient(host: "canvas.example.edu", token: token, transport: transport)
        let work = Task { try await client.maintainAccessToken(now: now) }
        while await transport.calls == 0 { await Task.yield() }
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(await transport.calls == 1)
    }
}
