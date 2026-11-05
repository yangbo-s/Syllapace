import SwiftUI
import SyllapaceKit

/// Foreground feedback lives in window chrome; it never takes schedule height.
struct ActivityControl: View {
    @Bindable var model: AppModel
    @State private var showsSummary = true
    private var message: String { model.curationStatus ?? model.notice ?? "" }

    var body: some View {
        Button { model.showActivity.toggle() } label: {
            HStack(spacing: 8) {
                if model.curationStatus != nil { ProgressView().controlSize(.small) }
                else { Image(systemName: "info.circle") }
                if showsSummary || model.curationStatus != nil {
                    Text(message).font(.caption).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
        }
        .help(message)
        .accessibilityLabel(L10n.string("Activity"))
        .accessibilityValue(message)
        .accessibilityIdentifier("activity-control")
        .popover(isPresented: $model.showActivity, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.string("Activity")).font(.headline)
                    Spacer()
                    Button { model.showActivity = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help(L10n.string("Close"))
                }
                ScrollView {
                    Text(message).font(.system(size: 13)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true).frame(maxHeight: 240)
                if model.curationStatus != nil {
                    Button(L10n.string("Stop")) { model.showActivity = false; model.cancelCuration() }
                } else {
                    HStack(spacing: 12) {
                        if model.lastImportUndo != nil { Button(L10n.string("Undo import")) { model.undoImport() }.disabled(model.busy) }
                        if model.lastCurationUndo != nil { Button(L10n.string("Undo reorganization")) { model.undoCuration() } }
                        Spacer()
                        Button(L10n.string("Dismiss message")) { model.showActivity = false; model.notice = nil }
                    }
                }
            }.padding(16).frame(width: 392).accessibilityIdentifier("activity-details")
        }
        .task(id: model.noticeID) {
            showsSummary = true
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            showsSummary = false
        }
    }
}
