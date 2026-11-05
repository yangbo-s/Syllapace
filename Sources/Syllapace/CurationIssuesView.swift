import SwiftUI
import SyllapaceKit

struct CurationIssuesView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("Needs information")).font(.system(size: 24, weight: .semibold))
            if model.curationIssues.isEmpty && model.unresolvedEvents.isEmpty && model.curationFailures.isEmpty && model.officialScheduleErrors.isEmpty {
                ContentUnavailableView(L10n.string("All organized"), systemImage: "checkmark.circle", description: Text(L10n.string("Relevant dates are added automatically. Only unresolved details appear here.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(model.curationIssues, id: \.source.id) { issue in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(issue.source.title).fontWeight(.semibold)
                                    Spacer()
                                    Button(L10n.string("Read")) { model.readingSource = issue.source }
                                    Button(L10n.string("Retry")) { model.extractAI(issue.source) }.disabled(model.curationTask != nil)
                                }
                                Text(issue.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Divider()
                        }
                        ForEach(model.unresolvedEvents) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(event.title).fontWeight(.semibold)
                                    Text(L10n.string(event.userEdited ? "A source change overlaps your edit." : model.scopedEvents.first(where: { $0.id == event.id })?.state != .conflict ? "The sources give different dates for this event." : "The source changed this event’s time.")).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L10n.string("Resolve")) { model.editor = model.scopedEvents.first { $0.id == event.id } ?? event }
                            }
                        }
                        if !model.officialScheduleErrors.isEmpty {
                            HStack {
                                Text(L10n.string("Official class schedule")).font(.headline)
                                Spacer()
                                Button(L10n.string("Retry")) { Task { await model.refreshOfficialSchedules(force: true) } }.disabled(model.fetchingCourseSchedules)
                            }
                            ForEach(model.officialScheduleErrors.keys.sorted(), id: \.self) { id in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(model.course(id).code).fontWeight(.semibold)
                                    Text(L10n.string(model.officialScheduleErrors[id] ?? "")).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !model.curationFailures.isEmpty {
                            Text(L10n.string("Processing interrupted")).font(.headline)
                            ForEach(model.curationFailures, id: \.source.id) { issue in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(issue.source.title).fontWeight(.semibold)
                                        Spacer()
                                        Button(L10n.string("Retry")) { model.extractAI(issue.source) }.disabled(model.curationTask != nil)
                                    }
                                    Text(issue.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $model.readingSource) { SourceReader(source: $0) }
    }
}
