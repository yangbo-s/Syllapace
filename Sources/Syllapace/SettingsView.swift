import SwiftUI
import SyllapaceKit
struct SettingsView: View {
    @Bindable var model: AppModel
    @ObservedObject var updater: UpdateController
    @AppStorage("appLanguage") private var languagePreference = AppLanguage.system.rawValue
    @State private var canvasToken = ""
    @State private var apiKey = ""
    @State private var result: String?
    @State private var resolving: AcademicEvent?
    @State private var saving = false
    var body: some View {
        TabView(selection: $model.settingsTab) {
            generalSettings.tabItem { Label(L10n.string("General"), systemImage: "gearshape") }.tag(3)
            Form {
                Section(L10n.string("Your Canvas account")) {
                    TextField(L10n.string("Canvas address"), text: $model.canvasHost, prompt: Text("https://canvas.your-university.edu")).disabled(saving)
                        .onChange(of: model.canvasHost) { _, _ in model.invalidateCanvasConnection() }
                    SecureField(L10n.string("Access token"), text: $canvasToken, prompt: Text(L10n.string("Leave blank to keep the saved token"))).disabled(saving)
                    HStack {
                        Button(L10n.string("Save connection")) { saveCanvas() }.disabled(model.isDemo || model.canvasHost.isEmpty || saving || model.busy)
                        Button(L10n.string("Sync now")) { model.syncCanvas() }.disabled(model.isDemo || model.busy || saving)
                    }
                }
                Section(L10n.string("Courses")) {
                    HStack { Text(model.selectedSemesterName); Spacer(); Button(L10n.string("Manage courses…")) { model.revealMain(); model.manageCanvasCourses() }.disabled(model.busy) }
                }
                Section { Toggle(L10n.string("Refresh every 10 minutes while running"), isOn: $model.canvasAutoSync).onChange(of: model.canvasAutoSync) { _, value in UserDefaults.standard.set(value, forKey: "canvasAutoSync") }; Text(L10n.string("Your token is stored in macOS Keychain. Requests go directly to your Canvas instance.")).font(.caption).foregroundStyle(.secondary) }
                Section {
                    Toggle(L10n.string("Renew token automatically"), isOn: Binding(get: { model.tokenRenewal.enabled }, set: { value in
                        model.tokenRenewal.setEnabled(value)
                        if value { model.checkCanvasToken(force: true) }
                    })).disabled(model.isDemo)
                        .help(L10n.string("Renews before expiry while Syllapace is open, when your school allows it."))
                    Text(model.tokenRenewal.statusText).font(.caption).foregroundStyle(.secondary)
                }
                if let result { Text(result).font(.caption).textSelection(.enabled) }
            }.formStyle(.grouped).tabItem { Label("Canvas", systemImage: "graduationcap") }.tag(0)
            Form {
                Section(L10n.string("Your model")) {
                    TextField(L10n.string("API base URL"), text: $model.modelEndpoint).disabled(saving)
                    TextField(L10n.string("Model"), text: $model.modelName, prompt: Text(L10n.string("Model identifier"))).disabled(saving)
                    SecureField(L10n.string("API key"), text: $apiKey, prompt: Text(L10n.string("Leave blank to keep the saved key"))).disabled(saving)
                    Button(L10n.string("Save model")) { saveModel() }.disabled(model.isDemo || saving || model.busy)
                }
                Section { Text(L10n.string("Use a provider with an OpenAI-compatible chat completions API. Only the document you choose is sent when you select Extract. Nothing is uploaded automatically.")).font(.caption).foregroundStyle(.secondary) }
                if let result { Text(result).font(.caption) }
            }.formStyle(.grouped).tabItem { Label(L10n.string("Extraction"), systemImage: "sparkles") }.tag(1)
            Form {
                Section(L10n.string("Apple Calendar")) {
                    Text(L10n.string("Keep confirmed events in a dedicated Syllapace calendar."))
                    Text(model.calendar.status).font(.caption).foregroundStyle(.secondary)
                    Button(L10n.string("Connect & sync calendar")) { model.syncCalendar() }.disabled(model.isDemo || model.busy || saving)
                    Text(L10n.string("Full calendar access is needed to update your events and detect edits. Syllapace only manages its own calendar; local storage is the default.")).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle(L10n.string("Sync confirmed changes automatically"), isOn: $model.calendarAutoSync)
                        .onChange(of: model.calendarAutoSync) { _, value in UserDefaults.standard.set(value, forKey: "calendarAutoSync"); if value { model.scheduleCalendarSync() } }
                    ForEach(Array(model.calendar.conflicts.enumerated()), id: \.offset) { index, message in
                        if index < model.calendar.conflictEventIDs.count, let event = model.scopedEvents.first(where: { $0.id == model.calendar.conflictEventIDs[index] }) {
                            VStack(alignment: .leading) {
                                Text(message).font(.caption).foregroundStyle(Palette.warning)
                                Button(L10n.string("Use Syllapace version")) { resolving = event }.disabled(model.busy)
                            }
                        }
                    }
                }
                Section(L10n.string("Portable calendar")) { Button(L10n.string("Export ICS…")) { model.exportICS() } }
                if let notice = model.notice { Text(notice).font(.caption).textSelection(.enabled) }
            }.formStyle(.grouped).tabItem { Label(L10n.string("Calendar"), systemImage: "calendar") }.tag(2)
        }.padding(16).frame(width: 580, height: 400).background(CalmFocus()).tint(Palette.accent)
        .onChange(of: languagePreference) { _, value in
            // This preference is scoped to Syllapace, not the macOS language.
            if value == AppLanguage.system.rawValue { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else { UserDefaults.standard.set([value], forKey: "AppleLanguages") }
            result = nil
            model.notice = nil
            model.error = nil
        }
        .confirmationDialog(L10n.string("Replace the Calendar version?"), isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } })) {
            Button(L10n.string("Use Syllapace version")) { if let event = resolving { model.resolveCalendar(event) }; resolving = nil }
        } message: { Text(L10n.string("This will replace edits or recreate a deleted event in the dedicated Syllapace calendar. Other calendars are unaffected.")) }
        .alert(L10n.string("Connection needs attention"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L10n.string("OK")) { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var generalSettings: some View {
        Form {
            Section(L10n.string("Language")) {
                Picker(L10n.string("App language"), selection: $languagePreference) {
                    Text(L10n.string("Follow system")).tag(AppLanguage.system.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese.rawValue)
                }.id("app-language-\(languagePreference)")
                Text(L10n.string("System menus and update windows use the new language after reopening Syllapace."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.string("Updates")) {
                LabeledContent(L10n.string("Version"), value: appVersion)
                Toggle(L10n.string("Automatically check for updates"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                )).disabled(!updater.isAvailable)
                HStack {
                    Button(L10n.string("Check for Updates…")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Link(L10n.string("Release notes"), destination: URL(string: "https://github.com/yangbo-s/Syllapace/releases")!)
                }
                if let error = updater.startupError {
                    Text(error).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled)
                } else {
                    Text(L10n.string("Updates are downloaded from GitHub and installed after your confirmation."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
    private func saveCanvas() {
        let host = model.canvasHost
        let token = canvasToken
        let account = model.canvasCredentialAccount
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try CanvasClient(host: host, token: token.isEmpty ? "validation" : token)
                if !token.isEmpty { try await CredentialStore.saveAsync(token, account: account) }
                guard model.canvasHost == host else { return }
                if UserDefaults.standard.string(forKey: "canvasHost") != host {
                    model.archive.canvasSelection = nil
                    model.selectedID = nil; model.courseFilter = nil
                    model.save()
                }
                UserDefaults.standard.set(host, forKey: "canvasHost"); canvasToken = ""; result = L10n.string("Connection saved.")
                model.checkCanvasToken(force: true)
            } catch { result = error.localizedDescription }
        }
    }
    private func saveModel() {
        let endpoint = model.modelEndpoint
        let name = model.modelName
        let key = apiKey
        let account = model.modelCredentialAccount
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try LLMClient(endpoint: endpoint, key: key.isEmpty ? "validation" : key, model: name)
                if !key.isEmpty { try await CredentialStore.saveAsync(key, account: account) }
                guard model.modelEndpoint == endpoint, model.modelName == name else { return }
                UserDefaults.standard.set(endpoint, forKey: "modelEndpoint"); UserDefaults.standard.set(name, forKey: "modelName"); apiKey = ""; result = L10n.string("Model saved.")
            } catch { result = error.localizedDescription }
        }
    }
}
