import Foundation

public struct AvailableModel: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String? = nil) {
        self.id = id
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = name?.isEmpty == false ? String(name!.prefix(240)) : id
    }
}

/// Lists models using each provider's API. Credentials never follow a redirect or a supplied next-page URL.
public struct ModelDiscoveryClient: Sendable {
    private let service: ModelServiceEndpoint
    private let key: String
    private let transport: any HTTPTransport

    public init(provider: ModelProvider, endpoint: String, key: String,
                transport: any HTTPTransport = BoundedHTTPTransport(), workspaceID: String? = nil) throws {
        self.service = try ModelServiceEndpoint(provider: provider, endpoint: endpoint, workspaceID: workspaceID)
        _ = try service.request(route: "models", key: key)
        self.key = key
        self.transport = transport
    }

    public func list() async throws -> [AvailableModel] {
        var models: [String: AvailableModel] = [:]
        var cursors = Set<String>()
        var cursor: String?
        for _ in 0..<10 {
            try Task.checkCancellation()
            var request = try service.request(route: "models", key: key)
            if service.provider == .anthropic {
                var parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                parts.queryItems = [URLQueryItem(name: "limit", value: "100")]
                if let cursor { parts.queryItems?.append(URLQueryItem(name: "after_id", value: cursor)) }
                request.url = parts.url
            }
            let reply = try await transport.send(request, maxBytes: 1024 * 1024)
            try Task.checkCancellation()
            if (300..<400).contains(reply.status) { throw ConnectorError.unsafeRedirect }
            guard (200..<300).contains(reply.status) else { throw ConnectorError.http(reply.status) }
            let page: ModelPage
            do { page = try JSONDecoder().decode(ModelPage.self, from: reply.data) }
            catch { throw ConnectorError.invalidResponse }
            guard page.data.count <= 1000 else { throw ConnectorError.responseTooLarge }
            for item in page.data {
                guard !item.id.isEmpty, item.id.count <= 200,
                      !item.id.contains(where: { $0.isWhitespace || $0.isNewline }),
                      item.id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                    throw ConnectorError.invalidResponse
                }
                if item.canExtract(provider: service.provider) {
                    if models[item.id] == nil || item.display_name != nil || item.name != nil {
                        models[item.id] = AvailableModel(id: item.id, displayName: item.display_name ?? item.name)
                    }
                }
            }
            guard models.count <= 1000 else { throw ConnectorError.responseTooLarge }
            guard page.has_more == true else {
                return models.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            }
            guard service.provider == .anthropic, let last = page.last_id,
                  page.data.contains(where: { $0.id == last }), cursors.insert(last).inserted else {
                throw ConnectorError.invalidResponse
            }
            cursor = last
        }
        throw ConnectorError.tooManyPages
    }
}

private struct ModelPage: Decodable {
    let data: [ModelRecord]
    let has_more: Bool?
    let last_id: String?
}

private struct ModelRecord: Decodable {
    let id: String
    let display_name: String?
    let name: String?
    let input_modalities: [String]?
    let output_modalities: [String]?
    let capabilities: Capabilities?
    struct Capabilities: Decodable {
        let structured_outputs: Support?
        struct Support: Decodable { let supported: Bool? }
    }
    private enum CodingKeys: String, CodingKey {
        case id, display_name, name, input_modalities, output_modalities, capabilities
    }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        display_name = try? container.decode(String.self, forKey: .display_name)
        name = try? container.decode(String.self, forKey: .name)
        input_modalities = try? container.decode([String].self, forKey: .input_modalities)
        output_modalities = try? container.decode([String].self, forKey: .output_modalities)
        capabilities = try? container.decode(Capabilities.self, forKey: .capabilities)
    }

    func canExtract(provider: ModelProvider) -> Bool {
        if let input_modalities, !input_modalities.contains("text") { return false }
        if let output_modalities, !output_modalities.contains("text") { return false }
        if provider == .anthropic, capabilities?.structured_outputs?.supported == false { return false }
        // Model lists do not consistently expose capabilities. Exclude known non-chat families;
        // preserve unknown/custom identifiers so a new provider model does not need an app update.
        let name = id.lowercased()
        let incompatible = ["embedding", "whisper", "tts-", "dall-e", "moderation", "sora", "realtime", "transcribe", "audio", "gpt-image", "babbage", "davinci", "-instruct"]
        return !incompatible.contains(where: name.contains)
    }
}
