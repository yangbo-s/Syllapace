import SwiftUI
import SyllapaceKit
@main struct SyllapaceApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = UpdateController()
    @AppStorage("appLanguage") private var languagePreference = AppLanguage.system.rawValue
    var body: some Scene {
        let _ = languagePreference
        Window("Syllapace", id: "main") {
            ContentView(model: model)
                .environment(\.locale, L10n.locale)
                .task { updater.startIfNeeded() }
                .onOpenURL { url in if url.scheme == "syllapace", url.host == "event" { model.page = .timeline; model.selectedID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value ?? url.lastPathComponent; if let event = model.selectedEvent { model.editor = event } } }
        }.defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.string("Check for Updates…")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("New Event")) { model.newEvent() }.keyboardShortcut("n")
                Button(L10n.string("Add material…")) { model.showImport = true }.keyboardShortcut("o")
                Button(L10n.string("Export Calendar…")) { model.exportICS() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu(L10n.string("Sync")) {
                Button(L10n.string("Sync Canvas")) { model.syncCanvas() }.keyboardShortcut("r")
                Button(L10n.string("Sync Apple Calendar")) { model.syncCalendar() }
            }
            CommandGroup(after: .windowArrangement) { Button(L10n.string("Show Desktop Card")) { model.showDesktop() }.keyboardShortcut("d", modifiers: [.command, .shift]) }
            SidebarCommands()
        }
        Settings {
            SettingsView(model: model, updater: updater)
                .environment(\.locale, L10n.locale)
        }
        MenuBarExtra("Syllapace", systemImage: "calendar.badge.clock") {
            Button(L10n.string("Show Desktop Card")) { model.showDesktop() }
            Button(L10n.string("Sync Canvas")) { model.syncCanvas() }
            Button(L10n.string("Quit Syllapace")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
