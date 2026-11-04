import SwiftUI
import SyllapaceKit
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var canvasToken = ""
    @State private var apiKey = ""
    @State private var result: String?
    @State private var resolving: AcademicEvent?
    var body: some View {
        TabView(selection: $model.settingsTab) {
            Form {
                Section("Your Canvas account") {
                    TextField("Canvas address", text: $model.canvasHost, prompt: Text("https://canvas.your-university.edu"))
                    SecureField("Access token", text: $canvasToken, prompt: Text("Leave blank to keep the saved token"))
                    HStack {
                        Button("Save connection") { saveCanvas() }.disabled(model.isDemo || model.canvasHost.isEmpty)
                        Button("Sync now") { model.syncCanvas() }.disabled(model.isDemo || model.busy)
                    }
                }
                Section { Toggle("Refresh every 10 minutes while running", isOn: $model.canvasAutoSync).onChange(of: model.canvasAutoSync) { _, value in UserDefaults.standard.set(value, forKey: "canvasAutoSync") }; Text("Your token is stored in macOS Keychain. Requests go directly to your Canvas instance.").font(.caption).foregroundStyle(.secondary) }
                if let result { Text(result).font(.caption).textSelection(.enabled) }
            }.formStyle(.grouped).tabItem { Label("Canvas", systemImage: "graduationcap") }.tag(0)
            Form {
                Section("Your model") {
                    TextField("API base URL", text: $model.modelEndpoint)
                    TextField("Model", text: $model.modelName, prompt: Text("Model identifier"))
                    SecureField("API key", text: $apiKey, prompt: Text("Leave blank to keep the saved key"))
                    Button("Save model") { saveModel() }.disabled(model.isDemo)
                }
                Section { Text("Use a provider with an OpenAI-compatible chat completions API. Only the document you choose is sent when you select Extract. Nothing is uploaded automatically.").font(.caption).foregroundStyle(.secondary) }
                if let result { Text(result).font(.caption) }
            }.formStyle(.grouped).tabItem { Label("Extraction", systemImage: "sparkles") }.tag(1)
            Form {
                Section("Apple Calendar") {
                    Text("Keep confirmed events in a dedicated Syllapace calendar.")
                    Text(model.calendar.status).font(.caption).foregroundStyle(.secondary)
                    Button("Connect & sync calendar") { model.syncCalendar() }.disabled(model.isDemo || model.busy)
                    Text("Full calendar access is needed to update your events and detect edits. Syllapace only manages its own calendar; local storage is the default.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Sync confirmed changes automatically", isOn: $model.calendarAutoSync)
                        .onChange(of: model.calendarAutoSync) { _, value in UserDefaults.standard.set(value, forKey: "calendarAutoSync"); if value { model.scheduleCalendarSync() } }
                    ForEach(Array(model.calendar.conflicts.enumerated()), id: \.offset) { index, message in
                        VStack(alignment: .leading) {
                            Text(message).font(.caption).foregroundStyle(Palette.warning)
                            if index < model.calendar.conflictEventIDs.count, let event = model.archive.events.first(where: { $0.id == model.calendar.conflictEventIDs[index] }) {
                                Button("Use Syllapace version") { resolving = event }.disabled(model.busy)
                            }
                        }
                    }
                }
                Section("Portable calendar") { Button("Export ICS…") { model.exportICS() } }
                if let notice = model.notice { Text(notice).font(.caption).textSelection(.enabled) }
            }.formStyle(.grouped).tabItem { Label("Calendar", systemImage: "calendar") }.tag(2)
        }.padding(16).frame(width: 580, height: 400).background(CalmFocus()).tint(Palette.accent)
        .confirmationDialog("Replace the Calendar version?", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } })) {
            Button("Use Syllapace version") { if let event = resolving { model.resolveCalendar(event) }; resolving = nil }
        } message: { Text("This will replace edits or recreate a deleted event in the dedicated Syllapace calendar. Other calendars are unaffected.") }
        .alert("Connection needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func saveCanvas() {
        do {
            _ = try CanvasClient(host: model.canvasHost, token: "validation")
            if !canvasToken.isEmpty { try CredentialStore.save(canvasToken, account: model.canvasCredentialAccount); canvasToken = "" }
            UserDefaults.standard.set(model.canvasHost, forKey: "canvasHost"); result = "Connection saved."
        } catch { result = error.localizedDescription }
    }
    private func saveModel() {
        do {
            _ = try LLMClient(endpoint: model.modelEndpoint, key: "validation", model: model.modelName)
            if !apiKey.isEmpty { try CredentialStore.save(apiKey, account: model.modelCredentialAccount); apiKey = "" }
            UserDefaults.standard.set(model.modelEndpoint, forKey: "modelEndpoint"); UserDefaults.standard.set(model.modelName, forKey: "modelName"); result = "Model saved."
        } catch { result = error.localizedDescription }
    }
}
