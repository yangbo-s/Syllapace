import SwiftUI
import SyllapaceKit

struct SchoolSearchView: View {
    let onSelect: (URL) -> Void
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var schools: [CanvasSchool] = []
    @State private var selectedID: String?
    @State private var searched = false
    @State private var loading = false
    @State private var manual = false
    @State private var address = ""
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var directory = CanvasSchoolDirectory()
    @FocusState private var focus: Field?
    private enum Field { case search, address }

    var body: some View {
        let _ = languagePreference
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Find your school")).font(.title2.weight(.semibold))
            if manual {
                TextField(L10n.string("Canvas address"), text: $address, prompt: Text("https://canvas.your-university.edu"))
                    .textFieldStyle(.roundedBorder).focused($focus, equals: .address)
                    .onSubmit { chooseAddress() }
                Text(L10n.string("Use your school’s Canvas address, not its general website."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 8) {
                    TextField(L10n.string("School name"), text: $query)
                        .textFieldStyle(.roundedBorder).focused($focus, equals: .search)
                        .onSubmit { search() }
                        .onChange(of: query) { _, _ in
                            cancelSearch()
                            schools = []; selectedID = nil; searched = false; failure = nil
                        }
                    Button(L10n.string("Search")) { search() }.disabled(!canSearch || loading)
                }
                Group {
                    if loading {
                        ProgressView(L10n.string("Searching schools…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !schools.isEmpty {
                        List(schools, selection: $selectedID) { school in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(school.name).lineLimit(2)
                                Text(school.url.host ?? school.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4).tag(school.id)
                        }.listStyle(.inset).clipShape(.rect(cornerRadius: 8))
                    } else if searched, failure == nil {
                        ContentUnavailableView(L10n.string("No schools found"), systemImage: "magnifyingglass",
                            description: Text(L10n.string("Try a fuller school name, or enter your Canvas address.")))
                    } else {
                        ContentUnavailableView(L10n.string("Search the Canvas directory"), systemImage: "building.2",
                            description: Text(L10n.string("Enter at least two characters of your school’s name.")))
                    }
                }.frame(maxWidth: .infinity, minHeight: 176, maxHeight: .infinity)
            }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button(L10n.string(manual ? "Search by school name" : "Enter Canvas address")) {
                    cancelSearch(); manual.toggle(); failure = nil
                    focus = manual ? .address : .search
                }.buttonStyle(.borderless)
                Spacer()
                Button(L10n.string("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.string("Use address")) {
                    if manual { chooseAddress() }
                    else if let school = schools.first(where: { $0.id == selectedID }) { finish(school.url) }
                }
                .buttonStyle(.borderedProminent).tint(Palette.actionAccent)
                .disabled(manual ? address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selectedID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 500, height: 400)
        .onAppear { focus = .search }
        .onDisappear { cancelSearch() }
        .onChange(of: languagePreference) { _, _ in failure = nil }
    }

    private var canSearch: Bool { (2...200).contains(query.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    private func cancelSearch() {
        task?.cancel(); task = nil; requestID = UUID(); loading = false
    }
    private func search() {
        guard canSearch else { return }
        cancelSearch()
        let text = query
        let id = requestID
        loading = true; searched = false; failure = nil; selectedID = nil
        task = Task {
            defer { if requestID == id { loading = false; task = nil } }
            do {
                let result = try await directory.search(name: text)
                guard requestID == id, query == text else { return }
                schools = result; searched = true
            } catch is CancellationError {
            } catch {
                guard requestID == id, query == text else { return }
                schools = []; searched = true
                failure = L10n.string("The school directory is unavailable. Try again or enter your Canvas address.")
            }
        }
    }
    private func chooseAddress() {
        do { finish(try ConnectorURL.canvasOrigin(address)) }
        catch { failure = error.localizedDescription }
    }
    private func finish(_ url: URL) { onSelect(url); dismiss() }
}
