import Foundation
import Testing
@testable import SyllapaceKit

private actor CompatibilityTransport: HTTPTransport {
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

@Suite("Connection compatibility") struct ConnectionCompatibilityTests {
    private let token = "abcdEF0123-synthetic-credential"
    private let source = SourceDocument(courseID: "test-course", title: "Test schedule", text: "Practice quiz is due November 20, 2026.")

    private func reply(_ object: Any, status: Int = 200) throws -> HTTPReply {
        HTTPReply(data: try JSONSerialization.data(withJSONObject: object), status: status)
    }
    private func success() throws -> HTTPReply {
        try reply(["choices": [["message": ["content": "{\"events\":[]}"], "finish_reason": "stop"]]])
    }
    private func rejection(_ parameter: String, status: Int = 400, code: String = "unsupported_parameter") throws -> HTTPReply {
        try reply(["error": ["type": "invalid_request_error", "code": code, "param": parameter]], status: status)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func run(_ transport: CompatibilityTransport, model: String = "gpt-6.1-terra", endpoint: String = "https://api.openai.com/v1") async throws {
        let client = try LLMClient(endpoint: endpoint, key: "synthetic-api-key", model: model, transport: transport)
        _ = try await client.extract(source: source, year: 2026, timeZone: "America/New_York")
    }

    @Test func recognizesServerHintsWithoutAssumingFixedMaskLength() {
        for mask in ["abcdE...", "abcdEF0123...", "abcdEF0123…"] {
            #expect(CanvasTokenIdentity.matches(token: token, hint: nil, visibleToken: mask))
            #expect(CanvasTokenIdentity.matches(token: "1234~" + token, hint: nil, visibleToken: mask))
        }
        #expect(CanvasTokenIdentity.matches(token: token, hint: "abcdE", visibleToken: nil))
        #expect(CanvasTokenIdentity.matches(token: token, hint: nil, visibleToken: token))
        #expect(CanvasTokenIdentity.matches(token: "1234~" + token, hint: nil, visibleToken: "1234~abcdE..."))
        #expect(CanvasTokenIdentity.matches(token: "1234~" + token, hint: "abcdE", visibleToken: "1234~abcdEF0123..."))
    }
    @Test func rejectsShortVagueConflictingAndWrongShardEvidence() {
        for mask in ["...", "abcd...", "1234~...", "1234~abcd...", "9999~abcdE...", "abcdE*****", "...ntial", "ABCDE...", "abcdE....", " abcdE...", "abcdE... "] {
            #expect(!CanvasTokenIdentity.matches(token: "1234~" + token, hint: nil, visibleToken: mask))
        }
        #expect(!CanvasTokenIdentity.matches(token: "12345~" + token, hint: nil, visibleToken: "12345..."))
        #expect(!CanvasTokenIdentity.matches(token: "123456~123456-matching-public-shard", hint: nil, visibleToken: "12345..."))
        #expect(!CanvasTokenIdentity.matches(token: token, hint: "abcdE", visibleToken: "wrong..."))
        #expect(!CanvasTokenIdentity.matches(token: token, hint: "wrong", visibleToken: "abcdE..."))
        #expect(!CanvasTokenIdentity.matches(token: token, hint: nil, visibleToken: nil))
        #expect(!CanvasTokenIdentity.matches(token: token, hint: "", visibleToken: ""))
        #expect(!CanvasTokenIdentity.matches(token: "prefix~" + token, hint: "abcdE", visibleToken: nil))
        #expect(!CanvasTokenIdentity.matches(token: "1~2~" + token, hint: "abcdE", visibleToken: nil))
    }
    @Test func variableMasksStillRequireUniqueTokenBeforeRenewal() async throws {
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        func record(_ id: Int, _ mask: String) -> [String: Any] {
            ["id": id, "created_at": now.addingTimeInterval(-25 * 86_400).ISO8601Format(),
             "expires_at": now.addingTimeInterval(5 * 86_400).ISO8601Format(), "workflow_state": "active", "visible_token": mask]
        }
        let transport = try CompatibilityTransport([reply([record(1, "abcdE..."), record(2, "abcdEF0123...")])])
        let client = try CanvasClient(host: "https://canvas.example.edu", token: token, transport: transport)
        await #expect(throws: CanvasTokenRenewalError.unverifiable) { try await client.maintainAccessToken(now: now) }
        #expect(await transport.requests.count == 1)
    }
    @Test func modernModelsUseCompletionBudgetWithoutSamplingControls() async throws {
        for model in ["gpt-6.1-terra", "gpt-5-mini", "o3", "o4-mini", "ft:gpt-5.1:org:test", "openai/gpt-6.1-terra"] {
            let transport = try CompatibilityTransport([success()])
            try await run(transport, model: model, endpoint: "https://compatible.example/v1")
            let request = try #require(await transport.requests.first)
            let payload = try body(request)
            #expect(payload["max_completion_tokens"] as? Int == 6000)
            #expect(payload["max_tokens"] == nil)
            #expect(payload["temperature"] == nil)
            #expect(payload["tools"] == nil)
            #expect(payload["response_format"] as? [String: String] == ["type": "json_object"])
        }
    }
    @Test func legacyModelsRetainCompatibleBudgetEvenOnOfficialHost() async throws {
        for model in ["chosen-model", "gpt-4o", "gpt-4.1", "gpt-3.5-turbo"] {
            let transport = try CompatibilityTransport([success()])
            try await run(transport, model: model)
            let payload = try body(#require(await transport.requests.first))
            #expect(payload["max_tokens"] as? Int == 6000)
            #expect(payload["max_completion_tokens"] == nil)
            #expect(payload["temperature"] as? Double == 0)
        }
    }
    @Test func explicitTokenParameterRejectionAllowsOneBoundedRetry() async throws {
        let transport = try CompatibilityTransport([rejection("max_tokens"), success()])
        try await run(transport, model: "provider-reasoning-model", endpoint: "https://compatible.example/v1")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url == requests[1].url)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == requests[1].value(forHTTPHeaderField: "Authorization"))
        let first = try body(requests[0]), second = try body(requests[1])
        #expect(first["max_tokens"] as? Int == 6000)
        #expect(second["max_completion_tokens"] as? Int == 6000)
        #expect(second["max_tokens"] == nil)
        #expect(second["temperature"] == nil)
        #expect(second["messages"] as? [[String: String]] == first["messages"] as? [[String: String]])
    }
    @Test func thirdPartyLegacyLimitAndSamplingFallbackStayBounded() async throws {
        let modern = try CompatibilityTransport([rejection("max_completion_tokens"), success()])
        try await run(modern, endpoint: "https://compatible.example/v1")
        let revised = try body(#require(await modern.requests.last))
        #expect(revised["max_tokens"] as? Int == 6000)
        #expect(revised["max_completion_tokens"] == nil)
        let sampling = try CompatibilityTransport([rejection("temperature"), success()])
        try await run(sampling, model: "provider-model")
        #expect(try body(#require(await sampling.requests.last))["temperature"] == nil)
        #expect(await sampling.requests.count == 2)
    }
    @Test func authenticationRateLimitServerAndUnspecifiedErrorsNeverRetry() async throws {
        for failure in try [rejection("max_tokens", status: 401), rejection("max_tokens", status: 429), rejection("max_tokens", status: 500),
                        rejection("max_tokens", code: "invalid_api_key"), rejection("messages"), reply(["error": ["message": "Unsupported max_tokens"]], status: 400)] {
            let transport = try CompatibilityTransport([failure, success()])
            await #expect(throws: ConnectorError.self) { try await run(transport, model: "provider-model") }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func aSecondParameterFailureDoesNotLoop() async throws {
        let transport = try CompatibilityTransport([rejection("max_tokens"), rejection("max_completion_tokens"), success()])
        await #expect(throws: ConnectorError.http(400)) { try await run(transport, model: "provider-model") }
        #expect(await transport.requests.count == 2)
    }
    @Test func timedSessionsKeepVerifiedLocationAndEndTime() throws {
        let source = SourceDocument(courseID: "course", title: "Schedule", text: "Lecture on November 20, 2026 from 10:00 to 11:20 in Hall 203.")
        let content = #"{"events":[{"title":"Lecture","kind":"session","date":"2026-11-20T10:00:00-05:00","endDate":"2026-11-20T11:20:00-05:00","location":"Hall 203","dateOnly":false,"timeZone":"America/New_York","evidence":"Lecture on November 20, 2026 from 10:00 to 11:20 in Hall 203."}]}"#
        let event = try #require(try LLMClient.parse(content: content, source: source, year: 2026, timeZone: "America/New_York").first)
        #expect(event.kind == .session)
        #expect(event.endsAt?.timeIntervalSince(try #require(event.date)) == 80 * 60)
        #expect(event.location == "Hall 203")
        #expect(event.state == .pending)
        for invalid in [content.replacingOccurrences(of: "2026-11-20T11:20:00-05:00", with: "2026-11-20T09:20:00-05:00"),
                        content.replacingOccurrences(of: #""location":"Hall 203""#, with: #""location":"Hall 999""#)] {
            #expect(throws: ConnectorError.self) { try LLMClient.parse(content: invalid, source: source, year: 2026, timeZone: "America/New_York") }
        }
    }
    @Test func quizParsingKeepsOptionalFieldsBackwardCompatible() throws {
        let content = #"{"events":[{"title":"Practice quiz","kind":"quiz","date":"2026-11-20","dateOnly":true,"evidence":"Practice quiz is due November 20, 2026."}]}"#
        let event = try #require(try LLMClient.parse(content: content, source: source, year: 2026, timeZone: "UTC").first)
        #expect(event.kind == .quiz)
        #expect(event.endsAt == nil)
        #expect(event.location == nil)
    }
    @Test func cancelledWorkDoesNotStartCredentialReadOrRequest() async throws {
        let transport = try CompatibilityTransport([success()])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await CredentialStore.readAsync("unused-test-account") }
            await #expect(throws: CancellationError.self) { try await run(transport) }
        }
        await task.value
        #expect(await transport.requests.isEmpty)
    }
}
