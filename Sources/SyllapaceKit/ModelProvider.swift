import Foundation

public enum ModelProvider: String, Codable, CaseIterable, Sendable {
    case openAI, anthropic, deepSeek, custom

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic · Claude"
        case .deepSeek: "DeepSeek"
        case .custom: L10n.string("Custom service")
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .custom: ""
        }
    }
}

/// Shared routing keeps discovery and extraction on the same, explicitly chosen service.
struct ModelServiceEndpoint: Sendable {
    let provider: ModelProvider
    let base: URL
    let workspaceID: String?

    init(provider: ModelProvider, endpoint: String, workspaceID: String?) throws {
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw ConnectorError.invalidURL
        }
        if provider != .custom {
            guard let expected = URL(string: provider.defaultEndpoint),
                  host.lowercased() == expected.host, (parts.port ?? 443) == 443 else {
                throw ConnectorError.invalidURL
            }
        }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for suffix in ["chat/completions", "messages", "models"] {
            if path == suffix { path = ""; break }
            if path.hasSuffix("/" + suffix) { path.removeLast(suffix.count + 1); break }
        }
        if path.isEmpty && provider != .deepSeek { path = "v1" }
        parts.path = path.isEmpty ? "" : "/" + path
        guard let base = parts.url else { throw ConnectorError.invalidURL }
        let workspace = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let workspace, !workspace.isEmpty {
            guard workspace.count <= 200, workspace.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
                throw ConnectorError.invalidCredential
            }
        }
        self.provider = provider
        self.base = base
        self.workspaceID = workspace?.isEmpty == false ? workspace : nil
    }

    func request(route: String, key: String) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConnectorError.missingCredential }
        guard key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw ConnectorError.invalidCredential }
        var request = URLRequest(url: base.appendingPathComponent(route))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .anthropic {
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            if let workspaceID { request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id") }
        }
        return request
    }
}
