import SwiftUI
import SyllapaceKit

struct CourseScopeView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showOtherCourses = false

    private var primaryCourses: [Course] {
        model.canvasCourses.filter { model.draftTermID == nil || $0.term?.id == model.draftTermID }
    }
    private var otherCourses: [Course] {
        guard model.draftTermID != nil else { return [] }
        return model.canvasCourses.filter {
            $0.term?.id != model.draftTermID && ($0.term == nil || $0.term?.name.caseInsensitiveCompare("Default Term") == .orderedSame)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Choose your semester")).font(.system(size: 22, weight: .medium, design: .rounded))
                Text(L10n.string("Only selected courses are synced and shown in your workspace."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.gridProbe("course-scope-heading", area: "course-scope")
            Picker(L10n.string("Semester"), selection: $model.draftTermID) {
                ForEach(model.availableTerms) { term in Text(term.name).tag(Optional(term.id)) }
                Divider()
                Text(L10n.string("All semesters")).tag(String?.none)
            }.pickerStyle(.menu).disabled(model.busy).gridProbe("course-scope-picker", area: "course-scope")
                .onChange(of: model.draftTermID) { _, termID in
                    if let selection = model.archive.canvasSelection, selection.termID == termID {
                        model.draftCourseIDs = selection.courseIDs.intersection(Set(model.canvasCourses.map(\.id)))
                    } else {
                        model.draftCourseIDs = Set(model.canvasCourses.filter { termID != nil && $0.term?.id == termID }.map(\.id))
                    }
                }
            Divider().frame(height: 0)
            if model.canvasCourses.isEmpty {
                ContentUnavailableView(L10n.string("No courses available"), systemImage: "graduationcap", description: Text(L10n.string("Refresh the course list or check your Canvas connection.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(primaryCourses) { course in courseRow(course, showTerm: model.draftTermID == nil) }
                        if !otherCourses.isEmpty {
                            DisclosureGroup(L10n.string("Other course spaces"), isExpanded: $showOtherCourses) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(L10n.string("Portals and courses without a semester are optional."))
                                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                                    ForEach(otherCourses) { course in courseRow(course, showTerm: false) }
                                }
                            }.padding(.top, 20)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.gridProbe("course-scope-list", area: "course-scope")
            }
            Divider().frame(height: 0)
            HStack(spacing: 12) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Button { model.discoverCanvasCourses() } label: { Image(systemName: "arrow.clockwise") }.help(L10n.string("Refresh course list")).disabled(model.isDemo) }
                Text(L10n.format("%ld courses selected", model.draftCourseIDs.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.string("Save & sync")) { model.applyCanvasSelection() }
                    .buttonStyle(.borderedProminent).tint(Palette.actionAccent)
                    .keyboardShortcut(.defaultAction).disabled(model.busy || model.canvasCourses.isEmpty)
            }.gridProbe("course-scope-actions", area: "course-scope", edge: "footer")
        }.padding(24).frame(width: 600, height: 540).gridArea("course-scope", inset: 24)
            .background(CalmFocus()).tint(Palette.accent)
    }

    private func courseRow(_ course: Course, showTerm: Bool) -> some View {
        Toggle(isOn: Binding(get: { model.draftCourseIDs.contains(course.id) }, set: { selected in
            if selected { model.draftCourseIDs.insert(course.id) } else { model.draftCourseIDs.remove(course.id) }
        })) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(course.code).fontWeight(.medium)
                    if showTerm { Text(course.term?.name ?? L10n.string("No semester")).font(.caption).foregroundStyle(.secondary) }
                }
                if course.name != course.code { Text(course.name).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(.checkbox).tint(Palette.actionAccent).disabled(model.busy).padding(.vertical, 12)
    }
}
