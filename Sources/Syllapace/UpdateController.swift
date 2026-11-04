import AppKit
import Combine
import Sparkle
import SyllapaceKit

/// Sparkle owns version comparison, download verification and replacement of
/// the application. GitHub only hosts the feed and signed update archive.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isAvailable = false
    @Published private(set) var startupError: String?
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard isAvailable, let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var subscriptions = Set<AnyCancellable>()
    private var started = false

    var isIsolatedRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_DEMO"] == "1" || environment["APP_SEED"] == "1"
            || environment["APP_SNAPSHOT"] != nil || environment["APP_SELFTEST"] == "1"
    }

    func startIfNeeded() {
        guard !started, !isIsolatedRun else { return }
        started = true
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host == "github.com" else {
            startupError = L10n.string("Updates are unavailable because this build is missing its update configuration.")
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self, self.automaticallyChecksForUpdates != value else { return }
                self.automaticallyChecksForUpdates = value
            }
            .store(in: &subscriptions)
        do {
            try updater.start()
            isAvailable = true
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            canCheckForUpdates = updater.canCheckForUpdates
        } catch {
            startupError = error.localizedDescription
            canCheckForUpdates = false
        }
    }

    func checkForUpdates() {
        startIfNeeded()
        guard isAvailable, canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }
}
