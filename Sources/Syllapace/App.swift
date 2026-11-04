import SwiftUI
@main struct SyllapaceApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("Syllapace", id: "main") {
            ContentView(model: model)
                .onOpenURL { url in if url.scheme == "syllapace", url.host == "event" { model.page = .timeline; model.selectedID = url.lastPathComponent } }
        }.defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Event") { model.newEvent() }.keyboardShortcut("n")
                Button("Import Syllabus…") { model.showImport = true }.keyboardShortcut("o")
                Button("Export Calendar…") { model.exportICS() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Sync") {
                Button("Sync Canvas") { model.syncCanvas() }.keyboardShortcut("r")
                Button("Sync Apple Calendar") { model.syncCalendar() }
            }
            CommandGroup(after: .windowArrangement) { Button("Show Desktop Card") { model.showDesktop() }.keyboardShortcut("d", modifiers: [.command, .shift]) }
            SidebarCommands()
        }
        Settings { SettingsView(model: model) }
        MenuBarExtra("Syllapace", systemImage: "calendar.badge.clock") {
            Button("Show Desktop Card") { model.showDesktop() }
            Button("Sync Canvas") { model.syncCanvas() }
            Button("Quit Syllapace") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
