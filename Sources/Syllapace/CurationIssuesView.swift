import SwiftUI
import SyllapaceKit

struct CurationIssuesView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("Needs information")).font(.system(size: 24, weight: .semibold))
            if model.curationIssues.isEmpty && model.unresolvedEvents.isEmpty {
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
                                VStack(alignment: .leading, spacing: 8) { Text(event.title).fontWeight(.semibold); Text(L10n.string("A source change overlaps your edit.")).font(.callout).foregroundStyle(.secondary) }
                                Spacer()
                                Button(L10n.string("Resolve")) { model.editor = event }
                            }
                        }
                    }
                }
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $model.readingSource) { SourceReader(source: $0) }
    }
}
