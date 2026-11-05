import SwiftUI
import SyllapaceKit

struct ModelSettingsView: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    @State private var provider: ModelProvider = .custom
    @State private var endpoint = ""
    @State private var workspaceID = ""
    @State private var apiKey = ""
    @State private var selectedModel = ""
    @State private var search = ""
    @State private var models: [AvailableModel] = []
    @State private var manual = false
    @State private var loading = false
    @State private var saving = false
    @State private var initialized = false
    @State private var notice: String?
    @State private var failure: String?
    @State private var requestID = UUID()
    @State private var task: Task<Void, Never>?
    @State private var cache: [String: [AvailableModel]] = [:]

    var body: some View {
        let _ = languagePreference
        Form {
            Section {
                Picker(L10n.string("Provider"), selection: Binding(get: { provider }, set: selectProvider)) {
                    ForEach(ModelProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.id("model-provider-\(languagePreference)")
                .id("model-provider-\(languagePreference)")
                if provider == .custom {
                    TextField(L10n.string("API base URL"), text: edited($endpoint), prompt: Text("https://api.example.com/v1"))
                }
                SecureField(L10n.string("API key"), text: edited($apiKey), prompt: Text(L10n.string("Leave blank to keep the saved key")))
                if provider == .anthropic {
                    DisclosureGroup(L10n.string("Workspace")) {
                        TextField(L10n.string("Workspace ID (optional)"), text: edited($workspaceID))
                        Text(L10n.string("Only needed when your Anthropic key requires a workspace."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button(L10n.string(models.isEmpty ? "Load models" : "Refresh models")) { loadModels() }
                        .disabled(model.isDemo || model.busy || loading || saving || endpoint.isEmpty)
                    if loading {
                        ProgressView().controlSize(.small)
                        Text(L10n.string("Loading models…")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.string("Cancel")) { cancelRequest() }.buttonStyle(.borderless)
                    }
                }
            }

            Section(L10n.string("Model")) {
                if !models.isEmpty, !manual {
                    TextField(L10n.string("Search models"), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.string("Search models"))
                    Picker(L10n.string("Model"), selection: $selectedModel) {
                        if selectedModel.isEmpty { Text(L10n.string("Choose a model")).tag("") }
                        ForEach(filteredModels) { option in
                            Text(option.displayName == option.id ? option.id : "\(option.displayName) · \(option.id)").tag(option.id)
                        }
                        if !selectedModel.isEmpty && !filteredModels.contains(where: { $0.id == selectedModel }) {
                            Text(selectedModel).tag(selectedModel)
                        }
                    }.id("model-choice-\(languagePreference)")
                    if filteredModels.isEmpty {
                        Text(L10n.string("No matching models.")).font(.caption).foregroundStyle(.secondary)
                    }
                } else if manual {
                    TextField(L10n.string("Model identifier"), text: $selectedModel)
                } else if !selectedModel.isEmpty {
                    LabeledContent(L10n.string("Saved model"), value: selectedModel)
                } else {
                    Text(L10n.string("Load your provider’s models, then choose one for extraction."))
                        .foregroundStyle(.secondary)
                }
                Toggle(L10n.string("Enter a model identifier manually"), isOn: $manual)
                    .toggleStyle(.checkbox).tint(Palette.actionAccent)
                    .font(.caption)
                Toggle(L10n.string("Automatically organize course materials"), isOn: $model.automaticCuration)
                    .onChange(of: model.automaticCuration) { _, enabled in
                        if !model.isDemo { UserDefaults.standard.set(enabled, forKey: "automaticCuration") }
                        if enabled { model.scheduleCuration() } else { model.cancelCuration() }
                    }
                Text(L10n.string("Selected course materials are sent directly to this model when they change. Relevant dates are added automatically.")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.string("Save model")) { saveModel() }
                    .disabled(selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isDemo || model.busy || loading || saving)
                if let failure {
                    Text(failure).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled)
                } else if let notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(L10n.string("Your key stays in macOS Keychain. Materials go directly to your provider during automatic organization or when you explicitly use AI. Local-only imports are excluded from automatic requests."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(saving)
        .onAppear(perform: initialize)
        .onDisappear { cancelRequest() }
        .onChange(of: languagePreference) { _, _ in notice = nil; failure = nil }
    }

    private var filteredModels: [AvailableModel] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? models : models.filter {
            $0.id.localizedCaseInsensitiveContains(query) || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }
    private var connection: DraftConnection {
        DraftConnection(provider: provider, endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                        workspace: workspaceID.trimmingCharacters(in: .whitespacesAndNewlines), key: apiKey)
    }
    private func initialize() {
        guard !initialized else { return }
        initialized = true
        provider = model.modelProvider
        endpoint = model.modelEndpoint
        workspaceID = model.modelWorkspaceID
        selectedModel = model.modelName
        if model.isDemo { models = [AvailableModel(id: "example-model", displayName: "Example model · Demo"), AvailableModel(id: "example-fast", displayName: "Example fast model · Demo")] }
    }
    private func edited(_ field: Binding<String>) -> Binding<String> {
        Binding(get: { field.wrappedValue }, set: { value in
            invalidateDiscovery()
            field.wrappedValue = value
        })
    }
    private func selectProvider(_ value: ModelProvider) {
        guard provider != value else { return }
        invalidateDiscovery(clearCache: false)
        provider = value
        endpoint = value == .custom ? (model.modelProvider == .custom ? model.modelEndpoint : "") : value.defaultEndpoint
        apiKey = ""
        workspaceID = value == model.modelProvider ? model.modelWorkspaceID : ""
        selectedModel = value == model.modelProvider ? model.modelName : ""
        manual = false
        models = cache[connection.cacheKey] ?? []
        if !models.isEmpty { notice = L10n.string("Showing models from this session. Refresh to check availability.") }
    }
    private func cancelRequest() {
        requestID = UUID()
        task?.cancel()
        task = nil
        loading = false
        saving = false
    }
    private func invalidateDiscovery(clearCache: Bool = true) {
        cancelRequest()
        models = []
        if clearCache { cache.removeAll() }
        search = ""
        notice = nil
        failure = nil
    }
    private func loadModels() {
        cancelRequest()
        let draft = connection
        let id = requestID
        loading = true
        notice = nil
        failure = nil
        task = Task {
            defer { if id == requestID { loading = false; task = nil } }
            do {
                // Validate before a potentially interactive Keychain read.
                _ = try ModelDiscoveryClient(provider: draft.provider, endpoint: draft.endpoint,
                                             key: draft.key.isEmpty ? "validation" : draft.key, workspaceID: draft.workspace)
                let key = try await credential(for: draft)
                try Task.checkCancellation()
                let client = try ModelDiscoveryClient(provider: draft.provider, endpoint: draft.endpoint, key: key, workspaceID: draft.workspace)
                let available = try await client.list()
                guard id == requestID, connection == draft else { return }
                if !draft.key.isEmpty { try await CredentialStore.saveAsync(draft.key, account: draft.account) }
                guard id == requestID, connection == draft else { return }
                models = available
                cache[draft.cacheKey] = available
                manual = available.isEmpty
                if !available.contains(where: { $0.id == selectedModel }) { selectedModel = "" }
                if available.isEmpty {
                    notice = L10n.string("Connected, but no text models were listed. Enter a model identifier or check your provider’s API access.")
                } else {
                    notice = L10n.string("Connected. Choose a model and save it.")
                }
            } catch is CancellationError {
                // Editing the connection or closing Settings cancels the previous result.
            } catch {
                guard id == requestID, connection == draft else { return }
                if let connector = error as? ConnectorError,
                   connector == .http(404) || connector == .http(405) || connector == .http(501) || connector == .invalidResponse {
                    failure = error.localizedDescription + " " + L10n.string("Try again, or enter a model identifier manually if this service cannot list models.")
                } else {
                    failure = error.localizedDescription
                }
            }
        }
    }
    private func saveModel() {
        cancelRequest()
        let draft = connection
        let name = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = requestID
        saving = true
        notice = nil
        failure = nil
        task = Task {
            defer { if id == requestID { saving = false; task = nil } }
            do {
                _ = try LLMClient(endpoint: draft.endpoint, key: draft.key.isEmpty ? "validation" : draft.key, model: name,
                                  provider: draft.provider, workspaceID: draft.workspace)
                let key = try await credential(for: draft)
                try Task.checkCancellation()
                guard id == requestID, connection == draft else { return }
                if !draft.key.isEmpty { try await CredentialStore.saveAsync(key, account: draft.account) }
                guard id == requestID, connection == draft else { return }
                model.modelProvider = draft.provider
                model.cancelCuration()
                model.modelEndpoint = draft.endpoint
                model.modelWorkspaceID = draft.workspace
                model.modelName = name
                UserDefaults.standard.set(draft.provider.rawValue, forKey: "modelProvider")
                UserDefaults.standard.set(draft.endpoint, forKey: "modelEndpoint")
                UserDefaults.standard.set(draft.workspace, forKey: "modelWorkspaceID")
                UserDefaults.standard.set(name, forKey: "modelName")
                apiKey = ""
                model.scheduleCuration()
                notice = manual ? L10n.string("Model saved. Availability will be checked when you extract a document.") : L10n.string("Model saved.")
            } catch is CancellationError {
            } catch {
                guard id == requestID, connection == draft else { return }
                failure = error.localizedDescription
            }
        }
    }
    private func credential(for draft: DraftConnection) async throws -> String {
        if !draft.key.isEmpty { return draft.key }
        guard let key = try await CredentialStore.readAsync(draft.account), !key.isEmpty else {
            throw ConnectorError.missingCredential
        }
        return key
    }
}

private struct DraftConnection: Equatable {
    let provider: ModelProvider
    let endpoint: String
    let workspace: String
    let key: String
    // Endpoint-scoped accounts preserve pre-0.3.0 credentials without exposing them to another host.
    var account: String { CredentialStore.modelKey + ":" + endpoint }
    var cacheKey: String { provider.rawValue + "\n" + endpoint + "\n" + workspace }
}
