import SwiftUI
import SyllapaceKit

struct CourseAppearanceView: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    let course: Course
    @State private var appearance = CourseAppearance()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let _ = languagePreference
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.string("Course display")).font(.title2.weight(.semibold))
            Text(course.localizedName).foregroundStyle(.secondary).textSelection(.enabled)
            Form {
                Picker(L10n.string("Display as"), selection: $appearance.mode) {
                    Text(L10n.string("Use default")).tag(nil as CourseDisplayMode?)
                    ForEach(CourseDisplayMode.allCases, id: \.self) { Text(L10n.string($0.label)).tag(Optional($0)) }
                }
                .id("course-display-\(languagePreference)")
                TextField(L10n.string("Custom name"), text: $appearance.alias)
                LabeledContent(L10n.string("Preview"), value: appearance.title(for: course, defaultMode: model.archive.courseDisplayMode ?? .code))
            }
            HStack { Spacer(); Button(L10n.string("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(L10n.string("Save")) { model.saveAppearance(appearance, for: course.id); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Palette.actionAccent) }
        }.padding(28).frame(width: 480).background(CalmFocus()).onAppear { appearance = model.archive.courseAppearances?[course.id] ?? CourseAppearance() }
    }
}
