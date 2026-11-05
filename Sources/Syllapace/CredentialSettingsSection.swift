import SwiftUI
import SyllapaceKit

struct CredentialSettingsSection: View {
    @Bindable var model: AppModel
    var savingConnection: Bool

    var body: some View {
        Section(L10n.string("Credential storage")) {
            Picker(L10n.string("Save tokens and API keys in"), selection: Binding(
                get: { model.credentialStorage },
                set: { model.updateCredentialStorage($0) }
            )) {
                ForEach(CredentialStorage.allCases, id: \.self) { Text(L10n.string($0.label)).tag($0) }
            }
            .disabled(!model.credentialStorageLoaded || model.busy || savingConnection || model.isDemo)
            if model.credentialStorage == .local {
                Text(L10n.string("Saved on this Mac without Keychain prompts. The file is not encrypted; other apps running as you may read it."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.string("Import from Keychain…")) { model.updateCredentialStorage() }
                        .disabled(!model.credentialStorageLoaded || model.busy || savingConnection || model.isDemo)
                    if model.credentialsChanging { ProgressView().controlSize(.small) }
                }
                Text(L10n.string("Upgrading? Import your existing keys or enter them again in Canvas and Models. Import may ask for macOS permission; originals stay in Keychain."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.string("macOS protects your keys and may ask for access. Switching to Local file requires importing or re-entering your keys."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.credentialsChanging { ProgressView().controlSize(.small) }
            }
            if let failure = model.credentialStorageError {
                Text(failure).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled)
                if !model.credentialStorageLoaded {
                    Button(L10n.string("Try again")) { Task { await model.loadCredentialStorage() } }
                }
            } else if let status = model.credentialStorageStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
