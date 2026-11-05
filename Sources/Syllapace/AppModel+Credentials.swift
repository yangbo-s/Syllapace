import Foundation
import SyllapaceKit

extension AppModel {
    func loadCredentialStorage() async {
        do {
            credentialStorage = try await CredentialStore.storage()
            credentialStorageLoaded = true
            credentialStorageError = nil
        } catch { credentialStorageError = error.localizedDescription }
    }

    /// A nil target explicitly imports existing keys. No import runs at launch.
    func updateCredentialStorage(_ target: CredentialStorage? = nil) {
        guard !busy, !isDemo, credentialStorageLoaded else { return }
        busy = true; credentialsChanging = true
        credentialStorageStatus = nil; credentialStorageError = nil
        cancelCuration(); tokenRenewal.cancel()
        Task {
            defer {
                credentialsChanging = false; busy = false
                checkCanvasToken(); scheduleCuration()
            }
            do {
                if let target {
                    try await CredentialStore.setStorage(target)
                    credentialStorage = target
                    credentialStorageStatus = L10n.string(target == .local
                        ? "Local storage selected. Import your existing keys or enter them again."
                        : "Keychain selected. Any saved local keys were moved successfully.")
                } else {
                    let count = try await CredentialStore.importFromKeychain()
                    credentialStorageStatus = count == 0 ? L10n.string("No additional keys to import. Existing local keys were kept.")
                        : L10n.format("Imported %ld credentials. Existing local keys were kept.", count)
                }
            } catch { credentialStorageError = error.localizedDescription }
        }
    }
}
