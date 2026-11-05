import Foundation
import Testing
@testable import SyllapaceKit

private actor ProviderTransport: HTTPTransport {
    var requests: [URLRequest] = []
    private var replies: [HTTPReply]
    init(_ replies: [HTTPReply]) { self.replies = replies }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        try Task.checkCancellation()
        requests.append(request)
        guard !replies.isEmpty else { throw ConnectorError.invalidResponse }
        return replies.removeFirst()
    }
}

@Suite("Model providers")
struct ModelProviderTests {
    private func reply(_ body: Any, status: Int = 200, headers: [String: String] = [:]) throws -> HTTPReply {
        HTTPReply(data: try JSONSerialization.data(withJSONObject: body), status: status, headers: headers)
    }
    private let source = SourceDocument(courseID: "course", title: "Schedule", text: "Exam on November 20, 2026.")
    private let output = #"{"events":[{"title":"Exam","kind":"exam","date":"2026-11-20","dateOnly":true,"timeZone":"UTC","evidence":"Exam on November 20, 2026.","endDate":null,"location":null}]}"#

    @Test func providerPresetsRouteDiscoveryAndDoNotRequireHardcodedModelLists() async throws {
        for provider in [ModelProvider.openAI, .deepSeek, .custom] {
            let endpoint = provider == .custom ? "https://models.example/v2/chat/completions" : provider.defaultEndpoint
            let mock = ProviderTransport([try reply(["data": [["id": "future-text-model"], ["id": "text-embedding-3-small"],
                                                                  ["id": "image-only", "output_modalities": ["image"]], ["id": "gpt-3.5-turbo-instruct"]]])])
            let client = try ModelDiscoveryClient(provider: provider, endpoint: endpoint, key: "secret-test", transport: mock)
            #expect(try await client.list().map(\.id) == ["future-text-model"])
            let requests = await mock.requests
            let request = try #require(requests.first)
            #expect(request.url?.path == (provider == .deepSeek ? "/models" : provider == .custom ? "/v2/models" : "/v1/models"))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-test")
            #expect(request.url?.query == nil)
        }
    }

    @Test func anthropicPaginationIsBoundedAndUsesOnlySameEndpointCursor() async throws {
        let mock = ProviderTransport([
            try reply(["data": [["id": "claude-first", "display_name": "Claude First"]], "has_more": true, "last_id": "claude-first",
                       "next": "https://evil.example/steal"]),
            try reply(["data": [["id": "claude-second", "display_name": "Claude Second"], ["id": "claude-first"]], "has_more": false])
        ])
        let client = try ModelDiscoveryClient(provider: .anthropic, endpoint: ModelProvider.anthropic.defaultEndpoint,
                                             key: "test-key", transport: mock, workspaceID: "workspace-example")
        let found = try await client.list()
        #expect(found.map(\.id) == ["claude-first", "claude-second"])
        let requests = await mock.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "api.anthropic.com" && $0.url?.path == "/v1/models" })
        #expect(requests[1].url?.query?.contains("after_id=claude-first") == true)
        #expect(requests[1].value(forHTTPHeaderField: "anthropic-workspace-id") == "workspace-example")
        #expect(requests[0].value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
    }

    @Test func repeatedPaginationCursorFailsInsteadOfLooping() async throws {
        let page = try reply(["data": [["id": "claude-first"]], "has_more": true, "last_id": "claude-first"])
        let mock = ProviderTransport([page, page])
        let client = try ModelDiscoveryClient(provider: .anthropic, endpoint: ModelProvider.anthropic.defaultEndpoint, key: "test", transport: mock)
        await #expect(throws: ConnectorError.invalidResponse) { try await client.list() }
        #expect(await mock.requests.count == 2)
    }

    @Test func discoveryStopsAfterTenPagesAndRejectsMalformedModelIDs() async throws {
        let pages = try (0..<11).map { index in
            try reply(["data": [["id": "claude-\(index)"]], "has_more": true, "last_id": "claude-\(index)"])
        }
        let mock = ProviderTransport(pages)
        let client = try ModelDiscoveryClient(provider: .anthropic, endpoint: ModelProvider.anthropic.defaultEndpoint, key: "test", transport: mock)
        await #expect(throws: ConnectorError.tooManyPages) { try await client.list() }
        #expect(await mock.requests.count == 10)

        let malformed = ProviderTransport([try reply(["data": [["id": "bad\nmodel"]]])])
        let invalid = try ModelDiscoveryClient(provider: .custom, endpoint: "https://models.example/v1", key: "test", transport: malformed)
        await #expect(throws: ConnectorError.invalidResponse) { try await invalid.list() }
    }

    @Test func discoveryRefusesCredentialRedirectAndPropagatesAuthenticationFailure() async throws {
        for status in [302, 401, 403, 429] {
            let mock = ProviderTransport([try reply([:], status: status, headers: ["Location": "https://evil.example/models"])])
            let client = try ModelDiscoveryClient(provider: .openAI, endpoint: ModelProvider.openAI.defaultEndpoint, key: "test", transport: mock)
            await #expect(throws: status == 302 ? ConnectorError.unsafeRedirect : ConnectorError.http(status)) { try await client.list() }
            #expect(await mock.requests.count == 1)
        }
    }

    @Test func presetsRejectDifferentCredentialDestinationAndInvalidHeaders() throws {
        #expect(throws: ConnectorError.invalidURL) {
            try ModelDiscoveryClient(provider: .anthropic, endpoint: "https://proxy.example/v1", key: "test")
        }
        #expect(throws: ConnectorError.invalidCredential) {
            try ModelDiscoveryClient(provider: .anthropic, endpoint: ModelProvider.anthropic.defaultEndpoint,
                                     key: "test", workspaceID: "workspace\r\nInjected: yes")
        }
        #expect(throws: ConnectorError.invalidCredential) {
            try ModelDiscoveryClient(provider: .openAI, endpoint: ModelProvider.openAI.defaultEndpoint, key: "test\nkey")
        }
    }

    @Test func anthropicUsesNativeMessagesAndStrictSchemaThenVerifiesEvidence() async throws {
        let mock = ProviderTransport([try reply(["content": [["type": "text", "text": output]], "stop_reason": "end_turn"])])
        let client = try LLMClient(endpoint: ModelProvider.anthropic.defaultEndpoint, key: "test", model: "claude-selected",
                                   transport: mock, provider: .anthropic)
        let events = try await client.extract(source: source, year: 2026, timeZone: "UTC", intent: "Only exams")
        #expect(events.count == 1)
        #expect(events.first?.state == .pending)
        let requests = await mock.requests
        let request = try #require(requests.first)
        #expect(request.url?.path == "/v1/messages")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["response_format"] == nil)
        #expect(body["tools"] == nil)
        #expect(body["system"] as? String != nil)
        let config = try #require(body["output_config"] as? [String: Any])
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["content"]?.contains("Only exams") == true)
        #expect(messages[1]["content"]?.contains(source.text) == true)
        #expect(events.first?.evidence == source.text)
    }

    @Test func anthropicRejectsIncompleteRefusalToolsAndInventedEvidence() async throws {
        let replies: [[String: Any]] = [
            ["content": [["type": "text", "text": output]], "stop_reason": "max_tokens"],
            ["content": [["type": "text", "text": output]], "stop_reason": "end_turn", "stop_details": ["type": "refusal"]],
            ["content": [["type": "tool_use", "name": "upload"]], "stop_reason": "tool_use"],
            ["content": [["type": "text", "text": output.replacingOccurrences(of: "Exam on November 20, 2026.", with: "Invented evidence")]], "stop_reason": "end_turn"]
        ]
        for response in replies {
            let mock = ProviderTransport([try reply(response)])
            let client = try LLMClient(endpoint: ModelProvider.anthropic.defaultEndpoint, key: "test", model: "claude-selected",
                                       transport: mock, provider: .anthropic)
            await #expect(throws: ConnectorError.self) { try await client.extract(source: source, year: 2026, timeZone: "UTC") }
            #expect(await mock.requests.count == 1)
        }
    }

    @Test func deepSeekUsesRootChatCompletionsAndLegacyConfigurationStillWorks() async throws {
        for provider in [ModelProvider.deepSeek, .custom] {
            let mock = ProviderTransport([try reply(["choices": [["message": ["content": output], "finish_reason": "stop"]]])])
            let endpoint = provider == .deepSeek ? provider.defaultEndpoint : "https://provider.example/v1/chat/completions"
            let client = try LLMClient(endpoint: endpoint, key: "test", model: "selected-model", transport: mock, provider: provider)
            #expect(try await client.extract(source: source, year: 2026, timeZone: "UTC").count == 1)
            let requests = await mock.requests
            #expect(requests.first?.url?.path == (provider == .deepSeek ? "/chat/completions" : "/v1/chat/completions"))
        }
    }

    @Test func userIntentIsBoundedBeforeAnyRequest() async throws {
        let mock = ProviderTransport([])
        let client = try LLMClient(endpoint: "https://provider.example/v1", key: "test", model: "model", transport: mock)
        await #expect(throws: ConnectorError.self) {
            try await client.extract(source: source, year: 2026, timeZone: "UTC", intent: String(repeating: "x", count: 2001))
        }
        #expect(await mock.requests.isEmpty)
    }

    @Test func academicCalendarScopeSurvivesExtraction() throws {
        let source = SourceDocument(courseID: "academic", title: "Academic calendar", text: "Fall break on November 20, 2026.", academicCalendarID: "fall-2026")
        let content = output.replacingOccurrences(of: "Exam", with: "Fall break").replacingOccurrences(of: #""kind":"exam""#, with: #""kind":"holiday""#)
        let events = try LLMClient.parse(content: content, source: source, year: 2026, timeZone: "UTC")
        #expect(events.first?.academicCalendarID == "fall-2026")
        #expect(events.first?.kind == .holiday)
        #expect(events.first?.state == .pending)
    }
}
